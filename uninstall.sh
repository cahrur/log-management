#!/usr/bin/env bash
# ==============================================================
# Pantra - Uninstaller
# Clean uninstall untuk Docker stack dan bare metal
# ==============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR ]${NC}  $*" >&2; }
fatal() { err "$*"; exit 1; }

# ---------- Banner ----------
echo -e "${CYAN}"
cat << 'BANNER'
  ____             _
 |  _ \ __ _ _ __ | |_ _ __ __ _
 | |_) / _` | '_ \| __| '__/ _` |
 |  __/ (_| | | | | |_| | | (_| |
 |_|   \__,_|_| |_|\__|_|  \__,_|
  Uninstaller
BANNER
echo -e "${NC}"

# ---------- Pre-flight ----------
if [[ "$(uname)" != "Linux" ]]; then
  fatal "Script ini cuma jalan di Linux."
fi

if [[ "$EUID" -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    fatal "Butuh root atau sudo."
  fi
  SUDO="sudo"
else
  SUDO=""
fi

# ---------- Detect installation type ----------
HAS_DOCKER=false
HAS_BARE_METAL=false
HAS_REMOTE_AGENT=false

if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
  # Cek apakah ini main stack atau remote agent
  if grep -q "name: pantra" "$SCRIPT_DIR/docker-compose.yml" 2>/dev/null; then
    HAS_DOCKER=true
  fi
fi

if [[ -f "/opt/pantra-agent/docker-compose.yml" ]]; then
  HAS_REMOTE_AGENT=true
fi

if systemctl list-unit-files 2>/dev/null | grep -q "promtail.service"; then
  HAS_BARE_METAL=true
fi
if systemctl list-unit-files 2>/dev/null | grep -q "node-exporter.service"; then
  HAS_BARE_METAL=true
fi

# ---------- Menu ----------
echo -e "${BOLD}Detected installations:${NC}"
[[ "$HAS_DOCKER" == "true" ]] && echo -e "  ${GREEN}✓${NC} Pantra Docker stack (main)"
[[ "$HAS_REMOTE_AGENT" == "true" ]] && echo -e "  ${GREEN}✓${NC} Remote agent (/opt/pantra-agent)"
[[ "$HAS_BARE_METAL" == "true" ]] && echo -e "  ${GREEN}✓${NC} Bare metal services (systemd)"

if [[ "$HAS_DOCKER" == "false" && "$HAS_BARE_METAL" == "false" && "$HAS_REMOTE_AGENT" == "false" ]]; then
  warn "Tidak ada instalasi Pantra yang terdeteksi."
  exit 0
fi

echo ""
echo "Apa yang mau di-uninstall?"
echo "  1) Pantra Docker stack (main server)"
echo "  2) Remote agent (/opt/pantra-agent)"
echo "  3) Bare metal services (Promtail + node-exporter systemd)"
echo "  4) Semua yang terdeteksi"
echo "  0) Batal"
echo ""
read -rp "Pilih [0-4]: " CHOICE

case "$CHOICE" in
  0) echo "Dibatalkan."; exit 0 ;;
  1) REMOVE_DOCKER=true; REMOVE_REMOTE=false; REMOVE_BARE=false ;;
  2) REMOVE_DOCKER=false; REMOVE_REMOTE=true; REMOVE_BARE=false ;;
  3) REMOVE_DOCKER=false; REMOVE_REMOTE=false; REMOVE_BARE=true ;;
  4) REMOVE_DOCKER=true; REMOVE_REMOTE=true; REMOVE_BARE=true ;;
  *) fatal "Pilihan tidak valid" ;;
esac

# ---------- Confirm data removal ----------
REMOVE_DATA=false
echo ""
warn "Hapus juga data (volumes, metrics, logs)? Data TIDAK bisa dikembalikan!"
read -rp "Hapus data? [y/N]: " REMOVE_DATA_ANS
if [[ "$REMOVE_DATA_ANS" =~ ^[Yy]$ ]]; then
  REMOVE_DATA=true
  warn "Data akan DIHAPUS PERMANEN."
fi

echo ""
echo -e "${RED}${BOLD}=== KONFIRMASI ===${NC}"
echo "Akan di-uninstall:"
[[ "$REMOVE_DOCKER" == "true" ]] && echo "  - Pantra Docker stack"
[[ "$REMOVE_REMOTE" == "true" ]] && echo "  - Remote agent"
[[ "$REMOVE_BARE" == "true" ]] && echo "  - Bare metal services"
[[ "$REMOVE_DATA" == "true" ]] && echo -e "  - ${RED}DATA (volumes, metrics, logs)${NC}"
echo ""
read -rp "Yakin? Ketik 'yes' untuk lanjut: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Dibatalkan."
  exit 0
