# Python/FastAPI + Pantra

## Setup

1. Install dependencies:
   ```bash
   pip install loguru
   ```

2. Copy `logger.py` ke project lu

3. Gunakan logger:
   ```python
   from logger import logger

   logger.info("User created", user_id=123)
   logger.error("DB failed", error=str(e))
   ```

4. FastAPI middleware:
   ```python
   from logger import create_request_logger
   from fastapi import FastAPI

   app = FastAPI()

   @app.middleware("http")
   async def log_requests(request, call_next):
       return await create_request_logger()(request, call_next)
   ```

5. Start:
   ```bash
   docker compose up -d --build
   ```

## Output Format (Production)

```json
{"timestamp":"2024-01-01T12:00:00.000000Z","level":"INFO","message":"User created","service":"python-api","env":"production","user_id":123}
```

## Query di Grafana

```logql
{service="python-api"} | json | level="ERROR"
{service="python-api"} | json | duration_ms > 1000
{project="myapp"} | json | message=~".*timeout.*"
```

## Tips

- Selalu pakai keyword args: `logger.info("msg", key=value)`
- Pakai `.bind()` untuk context: `logger.bind(user_id=123).info("action")`
- Exception logging: `logger.exception("Failed")` (auto-include traceback)
- Jangan f-string di message: ~~`logger.info(f"User {id}")`~~
  Pakai: `logger.info("User action", user_id=id)`
