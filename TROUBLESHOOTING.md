# Troubleshooting

## Service gak start

```bash
# Cek status
docker compose ps

# Cek log per service
docker compose logs loki
docker compose logs promtail
docker compose logs grafana
docker compose logs prometheus
```

### Loki: "permission denied" / cannot create directory

Volume Loki butuh user 10001:10001. Stack udah ngehandle dengan `user: "10001:10001"` di compose. Kalau masih error:

```bash
docker compose down
docker volume rm log-management_loki_data
docker compose up -d
```

### Promtail: "cannot connect to docker socket"

Pastiin user yang jalanin docker compose punya akses ke `/var/run/docker.sock`:

```bash
sudo usermod -aG docker $USER
# Logout-login ulang
```

### Prometheus: "rule files no match"

Kalau lu hapus folder `prometheus/rules/`, hapus juga line `rule_files` di `prometheus.yml`. Atau biarin folder kosongnya.

## Grafana login gagal

Default user `admin`, password dari `.env` (`GRAFANA_ADMIN_PASSWORD`).

Kalau lupa password, reset:

```bash
docker compose exec grafana grafana-cli admin reset-admin-password newpassword
```

## Log gak muncul di Grafana

1. Cek Promtail running: `docker compose ps promtail`
2. Cek targets: `docker compose logs promtail | grep -i target`
3. Cek di Grafana → Explore → Loki → query `{job="docker"}` (range 15 menit)
4. Pastiin app container lu punya label `logging=promtail`:

```yaml
labels:
  - "logging=promtail"
```

Atau matiin filter di `promtail-config.yaml` (komentari blok `relabel_configs` yang `keep`):

```yaml
# - source_labels: ['__meta_docker_container_label_logging']
#   regex: 'promtail'
#   action: keep
```

Lalu restart: `docker compose restart promtail`

## Metrics container gak ada

cAdvisor butuh privileged + akses cgroup. Kalau VPS lu di OpenVZ/LXC (bukan KVM), cAdvisor bisa gak jalan benar. Provider yang OK: Hetzner, Contabo (KVM), DigitalOcean, Vultr.

Cek: `docker compose logs cadvisor | grep -i error`

## Disk cepat penuh

```bash
# Cek volume size
docker system df -v | grep -E "loki|prometheus"

# Kurangi retention di .env
LOKI_RETENTION_HOURS=168h    # 7 hari
PROMETHEUS_RETENTION=15d

# Restart
docker compose up -d
```

Kalau mau hapus data lama manual:

```bash
docker compose stop loki
docker run --rm -v log-management_loki_data:/data alpine sh -c 'rm -rf /data/chunks/*'
docker compose start loki
```

## Alertmanager gak kirim Telegram

1. Cek bot token valid: `curl https://api.telegram.org/bot<TOKEN>/getMe`
2. Cek chat_id bener: chat sama bot dulu, terus `curl https://api.telegram.org/bot<TOKEN>/getUpdates`
3. Cek log: `docker compose logs alertmanager`
4. Test alert manual:

```bash
curl -XPOST http://localhost:9093/api/v1/alerts -H "Content-Type: application/json" -d '[
  {
    "labels": {"alertname":"TestAlert","severity":"warning","instance":"test"},
    "annotations": {"summary":"Test","description":"Manual test alert"}
  }
]'
```

## High RAM / OOM

Default sizing aman buat VPS 4GB+. Kalau lu di VPS 2GB, tambah resource limit di compose:

```yaml
services:
  loki:
    deploy:
      resources:
        limits:
          memory: 512M
  prometheus:
    deploy:
      resources:
        limits:
          memory: 512M
  grafana:
    deploy:
      resources:
        limits:
          memory: 256M
```

Atau matiin yang gak kepake — misal `cadvisor` kalau lu cuma butuh log:

```bash
docker compose stop cadvisor
docker compose rm cadvisor
```

## Reset total

```bash
docker compose down -v       # hapus volume juga (data ilang!)
rm -rf data/
./install.sh
```

## Update versi

```bash
docker compose pull
docker compose up -d
```

Kalau ada breaking change versi mayor, cek release notes:

- Loki: https://github.com/grafana/loki/releases
- Prometheus: https://github.com/prometheus/prometheus/releases
- Grafana: https://github.com/grafana/grafana/releases

## Backup

Backup volume Docker:

```bash
# Backup
docker run --rm \
  -v log-management_grafana_data:/data \
  -v $PWD/backups:/backup \
  alpine tar czf /backup/grafana-$(date +%F).tar.gz -C /data .

# Restore
docker run --rm \
  -v log-management_grafana_data:/data \
  -v $PWD/backups:/backup \
  alpine sh -c "rm -rf /data/* && tar xzf /backup/grafana-2026-05-27.tar.gz -C /data"
```

Kalau masih stuck, copy log error ke gua.
