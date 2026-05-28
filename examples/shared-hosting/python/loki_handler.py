"""
LokiHandler - Python logging handler that pushes logs to Loki HTTP API.

For shared hosting or environments where you can't install Promtail.

Usage:
    import logging
    from loki_handler import LokiHandler

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

@see https://github.com/cahrur/pantra/blob/main/SHARED-HOSTING.md
"""

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
        self._flush_interval = flush_interval
        self._timer = threading.Timer(flush_interval, self._auto_flush)
        self._timer.daemon = True
        self._timer.start()

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

        # Group by label set for better Loki performance
        grouped = {}
        for record in entries:
            labels = {**self.labels, 'level': record.levelname.lower()}
            key = json.dumps(labels, sort_keys=True)
            if key not in grouped:
                grouped[key] = {'stream': labels, 'values': []}
            ts = str(int(record.created * 1e9))
            msg = self.format(record) if self.formatter else record.getMessage()
            grouped[key]['values'].append([ts, msg])

        payload = json.dumps({'streams': list(grouped.values())}).encode()
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
