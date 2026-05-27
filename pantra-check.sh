#!/usr/bin/env bash
# ==============================================================
# Pantra - Health Check Script
# Verifikasi semua service running dan healthy
# ==============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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
err()   { echo -e "${RED}[FAIL]${NC}  $*"; }

PASS=0
FAIL=0
WARN_COUNT=0

check_pass() { ok "$*"; PASS=$((PASS + 1)); }
check_fail() { err "$*"; FAIL=$((FAIL + 1)); }
check_warn() { warn "$*"; WARN_COUNT=$((WARN_COUNT + 1)); }

# ---------- Load .env ----------
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

GRAFANA_PORT="${GRAFANA_PORT:-3000}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
ALERTMANAGER_PORT="${ALERTMANAGER_PORT:-9093}"
CADVISOR_PORT="${CADVISOR_PORT:-8080}"
LOKI_PORT="${LOKI_PORT:-3100}"

# ---------- Banner ----------
echo -e "${CYAN}"
cat << 'BANNER'
  ____             _
 |  _ \ __ _ _ __ | |_ _ __ __ _
 | |_) / _` | '_ \| __| '__/ _` |
 |  __/ (_| | | | | |_| | | (_| |
 |_|   \__,_|_| |_|\__|_|  \__,_|
  Health Check
BANNER
echo -e "${NC}"
echo "$(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="
echo ""

# ========== 1. Docker Services ==========
echo -e "${BOLD}[1/6] Docker Services${NC}"
echo "---"

SERVICES=("loki" "promtail" "prometheus" "node-exporter" "cadvisor" "alertmanager" "grafana")

for svc in "${SERVICES[@]}"; do
  STATUS=$(docker inspect --format='{{.State.Status}}' "$svc" 2>/dev/null || echo "not_found")
  HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no_healthcheck{{end}}' "$svc" 2>/dev/null || echo "unknown")

  if [[ "$STATUS" == "running" ]]; then
    if [[ "$HEALTH" == "healthy" || "$HEALTH" == "no_healthcheck" ]]; then
      check_pass "$svc: running ($HEALTH)"
    elif [[ "$HEALTH" == "starting" ]]; then
      check_warn "$svc: running (still starting)"
    else
      check_warn "$svc: running but $HEALTH"
    fi
  elif [[ "$STATUS" == "not_found" ]]; then
    check_fail "$svc: container not found"
  else
    check_fail "$svc: $STATUS"
  fi
done
echo ""

# ========== 2. Loki ==========
echo -e "${BOLD}[2/6] Loki - Log Ingestion${NC}"
echo "---"

# Test ready endpoint
if curl -sf --max-time 5 "http://localhost:${LOKI_PORT}/ready" >/dev/null 2>&1; then
  check_pass "Loki /ready endpoint OK"
else
  check_fail "Loki /ready endpoint unreachable"
fi

# Test push (kirim log dummy)
PUSH_RESULT=$(curl -sf --max-time 10 -o /dev/null -w "%{http_code}" \
  -X POST "http://localhost:${LOKI_PORT}/loki/api/v1/push" \
  -H "Content-Type: application/json" \
  -d "{\"streams\":[{\"stream\":{\"job\":\"healthcheck\",\"host\":\"pantra\"},\"values\":[[\"$(date +%s)000000000\",\"pantra-check healthcheck ping\"]]}]}" \
  2>/dev/null || echo "000")

if [[ "$PUSH_RESULT" == "204" || "$PUSH_RESULT" == "200" ]]; then
  check_pass "Loki accepting logs (HTTP $PUSH_RESULT)"
else
  check_fail "Loki log push failed (HTTP $PUSH_RESULT)"
fi

# Check labels
LABELS=$(curl -sf --max-time 5 "http://localhost:${LOKI_PORT}/loki/api/v1/labels" 2>/dev/null || echo "")
if [[ -n "$LABELS" ]]; then
  LABEL_COUNT=$(echo "$LABELS" | grep -o '"' | wc -l)
  check_pass "Loki has labels available"
else
  check_warn "Loki labels endpoint empty or unreachable"
fi
echo ""

# ========== 3. Prometheus ==========
echo -e "${BOLD}[3/6] Prometheus - Metrics${NC}"
echo "---"

if curl -sf --max-time 5 "http://localhost:${PROMETHEUS_PORT}/-/healthy" >/dev/null 2>&1; then
  check_pass "Prometheus healthy"
else
  check_fail "Prometheus unreachable"
fi

# Check targets
TARGETS_JSON=$(curl -sf --max-time 5 "http://localhost:${PROMETHEUS_PORT}/api/v1/targets" 2>/dev/null || echo "")
if [[ -n "$TARGETS_JSON" ]]; then
  UP_COUNT=$(echo "$TARGETS_JSON" | grep -o '"health":"up"' | wc -l)
  DOWN_COUNT=$(echo "$TARGETS_JSON" | grep -o '"health":"down"' | wc -l)
  UNKNOWN_COUNT=$(echo "$TARGETS_JSON" | grep -o '"health":"unknown"' | wc -l)

  if [[ $DOWN_COUNT -eq 0 && $UP_COUNT -gt 0 ]]; then
    check_pass "All targets UP ($UP_COUNT targets)"
  elif [[ $DOWN_COUNT -gt 0 ]]; then
    check_fail "$DOWN_COUNT target(s) DOWN, $UP_COUNT UP"
    # Show which targets are down
    echo "$TARGETS_JSON" | grep -oP '"scrapeUrl":"[^"]+".*?"health":"down"' | head -5 | while read -r line; do
      TARGET_URL=$(echo "$line" | grep -oP '"scrapeUrl":"\K[^"]+' || echo "unknown")
      echo -e "         ${RED}↳ DOWN: $TARGET_URL${NC}"
    done
  else
    check_warn "No active targets found"
  fi
else
  check_warn "Cannot query Prometheus targets API"
fi
echo ""

# ========== 4. Grafana ==========
echo -e "${BOLD}[4/6] Grafana - Dashboard${NC}"
echo "---"

GRAFANA_HEALTH=$(curl -sf --max-time 5 "http://localhost:${GRAFANA_PORT}/api/health" 2>/dev/null || echo "")
if [[ -n "$GRAFANA_HEALTH" ]]; then
  DB_STATUS=$(echo "$GRAFANA_HEALTH" | grep -oP '"database":"\K[^"]+' || echo "unknown")
  if [[ "$DB_STATUS" == "ok" ]]; then
    check_pass "Grafana healthy (database: ok)"
  else
    check_warn "Grafana responding but database: $DB_STATUS"
  fi
else
  check_fail "Grafana unreachable on port $GRAFANA_PORT"
fi

# Check datasources
DS_RESULT=$(curl -sf --max-time 5 "http://localhost:${GRAFANA_PORT}/api/datasources" \
  -u "${GRAFANA_ADMIN_USER:-admin}:${GRAFANA_ADMIN_PASSWORD:-admin}" 2>/dev/null || echo "")
if [[ -n "$DS_RESULT" && "$DS_RESULT" != "null" ]]; then
  DS_COUNT=$(echo "$DS_RESULT" | grep -o '"id"' | wc -l)
  check_pass "Grafana datasources configured ($DS_COUNT)"
else
  check_warn "Cannot verify Grafana datasources (auth issue?)"
fi
echo ""

# ========== 5. Alertmanager ==========
echo -e "${BOLD}[5/6] Alertmanager${NC}"
echo "---"

if curl -sf --max-time 5 "http://localhost:${ALERTMANAGER_PORT}/-/healthy" >/dev/null 2>&1; then
  check_pass "Alertmanager healthy"
else
  check_fail "Alertmanager unreachable on port $ALERTMANAGER_PORT"
fi

# Check active alerts
ALERTS=$(curl -sf --max-time 5 "http://localhost:${ALERTMANAGER_PORT}/api/v2/alerts" 2>/dev/null || echo "[]")
ALERT_COUNT=$(echo "$ALERTS" | grep -o '"status"' | wc -l)
if [[ $ALERT_COUNT -gt 0 ]]; then
  check_warn "$ALERT_COUNT active alert(s) in Alertmanager"
else
  check_pass "No active alerts"
fi
echo ""

# ========== 6. Disk Usage ==========
echo -e "${BOLD}[6/6] Disk Usage${NC}"
echo "---"

# Check Docker data
DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
DISK_USAGE=$(df -h "$DOCKER_ROOT" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
DISK_AVAIL=$(df -h "$DOCKER_ROOT" 2>/dev/null | tail -1 | awk '{print $4}')

if [[ -n "$DISK_USAGE" ]]; then
  if [[ $DISK_USAGE -ge 90 ]]; then
    check_fail "Disk usage CRITICAL: ${DISK_USAGE}% (available: $DISK_AVAIL)"
  elif [[ $DISK_USAGE -ge 80 ]]; then
    check_warn "Disk usage HIGH: ${DISK_USAGE}% (available: $DISK_AVAIL)"
  else
    check_pass "Disk usage OK: ${DISK_USAGE}% (available: $DISK_AVAIL)"
  fi
fi

# Docker volume sizes
log "Docker volume usage:"
docker system df --format 'table {{.Type}}\t{{.Size}}\t{{.Reclaimable}}' 2>/dev/null || true
echo ""

# ========== Summary ==========
echo "========================================="
echo -e "${BOLD}SUMMARY${NC}"
echo "========================================="
echo -e "  ${GREEN}PASS:${NC} $PASS"
echo -e "  ${YELLOW}WARN:${NC} $WARN_COUNT"
echo -e "  ${RED}FAIL:${NC} $FAIL"
echo ""

if [[ $FAIL -eq 0 && $WARN_COUNT -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✓ All checks passed!${NC}"
elif [[ $FAIL -eq 0 ]]; then
  echo -e "  ${YELLOW}${BOLD}⚠ Passed with warnings${NC}"
else
  echo -e "  ${RED}${BOLD}✗ $FAIL check(s) failed${NC}"
fi
echo ""

# Exit code: 0 = all good, 1 = failures, 2 = warnings only
if [[ $FAIL -gt 0 ]]; then
  exit 1
elif [[ $WARN_COUNT -gt 0 ]]; then
  exit 2
else
  exit 0
fi
