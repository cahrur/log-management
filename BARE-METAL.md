# Bare Metal & Non-Docker Guide

Pantra utamanya jalan di Docker, tapi app lu **gak harus** di Docker buat kirim log & metrics ke Pantra. Panduan ini cover cara konek app yang jalan langsung di server (bare metal, systemd, PM2, supervisor, dll).

## Kapan Pake Panduan Ini?

- App lu jalan langsung di server (bukan container)
- Laravel/PHP via `php-fpm` + nginx
- Go binary yang di-manage systemd
- Node.js via PM2 atau systemd
- Python via gunicorn/uvicorn + supervisor
- Java JAR langsung
- Legacy app yang gak bisa di-containerize

## Arsitektur (Non-Docker)

```
Server (bare metal / VM)
+------------------------------------------+
|                                          |
|  [App: Laravel]  [App: Go API]           |
|       |               |                  |
|       v               v                  |
|  /var/log/app1.log   stdout (journald)   |
|       |               |                  |
|       +-------+-------+                  |
|               |                          |
|               v                          |
|       [Promtail agent]                   |
|               |                          |
|               | push                     |
+---------------|--------------------------|
                v
        [Pantra VPS: Loki]
```

---

## Skenario 1: App Log ke File

Cocok buat: Laravel, PHP-FPM, nginx, Apache, legacy apps.

### Install Promtail (tanpa Docker)

```bash
# Download binary Promtail
PROMTAIL_VERSION="3.3.2"
curl -LO "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"
unzip promtail-linux-amd64.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
sudo chmod +x /usr/local/bin/promtail
```

### Config Promtail

```bash
sudo mkdir -p /etc/promtail
sudo nano /etc/promtail/config.yaml
```

Isi `/etc/promtail/config.yaml`:

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://PANTRA_VPS_IP:3100/loki/api/v1/push
    batchwait: 1s
    batchsize: 1048576

