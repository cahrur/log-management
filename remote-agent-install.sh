#!/usr/bin/env bash
# ==============================================================
# Pantra - Remote Agent Installer
# Install monitoring agent di VPS remote (bukan server Pantra)
# Komponen: Promtail + node-exporter + cAdvisor via Docker Compose
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

# ---------- Banner ----------
echo -e "${CYAN}"
cat << 'BANNER'
  ____             _
 |  _ \ __ _ _ __ | |_ _ __ __ _
 | |_) / _` | '_ \| __| '__/ _` |
 |  __/ (_| | | | | |_| | | (_| |
 |_|   \__,_|_| |_|\__|_|  \__,_|
  Remote Agent Installer
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

if ! docker compose version >/dev/null 2>&1; then
  fatal "Docker Compose v2 gak ketemu. Update Docker ke versi terbaru."
fi

ok "Docker $(docker --version | cut -d, -f1)"
ok "Compose $(docker compose version --short)"

# ---------- User Input ----------
echo ""
echo -e "${CYAN}=== Konfigurasi Remote Agent ===${NC}"
echo ""

# Pantra server URL
read -rp "Pantra server IP/URL (contoh: 10.0.0.1 atau pantra.example.com): " PANTRA_HOST
if [[ -z "$PANTRA_HOST" ]]; then
  fatal "Pantra server IP/URL wajib diisi"
fi

# Port Loki
read -rp "Loki port [3100]: " LOKI_PORT
LOKI_PORT="${LOKI_PORT:-3100}"

# Hostname label
DEFAULT_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
read -rp "Hostname label untuk VPS ini [${DEFAULT_HOSTNAME}]: " VPS_HOSTNAME
VPS_HOSTNAME="${VPS_HOSTNAME:-$DEFAULT_HOSTNAME}"

# Extra labels
read -rp "Team name (opsional): " TEAM_NAME
read -rp "Project name (opsional): " PROJECT_NAME

LOKI_URL="http://${PANTRA_HOST}:${LOKI_PORT}"

# ---------- Test connectivity ----------
log "Testing koneksi ke Pantra server..."
if curl -sf --max-time 10 "${LOKI_URL}/ready" >/dev/null 2>&1; then
  ok "Loki reachable di ${LOKI_URL}"
elif curl -sf --max-time 10 "${LOKI_URL}/loki/api/v1/labels" >/dev/null 2>&1; then
  ok "Loki API reachable di ${LOKI_URL}"
else
  warn "Loki tidak bisa dihubungi di ${LOKI_URL}"
  warn "Pastikan port ${LOKI_PORT} terbuka di firewall Pantra server"
  read -rp "Lanjut install anyway? [y/N]: " CONTINUE
  if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
    fatal "Dibatalkan. Fix koneksi dulu."
  fi
fi

# ---------- Setup directory ----------
INSTALL_DIR="/opt/pantra-agent"
log "Setup directory: $INSTALL_DIR"
$SUDO mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# ---------- Generate Promtail config ----------
log "Generating Promtail config..."

$SUDO tee "$INSTALL_DIR/promtail-config.yaml" > /dev/null << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: ${LOKI_URL}/loki/api/v1/push
    tenant_id: default
    batchwait: 1s
    batchsize: 1048576
    timeout: 10s
    backoff_config:
      min_period: 500ms
      max_period: 5m
      max_retries: 10

scrape_configs:
  # Docker container logs (via label filtering)
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
        filters:
          - name: label
            values: ["logging=promtail"]
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'  
        target_label: 'container'
      - source_labels: ['__meta_docker_container_label_team']
        target_label: 'team'
      - source_labels: ['__meta_docker_container_label_project']
        target_label: 'project'
      - source_labels: ['__meta_docker_container_label_service']
        target_label: 'service'
      - target_label: 'host'
        replacement: '${VPS_HOSTNAME}'
    pipeline_stages:
      - docker: {}

  # System logs
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          host: ${VPS_HOSTNAME}
          __path__: /var/log/syslog

  - job_name: auth
    static_configs:
      - targets:
          - localhost
        labels:
          job: auth
          host: ${VPS_HOSTNAME}
          __path__: /var/log/auth.log
EOF

ok "Promtail config generated"

# ---------- Generate docker-compose.yml ----------
log "Generating docker-compose.yml..."

LABELS_SECTION=""
if [[ -n "${TEAM_NAME:-}" ]]; then
  LABELS_SECTION+="      - \"team=${TEAM_NAME}\"\n"
fi
if [[ -n "${PROJECT_NAME:-}" ]]; then
  LABELS_SECTION+="      - \"project=${PROJECT_NAME}\"\n"
fi

$SUDO tee "$INSTALL_DIR/docker-compose.yml" > /dev/null << EOF
name: pantra-agent

services:
  promtail:
    image: grafana/promtail:3.3.2
    container_name: pantra-promtail
    restart: unless-stopped
    command:
      - -config.file=/etc/promtail/promtail-config.yaml
    volumes:
      - ./promtail-config.yaml:/etc/promtail/promtail-config.yaml:ro
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - promtail_data:/tmp
    networks:
      - agent-net

  node-exporter:
    image: prom/node-exporter:v1.8.2
    container_name: pantra-node-exporter
    restart: unless-stopped
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)(\$\$|/)'
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    ports:
      - "9100:9100"
    networks:
      - agent-net
    pid: host

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    container_name: pantra-cadvisor
    restart: unless-stopped
    privileged: true
    devices:
      - /dev/kmsg:/dev/kmsg
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    ports:
      - "8080:8080"
    networks:
      - agent-net
    command:
      - '--housekeeping_interval=30s'
      - '--docker_only=true'

networks:
  agent-net:
    driver: bridge

volumes:
  promtail_data:
EOF

ok "docker-compose.yml generated"

# ---------- Start stack ----------
log "Pulling images..."
cd "$INSTALL_DIR"
$SUDO docker compose pull
ok "Images ready"

log "Starting Pantra agent..."
$SUDO docker compose up -d
ok "Agent stack running"

# ---------- Verify ----------
log "Verifying services..."
sleep 5

ALL_OK=true
for svc in pantra-promtail pantra-node-exporter pantra-cadvisor; do
  STATUS=$($SUDO docker inspect --format='{{.State.Status}}' "$svc" 2>/dev/null || echo "not_found")
  if [[ "$STATUS" == "running" ]]; then
    ok "$svc: running"
  else
    err "$svc: $STATUS"
    ALL_OK=false
  fi
done

echo ""
echo "========================================="
if [[ "$ALL_OK" == "true" ]]; then
  ok "Remote agent berhasil diinstall!"
else
  warn "Beberapa service bermasalah. Cek logs."
fi
echo "========================================="
echo ""

VPS_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "<IP_VPS_INI>")

cat << EOF

📍 Install directory: $INSTALL_DIR
📊 Hostname label:    $VPS_HOSTNAME
🔗 Pantra server:     $LOKI_URL

🔧 Langkah selanjutnya di PANTRA SERVER:

   1. Tambahkan target node-exporter di prometheus.yml:
      - job_name: 'remote-${VPS_HOSTNAME}'
        static_configs:
          - targets: ['${VPS_IP}:9100']
            labels:
              host: '${VPS_HOSTNAME}'

   2. Tambahkan target cAdvisor di prometheus.yml:
      - job_name: 'remote-${VPS_HOSTNAME}-cadvisor'
        static_configs:
          - targets: ['${VPS_IP}:8080']
            labels:
              host: '${VPS_HOSTNAME}'

   3. Reload Prometheus:
      curl -X POST http://localhost:9090/-/reload

   4. Verifikasi log masuk:
      - Buka Grafana → Explore → Loki
      - Query: {host="${VPS_HOSTNAME}"}

🛠️  Management:
   cd $INSTALL_DIR
   docker compose logs -f        # Lihat logs
   docker compose restart         # Restart
   docker compose down             # Stop

EOF
