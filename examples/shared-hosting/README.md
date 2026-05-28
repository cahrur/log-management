# Shared Hosting Examples

Contoh implementasi push log ke Pantra dari shared hosting (tanpa Docker/root).

## Struktur

```
shared-hosting/
├── php/
│   └── LokiHandler.php       # Monolog handler untuk Laravel/PHP
├── nodejs/
│   └── loki-transport.js     # HTTP transport untuk Node.js
└── python/
    └── loki_handler.py       # logging.Handler untuk Python
```

## Cara Pakai

1. Baca [SHARED-HOSTING.md](../../SHARED-HOSTING.md) dulu buat setup Loki endpoint
2. Copy file handler sesuai bahasa app lu
3. Configure URL, username, password
4. Done — log otomatis push ke Pantra

## Prasyarat

- Pantra stack udah jalan di VPS
- Loki endpoint udah di-expose via reverse proxy + auth (lihat SHARED-HOSTING.md Step 1)
