# Log Management Stack — Dealtech

Stack observability all-in-one buat dealtech-code dan project lain. 100% open source, gak ada biaya lisensi.

## 📚 Dokumentasi

| File | Isi |
|---|---|
| **README.md** (kamu di sini) | Overview, install, arsitektur |
| **[INTEGRATION.md](INTEGRATION.md)** | **Cara konek dealtech-code & app lain ke stack ini** (per bahasa, multi-VPS, multi-tim) |
| **[SECURITY.md](SECURITY.md)** | Security policy, threat model, port binding, disclosure |
| **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** | Solusi error umum |
| **[LICENSE](LICENSE)** | MIT License |
| **[agent/README.md](agent/README.md)** | Template label & contoh `docker-compose.yml` buat app |

## ⚠️ Sebelum Deploy

Stack ini **AS-IS** under MIT License. Lu wajib baca [SECURITY.md](SECURITY.md) buat tau:

- Port mana yang aman public, mana yang harus localhost-only
- Cara akses Prometheus/Alertmanager via SSH tunnel
- Threat model & known security considerations

Default sekarang: cuma Grafana (port 3000) yang accessible dari luar. Prometheus/Alertmanager/cAdvisor bind ke `127.0.0.1`. Mau ubah? Set `*_BIND=0.0.0.0` di `.env` (tapi pasang reverse proxy + auth dulu).

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
# 1. SSH ke VPS
ssh user@VPS_IP

# 2. Clone repo ke /opt
sudo git clone https://github.com/cahrur/log-management.git /opt/log-management
sudo chown -R $USER:$USER /opt/log-management
cd /opt/log-management

# 3. Setup environment
cp .env.example .env
nano .env   # ganti GRAFANA_ADMIN_PASSWORD (wajib), Telegram token (opsional)

# 4. Jalanin installer
chmod +x install.sh
./install.sh

# 5. Buka di browser (HARUS dari laptop, bukan public)
# Grafana:      http://VPS_IP:3000   (public OK, ada login)
#
# Service localhost-only - akses via SSH tunnel:
# ssh -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 -L 8080:127.0.0.1:8080 user@VPS_IP
# Lalu buka di browser laptop:
# Prometheus:   http://localhost:9090
# Alertmanager: http://localhost:9093
# cAdvisor:     http://localhost:8080
```

## Update ke versi terbaru

```bash
cd /opt/log-management
git pull
docker compose pull
docker compose up -d
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

## 🔌 Konek App ke Stack Ini

Udah install stack-nya tapi belum tau cara nyambungin app (dealtech-code, tim-1..4, atau aplikasi lain)?

**Singkatnya:** kasih label `logging=promtail` di container app lu, terus restart Promtail. Selesai.

```yaml
# docker-compose.yml app lu (contoh dealtech-code tim 1)
services:
  tim1-app:
    image: ghcr.io/youruser/dealtech-tim1:latest
    labels:
      - "logging=promtail"          # WAJIB - opt-in ke log scraping
      - "team=tim1"                 # opsional - filter per tim
      - "project=dealtech-code"     # opsional
      - "service=api"               # opsional
```

Di Grafana → **Explore → Loki**, query `{container="tim1-app"}` — log lu udah masuk.

### Skenario yang dicover di [INTEGRATION.md](INTEGRATION.md):

- ✅ **App di VPS yang sama** dengan stack — tinggal label
- ✅ **App di VPS berbeda** — install Promtail + node-exporter + cAdvisor agent, push log/metrics ke VPS observability (pake Tailscale/WireGuard biar aman)
- ✅ **Multi-tim isolation** — pattern label `team=` + user terpisah di Grafana per tim
- ✅ **Best practice logging** — log ke stdout, format JSON, log rotation
- ✅ **Contoh kode per bahasa** — Node.js (pino/winston), Python (loguru/structlog), PHP/Laravel (monolog), Go (slog), Java/Spring (logback JSON)
- ✅ **Verifikasi & debugging** — checklist setelah konek + cara cek log/metric kebaca

📖 **Baca lengkap:** [INTEGRATION.md](INTEGRATION.md)

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
