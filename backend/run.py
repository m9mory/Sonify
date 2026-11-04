"""Запуск Sonify API без установки пакета (использует системный Python и его fastapi/uvicorn).

Эквивалент `python -m uvicorn sonify_api.main:app`, но не требует `pip install`,
поэтому работает и в окружении без доступа к PyPI.

Usage:
    python backend/run.py [--host 127.0.0.1] [--port 8080]
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent
sys.path.insert(0, str(BACKEND))
os.environ.setdefault("SONIFY_VAR_DIR", str(BACKEND / "var"))


def main() -> int:
    ap = argparse.ArgumentParser(description="Run Sonify API")
    ap.add_argument("--host", default=os.getenv("SONIFY_HOST", "127.0.0.1"))
    ap.add_argument("--port", type=int, default=int(os.getenv("SONIFY_PORT", "8080")))
    ap.add_argument("--log-level", default="info")
    args = ap.parse_args()

    try:
        import uvicorn
    except ImportError:
        print("Нужны fastapi и uvicorn:  pip install 'fastapi>=0.115' 'uvicorn>=0.30'", file=sys.stderr)
        return 2

    from sonify_api.main import app

    uvicorn.run(app, host=args.host, port=args.port, log_level=args.log_level)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
