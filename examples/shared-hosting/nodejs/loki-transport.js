/**
 * LokiTransport - Push logs to Loki HTTP API from Node.js.
 * 
 * For shared hosting or environments where you can't install Promtail.
 * 
 * Usage:
 *   const { LokiTransport } = require('./loki-transport');
 *   const loki = new LokiTransport({
 *     url: process.env.LOKI_URL || 'https://YOUR_VPS:3101',
 *     username: process.env.LOKI_USERNAME || 'pantra-push',
 *     password: process.env.LOKI_PASSWORD || '',
 *     labels: { app: 'myapp', env: 'production' },
 *   });
 *   loki.log('info', 'server started', { port: 3000 });
 *
 * @see https://github.com/cahrur/pantra/blob/main/SHARED-HOSTING.md
 */

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

  info(message, meta = {}) { this.log('info', message, meta); }
  warn(message, meta = {}) { this.log('warn', message, meta); }
  error(message, meta = {}) { this.log('error', message, meta); }
  debug(message, meta = {}) { this.log('debug', message, meta); }

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

module.exports = { LokiTransport };
