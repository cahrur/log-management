# Integration Guide

Panduan menghubungkan app (dealtech-code, tim-1..4, atau aplikasi lain) ke stack ini.

## TL;DR

Stack ini ngumpulin **2 hal** dari app lu:

1. **Logs** — apapun yang app lu print ke `stdout`/`stderr`. Promtail otomatis nyedot dari Docker log driver.
2. **Metrics** — CPU, RAM, network, disk per container. cAdvisor otomatis baca dari Docker engine. Nol kode di app lu.

Yang lu perlu lakuin: **pasang label di container app** + (opsional) **konek ke network observability**.

---

## Skenario 1: App di VPS yang SAMA dengan stack ini

### Langkah 1 — Pasang label di docker-compose.yml app lu

```yaml
services:
  myapp:
    image: ghcr.io/youruser/myapp:latest
    # ... config lain ...
    labels:
      - "logging=promtail"          # WAJIB — opt-in ke log scraping
      - "team=tim1"                 # opsional — buat filter di Grafana
      - "project=dealtech-code"     # opsional
      - "service=api"               # opsional
```

### Langkah 2 — Restart Promtail (kalau sebelumnya udah jalan)

```bash
cd /opt/log-management
docker compose restart promtail
```

### Langkah 3 — Verifikasi di Grafana

Buka Grafana → **Explore** → pilih datasource **Loki** → query:

```
{container="myapp"}
```

Atau buka dashboard **Logs Explorer** dan filter pake variable `Container`.

**Selesai.** Logs udah masuk. Metrics container otomatis kebaca cAdvisor.

---

## Skenario 2: App di VPS BERBEDA

Kalau app lu jalan di VPS lain (misal observability di VPS-A, dealtech-code di VPS-B), lu perlu install Promtail agent di VPS-B yang push log ke Loki di VPS-A.

### Arsitektur

```
VPS-B (app)                        VPS-A (observability)
┌─────────────────┐                ┌────────────────────┐
│ container1..N   │                │  Loki  ◀──────┐    │
│ Promtail-agent  │──HTTPS push────▶│  Prometheus   │    │
│ node-exporter   │──remote_write─▶│  Grafana      │    │
│ cAdvisor        │──scrape pull──▶│               │    │
└─────────────────┘                └────────────────────┘
```

### Langkah 1 — Buka port di VPS-A (observability)

Port 3100 (Loki) dan 9090 (Prometheus) **JANGAN** dibuka public. Pake satu dari pilihan ini:

**A. Tailscale / WireGuard (RECOMMENDED)**
```bash
# Di kedua VPS
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```
Pake Tailscale IP buat komunikasi internal. Aman, gak perlu buka port di firewall.

**B. UFW whitelist by IP**
```bash
# Di VPS-A
sudo ufw allow from VPS_B_IP to any port 3100 proto tcp
sudo ufw allow from VPS_B_IP to any port 9090 proto tcp
```

**C. Reverse proxy + Basic Auth** (kalau public unavoidable)
Pake Caddy/nginx di depan Loki dengan username/password.

### Langkah 2 — Expose Loki di VPS-A

Edit `docker-compose.yml` di VPS-A, tambahin port mapping Loki:

```yaml
loki:
  # ... config lain ...
  ports:
    - "3100:3100"   # tambahin baris ini
```

Restart: `docker compose up -d loki`

### Langkah 3 — Install Promtail di VPS-B

Bikin folder `/opt/promtail-agent/` di VPS-B, isinya:

**`/opt/promtail-agent/promtail-config.yaml`**:
```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  # Ganti IP dengan Tailscale IP atau public IP VPS-A
  - url: http://VPS_A_IP:3100/loki/api/v1/push
    batchwait: 1s
    batchsize: 1048576

scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_label_logging']
        regex: 'promtail'
        action: keep
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container'
      - source_labels: ['__meta_docker_container_label_team']
        target_label: 'team'
      - source_labels: ['__meta_docker_container_label_project']
        target_label: 'project'
      - target_label: 'host'
        replacement: 'vps-b'      # ganti sesuai nama VPS
      - target_label: 'job'
        replacement: 'docker'
    pipeline_stages:
      - json:
          expressions:
            stream: stream
            log: log
            time: time
      - timestamp:
          source: time
          format: RFC3339Nano
      - output:
          source: log
      - match:
          selector: '{job="docker"}'
          stages:
            - regex:
                expression: '(?i)(?P<level>ERROR|ERR|FATAL|CRITICAL|WARN|WARNING|INFO|DEBUG|TRACE)'
            - labels:
                level:
```

