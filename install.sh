#!/usr/bin/env bash
# ==============================================================
# Log Management Stack - Installer
# Target: Linux VPS (Ubuntu/Debian/CentOS)
# ==============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR ]${NC}  $*" >&2; }
fatal() { err "$*"; exit 1; }

# ---------- Self-fix CRLF (kalau di-copy dari Windows) ----------
if file install.sh 2>/dev/null | grep -q CRLF; then
  warn "CRLF detected, converting to LF..."
  find . -type f \( -name "*.sh" -o -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name ".env*" \) -exec sed -i 's/\r$//' {} \;
  ok "CRLF -> LF done"
fi

# ---------- Pre-flight ----------
log "Log Management Stack - Installer"
echo "================================="

# OS check
if [[ "$(uname)" != "Linux" ]]; then
  fatal "Script ini cuma jalan di Linux. Buat Windows pake WSL2."
fi

# Root / sudo check
if [[ "$EUID" -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    fatal "Butuh root atau sudo."
  fi
  SUDO="sudo"
else
  SUDO=""
fi

# Docker check
if ! command -v docker >/dev/null 2>&1; then
  warn "Docker belum terinstall. Install otomatis? [y/N]"
  read -r ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | $SUDO sh
    $SUDO systemctl enable --now docker
    ok "Docker terinstall"
  else
    fatal "Install Docker dulu: https://docs.docker.com/engine/install/"
  fi
fi

# Docker Compose v2 check
if ! docker compose version >/dev/null 2>&1; then
  fatal "Docker Compose v2 gak ketemu. Update Docker ke versi terbaru."
fi

ok "Docker $(docker --version | cut -d, -f1)"
ok "Compose $(docker compose version --short)"

# ---------- Env ----------
if [[ ! -f .env ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example .env
    warn ".env dibuat dari template. Edit dulu password & token sebelum lanjut."
    warn "File: $SCRIPT_DIR/.env"
    read -p "Tekan ENTER setelah selesai edit (atau Ctrl+C buat batal)..." _
  else
    fatal ".env.example gak ada"
  fi
fi

# Load .env
set -a
# shellcheck disable=SC1091
source .env
set +a

# Validate password
if [[ "${GRAFANA_ADMIN_PASSWORD:-}" == "changeme_strong_password_here" ]] || [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
  fatal "GRAFANA_ADMIN_PASSWORD belum diganti di .env"
fi

# ---------- Generate Alertmanager config (telegram on/off) ----------
log "Generating alertmanager config..."

if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "$TELEGRAM_BOT_TOKEN" > alertmanager/telegram_token
  # 644 (bukan 600) supaya alertmanager container (UID 65534) bisa baca
  chmod 644 alertmanager/telegram_token

  cp alertmanager/alertmanager.yml.telegram alertmanager/alertmanager.yml
  sed -i.bak "s|__CHAT_ID__|${TELEGRAM_CHAT_ID}|g" alertmanager/alertmanager.yml
  rm -f alertmanager/alertmanager.yml.bak
  ok "Telegram alerting ON"
else
  # Pakai config no-op (cuma log alert ke stdout alertmanager)
  cp alertmanager/alertmanager.yml.notelegram alertmanager/alertmanager.yml
  # Token file dummy biar mount gak error
  echo "disabled" > alertmanager/telegram_token
  chmod 644 alertmanager/telegram_token
  warn "Telegram kosong - alert cuma masuk ke Alertmanager UI (http://VPS_IP:9093)"
fi

# ---------- Permissions ----------
log "Setup permissions..."
mkdir -p data/promtail
# Promtail official image jalan sebagai root, tapi kasih world-writable buat aman
chmod 777 data/promtail
ok "Permissions OK"

# ---------- Pull images ----------
log "Pulling Docker images (sekali aja, agak lama)..."
docker compose pull
ok "Images ready"

# ---------- Validate configs (after pull) ----------
log "Validating Prometheus config..."
if docker compose run --rm --no-deps --entrypoint promtool prometheus check config /etc/prometheus/prometheus.yml >/dev/null 2>&1; then
  ok "Prometheus config OK"
else
  warn "Prometheus config validation failed - cek 'docker compose run --rm prometheus promtool check config /etc/prometheus/prometheus.yml'"
fi

log "Validating Alertmanager config..."
if docker compose run --rm --no-deps --entrypoint amtool alertmanager check-config /etc/alertmanager/alertmanager.yml >/dev/null 2>&1; then
  ok "Alertmanager config OK"
else
  warn "Alertmanager config validation failed - cek 'docker compose logs alertmanager' setelah start"
fi

# ---------- Start ----------
log "Starting stack..."
docker compose up -d

# ---------- Wait healthy ----------
log "Tunggu service ready..."
sleep 5

WAIT=90
ELAPSED=0
while [[ $ELAPSED -lt $WAIT ]]; do
  if curl -sf "http://localhost:${GRAFANA_PORT:-3000}/api/health" >/dev/null 2>&1; then
    ok "Grafana siap"
    break
  fi
  sleep 3
  ELAPSED=$((ELAPSED+3))
  printf "."
done
echo ""

if [[ $ELAPSED -ge $WAIT ]]; then
  warn "Grafana belum respond dalam ${WAIT}s. Cek 'docker compose logs grafana'"
fi

# ---------- Status ----------
echo ""
echo "================================="
ok "Stack berjalan!"
echo "================================="
docker compose ps
echo ""

VPS_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "VPS_IP")

cat <<EOF

📊 Akses dashboard:
   Grafana:      http://${VPS_IP}:${GRAFANA_PORT:-3000}
                 user: ${GRAFANA_ADMIN_USER:-admin}
                 pass: (dari .env)

   Prometheus:   http://${VPS_IP}:${PROMETHEUS_PORT:-9090}
   Alertmanager: http://${VPS_IP}:${ALERTMANAGER_PORT:-9093}
   cAdvisor:     http://${VPS_IP}:${CADVISOR_PORT:-8080}

🔧 Berikutnya:
   1. Login Grafana, ganti password kalau perlu
   2. Cek dashboard: Host Overview, Container Metrics, Logs Explorer
   3. Buat container app lu pake label:
      labels:
        - "logging=promtail"
        - "team=tim1"
        - "project=dealtech-code"

📖 Lihat README.md, TROUBLESHOOTING.md, dan agent/README.md.

EOF
