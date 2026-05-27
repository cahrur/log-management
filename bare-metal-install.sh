#!/usr/bin/env bash
# ==============================================================
# Pantra - Bare Metal Installer
# Install Promtail + node-exporter tanpa Docker
# Target: Ubuntu/Debian/CentOS/RHEL
# ==============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR ]${NC}  $*" >&2; }
fatal() { err "$*"; exit 1; }

# ---------- Versions ----------
PROMTAIL_VERSION="${PROMTAIL_VERSION:-3.3.2}"
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.8.2}"

# ---------- Pre-flight ----------
echo -e "${CYAN}"
cat << 'BANNER'
  ____             _
 |  _ \ __ _ _ __ | |_ _ __ __ _
 | |_) / _` | '_ \| __| '__/ _` |
 |  __/ (_| | | | | |_| | | (_| |
 |_|   \__,_|_| |_|\__|_|  \__,_|
  Bare Metal Installer
BANNER
echo -e "${NC}"

# OS check
if [[ "$(uname)" != "Linux" ]]; then
  fatal "Script ini cuma jalan di Linux."
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

# ---------- Detect OS ----------
detect_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID}"
    OS_VERSION="${VERSION_ID:-}"
  elif [[ -f /etc/redhat-release ]]; then
    OS_ID="centos"
    OS_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
  else
    fatal "OS tidak dikenali. Support: Ubuntu, Debian, CentOS, RHEL."
  fi

  case "$OS_ID" in
    ubuntu|debian)
      PKG_MANAGER="apt"
      ;;
    centos|rhel|rocky|almalinux)
      PKG_MANAGER="yum"
      ;;
    *)
      fatal "OS '$OS_ID' belum disupport. Support: Ubuntu, Debian, CentOS, RHEL."
      ;;
  esac

  ok "Detected OS: $OS_ID ${OS_VERSION:-} (package manager: $PKG_MANAGER)"
}

# ---------- Detect Architecture ----------
detect_arch() {
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|amd64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv7l)        ARCH="armv7" ;;
    *)             fatal "Arsitektur '$ARCH' tidak disupport." ;;
  esac
  ok "Architecture: $ARCH"
}

# ---------- Install dependencies ----------
install_deps() {
  log "Install dependencies..."
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq curl wget tar unzip >/dev/null
  else
    $SUDO yum install -y -q curl wget tar unzip >/dev/null
  fi
  ok "Dependencies ready"
}

# ---------- Create user ----------
create_service_user() {
  local username="$1"
  if id "$username" &>/dev/null; then
    ok "User '$username' sudah ada"
  else
    $SUDO useradd --no-create-home --shell /bin/false "$username"
    ok "User '$username' dibuat"
  fi
}

# ---------- Install node-exporter ----------
install_node_exporter() {
  log "Installing node-exporter v${NODE_EXPORTER_VERSION}..."

  # Cek kalau sudah terinstall dengan versi yang sama
  if command -v node_exporter &>/dev/null; then
    CURRENT_VER=$(node_exporter --version 2>&1 | grep -oP 'version \K[0-9.]+' || echo "")
    if [[ "$CURRENT_VER" == "$NODE_EXPORTER_VERSION" ]]; then
      ok "node-exporter v${NODE_EXPORTER_VERSION} sudah terinstall"
      return 0
    fi
    warn "node-exporter versi lama ($CURRENT_VER) ditemukan, upgrade..."
  fi

  local TARBALL="node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz"
  local URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${TARBALL}"

  cd /tmp
  wget -q "$URL" -O "$TARBALL"
  tar xzf "$TARBALL"
  $SUDO cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}/node_exporter" /usr/local/bin/
  $SUDO chmod +x /usr/local/bin/node_exporter
  rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}" "$TARBALL"

  create_service_user "node_exporter"

  # Systemd service
  $SUDO tee /etc/systemd/system/node-exporter.service > /dev/null << 'EOF'
[Unit]
Description=Prometheus Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
  --collector.filesystem.mount-points-exclude="^/(sys|proc|dev|host|etc)($$|/)" \
  --collector.systemd \
  --collector.processes
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now node-exporter
  ok "node-exporter v${NODE_EXPORTER_VERSION} terinstall dan running"
}

