# Shared Hosting Guide

Panduan menghubungkan app yang jalan di **shared hosting** ke Pantra. Di shared hosting lu gak bisa install binary, jalanin systemd, atau buka port — jadi strateginya: **app push log langsung ke Loki via HTTP API**.

## Kapan Pake Panduan Ini?

- App lu di shared hosting (cPanel, Plesk, dll)
- Gak punya akses root/sudo
- Gak bisa install Promtail
- Gak bisa jalanin Docker
- Contoh: Laravel di Niagahoster, Hostinger, Domainesia, dll

## Arsitektur

```
Shared Hosting                         Pantra VPS
┌──────────────────────┐               ┌────────────────────┐
│                      │               │                    │
│  [App: Laravel/PHP]  │               │  Nginx (auth)      │
│         │            │               │       │            │
│         │ HTTP POST  │               │       ▼            │
│         └────────────┼──── HTTPS ───▶│     Loki           │
│                      │               │       │            │
└──────────────────────┘               │       ▼            │
                                       │    Grafana         │
                                       └────────────────────┘
```

## ⚠️ Prasyarat

1. **Pantra stack udah jalan** di VPS lu (via `install.sh`)
2. **Loki harus bisa diakses dari internet** — default-nya internal only, perlu expose via reverse proxy + auth
3. **App lu support HTTP request** (curl/guzzle/fetch)

---

## Step 1: Expose Loki dengan Auth (di Pantra VPS)

Default Pantra, Loki cuma bisa diakses internal. Buat shared hosting, lu perlu expose endpoint push-nya via reverse proxy dengan Basic Auth.

### Opsi A: Nginx Reverse Proxy (Recommended)

Install nginx di Pantra VPS (kalau belum):

```bash
sudo apt install -y nginx apache2-utils
```

Buat password file:

```bash
# Ganti USERNAME dan PASSWORD sesuai keinginan
sudo htpasswd -cb /etc/nginx/.loki-htpasswd pantra-push YOUR_STRONG_PASSWORD
```

Buat config nginx:

```nginx
# /etc/nginx/sites-available/loki-push
server {
    listen 3101 ssl;
    server_name _;

    # SSL (pake Let's Encrypt atau self-signed)
    ssl_certificate /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem;

    # HANYA izinkan endpoint push — block semua lainnya
    location /loki/api/v1/push {
        auth_basic "Pantra Push";
        auth_basic_user_file /etc/nginx/.loki-htpasswd;

        proxy_pass http://127.0.0.1:3100;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;

        # Limit request size (prevent abuse)
        client_max_body_size 5m;
    }

    # Block everything else
    location / {
        return 403;
    }
}
```

Enable & restart:

```bash
sudo ln -s /etc/nginx/sites-available/loki-push /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Buka port di firewall
sudo ufw allow 3101/tcp
```

### Opsi B: Tanpa SSL (Development Only)

Kalau cuma buat testing, bisa skip SSL:

```nginx
# /etc/nginx/sites-available/loki-push
server {
    listen 3101;
    server_name _;

    location /loki/api/v1/push {
        auth_basic "Pantra Push";
        auth_basic_user_file /etc/nginx/.loki-htpasswd;

        proxy_pass http://127.0.0.1:3100;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
        client_max_body_size 5m;
    }

    location / {
        return 403;
    }
}
```

> ⚠️ **JANGAN pake ini di production** — password dikirim plaintext tanpa SSL.

### Opsi C: Caddy (Auto-SSL)

```
:3101 {
    basicauth /loki/api/v1/push {
        pantra-push $2a$14$HASHED_PASSWORD_HERE
    }
    reverse_proxy /loki/api/v1/push localhost:3100
    respond / 403
}
```

### Verifikasi

Test dari laptop/server lain:

```bash
curl -u pantra-push:YOUR_STRONG_PASSWORD \
  -X POST "https://YOUR_VPS_IP:3101/loki/api/v1/push" \
  -H "Content-Type: application/json" \
  -d '{"streams":[{"stream":{"app":"test","env":"dev"},"values":[["'$(date +%s)000000000'","hello from curl"]]}]}'
```