**`/opt/promtail-agent/docker-compose.yml`**:
```yaml
services:
  promtail:
    image: grafana/promtail:3.3.2
    container_name: promtail-agent
    restart: unless-stopped
    command: -config.file=/etc/promtail/promtail-config.yaml
    volumes:
      - ./promtail-config.yaml:/etc/promtail/promtail-config.yaml:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - promtail_positions:/tmp

volumes:
  promtail_positions:
```

Jalanin: `cd /opt/promtail-agent && docker compose up -d`

### Langkah 4 — Install node-exporter + cAdvisor di VPS-B

Buat metrics, install agent metrics di VPS-B:

**`/opt/metrics-agent/docker-compose.yml`**:
```yaml
services:
  node-exporter:
    image: prom/node-exporter:v1.8.2
    container_name: node-exporter
    restart: unless-stopped
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    ports:
      - "9100:9100"
    pid: host

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    container_name: cadvisor
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
    command:
      - '--housekeeping_interval=30s'
      - '--docker_only=true'
```

Jalanin: `cd /opt/metrics-agent && docker compose up -d`

### Langkah 5 — Tambahin VPS-B di Prometheus VPS-A

Di VPS-A, edit `prometheus/prometheus.yml`, tambahin:

```yaml
scrape_configs:
  # ... yang udah ada ...

  - job_name: 'node-vps-b'
    static_configs:
      - targets: ['VPS_B_IP:9100']
        labels:
          host: 'vps-b'

  - job_name: 'cadvisor-vps-b'
    static_configs:
      - targets: ['VPS_B_IP:8080']
        labels:
          host: 'vps-b'
```

Reload Prometheus tanpa restart:
```bash
curl -X POST http://localhost:9090/-/reload
```

Cek di Prometheus UI → **Status** → **Targets**, harusnya `vps-b` jadi `UP`.

---

## Best Practice: Cara Logging yang Bener

### 1. Selalu log ke stdout/stderr, JANGAN ke file

Container app **harus** log ke stdout/stderr. Docker auto-capture, Promtail otomatis baca. Kalau lu nulis ke file (misal `/var/log/app.log` di dalem container), log-nya bisa hilang pas container restart.

### 2. Format JSON (recommended)

Log JSON bisa di-parse di Loki, jadi lu bisa filter per field. Contoh:

```json
{"level":"error","ts":"2026-05-27T10:00:00Z","msg":"DB timeout","user_id":42,"endpoint":"/api/users","duration_ms":3500}
```

Di Grafana lu bisa query:
```
{container="myapp"} | json | level="error" | duration_ms > 1000
```

### 3. Konsisten level naming

Stack ini auto-detect level dari kata kunci: `ERROR`, `ERR`, `FATAL`, `CRITICAL`, `WARN`, `WARNING`, `INFO`, `DEBUG`, `TRACE`. Pake salah satu di message lu, bakal kebaca otomatis.

### 4. Set log rotation di Docker

Biar disk gak meledak, set `logging` driver di setiap service:

```yaml
services:
  myapp:
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

---

## Contoh per Bahasa

### Node.js / Express

```js
// server.js
const log = (level, msg, meta = {}) => {
  console.log(JSON.stringify({
    level,
    ts: new Date().toISOString(),
    msg,
    ...meta
  }));
};

app.get('/api/users', async (req, res) => {
  try {
    const users = await db.users.findMany();
    log('info', 'fetched users', { count: users.length });
    res.json(users);
  } catch (err) {
    log('error', 'DB error', { error: err.message, stack: err.stack });
    res.status(500).json({ error: 'internal' });
  }
});
```

Atau pake library: **pino** (paling cepet), **winston**, **bunyan**.

```js
const pino = require('pino')();
pino.info({ user_id: 42 }, 'user logged in');
pino.error({ err }, 'DB timeout');
```

### Python / FastAPI

```python
import logging
import json
import sys
from datetime import datetime

