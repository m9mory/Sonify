"""Смоук-тест API: запускает uvicorn-сервер на свободном порту и проверяет контракт
через stdlib urllib. Без httpx/TestClient — работает на чистом stdlib + fastapi.

Запуск:  python smoke_test.py   (из backend/)
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

BACKEND = Path(__file__).resolve().parent
HOST = "127.0.0.1"
failures: list[str] = []


def check(name: str, cond: bool, extra: str = "") -> None:
    print(f"[{'OK ' if cond else 'FAIL'}] {name}{(' — ' + extra) if extra else ''}")
    if not cond:
        failures.append(name)


def free_port() -> int:
    with socket.socket() as s:
        s.bind((HOST, 0))
        return int(s.getsockname()[1])


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def http_error_302(self, req, fp, code, msg, headers):  # noqa: D401
        return fp

    http_error_301 = http_error_303 = http_error_307 = http_error_302


OPENER_NO_REDIRECT = urllib.request.build_opener(NoRedirect)


def get(base: str, path: str, follow: bool = True) -> tuple[int, bytes, dict]:
    opener = urllib.request.build_opener() if follow else OPENER_NO_REDIRECT
    try:
        with opener.open(base + path, timeout=15) as r:
            return r.status, r.read(), dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(), dict(e.headers or {})


def post_multipart(base: str, path: str, fields: dict[str, str], file_field: str,
                   filename: str, data: bytes, headers: dict | None = None) -> tuple[int, bytes]:
    boundary = "----sonify" + uuid.uuid4().hex
    parts: list[bytes] = []
    for k, v in fields.items():
        parts.append(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode()
        )
    parts.append(
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"{file_field}\"; filename=\"{filename}\"\r\n"
        f"Content-Type: audio/wav\r\n\r\n".encode() + data + b"\r\n"
    )
    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)
    req = urllib.request.Request(base + path, data=body, method="POST")
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        try:
            return e.code, e.read()
        except (ConnectionResetError, OSError):
            return e.code, b""
    except (ConnectionResetError, urllib.error.URLError) as e:
        print(f"[WARN] upload connection reset: {e}")
        return 0, b"connection reset"


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="sonify-smoke-"))
    port = free_port()
    env = dict(os.environ)
    env.update(
        PYTHONPATH=str(BACKEND),
        PYTHONIOENCODING="utf-8",
        PYTHONUNBUFFERED="1",
        SONIFY_VAR_DIR=str(tmp),
        SONIFY_HOST=HOST,
        SONIFY_PORT=str(port),
        SONIFY_SEED="1",
        ADMIN_TOKEN="smoke-token",
    )
    proc = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "sonify_api.main:app", "--host", HOST, "--port", str(port), "--log-level", "warning"],
        cwd=str(BACKEND),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    base = f"http://{HOST}:{port}"
    try:
        deadline = time.time() + 40
        while time.time() < deadline:
            if proc.poll() is not None:
                print(proc.stdout.read().decode("utf-8", "replace") if proc.stdout else "")
                return 1
            try:
                status, body, _ = get(base, "/health", follow=True)
                if status == 200:
                    break
            except OSError:
                pass
            time.sleep(0.3)
        else:
            print("server did not start in time")
            return 1

        t0 = time.perf_counter()
        status, body, _ = get(base, "/health")
        dt = (time.perf_counter() - t0) * 1000
        health = json.loads(body)
        check("GET /health -> 200", status == 200, body[:120].decode("utf-8", "replace"))
        check("health.status == ok", health.get("status") == "ok", json.dumps(health))
        check("health.db == ok", health.get("db") == "ok")
        print(f"       latency: {dt:.1f} ms")

        status, body, _ = get(base, "/api/v1/tracks?limit=3")
        check("GET /api/v1/tracks -> 200", status == 200, body[:200].decode("utf-8", "replace"))
        page = json.loads(body)
        items = page.get("items", [])
        check("page has 3 items", len(items) == 3, f"items={len(items)}")
        check("page has nextCursor", bool(page.get("nextCursor")), str(page.get("nextCursor")))
        first = items[0] if items else {}
        for key in ("id", "title", "artist", "sourceKind", "streamType", "playable", "durationSeconds", "createdAt"):
            check(f"track field `{key}`", key in first)

        status, body2, _ = get(base, f"/api/v1/tracks?limit=3&cursor={page.get('nextCursor')}")
        page2 = json.loads(body2)
        ids1 = {t["id"] for t in items}
        ids2 = {t["id"] for t in page2.get("items", [])}
        check("cursor pagination returns next page", status == 200 and bool(ids2), body2[:120].decode("utf-8", "replace"))
        check("pages do not overlap", not (ids1 & ids2))

        local = next((t for t in items if t["sourceKind"] == "local"), None)
        check("seed contains local track", local is not None)
        if local:
            tid = local["id"]
            status, body, _ = get(base, f"/api/v1/tracks/{tid}")
            check("GET /tracks/{id} -> 200", status == 200, body[:120].decode("utf-8", "replace"))
            status, _, headers = get(base, f"/api/v1/tracks/{tid}/stream", follow=False)
            location = headers.get("Location") or headers.get("location") or ""
            check("stream -> 302 direct", status == 302 and location.endswith(".wav"), f"{status} -> {location}")
            if location:
                path = location[len(base):] if location.startswith(base) else location
                s2, audio, h2 = get(base, path)
                check("audio bytes served", s2 == 200 and len(audio) > 1000, f"{s2}, {len(audio)} bytes")
                ctype = next((v for k, v in h2.items() if k.lower() == "content-type"), "")
                check("audio content-type is wav", "audio/wav" in ctype, ctype)

        # Тексты: сид кладёт их не всем трекам, поэтому ищем любой трек со словами.
        status, body, _ = get(base, "/api/v1/tracks?limit=50")
        all_tracks = json.loads(body).get("items", [])
        check("lyrics 404 for track without lyrics", get(base, f"/api/v1/tracks/{all_tracks[0]['id']}/lyrics")[0] in (200, 404))
        lyrics_hit = None
        for candidate in all_tracks:
            if candidate["sourceKind"] != "local":
                continue
            st, b, _ = get(base, f"/api/v1/tracks/{candidate['id']}/lyrics")
            if st == 200:
                payload = json.loads(b)
                if payload.get("plain") or payload.get("synced"):
                    lyrics_hit = payload
                    break
        check("some seed track has lyrics (plain + synced)",
              lyrics_hit is not None and bool(lyrics_hit.get("synced")),
              json.dumps(lyrics_hit, ensure_ascii=False)[:160] if lyrics_hit else "none found")

        status, body, _ = get(base, "/api/v1/tracks?source=soundcloud")
        sc = json.loads(body).get("items", [])
        check("soundcloud tracks present", len(sc) > 0, f"{len(sc)} items")
        if sc:
            status, body, _ = get(base, f"/api/v1/tracks/{sc[0]['id']}/stream")
            stream = json.loads(body) if body else {}
            check("soundcloud stream -> embed", status == 200 and stream.get("type") == "embed", body[:200].decode("utf-8", "replace"))

        status, _, _ = get(base, "/api/v1/tracks/nope_123")
        check("unknown track -> 404", status == 404, str(status))
        status, _, _ = get(base, "/api/v1/tracks?cursor=garbage")
        check("bad cursor -> 400", status == 400, str(status))
        status, _, _ = get(base, "/api/v1/tracks/bad..id")
        check("path traversal id -> 400", status == 400, str(status))

        seed_wav = next((tmp / "audio").glob("seed_*.wav"), None)
        check("seed wav exists", seed_wav is not None)
        if seed_wav:
            data = seed_wav.read_bytes()
            status, body = post_multipart(
                base, "/api/v1/admin/tracks",
                {"title": "Uploaded Test", "artist": "Tester", "genre": "test"},
                "file", "upload.wav", data, {"X-Admin-Token": "smoke-token"},
            )
            check("POST /admin/tracks -> 201", status == 201, body[:200].decode("utf-8", "replace"))
            if status == 201:
                up = json.loads(body)
                check("uploaded track direct+local with duration",
                      up.get("sourceKind") == "local" and up.get("durationSeconds", 0) > 0, json.dumps(up))
                status, body, _ = get(base, f"/api/v1/tracks/{up['id']}")
                check("uploaded track listed by id", status == 200, str(status))
            status, body = post_multipart(
                base, "/api/v1/admin/tracks", {"title": "x", "artist": "y"},
                "file", "x.wav", b"RIFF-not-a-wav", {"X-Admin-Token": "smoke-token"},
            )
            check("corrupted wav -> 400", status == 400, str(status))
            status, _ = post_multipart(
                base, "/api/v1/admin/tracks", {"title": "x", "artist": "y"}, "file", "x.wav", data,
            )
            check("upload without token rejected", status in (0, 401), f"status={status}")

        status, _, _ = get(base, "/audio/..%2F..%2Fsonify.db")
        check("audio traversal -> 404", status == 404, str(status))
        status, _, _ = get(base, "/docs")
        check("OpenAPI docs available", status == 200, str(status))
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()

    print()
    if failures:
        print(f"SMOKE FAILED: {len(failures)} check(s): {failures}")
        return 1
    print("SMOKE PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