Cek di Grafana → Explore → Loki → `{app="test"}` — harusnya muncul.

---

## Step 2: Install Handler di App

### Laravel / PHP

Buat file `app/Logging/LokiHandler.php`:

```php
<?php

namespace App\Logging;

use Monolog\Handler\AbstractProcessingHandler;
use Monolog\Level;
use Monolog\LogRecord;

class LokiHandler extends AbstractProcessingHandler
{
    private string $lokiUrl;
    private string $username;
    private string $password;
    private array $labels;
    private array $buffer = [];
    private int $batchSize;

    public function __construct(
        string $lokiUrl,
        string $username = '',
        string $password = '',
        array $labels = [],
        int $batchSize = 10,
        Level $level = Level::Debug,
        bool $bubble = true
    ) {
        parent::__construct($level, $bubble);
        $this->lokiUrl = rtrim($lokiUrl, '/') . '/loki/api/v1/push';
        $this->username = $username;
        $this->password = $password;
        $this->labels = $labels;
        $this->batchSize = $batchSize;

        register_shutdown_function([$this, 'flush']);
    }

    protected function write(LogRecord $record): void
    {
        $this->buffer[] = $record;

        if (count($this->buffer) >= $this->batchSize) {
            $this->flush();
        }
    }

    public function flush(): void
    {
        if (empty($this->buffer)) {
            return;
        }

        $streams = [];
        foreach ($this->buffer as $record) {
            $labels = array_merge($this->labels, [
                'level' => strtolower($record->level->name),
                'channel' => $record->channel,
            ]);

            $labelStr = '{';
            $parts = [];
            foreach ($labels as $k => $v) {
                $parts[] = $k . '="' . addslashes($v) . '"';
            }
            $labelStr .= implode(',', $parts) . '}';

            $message = $record->formatted ?? $record->message;
            if (!empty($record->context)) {
                $message .= ' ' . json_encode($record->context);
            }

            $streams[] = [
                'stream' => $labels,
                'values' => [[
                    (string)(intval($record->datetime->format('U.u') * 1e9)),
                    $message,
                ]],
            ];
        }

        $payload = json_encode(['streams' => $streams]);
        $this->send($payload);
        $this->buffer = [];
    }

    private function send(string $payload): void
    {
        $ch = curl_init($this->lokiUrl);
        $headers = ['Content-Type: application/json'];

        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_TIMEOUT => 3,
            CURLOPT_CONNECTTIMEOUT => 2,
            CURLOPT_RETURNTRANSFER => true,
        ]);

        if ($this->username && $this->password) {
            curl_setopt($ch, CURLOPT_USERPWD, $this->username . ':' . $this->password);
        }

        curl_exec($ch);
        curl_close($ch);
    }
}
```

Registrasi di `config/logging.php`:

```php
'channels' => [
    'loki' => [
        'driver' => 'custom',
        'via' => App\Logging\CreateLokiLogger::class,
    ],
],
```

Buat `app/Logging/CreateLokiLogger.php`:

```php
<?php

namespace App\Logging;

use Monolog\Logger;

class CreateLokiLogger
{
    public function __invoke(array $config): Logger
    {
        $logger = new Logger('loki');
        $logger->pushHandler(new LokiHandler(
            lokiUrl: env('LOKI_URL', 'https://your-vps:3101'),
            username: env('LOKI_USERNAME', 'pantra-push'),
            password: env('LOKI_PASSWORD', ''),
            labels: [
                'app' => env('APP_NAME', 'laravel'),
                'env' => env('APP_ENV', 'production'),
                'host' => gethostname(),
            ],
            batchSize: 10,
        ));
        return $logger;
    }
}
```

Tambahin di `.env`:

```env
LOG_CHANNEL=loki
LOKI_URL=https://YOUR_VPS_IP:3101
LOKI_USERNAME=pantra-push
LOKI_PASSWORD=your_strong_password
```

> **Tip:** Mau dual logging (file + loki)? Pake `LOG_CHANNEL=stack` dan tambahin `loki` ke stack channels.

