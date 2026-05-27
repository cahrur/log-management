# Go App + Pantra

## Setup

1. Copy `docker-compose.yml` dan `Dockerfile` ke project Go lu

2. Pastikan app lu output JSON logs ke stdout. Contoh pakai `slog`:
   ```go
   logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
       Level: slog.LevelInfo,
   }))
   slog.SetDefault(logger)
   ```

3. Pastikan Pantra network ada:
   ```bash
   docker network ls | grep pantra
   ```

4. Start:
   ```bash
   docker compose up -d --build
   ```

## Structured Logging

Go punya built-in `log/slog` (Go 1.21+). Output JSON ke stdout:

```go
slog.Info("request handled",
    "method", r.Method,
    "path", r.URL.Path,
    "status", statusCode,
    "duration_ms", elapsed.Milliseconds(),
)
```

Output:
```json
{"time":"2024-01-01T12:00:00Z","level":"INFO","msg":"request handled","method":"GET","path":"/api/users","status":200,"duration_ms":15}
```

## Query di Grafana

```logql
{service="go-api"} | json | level="ERROR"
{service="go-api"} | json | duration_ms > 1000
{project="myapp", service=~"go-.*"}
```

## Metrics (opsional)

Expose Prometheus metrics di `/metrics`:
```go
import "github.com/prometheus/client_golang/prometheus/promhttp"

http.Handle("/metrics", promhttp.Handler())
```

Tambahkan di `prometheus.yml`:
```yaml
- job_name: 'go-api'
  static_configs:
    - targets: ['go-api:8080']
```
