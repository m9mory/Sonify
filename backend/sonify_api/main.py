"""Точка входа: uvicorn sonify_api.main:app --port 8080"""

from __future__ import annotations

import logging

import uvicorn

from .app import create_app
from .config import Settings

settings = Settings.from_env()
app = create_app(settings)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")


def run() -> None:
    uvicorn.run(app, host=settings.host, port=settings.port, log_level="info")


if __name__ == "__main__":
    run()