### Node.js

```js
// loki-transport.js
const https = require('https');
const http = require('http');

class LokiTransport {
  constructor({ url, username, password, labels = {}, batchSize = 10, flushInterval = 5000 }) {
    this.url = new URL(url + '/loki/api/v1/push');
    this.username = username;
    this.password = password;
    this.labels = labels;
    this.batchSize = batchSize;
    this.buffer = [];
    this.flushInterval = setInterval(() => this.flush(), flushInterval);
  }

  log(level, message, meta = {}) {
    const ts = (Date.now() * 1e6).toString(); // nanoseconds
    const line = JSON.stringify({ level, msg: message, ...meta });
    this.buffer.push({ ts, line, level });
    if (this.buffer.length >= this.batchSize) this.flush();
  }

  flush() {
    if (this.buffer.length === 0) return;
    const entries = this.buffer.splice(0);

    const streams = entries.map(({ ts, line, level }) => ({
      stream: { ...this.labels, level },
      values: [[ts, line]],
    }));

    const payload = JSON.stringify({ streams });
    const options = {
      method: 'POST',
      hostname: this.url.hostname,
      port: this.url.port,
      path: this.url.pathname,
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
      },
      timeout: 3000,
    };

    if (this.username && this.password) {
      options.headers['Authorization'] = 'Basic ' +
        Buffer.from(`${this.username}:${this.password}`).toString('base64');
    }

    const transport = this.url.protocol === 'https:' ? https : http;
    const req = transport.request(options);
    req.on('error', () => {}); // fire and forget
    req.write(payload);
    req.end();
  }

  close() {
    clearInterval(this.flushInterval);
    this.flush();
  }
}

// Usage:
const loki = new LokiTransport({
  url: process.env.LOKI_URL || 'https://YOUR_VPS:3101',
  username: process.env.LOKI_USERNAME || 'pantra-push',
  password: process.env.LOKI_PASSWORD || '',
  labels: { app: 'myapp', env: process.env.NODE_ENV || 'production' },
});

loki.log('info', 'server started', { port: 3000 });
loki.log('error', 'DB timeout', { endpoint: '/api/users' });

// Graceful shutdown
process.on('SIGTERM', () => loki.close());

module.exports = { LokiTransport };
```

### Python

```python
# loki_handler.py
import json
import time
import threading
import logging
from urllib.request import Request, urlopen
from urllib.error import URLError
from base64 import b64encode


class LokiHandler(logging.Handler):
    """Push logs to Loki HTTP API. Works on shared hosting (no binary needed)."""

    def __init__(self, url, username='', password='', labels=None,
                 batch_size=10, flush_interval=5.0, level=logging.DEBUG):
        super().__init__(level)
        self.url = url.rstrip('/') + '/loki/api/v1/push'
        self.auth = None
        if username and password:
            cred = b64encode(f'{username}:{password}'.encode()).decode()
            self.auth = f'Basic {cred}'
        self.labels = labels or {}
        self.batch_size = batch_size
        self.buffer = []
        self.lock = threading.Lock()

        # Auto-flush timer
        self._timer = threading.Timer(flush_interval, self._auto_flush)
        self._timer.daemon = True
        self._timer.start()
        self._flush_interval = flush_interval

    def emit(self, record):
        with self.lock:
            self.buffer.append(record)
            if len(self.buffer) >= self.batch_size:
                self._flush()

    def _auto_flush(self):
        with self.lock:
            self._flush()
        self._timer = threading.Timer(self._flush_interval, self._auto_flush)
        self._timer.daemon = True
        self._timer.start()

    def _flush(self):
        if not self.buffer:
            return
        entries = self.buffer[:]
        self.buffer = []

        streams = []
        for record in entries:
            labels = {**self.labels, 'level': record.levelname.lower()}
            ts = str(int(record.created * 1e9))
            msg = self.format(record) if self.formatter else record.getMessage()
            streams.append({'stream': labels, 'values': [[ts, msg]]})

        payload = json.dumps({'streams': streams}).encode()
        req = Request(self.url, data=payload, method='POST')
        req.add_header('Content-Type', 'application/json')
        if self.auth:
            req.add_header('Authorization', self.auth)

        try:
            urlopen(req, timeout=3)
        except (URLError, OSError):
            pass  # fire and forget

    def close(self):
        self._timer.cancel()
        with self.lock:
            self._flush()
        super().close()


# Usage:
logger = logging.getLogger('myapp')
handler = LokiHandler(
    url='https://YOUR_VPS:3101',
    username='pantra-push',
    password='your_strong_password',
    labels={'app': 'myapp', 'env': 'production'},
)
logger.addHandler(handler)
logger.setLevel(logging.INFO)

logger.info('server started on port 8000')
logger.error('DB connection failed', exc_info=True)
```