# ---------- Install Promtail ----------
install_promtail() {
  log "Installing Promtail v${PROMTAIL_VERSION}..."

  # Cek kalau sudah terinstall
  if command -v promtail &>/dev/null; then
    CURRENT_VER=$(promtail --version 2>&1 | grep -oP 'version \K[0-9.]+' || echo "")
    if [[ "$CURRENT_VER" == "$PROMTAIL_VERSION" ]]; then
      ok "Promtail v${PROMTAIL_VERSION} sudah terinstall"
      return 0
    fi
    warn "Promtail versi lama ($CURRENT_VER) ditemukan, upgrade..."
  fi

  local ZIPFILE="promtail-linux-${ARCH}.zip"
  local URL="https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/${ZIPFILE}"

  cd /tmp
  wget -q "$URL" -O "$ZIPFILE"
  unzip -o -q "$ZIPFILE"
  $SUDO cp "promtail-linux-${ARCH}" /usr/local/bin/promtail
  $SUDO chmod +x /usr/local/bin/promtail
  rm -f "$ZIPFILE" "promtail-linux-${ARCH}"

  create_service_user "promtail"

  # Buat config directory
  $SUDO mkdir -p /etc/promtail
  $SUDO mkdir -p /var/lib/promtail

  ok "Promtail binary v${PROMTAIL_VERSION} terinstall"
}

# ---------- Generate Promtail config ----------
generate_promtail_config() {
  local loki_url="$1"
  local hostname="$2"
  local log_paths="$3"

  log "Generating Promtail config..."

  # Build scrape configs dari log paths
  local scrape_configs=""
  IFS=',' read -ra PATHS <<< "$log_paths"
  for i in "${!PATHS[@]}"; do
    local path="${PATHS[$i]}"
    path=$(echo "$path" | xargs)  # trim whitespace
    scrape_configs+="
  - job_name: custom_logs_${i}
    static_configs:
      - targets:
          - localhost
        labels:
          job: custom_logs
          host: ${hostname}
          __path__: ${path}"
  done

  $SUDO tee /etc/promtail/promtail-config.yaml > /dev/null << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: ${loki_url}/loki/api/v1/push
    tenant_id: default
    batchwait: 1s
    batchsize: 1048576
    timeout: 10s
    backoff_config:
      min_period: 500ms
      max_period: 5m
      max_retries: 10

scrape_configs:
  # System logs
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          host: ${hostname}
          __path__: /var/log/syslog

  - job_name: auth
    static_configs:
      - targets:
          - localhost
        labels:
          job: auth
          host: ${hostname}
          __path__: /var/log/auth.log

  # Journal (systemd)
  - job_name: journal
    journal:
      max_age: 12h
      labels:
        job: journal
        host: ${hostname}
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
${scrape_configs}
EOF

  # Fix permissions
  $SUDO chown promtail:promtail /etc/promtail/promtail-config.yaml
  $SUDO chown -R promtail:promtail /var/lib/promtail

  ok "Promtail config generated: /etc/promtail/promtail-config.yaml"
}

# ---------- Create Promtail systemd service ----------
create_promtail_service() {
  $SUDO tee /etc/systemd/system/promtail.service > /dev/null << 'EOF'
[Unit]
Description=Grafana Promtail - Log collector
Documentation=https://grafana.com/docs/loki/latest/clients/promtail/
After=network-online.target
Wants=network-online.target

[Service]
User=promtail
Group=promtail
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail-config.yaml
Restart=always
RestartSec=5
# Promtail butuh akses ke log files
ReadOnlyPaths=/var/log
CapabilityBoundingSet=CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_DAC_READ_SEARCH

[Install]
WantedBy=multi-user.target
EOF

  # Tambah promtail ke group adm biar bisa baca /var/log
  $SUDO usermod -aG adm promtail 2>/dev/null || true

  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now promtail
  ok "Promtail service running"
}