class JsonFormatter(logging.Formatter):
    def format(self, record):
        return json.dumps({
            "level": record.levelname,
            "ts": datetime.utcnow().isoformat() + "Z",
            "msg": record.getMessage(),
            "module": record.module,
        })

logger = logging.getLogger("app")
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
logger.addHandler(handler)
logger.setLevel(logging.INFO)

logger.info("server started", extra={"port": 8000})
logger.error("DB timeout", extra={"endpoint": "/api/users"})
```

Atau pake **structlog** / **loguru**:

```python
from loguru import logger
logger.add(sys.stdout, serialize=True)  # JSON output
logger.info("user logged in", user_id=42)
```

### PHP / Laravel

```php
// config/logging.php — gunakan stderr channel
'channels' => [
    'stderr' => [
        'driver' => 'monolog',
        'level'  => env('LOG_LEVEL', 'debug'),
        'handler' => Monolog\Handler\StreamHandler::class,
        'formatter' => Monolog\Formatter\JsonFormatter::class,
        'with' => ['stream' => 'php://stderr'],
    ],
],
```

Set di `.env`: `LOG_CHANNEL=stderr`

```php
Log::error('DB timeout', ['endpoint' => '/api/users', 'duration' => 3500]);
```

### Go

```go
import "log/slog"

logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
logger.Info("user logged in", "user_id", 42)
logger.Error("DB timeout", "endpoint", "/api/users", "err", err)
```

### Java / Spring Boot

`application.yml`:
```yaml
logging:
  pattern:
    console: '{"level":"%level","ts":"%d{yyyy-MM-dd''T''HH:mm:ss.SSSXXX}","logger":"%logger","msg":"%msg"}%n'
```

Atau pake **logstash-logback-encoder** buat JSON proper.

---

## Khusus dealtech-code (Multi-Tim)

Kalau setiap tim punya project sendiri, gunakan label `team` buat isolasi view:

```yaml
# Tim 1
services:
  api:
    labels:
      - "logging=promtail"
      - "team=tim1"
      - "project=dealtech-code"
      - "service=api"

# Tim 2
services:
  api:
    labels:
      - "logging=promtail"
      - "team=tim2"
      - "project=dealtech-code"
      - "service=api"
```

Di Grafana **Logs Explorer** dashboard, ada variable `Team` — pilih `tim1` doang, log dari tim lain ke-hide.

### Tip: Bikin user terpisah per tim di Grafana

1. Login Grafana sebagai admin
2. **Configuration → Users → Invite**
3. Bikin user `tim1`, role **Viewer**
4. Bikin folder dashboard `Tim 1/`, set permission folder cuma viewable sama user `tim1`
5. Ulangi buat tim lain

---

## Verifikasi Integrasi

Checklist setelah konek app:

- [ ] `docker compose ps` di VPS-app, container app status `Up`
- [ ] Container app punya label `logging=promtail`
- [ ] Di Grafana → Explore → Loki, query `{container="nama-app"}` ada hasilnya
- [ ] Di Grafana → Explore → Prometheus, query `container_memory_working_set_bytes{name="nama-app"}` ada hasilnya
- [ ] Dashboard **Logs Explorer** filter `Container=nama-app` jalan
- [ ] Dashboard **Container Metrics** keliatan grafik CPU/RAM-nya

Kalau ada yang gagal, cek `TROUBLESHOOTING.md`.

---

## Disable Logging buat Container Tertentu

Default-nya cuma container ber-label `logging=promtail` yang di-scrape. Container tanpa label otomatis di-skip — bagus buat skip noise (misal database log yang verbose).

Mau scrape SEMUA container? Edit `promtail/promtail-config.yaml`, komentari blok ini:

```yaml
# - source_labels: ['__meta_docker_container_label_logging']
#   regex: 'promtail'
#   action: keep
```

Restart: `docker compose restart promtail`
