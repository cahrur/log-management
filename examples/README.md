# Examples - Pantra Integration

Contoh konfigurasi untuk berbagai stack/framework. Setiap contoh sudah dikonfigurasi dengan:
- Docker Compose labels yang benar untuk Promtail
- JSON structured logging
- Resource limits
- Health checks
- Network integration dengan Pantra

## Quick Start

1. Pastikan Pantra stack sudah running
2. Pilih contoh sesuai stack lu
3. Copy file ke project
4. Sesuaikan `.env` / config
5. `docker compose up -d`

## Available Examples

| Framework | Deskripsi | Files |
|-----------|-----------|-------|
| [Laravel](./laravel/) | PHP/Laravel dengan queue worker & scheduler | docker-compose.yml, .env.example |
| [Go](./golang/) | Go app dengan multi-stage build | docker-compose.yml, Dockerfile |
| [Node.js](./nodejs/) | Node.js dengan Pino JSON logger | docker-compose.yml, logger.js |
| [Python](./python/) | FastAPI dengan Loguru JSON logger | docker-compose.yml, logger.py |
| [Java Spring](./java-spring/) | Spring Boot dengan Logback JSON | docker-compose.yml, logback-spring.xml |
| [Nginx](./nginx/) | Nginx reverse proxy dengan JSON access log | docker-compose.yml |

## Labels (WAJIB)

Setiap container yang mau di-monitor HARUS punya label ini:

```yaml
labels:
  - "logging=promtail"        # WAJIB: opt-in ke log collection
  - "team=nama-tim"           # Recommended: identifikasi tim
  - "project=nama-project"    # Recommended: identifikasi project
  - "service=nama-service"    # Recommended: identifikasi service
```

## Network

Semua contoh pakai external network `pantra`:

```yaml
networks:
  observability:
    name: pantra
    external: true
```

Pastikan network sudah ada:
```bash
docker network ls | grep pantra
```

## Logging Best Practices

1. **Output ke stdout/stderr** — jangan log ke file di dalam container
2. **JSON format** — structured logging gampang di-query
3. **Include context** — request ID, user ID, service name
4. **Level yang tepat** — ERROR untuk error, INFO untuk normal flow
5. **Jangan log sensitive data** — password, token, PII

## Query di Grafana (LogQL)

```logql
# Semua error dari satu project
{project="myapp"} | json | level="ERROR"

# Request lambat
{service="node-api"} | json | duration_ms > 1000

# Filter by team
{team="backend"} |= "exception"

# Rate of errors
rate({project="myapp"} | json | level="ERROR" [5m])
```

## Custom Metrics (Opsional)

Kalau app lu expose Prometheus metrics, tambahkan di `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'my-app'
    static_configs:
      - targets: ['container-name:port']
        labels:
          team: 'nama-tim'
          project: 'nama-project'
```