# ---------- Validate connectivity ----------
validate_loki() {
  local loki_url="$1"
  log "Testing koneksi ke Loki: $loki_url ..."

  # Test /ready endpoint
  if curl -sf --max-time 10 "${loki_url}/ready" >/dev/null 2>&1; then
    ok "Loki reachable dan ready"
    return 0
  fi

  # Fallback: test /loki/api/v1/labels
  if curl -sf --max-time 10 "${loki_url}/loki/api/v1/labels" >/dev/null 2>&1; then
    ok "Loki API reachable"
    return 0
  fi

  warn "Loki tidak bisa dihubungi di $loki_url"
  warn "Pastikan:"
  warn "  1. Loki server running"
  warn "  2. Port terbuka (firewall)"
  warn "  3. URL benar (http://IP:3100)"
  return 1
}

# ---------- Interactive input ----------
get_user_input() {
  echo ""
  echo -e "${CYAN}=== Konfigurasi ===${NC}"
  echo ""

  # Loki URL
  read -rp "Loki URL (contoh: http://10.0.0.1:3100): " LOKI_URL
  if [[ -z "$LOKI_URL" ]]; then
    fatal "Loki URL wajib diisi"
  fi
  # Hapus trailing slash
  LOKI_URL="${LOKI_URL%/}"

  # Hostname
  DEFAULT_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
  read -rp "Hostname label [${DEFAULT_HOSTNAME}]: " INPUT_HOSTNAME
  HOSTNAME_LABEL="${INPUT_HOSTNAME:-$DEFAULT_HOSTNAME}"

  # Log paths
  echo ""
  echo "Log paths tambahan (selain /var/log/syslog & /var/log/auth.log)"
  echo "Pisahkan dengan koma. Contoh: /var/log/nginx/*.log,/opt/app/logs/*.log"
  read -rp "Extra log paths (kosongkan kalau gak ada): " EXTRA_LOGS
}

# ========== MAIN ==========
main() {
  detect_os
  detect_arch
  install_deps

  echo ""
  echo -e "${CYAN}Apa yang mau diinstall?${NC}"
  echo "  1) Promtail + node-exporter (recommended)"
  echo "  2) Promtail only"
  echo "  3) node-exporter only"
  echo ""
  read -rp "Pilih [1/2/3]: " INSTALL_CHOICE
  INSTALL_CHOICE="${INSTALL_CHOICE:-1}"

  case "$INSTALL_CHOICE" in
    1|2)
      get_user_input
      install_promtail
      generate_promtail_config "$LOKI_URL" "$HOSTNAME_LABEL" "${EXTRA_LOGS:-}"
      create_promtail_service

      # Validate
      validate_loki "$LOKI_URL" || true
      ;;&
    1|3)
      install_node_exporter
      ;;
    2) ;; # sudah dihandle di atas
    *)
      fatal "Pilihan tidak valid"
      ;;
  esac

  # ---------- Summary ----------
  echo ""
  echo "========================================="
  ok "Instalasi selesai!"
  echo "========================================="
  echo ""

  if [[ "$INSTALL_CHOICE" == "1" || "$INSTALL_CHOICE" == "2" ]]; then
    echo -e "  Promtail:       ${GREEN}running${NC} (port 9080)"
    echo -e "  Config:         /etc/promtail/promtail-config.yaml"
    echo -e "  Positions:      /var/lib/promtail/positions.yaml"
    echo -e "  Service:        systemctl status promtail"
    echo ""
  fi

  if [[ "$INSTALL_CHOICE" == "1" || "$INSTALL_CHOICE" == "3" ]]; then
    echo -e "  node-exporter:  ${GREEN}running${NC} (port 9100)"
    echo -e "  Service:        systemctl status node-exporter"
    echo ""
  fi

  cat << 'EOF'
🔧 Langkah selanjutnya:
   1. Tambahkan target di Prometheus server:
      - job_name: 'remote-node'
        static_configs:
          - targets: ['<IP_HOST_INI>:9100']
            labels:
              host: '<HOSTNAME>'

   2. Verifikasi log masuk ke Loki:
      curl -s "http://<LOKI_IP>:3100/loki/api/v1/labels" | jq

   3. Cek service status:
      systemctl status promtail
      systemctl status node-exporter

   4. Lihat logs:
      journalctl -u promtail -f
      journalctl -u node-exporter -f
EOF
}

main "$@"