### Go

```go
// lokipush.go
package lokipush

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"sync"
	"time"
)

type Client struct {
	url      string
	auth     string
	labels   map[string]string
	buffer   []entry
	mu       sync.Mutex
	batchSz  int
	client   *http.Client
}

type entry struct {
	ts    time.Time
	line  string
	level string
}

func New(lokiURL, username, password string, labels map[string]string) *Client {
	c := &Client{
		url:     lokiURL + "/loki/api/v1/push",
		labels:  labels,
		batchSz: 10,
		client:  &http.Client{Timeout: 3 * time.Second},
	}
	if username != "" && password != "" {
		c.auth = username + ":" + password
	}
	go c.autoFlush(5 * time.Second)
	return c
}

func (c *Client) Log(level, msg string, fields map[string]interface{}) {
	line, _ := json.Marshal(map[string]interface{}{
		"level": level, "msg": msg, "fields": fields,
	})
	c.mu.Lock()
	c.buffer = append(c.buffer, entry{time.Now(), string(line), level})
	if len(c.buffer) >= c.batchSz {
		c.flush()
	}
	c.mu.Unlock()
}

func (c *Client) Flush() {
	c.mu.Lock()
	c.flush()
	c.mu.Unlock()
}

func (c *Client) flush() {
	if len(c.buffer) == 0 {
		return
	}
	entries := c.buffer
	c.buffer = nil

	type stream struct {
		Stream map[string]string `json:"stream"`
		Values [][]string        `json:"values"`
	}
	streams := make([]stream, 0, len(entries))
	for _, e := range entries {
		lbls := make(map[string]string, len(c.labels)+1)
		for k, v := range c.labels {
			lbls[k] = v
		}
		lbls["level"] = e.level
		ts := strconv.FormatInt(e.ts.UnixNano(), 10)
		streams = append(streams, stream{Stream: lbls, Values: [][]string{{ts, e.line}}})
	}

	body, _ := json.Marshal(map[string]interface{}{"streams": streams})
	req, _ := http.NewRequest("POST", c.url, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if c.auth != "" {
		req.SetBasicAuth(c.labels["app"], c.auth) // simplified
	}
	c.client.Do(req) //nolint:errcheck
}

func (c *Client) autoFlush(interval time.Duration) {
	for range time.Tick(interval) {
		c.Flush()
	}
}
```

Usage:

```go
loki := lokipush.New(
    "https://YOUR_VPS:3101",
    "pantra-push",
    "your_password",
    map[string]string{"app": "myapi", "env": "production"},
)
defer loki.Flush()

loki.Log("info", "server started", map[string]interface{}{"port": 8080})
loki.Log("error", "DB timeout", map[string]interface{}{"duration_ms": 3500})
```

---

## Step 3: Verifikasi

1. Trigger log dari app lu (misal hit endpoint yang ada `Log::info()`)
2. Buka Grafana → **Explore** → pilih datasource **Loki**
3. Query: `{app="nama-app-lu"}`
4. Harusnya log muncul dalam 1-5 detik

Kalau gak muncul, cek:
- Endpoint Loki bisa diakses dari shared hosting? (`curl` dari server lain)
- Username/password bener?
- Firewall port 3101 udah dibuka?
- Cek error log app (Laravel: `storage/logs/laravel.log`)

---

## Alternatif: Batch Upload via Cron

