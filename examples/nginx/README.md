# Nginx + Pantra

## Setup

1. Copy `docker-compose.yml` ke project lu

2. Konfigurasi Nginx log format JSON di `nginx.conf`:
   ```nginx
   http {
       log_format json_combined escape=json
           '{'
             '"time":"$time_iso8601",'
             '"remote_addr":"$remote_addr",'
             '"request_method":"$request_method",'
             '"request_uri":"$request_uri",'
             '"status":$status,'
             '"body_bytes_sent":$body_bytes_sent,'
             '"request_time":$request_time,'
             '"http_referrer":"$http_referer",'
             '"http_user_agent":"$http_user_agent",'
             '"upstream_response_time":"$upstream_response_time"'
           '}';

       access_log /dev/stdout json_combined;
       error_log /dev/stderr warn;
   }
   ```

3. Start:
   ```bash
   docker compose up -d
   ```

## Tips

- Pakai JSON log format supaya gampang di-query di Loki
- Access log ke `/dev/stdout` → Docker capture otomatis
- Error log ke `/dev/stderr` → Docker capture otomatis
- Jangan log ke file di dalam container

## Query di Grafana

```logql
{service="nginx"} | json | status >= 500
{service="nginx"} | json | request_time > 1
{service="nginx"} | json | status=~"4.."
{service="nginx"} | json | request_uri=~"/api/.*" | status >= 400
```

## Health Check Endpoint

Tambah di nginx config:
```nginx
server {
    location /health {
        access_log off;
        return 200 "ok";
    }
}
```
