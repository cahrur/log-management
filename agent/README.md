# Agent Setup — Buat App Container Lu

Folder ini contoh gimana app container (dealtech-code, tim-1..4, dll) supaya log & metrics-nya kebaca sama observability stack.

## Cara Pake

### 1. Pastiin app container join ke network `observability` (opsional)

Cara ini paling clean kalau app & monitoring di server yang sama. Di `docker-compose.yml` app lu, tambahin network external:

```yaml
networks:
  default:
    name: app-internal
  observability:
    external: true
```

Lalu di service kasih label + network:

```yaml
services:
  tim1-app:
    image: nginx:alpine
    networks:
      - default
      - observability
    labels:
      - "logging=promtail"
      - "team=tim1"
      - "project=dealtech-code"
      - "service=api"
```

### 2. Atau cukup label aja (minimal)

Promtail nyedot dari Docker socket, jadi gak harus satu network. Tinggal kasih label:

```yaml
services:
  tim1-app:
    image: ghcr.io/youruser/dealtech-tim1:latest
    labels:
      - "logging=promtail"      # WAJIB - kalau gak ada, log gak di-scrape
      - "team=tim1"             # opsional, buat filter di Grafana
      - "project=dealtech-code"
      - "service=api"
```

### 3. Best practice: log ke stdout/stderr

Container app **HARUS** log ke stdout/stderr, bukan ke file di dalam container. Ini standard 12-factor app dan otomatis kebaca Docker driver:

- Node.js: `console.log` / `console.error` ✅
- Python: `print()` atau `logging` ke `StreamHandler` ✅
- PHP: `error_log()` (PHP-FPM otomatis ke stderr) ✅
- Go: `log.Println` ✅
- Java/Spring: `logback` console appender ✅

### 4. Format log JSON (recommended)

Kalau lu pake JSON log, Loki bisa parse field-nya jadi label dynamic. Contoh log JSON:

```json
{"level":"error","ts":"2026-05-27T10:00:00Z","msg":"DB timeout","user_id":42,"endpoint":"/api/users"}
```

Promtail udah support, dan di Grafana lu bisa query:

```
{job="docker", team="tim1"} | json | level="error" | endpoint=~"/api/.*"
```

## Contoh File

Lihat `docker-compose.example.yml` di folder ini buat template lengkap.

## Verifikasi

Setelah app jalan, cek di Grafana → Explore → Loki:

```
{container="tim1-app"}
```

Atau pake template variable di dashboard "Logs Explorer".

## FAQ

**Q: Gua udah kasih label tapi log gak muncul?**
A: Restart Promtail: `docker compose restart promtail` di folder log-management. Atau cek `docker compose logs promtail` ada error apa.

**Q: Container saya log-nya ke file, bukan stdout. Gimana?**
A: 2 opsi:
1. Mount file log ke `/var/log/` di host, Promtail bakal nyedot dari `/var/log/*log` (lihat `system` job)
2. Lebih bagus: ubah app supaya log ke stdout. Container yang baik gak nulis log ke file.

**Q: Mau forward log dari server lain (multi-VPS)?**
A: Install Promtail di VPS lain, point ke Loki di VPS observability:

```yaml
clients:
  - url: http://OBSERVABILITY_VPS_IP:3100/loki/api/v1/push
```

Buka port 3100 di firewall VPS observability (atau pake Tailscale/WireGuard buat aman).