Kalau app lu gak bisa HTTP request real-time (atau mau hemat resource), bisa pake pendekatan batch:

1. App nulis log ke file seperti biasa
2. Cron job (tiap 1-5 menit) baca file, push ke Loki, truncate

```php
// batch-push.php — jalanin via cron: */1 * * * * php batch-push.php
<?php
$logFile = '/home/user/public_html/storage/logs/laravel.log';
$lokiUrl = 'https://YOUR_VPS:3101/loki/api/v1/push';
$username = 'pantra-push';
$password = 'YOUR_PASSWORD';

if (!file_exists($logFile) || filesize($logFile) === 0) exit;

$lines = file($logFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
if (empty($lines)) exit;

$values = [];
foreach ($lines as $line) {
    $values[] = [(string)(time() * 1000000000), $line];
}

$payload = json_encode([
    'streams' => [[
        'stream' => ['app' => 'myapp', 'env' => 'production', 'host' => gethostname()],
        'values' => $values,
    ]]
]);

$ch = curl_init($lokiUrl);
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => $payload,
    CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
    CURLOPT_USERPWD => "$username:$password",
    CURLOPT_TIMEOUT => 10,
    CURLOPT_RETURNTRANSFER => true,
]);

$result = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

// Truncate log file setelah berhasil push
if ($httpCode >= 200 && $httpCode < 300) {
    file_put_contents($logFile, '');
}
```

Setup cron di cPanel:
```
*/1 * * * * /usr/bin/php /home/user/batch-push.php >> /dev/null 2>&1
```

---

## Security Considerations

1. **Selalu pake HTTPS** — password dikirim via Basic Auth, tanpa SSL bisa di-sniff
2. **Limit endpoint** — cuma expose `/loki/api/v1/push`, block query/delete endpoint
3. **Rate limit** — tambahin `limit_req` di nginx buat prevent abuse
4. **Rotate password** — ganti password berkala, update di app `.env`
5. **IP whitelist** (opsional) — kalau shared hosting punya static IP, whitelist di nginx

Contoh rate limit nginx:

```nginx
# Di http block
limit_req_zone $binary_remote_addr zone=loki_push:10m rate=10r/s;

# Di location block
location /loki/api/v1/push {
    limit_req zone=loki_push burst=20 nodelay;
    # ... rest of config
}
```

---

## Troubleshooting

| Problem | Solusi |
|---|---|
| `Connection refused` | Cek firewall port 3101, nginx running? |
| `401 Unauthorized` | Username/password salah di app `.env` |
| `413 Request Entity Too Large` | Kurangi batch size atau naikin `client_max_body_size` |
| Log gak muncul di Grafana | Cek timestamp format (harus nanosecond string) |
| `SSL certificate problem` | Pake Let's Encrypt, atau set `CURLOPT_SSL_VERIFYPEER => false` (dev only) |
| Timeout dari shared hosting | Kurangi `CURLOPT_TIMEOUT`, pake batch approach |
| Memory limit PHP | Kurangi `batchSize` di LokiHandler |

---

## Perbandingan Approach

| Approach | Latency | Reliability | Effort | Best For |
|---|---|---|---|---|
| Real-time push (handler) | <1s | Medium (Loki down = log hilang) | Medium | App yang butuh real-time monitoring |
| Batch cron upload | 1-5 min | High (file sebagai buffer) | Low | Shared hosting dengan cron access |
| Dual (file + push) | <1s | High (file backup) | Medium | Production critical apps |

---

## Limitasi

- **Gak ada metrics** — shared hosting gak bisa install node-exporter/cAdvisor. Lu cuma dapet **logs**, bukan CPU/RAM metrics.
- **Gak ada auto-discovery** — harus manual config di setiap app
- **Dependency ke network** — kalau koneksi ke VPS putus, log bisa hilang (kecuali pake batch approach)
- **Performance overhead** — setiap log = HTTP request (mitigasi: batching)

Buat monitoring yang lebih lengkap, pertimbangkan migrasi ke VPS (bahkan yang murah $5/bulan udah cukup buat jalanin app + Pantra agent).

