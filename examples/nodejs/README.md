# Node.js + Pantra

## Setup

1. Install pino:
   ```bash
   npm install pino pino-pretty
   ```

2. Copy `logger.js` ke project lu

3. Gunakan logger:
   ```javascript
   const logger = require('./logger');
   logger.info({ userId: 123 }, 'User created');
   logger.error({ err }, 'Database connection failed');
   ```

4. Pasang middleware (Express):
   ```javascript
   const { requestLogger } = require('./logger');
   app.use(requestLogger);
   ```

5. Start dengan Docker Compose:
   ```bash
   docker compose up -d --build
   ```

## Kenapa Pino?

- Output JSON native (gak perlu transform)
- Sangat cepat (low overhead)
- Structured logging out of the box
- Redaction built-in (auto-hide password, token)
- Child loggers untuk request context

## Output Format

```json
{"level":30,"time":"2024-01-01T12:00:00.000Z","service":"node-api","env":"production","msg":"User created","userId":123}
```

## Query di Grafana

```logql
{service="node-api"} | json | level=50
{service="node-api"} | json | duration_ms > 500
{project="myapp"} | json | msg=~".*error.*"
```

## Tips

- Selalu pakai structured data: `logger.info({ key: value }, 'message')`
- Jangan string concatenation: ~~`logger.info('User ' + id + ' created')`~~
- Pakai child logger per request untuk tracing
- Set `LOG_LEVEL=debug` di development, `info` di production
