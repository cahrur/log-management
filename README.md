# Log Management Stack — Dealtech

Stack observability all-in-one buat dealtech-code dan project lain. 100% open source, gak ada biaya lisensi.

## Komponen

| Service | Fungsi | Port |
|---|---|---|
| **Grafana** | Dashboard UI (logs + metrics) | 3000 |
| **Loki** | Log aggregation & storage | 3100 (internal) |
| **Promtail** | Log shipper dari Docker container | - |
| **Prometheus** | Metrics storage & query | 9090 |
| **node-exporter** | Host metrics (CPU/RAM/disk/net) | 9100 (internal) |
| **cAdvisor** | Per-container metrics | 8080 |
| **Alertmanager** | Alert routing → Telegram | 9093 |

## Quick Start (di VPS)

```bash
# 1. Copy folder ini ke VPS
scp -r log-management/ user@vps:/opt/

# 2. SSH ke VPS, masuk ke folder
ssh user@vps
cd /opt/log-management

# 3. Setup environment
cp .env.example .env
nano .env   # edit password Grafana, Telegram bot token, dll

# 4. Jalanin installer
chmod +x install.sh
./install.sh

# 5. Buka di browser
# Grafana: http://VPS_IP:3000  (default user: admin)
# Prometheus: http://VPS_IP:9090
# Alertmanager: http://VPS_IP:9093
```

## Arsitektur

```
┌────────────────────────────────────────────────────┐
│ VPS                                                │
│                                                    │
│  ┌──────────────┐    ┌──────────────┐             │
│  │  Promtail    │───▶│    Loki      │             │
│  └──────────────┘    └──────┬───────┘             │
│         ▲                    │                     │
│         │ log Docker         │                     │
│  ┌──────┴───────────┐        ▼                     │
│  │ Container Apps   │   ┌─────────┐                │
│  │ (dealtech-code,  │   │ Grafana │◀──user        │
│  │  tim-1..4, etc)  │   └────▲────┘                │
│  └──────────────────┘        │                     │
│         │ metrics             │                     │
│  ┌──────▼─────┐  ┌──────┐  ┌─┴──────────┐         │
│  │  cAdvisor  │  │ node │  │ Prometheus │         │
│  └────────────┘  │ exp  │  └─────┬──────┘         │
│                  └──────┘        │                 │
│                                  ▼                 │
│                          ┌──────────────┐          │
│                          │ Alertmanager │──Telegram│
│                          └──────────────┘          │
└────────────────────────────────────────────────────┘
```

## Konvensi Label Container

Buat dapet metric/log per-tim, kasih label di container app lu:

```yaml
# di docker-compose.yml app dealtech-code
services:
  tim1-app:
    labels:
      - "team=tim1"
      - "project=dealtech-code"
      - "logging=promtail"
```

Promtail udah dikonfigurasi nyedot log dari container yang punya label `logging=promtail`. Di Grafana lu bisa filter `{team="tim1"}`.

## Maintenance

```bash
# Lihat status semua service
docker compose ps

# Lihat log salah satu service
docker compose logs -f loki

# Restart 1 service
docker compose restart promtail

# Update image ke versi terbaru
docker compose pull && docker compose up -d

# Stop semuanya
docker compose down

# Stop + hapus data (HATI-HATI, log/metric history hilang)
docker compose down -v
```

## Troubleshooting

Lihat `TROUBLESHOOTING.md` kalau ada masalah.

## Resource Footprint

Idle: ~1.2-1.8 GB RAM, <5% CPU
Under load: ~2.5-3.5 GB RAM, 10-20% CPU
Disk growth: ~500MB-2GB per hari (tergantung volume log)

Retention default: 14 hari (logs), 30 hari (metrics). Bisa diubah di `.env`.
