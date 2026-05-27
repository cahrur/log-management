"""
Loguru JSON Logger - Setup untuk Pantra

Install: pip install loguru python-json-logger

Loguru output JSON ke stderr, yang otomatis di-capture Docker
dan di-pickup Promtail.

Usage:
    from logger import logger

    logger.info("User created", user_id=123, action="signup")
    logger.error("Database error", error=str(e), query=query)
    logger.bind(request_id="abc-123").info("Request started")
"""

import sys
import os
import json
from datetime import datetime, timezone

from loguru import logger

# Hapus default handler
logger.remove()

# ---------- JSON Serializer ----------
def json_serializer(message):
    """Format log sebagai JSON untuk Promtail/Loki."""
    record = message.record

    log_entry = {
        "timestamp": record["time"].strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
        "level": record["level"].name,
        "message": record["message"],
        "service": os.getenv("SERVICE_NAME", "python-api"),
        "env": os.getenv("APP_ENV", "development"),
        "host": os.getenv("HOSTNAME", "localhost"),
    }

    # Tambah extra fields dari .bind()
    if record["extra"]:
        for key, value in record["extra"].items():
            if key not in log_entry:
                log_entry[key] = value

    # Tambah exception info kalau ada
    if record["exception"]:
        log_entry["exception"] = {
            "type": record["exception"].type.__name__ if record["exception"].type else None,
            "value": str(record["exception"].value) if record["exception"].value else None,
            "traceback": "".join(
                record["exception"].traceback.format()
            ) if record["exception"].traceback else None,
        }

    # Tambah caller info
    log_entry["caller"] = {
        "file": record["file"].name,
        "line": record["line"],
        "function": record["function"],
    }

    return json.dumps(log_entry, default=str)


def json_sink(message):
    """Sink yang output JSON ke stderr."""
    serialized = json_serializer(message)
    sys.stderr.write(serialized + "\n")
    sys.stderr.flush()


# ---------- Setup ----------
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
APP_ENV = os.getenv("APP_ENV", "development")

if APP_ENV == "production":
    # Production: JSON ke stderr
    logger.add(
        json_sink,
        level=LOG_LEVEL,
        serialize=False,
    )
else:
    # Development: pretty print ke stderr
    logger.add(
        sys.stderr,
        level="DEBUG",
        format=(
            "<green>{time:YYYY-MM-DD HH:mm:ss.SSS}</green> | "
            "<level>{level: <8}</level> | "
            "<cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> | "
            "<level>{message}</level> | "
            "{extra}"
        ),
        colorize=True,
    )


# ---------- FastAPI Middleware ----------
def create_request_logger():
    """
    FastAPI middleware untuk request logging.

    Usage:
        from logger import create_request_logger
        from fastapi import FastAPI

        app = FastAPI()

        @app.middleware("http")
        async def log_requests(request, call_next):
            return await create_request_logger()(request, call_next)
    """
    import time
    import uuid

    async def request_logger(request, call_next):
        request_id = request.headers.get("x-request-id", str(uuid.uuid4()))
        start_time = time.time()

        # Bind request context
        req_logger = logger.bind(
            request_id=request_id,
            method=request.method,
            path=request.url.path,
            client_ip=request.client.host if request.client else "unknown",
        )

        try:
            response = await call_next(request)
            duration_ms = round((time.time() - start_time) * 1000, 2)

            level = "error" if response.status_code >= 500 else \
                    "warning" if response.status_code >= 400 else "info"

            getattr(req_logger, level)(
                f"{request.method} {request.url.path} {response.status_code} {duration_ms}ms",
                status_code=response.status_code,
                duration_ms=duration_ms,
            )

            response.headers["x-request-id"] = request_id
            return response

        except Exception as e:
            duration_ms = round((time.time() - start_time) * 1000, 2)
            req_logger.exception(
                f"Request failed: {str(e)}",
                duration_ms=duration_ms,
            )
            raise

    return request_logger


# Export
__all__ = ["logger", "create_request_logger"]
