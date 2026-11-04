FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY backend/pyproject.toml /app/pyproject.toml
COPY backend/sonify_api /app/sonify_api
COPY docs/DATABASE.sql /docs/DATABASE.sql

RUN pip install --upgrade pip && pip install ".[postgres]"

# SQLite-файл и аудио; в проде монтируется том или заменяется S3
RUN mkdir -p /app/var/audio && useradd -m -u 10001 sonify && chown -R sonify:sonify /app /docs
USER sonify

ENV SONIFY_HOST=0.0.0.0 \
    SONIFY_PORT=8080 \
    SONIFY_VAR_DIR=/app/var \
    SONIFY_STATIC_DIR=/app/var

EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=40s --retries=5 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2).status==200 else 1)"

CMD ["python", "-m", "uvicorn", "sonify_api.main:app", "--host", "0.0.0.0", "--port", "8080"]