scrape_configs:
  # Laravel / PHP logs
  - job_name: laravel
    static_configs:
      - targets: [localhost]
        labels:
          job: laravel
          app: myapp
          team: tim1
          host: server-name
          __path__: /var/www/myapp/storage/logs/*.log

  # Nginx access & error logs
  - job_name: nginx
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx
          host: server-name
          __path__: /var/log/nginx/*.log

  # Custom app logs (Go, Node, Python yang log ke file)
  - job_name: app-logs
    static_configs:
      - targets: [localhost]
        labels:
          job: app
          app: my-go-api
          team: tim2
          host: server-name
          __path__: /var/log/myapp/*.log

    # Parse level dari isi log
    pipeline_stages:
      - regex:
          expression: '(?i)(?P<level>ERROR|ERR|FATAL|CRITICAL|WARN|WARNING|INFO|DEBUG|TRACE)'
      - labels:
          level:

### Systemd Service buat Promtail

```bash
sudo nano /etc/systemd/system/promtail.service
```

```ini
[Unit]
Description=Promtail Log Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo mkdir -p /var/lib/promtail
sudo systemctl daemon-reload
sudo systemctl enable --now promtail
sudo systemctl status promtail
```

---

## Skenario 2: App Log ke Journald (systemd)

Cocok buat: Go binary, Node.js via systemd, Python gunicorn, Java JAR.

Kalau app lu di-manage systemd, log otomatis masuk journald. Promtail bisa baca langsung dari journal:

Tambahin di `/etc/promtail/config.yaml`:

```yaml
scrape_configs:
  # ... file-based jobs di atas ...

  # Systemd journal (Go, Node, Python services)
  - job_name: journal
    journal:
      max_age: 12h
      labels:
        job: systemd
        host: server-name
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
      - source_labels: ['__journal__hostname']
        target_label: 'hostname'
    pipeline_stages:
      - regex:
          expression: '(?i)(?P<level>ERROR|ERR|FATAL|CRITICAL|WARN|WARNING|INFO|DEBUG|TRACE)'
      - labels:
          level:
```

Restart Promtail: `sudo systemctl restart promtail`

Di Grafana query: `{job="systemd", unit="my-go-api.service"}`

---

## Skenario 3: App Kirim Log via Syslog

Cocok buat: legacy apps, network devices, apps yang cuma support syslog output.

Tambahin di Promtail config:

```yaml
scrape_configs:
  - job_name: syslog
    syslog:
      listen_address: 0.0.0.0:1514
      labels:
        job: syslog
        host: server-name
    relabel_configs:
      - source_labels: ['__syslog_message_hostname']
        target_label: 'hostname'
      - source_labels: ['__syslog_message_app_name']
        target_label: 'app'
```

Arahkan app lu kirim syslog ke `localhost:1514`.

---

## Metrics: node-exporter Tanpa Docker

```bash
NODE_EXPORTER_VERSION="1.8.2"
curl -LO "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/node_exporter
```

Systemd service:

```ini
[Unit]
Description=Node Exporter
After=network-online.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
# Verify: curl http://localhost:9100/metrics
```

Tambahin di Prometheus config (VPS Pantra):

```yaml
scrape_configs:
  - job_name: 'node-bare-metal'
    static_configs:
      - targets: ['BARE_METAL_IP:9100']
        labels:
          host: 'my-server'
```

---

## Contoh per Framework

### Laravel (PHP)

Laravel default log ke `storage/logs/laravel.log`. Promtail otomatis baca kalau path udah diset.

**Recommended: JSON log format**

Edit `config/logging.php`:

```php
'channels' => [
    'daily' => [
        'driver' => 'daily',
        'path' => storage_path('logs/laravel.log'),
        'level' => env('LOG_LEVEL', 'debug'),
        'days' => 7,
        'formatter' => Monolog\Formatter\JsonFormatter::class,
    ],
],
```

Atau log ke stderr (biar kebaca journald kalau pake systemd):

```php
'channels' => [
    'stderr' => [
        'driver' => 'monolog',
        'level' => env('LOG_LEVEL', 'debug'),
        'handler' => Monolog\Handler\StreamHandler::class,
        'formatter' => Monolog\Formatter\JsonFormatter::class,
        'with' => ['stream' => 'php://stderr'],
    ],
],
```

Set di `.env`: `LOG_CHANNEL=stderr` (kalau pake systemd) atau `LOG_CHANNEL=daily` (kalau pake file).

Query di Grafana:
```
{job="laravel", app="myapp"} | json | level="ERROR"
{job="laravel"} |= "SQLSTATE"
```

---

### Go

Go binary biasanya di-manage systemd. Log ke stdout/stderr otomatis masuk journald.

**Recommended: structured logging (slog)**

```go
package main

import (
    "log/slog"
    "os"
)

func main() {
    logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
    slog.SetDefault(logger)

    slog.Info("server started", "port", 8080)
    slog.Error("db connection failed", "err", err, "host", dbHost)
}
```

Systemd unit buat Go app:

```ini
[Unit]
Description=My Go API
After=network-online.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/myapp
ExecStart=/opt/myapp/server
Restart=always
RestartSec=5
Environment=PORT=8080
Environment=DB_HOST=localhost

[Install]
WantedBy=multi-user.target
```

Query di Grafana:
```
{job="systemd", unit="myapp.service"} | json | level="error"
```

---

### Node.js (PM2 / systemd)

**Opsi A: PM2 (log ke file)**

```bash
pm2 start app.js --name myapp --log /var/log/myapp/app.log --log-type json
```

Promtail config:
```yaml
- job_name: nodejs
  static_configs:
    - targets: [localhost]
      labels:
        job: nodejs
        app: myapp
        __path__: /var/log/myapp/*.log
```

**Opsi B: systemd (log ke journald)**

```ini
[Unit]
Description=Node.js App
After=network-online.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/myapp
ExecStart=/usr/bin/node /opt/myapp/index.js
Restart=always
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
```

**Recommended: pino logger (JSON)**

```js
const pino = require('pino')();

pino.info({ user_id: 42, endpoint: '/api/users' }, 'request handled');
pino.error({ err, query: sql }, 'database timeout');
```

---

### Python (gunicorn / uvicorn)

**Opsi A: gunicorn + systemd**

```ini
[Unit]
Description=Gunicorn Python App
After=network-online.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/myapp
ExecStart=/opt/myapp/venv/bin/gunicorn app:app -w 4 -b 0.0.0.0:8000 --access-logfile - --error-logfile -
Restart=always

[Install]
WantedBy=multi-user.target
```

`--access-logfile -` dan `--error-logfile -` = log ke stdout/stderr = masuk journald.

**Recommended: structlog / loguru (JSON)**

```python
from loguru import logger
import sys

# JSON output ke stdout
logger.remove()
logger.add(sys.stdout, serialize=True)

logger.info("request handled", user_id=42, endpoint="/api/users")
logger.error("database timeout", query=sql, duration_ms=3500)
```

---

### Java / Spring Boot

**Systemd unit:**

```ini
[Unit]
Description=Spring Boot App
After=network-online.target

[Service]
Type=simple
User=www-data
ExecStart=/usr/bin/java -jar /opt/myapp/app.jar
Restart=always
Environment=SPRING_PROFILES_ACTIVE=production

[Install]
WantedBy=multi-user.target
```

**JSON log (logback):**

`application.yml`:
```yaml
logging:
  pattern:
    console: '{"level":"%level","ts":"%d{yyyy-MM-dd''T''HH:mm:ss.SSSXXX}","logger":"%logger{36}","msg":"%msg"}%n'
```

Atau pake `logstash-logback-encoder` buat proper JSON.

---

## Verifikasi

Setelah setup, cek:

1. **Promtail jalan:**
   ```bash
   sudo systemctl status promtail
   curl http://localhost:9080/targets
   ```

2. **node-exporter jalan:**
   ```bash
   curl http://localhost:9100/metrics | head -20
   ```

3. **Di Grafana (VPS Pantra):**
   - Explore > Loki > `{host="my-server"}` -- ada log?
   - Explore > Prometheus > `up{host="my-server"}` -- value 1?

4. **Dashboard:**
   - Host Overview: server bare metal keliatan?
   - Logs Explorer: filter host, app, level

---

## Tips

- **Log rotation:** Promtail handle file rotation otomatis (detect inode change). Tapi tetep set logrotate di server biar disk gak meledak.
- **Firewall:** node-exporter port 9100 jangan public. Whitelist IP Pantra VPS aja, atau pake Tailscale.
- **Multiple apps:** tambahin job baru di Promtail config per app. Restart Promtail setelah edit.
- **Performance:** Promtail binary cuma makan ~30-50MB RAM. node-exporter ~15MB. Ringan banget.
