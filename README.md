# Pantra ⚡

> **Pan**tau + **tra**cker — observability stack siap-deploy buat self-hosted infra.
> Tau apa yang lagi terjadi di server lu, dari log sampai resource usage, tanpa bayar lisensi sepeserpun.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docker Compose](https://img.shields.io/badge/Docker-Compose%20v2-blue)](https://docs.docker.com/compose/)
[![Status: Beta](https://img.shields.io/badge/status-beta-orange)]()

Pantra ngumpulin **log + metrics + alert** dari semua container Docker lu, dalam satu stack yang tinggal `git clone` & `./install.sh`. Dirancang buat tim yang butuh observability serius tanpa biaya cloud SaaS.

## 🤔 Apa itu Pantra?

Bayangin server lu lagi lemot, container ada yang restart-restart sendiri, atau user complain error tapi lu gak tau penyebabnya. Lu butuh **3 hal** sekaligus:

1. **Log** — apa yang app lu print sebelum crash?
2. **Metrics** — CPU/RAM/disk lagi berapa? Container mana yang paling boros?
3. **Alert** — dapet notif duluan sebelum user yang complain

Biasanya buat dapet 3 itu, lu harus:
- Bayar Datadog/New Relic ($$$ tiap bulan)
- Atau setup manual: install Loki, Prometheus, Grafana, Alertmanager, cAdvisor, node-exporter, bikin config-nya satu-satu, bikin dashboard dari nol, tulis alert rule dari pengalaman — **butuh 1-2 minggu**

**Pantra = jalan pintas.** Lu dapet semua itu **dalam 5 menit**, free, self-hosted, gak ada vendor lock-in.

```bash
git clone https://github.com/cahrur/pantra.git /opt/pantra
cd /opt/pantra && ./install.sh
# Selesai. Buka Grafana, dashboard udah jadi.
```

Pantra **bukan tool baru** — ini stack curated dari 7 proyek open-source kelas dunia (Loki, Prometheus, Grafana, dll), dipaket jadi satu **opinionated setup** yang udah validated buat kasus pemakaian umum: self-hosted infra dengan 1-50 container, multi-tim, multi-VPS.

Cocok buat: startup, dev team, indie hacker, tim engineer yang gak mau ribet observability tapi tetep pengen kontrol penuh atas data mereka.

## ✨ Fitur

- 🔍 **Log aggregation** — semua log masuk Loki, search pake LogQL di Grafana
- 📊 **Resource monitoring** — CPU/RAM/disk/network per host & per container, real-time
- 🚨 **Alerting** — 11 rule pre-built (CPU tinggi, OOM-kill, container restart loop, disk penuh, dll), kirim ke Telegram
- 🏷️ **Multi-tim isolation** — pattern label `team=` buat misahin dashboard per tim
- 🌐 **Multi-VPS** — agent ringan (~150MB RAM) buat ngirim log/metric dari VPS lain
- 🔒 **Secure default** — port sensitif bind ke `127.0.0.1`, akses via SSH tunnel
- 🐳 **Docker & Non-Docker** — container pake label, bare metal pake Promtail binary + systemd
- 🛠️ **Framework-ready** — panduan lengkap buat Laravel, Go, Node.js, Python, Java/Spring
- 📡 **Multi-source** — file log, journald, syslog, stdout — semua bisa masuk Pantra

## 📚 Dokumentasi

| File | Isi |
|---|---|
| **README.md** (kamu di sini) | Overview, install, arsitektur |
| **[INTEGRATION.md](INTEGRATION.md)** | **Cara konek app Docker ke Pantra** (label, multi-VPS, multi-tim) |
| **[BARE-METAL.md](BARE-METAL.md)** | **Cara konek app non-Docker** (Laravel, Go, Node.js, Python, Java, systemd, syslog) |
| **[SHARED-HOSTING.md](SHARED-HOSTING.md)** | **Cara konek app dari shared hosting** (push via Loki API, tanpa root/Docker) |
| **[SECURITY.md](SECURITY.md)** | Security policy, threat model, port binding, disclosure |
| **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** | Solusi error umum |
| **[examples/](examples/)** | **Ready-to-use config** buat Laravel, Go, Node.js, Python, Java Spring, Nginx |
| **[LICENSE](LICENSE)** | MIT License |
| **[agent/README.md](agent/README.md)** | Template label & contoh `docker-compose.yml` buat app |

## 🧰 CLI Tools

Pantra dateng dengan beberapa script otomasi:

| Script | Fungsi | Target |
|---|---|---|
| `install.sh` | Install Pantra stack (Docker) | VPS utama |
| `bare-metal-install.sh` | Install Promtail + node-exporter tanpa Docker | Server app (bare metal) |
| `remote-agent-install.sh` | Install monitoring agent di VPS lain | VPS remote |
| `pantra-check.sh` | Health check semua service + status report | VPS utama |
| `uninstall.sh` | Clean uninstall (Docker / bare metal) | Any |

```bash
# Health check (jalanin kapan aja buat cek status)
./pantra-check.sh

# Install agent di VPS remote
scp remote-agent-install.sh user@REMOTE_VPS:/tmp/
ssh user@REMOTE_VPS 'chmod +x /tmp/remote-agent-install.sh && /tmp/remote-agent-install.sh'

# Install bare metal (tanpa Docker)
scp bare-metal-install.sh user@APP_SERVER:/tmp/
ssh user@APP_SERVER 'chmod +x /tmp/bare-metal-install.sh && /tmp/bare-metal-install.sh'
```

## ⚠️ Sebelum Deploy

Pantra **AS-IS** under MIT License. Lu wajib baca [SECURITY.md](SECURITY.md) buat tau:

- Port mana yang aman public, mana yang harus localhost-only
- Cara akses Prometheus/Alertmanager via SSH tunnel
- Threat model & known security considerations

Default sekarang: cuma Grafana (port 3000) yang accessible dari luar. Prometheus/Alertmanager/cAdvisor bind ke `127.0.0.1`. Mau ubah? Set `*_BIND=0.0.0.0` di `.env` (tapi pasang reverse proxy + auth dulu).

## 🧩 Komponen

| Service | Fungsi | Port (default bind) |
|---|---|---|
| **Grafana** | Dashboard UI (logs + metrics) | `0.0.0.0:3000` |
| **Loki** | Log aggregation & storage | internal only |
| **Promtail** | Log shipper dari Docker container | internal only |
| **Prometheus** | Metrics storage & query | `127.0.0.1:9090` |
| **node-exporter** | Host metrics (CPU/RAM/disk/net) | internal only |
| **cAdvisor** | Per-container metrics | `127.0.0.1:8080` |
| **Alertmanager** | Alert routing → Telegram | `127.0.0.1:9093` |

## 🚀 Quick Start (di VPS)

```bash
# 1. SSH ke VPS
ssh user@VPS_IP

# 2. Clone repo ke /opt
sudo git clone https://github.com/cahrur/pantra.git /opt/pantra
sudo chown -R $USER:$USER /opt/pantra
cd /opt/pantra

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

## ♻️ Update ke versi terbaru

```bash
cd /opt/pantra
git pull
docker compose pull
docker compose up -d
```

## 🏗️ Arsitektur

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
│  │ (any project,    │   │ Grafana │◀──user        │
│  │  multi-tim ok)   │   └────▲────┘                │
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

## 🔌 Konek App ke Pantra

Pantra support **Docker & non-Docker**. Pilih panduan sesuai setup lu:

| Setup App Lu | Panduan | Effort |
|---|---|---|
| Docker container | [INTEGRATION.md](INTEGRATION.md) | 1 menit (tambahin label) |
| Bare metal / systemd / PM2 | [BARE-METAL.md](BARE-METAL.md) | 5-10 menit (install Promtail binary) |
| Multi-VPS (Docker) | [INTEGRATION.md → Skenario 2](INTEGRATION.md#skenario-2-app-di-vps-berbeda) | 10 menit |
| Multi-VPS (bare metal) | [BARE-METAL.md](BARE-METAL.md) | 10 menit |
| Shared hosting (cPanel/Plesk) | [SHARED-HOSTING.md](SHARED-HOSTING.md) | 10-15 menit (push via Loki API) |

### Quick example (Docker):

```yaml
services:
  myapp:
    labels:
      - "logging=promtail"
      - "team=tim1"
```

### Quick example (Non-Docker / bare metal):

```bash
# Install Promtail binary di server app
curl -LO https://github.com/grafana/loki/releases/download/v3.3.2/promtail-linux-amd64.zip
unzip promtail-linux-amd64.zip && sudo mv promtail-linux-amd64 /usr/local/bin/promtail
# Config: point ke file log app + Pantra VPS IP
sudo systemctl enable --now promtail
```

### Framework yang udah ada panduannya:

| Framework | Docker | Bare Metal | Log Format |
|---|---|---|---|
| **Laravel / PHP** | [INTEGRATION.md](INTEGRATION.md) | [BARE-METAL.md](BARE-METAL.md#laravel-php) | Monolog JSON |
| **Go** | [INTEGRATION.md](INTEGRATION.md) | [BARE-METAL.md](BARE-METAL.md#go) | slog JSON |
| **Node.js** | [INTEGRATION.md](INTEGRATION.md) | [BARE-METAL.md](BARE-METAL.md#nodejs-pm2--systemd) | pino JSON |
| **Python** | [INTEGRATION.md](INTEGRATION.md) | [BARE-METAL.md](BARE-METAL.md#python-gunicorn--uvicorn) | loguru JSON |
| **Java / Spring** | [INTEGRATION.md](INTEGRATION.md) | [BARE-METAL.md](BARE-METAL.md#java--spring-boot) | logback JSON |
| **Nginx / Apache** | auto (Docker log) | [BARE-METAL.md](BARE-METAL.md#skenario-1-app-log-ke-file) | access log |
| **Syslog devices** | — | [BARE-METAL.md](BARE-METAL.md#skenario-3-app-kirim-log-via-syslog) | syslog |
| **Any (shared hosting)** | [SHARED-HOSTING.md](SHARED-HOSTING.md) | [SHARED-HOSTING.md](SHARED-HOSTING.md) | Any JSON |

Di Grafana → **Explore → Loki**, query `{host="my-server"}` atau `{app="myapp"}` — log lu udah masuk.

## 🔧 Maintenance

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

## 🆘 Troubleshooting

Lihat [TROUBLESHOOTING.md](TROUBLESHOOTING.md) kalau ada masalah.

## 💪 Resource Footprint

- **Idle:** ~1.2-1.8 GB RAM, <5% CPU
- **Under load:** ~2.5-3.5 GB RAM, 10-20% CPU
- **Disk growth:** ~500MB-2GB per hari (tergantung volume log)

Retention default: 14 hari (logs), 30 hari (metrics). Bisa diubah di `.env`.

---

## 🙏 Built On (Open-Source Stack)

Pantra **bukan tool yang nulis dari nol**. Pantra adalah **kurasi & integrasi** dari proyek open-source kelas dunia, dipaket jadi satu stack yang plug-and-play. Semua credit, ide, dan kerja keras ada di proyek-proyek di bawah ini:

### Core Components

| Project | License | Role | Upstream |
|---|---|---|---|
| **[Grafana](https://github.com/grafana/grafana)** | AGPL-3.0 | Dashboard & visualization UI | grafana/grafana |
| **[Loki](https://github.com/grafana/loki)** | AGPL-3.0 | Log aggregation system | grafana/loki |
| **[Promtail](https://github.com/grafana/loki/tree/main/clients/cmd/promtail)** | Apache-2.0 | Log shipper agent | grafana/loki |
| **[Prometheus](https://github.com/prometheus/prometheus)** | Apache-2.0 | Time-series metrics database | prometheus/prometheus |
| **[Alertmanager](https://github.com/prometheus/alertmanager)** | Apache-2.0 | Alert routing & deduplication | prometheus/alertmanager |
| **[node-exporter](https://github.com/prometheus/node_exporter)** | Apache-2.0 | Host hardware metrics | prometheus/node_exporter |
| **[cAdvisor](https://github.com/google/cadvisor)** | Apache-2.0 | Container resource analyzer | google/cadvisor |

### Yang Pantra Tambahin

Pantra sendiri **gak nulis ulang** komponen di atas. Yang Pantra kasih:

- ✍️ **Opinionated config** — tuning yang udah dicoba buat self-hosted scale (1-50 container)
- 🎨 **3 dashboard pre-loaded** — Host Overview, Container Metrics, Logs Explorer (siap pakai, gak perlu setup manual)
- 🚨 **11 alert rule pre-built** — best practice yang udah validated (CPU/RAM/disk/OOM/restart-loop)
- 🏷️ **Multi-tim labeling pattern** — konvensi `team=` + `project=` + `service=` buat isolasi
- 🔒 **Secure-by-default port binding** — service tanpa auth otomatis bind `127.0.0.1`
- 📦 **One-command installer** — `install.sh` validate config, generate alertmanager template, pull image, start stack
- 📖 **Dokumentasi bahasa Indonesia** — INTEGRATION/SECURITY/TROUBLESHOOTING dalam bahasa yang gampang dipahamin
- 🤖 **Auto-discovery via Docker labels** — label `logging=promtail` doang, Promtail auto-scrape

### Lisensi & Atribusi

- Pantra (orchestration, config, docs, dashboards): **MIT License** (lihat [LICENSE](LICENSE))
- Image upstream tetap pake lisensi masing-masing (AGPL/Apache-2.0). Kalau lu fork & redistribute Pantra, lu wajib comply dengan lisensi upstream image yang lu pake.
- AGPL note: Loki & Grafana AGPL-3.0 berlaku ke kode mereka. Pantra cuma orchestrate via Docker image — lu **tidak** wajib open-source app lu yang konek ke stack ini.

### Inspirasi

- [Grafana's official docker-compose example](https://github.com/grafana/loki/tree/main/production/docker)
- [stefanprodan/dockprom](https://github.com/stefanprodan/dockprom) — popular reference implementation
- [Cloudprober](https://github.com/cloudprober/cloudprober) — buat alert rule patterns

Terima kasih ke maintainer & contributor proyek-proyek di atas. Tanpa mereka, Pantra gak ada.

---

## 🤝 Contributing

Pantra masih beta. Kontribusi welcome:

- Bug report → [Issues](https://github.com/cahrur/pantra/issues)
- Pull request → branch `main`, jelasin di PR description ngapain
- Security report → baca [SECURITY.md](SECURITY.md) dulu, jangan public issue

## 📜 License

[MIT License](LICENSE) — bebas dipake commercial, modifikasi, distribusi. Tanpa warranty.

---

**⚡ Pantra — observability buat self-hosted, tanpa cloud bill, tanpa drama.**
