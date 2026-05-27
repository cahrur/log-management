# Laravel + Pantra

## Setup

1. Copy file ke project Laravel lu:
   ```bash
   cp docker-compose.yml /path/to/laravel/
   cp .env.example /path/to/laravel/.env
   ```

2. Edit `.env` — isi password dan sesuaikan config

3. Pastikan Pantra stack sudah running:
   ```bash
   docker network ls | grep pantra
   ```

4. Start:
   ```bash
   docker compose up -d
   ```

## Logging

Laravel dikonfigurasi pakai `LOG_CHANNEL=stderr` supaya semua log masuk ke Docker stdout/stderr dan otomatis di-pickup Promtail.

Format log Laravel default sudah cukup bagus. Kalau mau JSON structured logging, install package:
```bash
composer require monolog/monolog
```

Dan set di `config/logging.php`:
```php
'stderr' => [
    'driver' => 'monolog',
    'handler' => StreamHandler::class,
    'formatter' => JsonFormatter::class,
    'with' => [
        'stream' => 'php://stderr',
    ],
],
```

## Labels

- `logging=promtail` — WAJIB, opt-in ke log collection
- `team=<nama_tim>` — identifikasi tim
- `project=<nama_project>` — identifikasi project
- `service=<nama_service>` — identifikasi service (api, worker, scheduler)

## Query di Grafana

```logql
{service="laravel-api"} |= "ERROR"
{project="myapp"} | json | level="error"
```
