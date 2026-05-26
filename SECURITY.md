# Security Policy

## Reporting a Vulnerability

Kalau lu nemu bug security:
1. **JANGAN** buka public issue
2. Email langsung ke maintainer (lihat profile GitHub @cahrur)
3. Tunggu response 7 hari sebelum disclose

## Threat Model — Stack Ini

Stack ini dirancang untuk **observability internal**, bukan public-facing. Asumsi:

- **Trusted operator:** orang yang deploy stack ini punya akses root ke VPS
- **Trusted network:** akses ke Prometheus/Alertmanager/cAdvisor cuma dari operator (via SSH tunnel atau VPN)
- **Untrusted internet:** stack TIDAK boleh expose port 9090/9093/8080 ke public internet

## Default Security Posture

**Yang AMAN by default:**
- ✅ Grafana (port 3000) — punya login, password wajib diset di `.env`
- ✅ Prometheus, Alertmanager, cAdvisor — bind ke `127.0.0.1` only (gak accessible dari luar VPS)
- ✅ Loki, Promtail, node-exporter — gak expose port ke host (cuma internal Docker network)
- ✅ Telegram bot token disimpan di file dengan permission 644 (cuma user di VPS yang bisa baca)
- ✅ `.env` di-gitignore (token gak bakal ke-commit)

**Yang JADI tanggung jawab operator:**
- ⚠️ Ganti `GRAFANA_ADMIN_PASSWORD` default sebelum production
- ⚠️ Pasang firewall (ufw/iptables) — buka cuma port yang perlu (22 SSH, 3000 Grafana)
- ⚠️ Pake HTTPS di Grafana kalau public (pake Caddy/nginx + Let's Encrypt)
- ⚠️ Update image secara berkala (`docker compose pull && docker compose up -d`)
- ⚠️ Monitor login attempt di Grafana audit log

## Cara Akses Service Localhost-Only

Sejak v1, port Prometheus/Alertmanager/cAdvisor bind ke `127.0.0.1`. Akses dari laptop lu via SSH tunnel:

```bash
# Di laptop lu
ssh -L 9090:127.0.0.1:9090 \
    -L 9093:127.0.0.1:9093 \
    -L 8080:127.0.0.1:8080 \
    user@VPS_IP

# Buka browser di laptop:
# http://localhost:9090  (Prometheus)
# http://localhost:9093  (Alertmanager)
# http://localhost:8080  (cAdvisor)
```

Atau pake VPN (Tailscale, WireGuard) — buka port 0.0.0.0 di compose tapi firewall whitelist IP VPN.

**Mau expose ke public?** Override di `.env`:
```bash
PROMETHEUS_BIND=0.0.0.0  # JANGAN, kecuali di belakang reverse proxy + auth
```

## Known Security Considerations

### 1. Docker socket mounted di Promtail

Promtail butuh `/var/run/docker.sock` buat baca container metadata. Kalau Promtail kompromis, attacker punya control penuh atas Docker daemon. Mitigasi:
- Pake image official Promtail (kita pinned ke `grafana/promtail:3.3.2`)
- Jangan run image promtail dari source untrusted

### 2. cAdvisor butuh privileged mode

`privileged: true` di cAdvisor karena butuh akses cgroup & kernel info. Risiko:
- Container escape vulnerability di cAdvisor = root di host
- Mitigasi: pinned ke versi stable (`gcr.io/cadvisor/cadvisor:v0.49.1`), update rutin

Alternatif: kalau lu paranoid, ganti cAdvisor dengan sidecar metrics di app lu sendiri (pake `prometheus-client` library).

### 3. Loki tanpa auth

Loki di-akses cuma dari Docker network internal (gak expose port). Tapi kalau lu konek dari VPS lain (multi-VPS setup di INTEGRATION.md), pastiin pake Tailscale/WireGuard, **bukan** public IP.

### 4. Alert Manager Telegram token

Token disimpan di `alertmanager/telegram_token` dengan chmod 644 (biar container UID 65534 bisa baca). Anyone with shell access ke VPS bisa baca. Mitigasi:
- Restrict SSH access (key-only, no password, fail2ban)
- Token-nya cuma buat Telegram bot — kalau bocor, revoke di @BotFather, ganti

## Disclaimer

Stack ini disediakan **AS-IS** sesuai MIT License. Maintainer **TIDAK bertanggung jawab** atas:
- Data loss akibat misconfig
- Security breach akibat operator tidak follow best practice di SECURITY.md ini
- Downtime akibat bug upstream (Loki/Prometheus/Grafana/Alertmanager)
- Cost overrun (resource VPS over-allocate)

Lu deploy = lu setuju dengan terms ini.

## Upstream Security Advisories

Subscribe ke advisory upstream buat dapet patch:

- **Grafana:** https://github.com/grafana/grafana/security/advisories
- **Loki:** https://github.com/grafana/loki/security/advisories
- **Prometheus:** https://github.com/prometheus/prometheus/security/advisories
- **Alertmanager:** https://github.com/prometheus/alertmanager/security/advisories
- **Docker:** https://docs.docker.com/security/

## Versi Image yang Dipake

| Component | Version | Image |
|---|---|---|
| Grafana | 11.4.0 | `grafana/grafana-oss:11.4.0` |
| Loki | 3.3.2 | `grafana/loki:3.3.2` |
| Promtail | 3.3.2 | `grafana/promtail:3.3.2` |
| Prometheus | 3.1.0 | `prom/prometheus:v3.1.0` |
| Alertmanager | 0.27.0 | `prom/alertmanager:v0.27.0` |
| node-exporter | 1.8.2 | `prom/node-exporter:v1.8.2` |
| cAdvisor | 0.49.1 | `gcr.io/cadvisor/cadvisor:v0.49.1` |

Semua pinned ke versi spesifik (gak pake `latest`) buat reproducibility & supply-chain safety.