fi

# ========== Uninstall Docker Stack ==========
if [[ "$REMOVE_DOCKER" == "true" ]]; then
  log "Removing Pantra Docker stack..."

  if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
    cd "$SCRIPT_DIR"

    # Stop containers
    docker compose down 2>/dev/null || true
    ok "Containers stopped dan removed"

    # Remove volumes kalau diminta
    if [[ "$REMOVE_DATA" == "true" ]]; then
      docker compose down -v 2>/dev/null || true
      ok "Docker volumes removed"

      # Remove data directory
      if [[ -d "$SCRIPT_DIR/data" ]]; then
        rm -rf "$SCRIPT_DIR/data"
        ok "Data directory removed"
      fi
    fi

    # Remove generated configs
    rm -f "$SCRIPT_DIR/alertmanager/alertmanager.yml"
    rm -f "$SCRIPT_DIR/alertmanager/telegram_token"
    ok "Generated configs cleaned"
  else
    warn "docker-compose.yml tidak ditemukan di $SCRIPT_DIR"
  fi
fi

# ========== Uninstall Remote Agent ==========
if [[ "$REMOVE_REMOTE" == "true" ]]; then
  log "Removing remote agent..."

  if [[ -d "/opt/pantra-agent" ]]; then
    cd /opt/pantra-agent

    # Stop containers
    $SUDO docker compose down 2>/dev/null || true
    ok "Remote agent containers stopped"

    if [[ "$REMOVE_DATA" == "true" ]]; then
      $SUDO docker compose down -v 2>/dev/null || true
      ok "Remote agent volumes removed"
    fi

    # Remove directory
    $SUDO rm -rf /opt/pantra-agent
    ok "Directory /opt/pantra-agent removed"
  else
    warn "/opt/pantra-agent tidak ditemukan"
  fi
fi

# ========== Uninstall Bare Metal ==========
if [[ "$REMOVE_BARE" == "true" ]]; then
  log "Removing bare metal services..."

  # Promtail
  if systemctl list-unit-files 2>/dev/null | grep -q "promtail.service"; then
    $SUDO systemctl stop promtail 2>/dev/null || true
    $SUDO systemctl disable promtail 2>/dev/null || true
    $SUDO rm -f /etc/systemd/system/promtail.service
    $SUDO rm -f /usr/local/bin/promtail
    $SUDO rm -rf /etc/promtail
    if [[ "$REMOVE_DATA" == "true" ]]; then
      $SUDO rm -rf /var/lib/promtail
    fi
    ok "Promtail service removed"
  else
    log "Promtail service tidak ditemukan (skip)"
  fi

  # node-exporter
  if systemctl list-unit-files 2>/dev/null | grep -q "node-exporter.service"; then
    $SUDO systemctl stop node-exporter 2>/dev/null || true
    $SUDO systemctl disable node-exporter 2>/dev/null || true
    $SUDO rm -f /etc/systemd/system/node-exporter.service
    $SUDO rm -f /usr/local/bin/node_exporter
    ok "node-exporter service removed"
  else
    log "node-exporter service tidak ditemukan (skip)"
  fi

  # Reload systemd
  $SUDO systemctl daemon-reload

  # Remove users
  if id promtail &>/dev/null; then
    $SUDO userdel promtail 2>/dev/null || true
    ok "User 'promtail' removed"
  fi
  if id node_exporter &>/dev/null; then
    $SUDO userdel node_exporter 2>/dev/null || true
    ok "User 'node_exporter' removed"
  fi
fi

# ========== Summary ==========
echo ""
echo "========================================="
ok "Uninstall selesai!"
echo "========================================="
echo ""

if [[ "$REMOVE_DATA" == "false" ]]; then
  echo -e "${YELLOW}Note:${NC} Data/volumes tidak dihapus."
  echo "Untuk hapus manual:"
  [[ "$REMOVE_DOCKER" == "true" ]] && echo "  docker volume rm pantra_prometheus_data pantra_loki_data pantra_grafana_data pantra_alertmanager_data"
fi

echo ""
echo "Terima kasih sudah pakai Pantra! 👋"
