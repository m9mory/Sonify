"""Сборка FastAPI-приложения."""

from __future__ import annotations

import json
import logging
import re
import sqlite3
import time
import uuid
from contextlib import asynccontextmanager
from typing import Annotated
from urllib.parse import unquote_plus

from fastapi import FastAPI, Header, HTTPException, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, Response, RedirectResponse

from . import __version__
from .config import Settings
from .db import Database, utcnow_iso
from .schemas import HealthOut, LyricsOut, PageOut, StreamOut, TrackOut, UploadResultOut
from .seed import seed_if_empty
from .sources import SourceError, TrackRecord, build_default_sources
from .storage import Storage
from .wavutil import wav_duration

log = logging.getLogger("sonify")
ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
CURSOR_OFFSET_RE = re.compile(r"^o:(\d+)$")
CURSOR_KEYSET_RE = re.compile(r"^k:([0-9T:\-Z]+)\|(.+)$")
MAX_MULTIPART_BYTES = 1024 * 1024  # поля формы, без учёта аудио


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


def _err(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"error": {"code": code, "message": message}})


def parse_multipart(body: bytes, content_type: str) -> tuple[dict[str, str], dict[str, tuple[str, bytes]]]:
    """Минимальный multipart/form-data парсер (stdlib): поля и файлы.

    Возвращает ({поле: значение}, {имя: (filename, bytes)}). Достаточно для
    загрузки трека из iOS/curl без зависимости python-multipart.
    """
    marker = "boundary="
    idx = content_type.find(marker)
    if idx < 0:
        raise ApiError(400, "bad_request", "multipart boundary missing")
    boundary = content_type[idx + len(marker):].split(";")[0].strip().strip('"')
    if not boundary:
        raise ApiError(400, "bad_request", "multipart boundary missing")
    sep = b"--" + boundary.encode()
    fields: dict[str, str] = {}
    files: dict[str, tuple[str, bytes]] = {}
    for part in body.split(sep):
        if not part or part.strip(b"-") == b"":
            continue
        part = part[2:] if part.startswith(b"\r\n") else part
        head, _, payload = part.partition(b"\r\n\r\n")
        payload = payload[: -2] if payload.endswith(b"\r\n") else payload
        headers = {}
        for line in head.decode("utf-8", "replace").split("\r\n"):
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()
        disp = headers.get("content-disposition", "")
        name_m = re.search(r'name="([^"]*)"', disp)
        if not name_m:
            continue
        name = name_m.group(1)
        file_m = re.search(r'filename="([^"]*)"', disp)
        if file_m:
            files[name] = (file_m.group(1), payload)
        else:
            fields[name] = payload.decode("utf-8", "replace")
    return fields, files


def _new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


def _row_to_track(row: sqlite3.Row, base_url: str) -> dict:
    kind = row["source_kind"]
    stream_type = "unavailable"
    if row["is_playable"]:
        if kind == "local":
            stream_type = "direct"
        elif kind == "soundcloud":
            stream_type = "embed"
    artwork = row["artwork_url"]
    if artwork and not artwork.startswith(("http://", "https://")):
        artwork = base_url + artwork
    return {
        "id": row["id"],
        "title": row["title"],
        "artist": {"id": row["artist_id"], "name": row["artist_name"], "avatarUrl": row["avatar_url"]},
        "artworkUrl": artwork,
        "durationSeconds": row["duration_seconds"],
        "genre": row["genre"],
        "sourceKind": kind,
        "streamType": stream_type,
        "playable": bool(row["is_playable"]),
        "likeCount": row["like_count"],
        "createdAt": row["created_at"],
    }


def _row_to_record(row: sqlite3.Row) -> TrackRecord:
    return TrackRecord(
        id=row["id"],
        title=row["title"],
        artist_id=row["artist_id"],
        artist_name=row["artist_name"],
        genre=row["genre"],
        duration_seconds=row["duration_seconds"],
        artwork_url=row["artwork_url"],
        source_kind=row["source_kind"],
        source_ref=row["source_ref"],
        audio_url=row["audio_url"],
        is_playable=bool(row["is_playable"]),
        like_count=row["like_count"],
        play_count=row["play_count"],
        created_at=row["created_at"],
        lyrics_available=row["lyrics_available"] is not None,
    )


TRACK_SELECT = """
SELECT t.id, t.title, t.genre, t.duration_seconds, t.artwork_url, t.source_kind, t.source_ref,
       t.audio_url, t.is_playable, t.like_count, t.play_count, t.created_at,
       t.artist_id, a.name AS artist_name, a.avatar_url AS avatar_url,
       l.track_id AS lyrics_available
FROM tracks t
JOIN artists a ON a.id = t.artist_id
LEFT JOIN lyrics l ON l.track_id = t.id
"""


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    db = Database(settings.db_path)
    storage = Storage(settings.audio_dir, settings.static_dir)
    sources = build_default_sources(settings)
    started_at = time.monotonic()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        db.connect()
        storage.ensure()
        if settings.seed:
            seed_if_empty(db, storage)
        log.info("sonify api ready: db=%s audio=%s", settings.db_path, settings.audio_dir)
        yield
        db.close()

    app = FastAPI(
        title="Sonify API",
        version=__version__,
        description="Backend для iOS-приложения Sonify. Контракт: docs/API.md",
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.db = db
    app.state.storage = storage
    app.state.sources = sources

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"] if settings.env == "dev" else [],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.exception_handler(SourceError)
    async def _source_error(_: Request, exc: SourceError) -> JSONResponse:
        return _err(exc.status, exc.code, exc.message)

    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError) -> JSONResponse:
        return _err(exc.status, exc.code, exc.message)

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={"error": {"code": "bad_request", "message": "validation failed", "details": exc.errors()}},
        )

    def _base_url(request: Request) -> str:
        if settings.public_base_url:
            return settings.public_base_url.rstrip("/")
        return str(request.base_url).rstrip("/")

    def _absolutize(value: str | None, base_url: str) -> str | None:
        if not value:
            return None
        if value.startswith("http://") or value.startswith("https://"):
            return value
        return base_url + value

    # ---------- health ----------

    @app.get("/health", response_model=HealthOut, tags=["system"])
    def health() -> dict:
        ok = db.ping()
        return {
            "status": "ok" if ok else "degraded",
            "version": __version__,
            "db": "ok" if ok else "error",
            "uptimeSeconds": int(time.monotonic() - started_at),
        }

    # ---------- tracks ----------

    @app.get("/api/v1/tracks", response_model=PageOut, tags=["tracks"])
    def list_tracks(
        request: Request,
        limit: Annotated[int, Query(ge=1, le=100)] = 20,
        cursor: str | None = None,
        source: Annotated[str | None, Query(pattern="^(local|soundcloud)$")] = None,
        artist_id: str | None = None,
        genre: str | None = None,
        q: str | None = None,
    ) -> dict:
        base_url = _base_url(request)
        where = ["t.moderation_status = 'approved'"]
        params: list = []
        if source:
            where.append("t.source_kind = ?")
            params.append(source)
        if artist_id:
            if not ID_RE.match(artist_id):
                raise HTTPException(status_code=400, detail="invalid artistId")
            where.append("t.artist_id = ?")
            params.append(artist_id)
        if genre:
            where.append("t.genre = ?")
            params.append(genre)
        if q:
            where.append("(t.title LIKE ? OR a.name LIKE ?)")
            like = f"%{q}%"
            params += [like, like]

        offset = 0
        keyset: tuple[str, str] | None = None
        if cursor:
            m_off = CURSOR_OFFSET_RE.match(cursor)
            m_key = CURSOR_KEYSET_RE.match(cursor)
            if m_off:
                offset = int(m_off.group(1))
            elif m_key:
                keyset = (m_key.group(1), m_key.group(2))
            else:
                raise HTTPException(status_code=400, detail="invalid cursor")

        sql = TRACK_SELECT + " WHERE " + " AND ".join(where)
        sql_params = list(params)
        if keyset is not None:
            sql += " AND (t.created_at < ? OR (t.created_at = ? AND t.id > ?))"
            sql_params += [keyset[0], keyset[0], keyset[1]]
            sql += " ORDER BY t.created_at DESC, t.id ASC LIMIT ?"
            sql_params.append(limit + 1)
        else:
            sql += " ORDER BY t.created_at DESC, t.id ASC LIMIT ? OFFSET ?"
            sql_params += [limit + 1, offset]

        rows = db.query_all(sql, tuple(sql_params))
        has_more = len(rows) > limit
        rows = rows[:limit]

        if keyset is not None:
            next_cursor = None
            if has_more and rows:
                last = rows[-1]
                next_cursor = f"k:{last['created_at']}|{last['id']}"
        else:
            next_cursor = f"o:{offset + limit}" if has_more else None

        return {"items": [_row_to_track(r, base_url) for r in rows], "nextCursor": next_cursor}

    def _get_track_row(track_id: str) -> sqlite3.Row:
        if not ID_RE.match(track_id):
            raise HTTPException(status_code=400, detail="invalid track id")
        row = db.query_one(TRACK_SELECT + " WHERE t.id = ? AND t.moderation_status = 'approved'", (track_id,))
        if row is None:
            raise HTTPException(status_code=404, detail="track not found")
        return row

    @app.get("/api/v1/tracks/{track_id}", response_model=TrackOut, tags=["tracks"])
    def get_track(track_id: str, request: Request) -> dict:
        row = _get_track_row(track_id)
        payload = _row_to_track(row, _base_url(request))
        if payload["streamType"] == "embed":
            desc = sources["soundcloud"].resolve_stream(_row_to_record(row))
            payload["embedUrl"] = desc.embed_url
        return payload

    @app.get("/api/v1/tracks/{track_id}/stream", tags=["tracks"])
    @app.head("/api/v1/tracks/{track_id}/stream", include_in_schema=False)
    def track_stream(track_id: str, request: Request):
        row = _get_track_row(track_id)
        record = _row_to_record(row)
        source = sources.get(row["source_kind"])
        if source is None:
            raise HTTPException(status_code=404, detail="source not configured")
        desc = source.resolve_stream(record)
        if desc.type == "direct" and desc.url:
            url = _absolutize(desc.url, _base_url(request)) or desc.url
            return RedirectResponse(url=url, status_code=302)
        if desc.type == "embed":
            return StreamOut(type="embed", embedUrl=desc.embed_url)
        raise HTTPException(status_code=409, detail="track is not playable")

    @app.get("/api/v1/tracks/{track_id}/lyrics", response_model=LyricsOut, tags=["tracks"])
    def track_lyrics(track_id: str):
        _get_track_row(track_id)
        row = db.query_one("SELECT plain, synced FROM lyrics WHERE track_id = ?", (track_id,))
        if row is None:
            raise HTTPException(status_code=404, detail="lyrics not found")
        import json

        return {
            "trackId": track_id,
            "plain": row["plain"],
            "synced": json.loads(row["synced"]) if row["synced"] else None,
        }

    # ---------- artists ----------

    @app.get("/api/v1/artists/{artist_id}", tags=["artists"])
    def get_artist(artist_id: str, request: Request):
        if not ID_RE.match(artist_id):
            raise HTTPException(status_code=400, detail="invalid artist id")
        row = db.query_one("SELECT * FROM artists WHERE id = ?", (artist_id,))
        if row is None:
            raise HTTPException(status_code=404, detail="artist not found")
        count = db.query_one("SELECT COUNT(*) AS c FROM tracks WHERE artist_id = ?", (artist_id,))
        return {
            "id": row["id"],
            "name": row["name"],
            "bio": row["bio"],
            "avatarUrl": _absolutize(row["avatar_url"], _base_url(request)),
            "trackCount": count["c"] if count else 0,
        }

    @app.get("/api/v1/search", tags=["search"])
    def search(request: Request, q: Annotated[str, Query(min_length=1, max_length=100)], limit: int = 20):
        base_url = _base_url(request)
        like = f"%{q}%"
        rows = db.query_all(
            TRACK_SELECT
            + " WHERE t.moderation_status = 'approved' AND (t.title LIKE ? OR a.name LIKE ?)"
            + " ORDER BY t.created_at DESC LIMIT ?",
            (like, like, max(1, min(limit, 50))),
        )
        items = [{"kind": "track", "track": _row_to_track(r, base_url)} for r in rows]
        return {"items": items, "nextCursor": None}

    # ---------- audio (static, Range supported) ----------

    @app.get("/audio/{filename}", tags=["tracks"])
    @app.head("/audio/{filename}", include_in_schema=False)
    def audio_file(filename: str):
        path = storage.audio_path(filename)
        if path is None:
            raise HTTPException(status_code=404, detail="audio not found")
        return FileResponse(path, media_type="audio/wav", filename=path.name)

    # ---------- admin: upload ----------

    def _require_admin(token: str | None) -> None:
        if not token or token != settings.admin_token:
            raise HTTPException(status_code=401, detail="admin token required")

    @app.post("/api/v1/admin/tracks", response_model=UploadResultOut, status_code=201, tags=["admin"])
    async def upload_track(request: Request, x_admin_token: Annotated[str | None, Header()] = None):
        _require_admin(x_admin_token)

        body = await request.body()
        if len(body) > settings.max_upload_bytes:
            raise HTTPException(status_code=413, detail="file too large")
        fields, files = parse_multipart(body, request.headers.get("content-type", ""))
        title = (fields.get("title") or "").strip()
        artist = (fields.get("artist") or fields.get("artistName") or "").strip()
        genre = (fields.get("genre") or "").strip() or None
        source_url = (fields.get("source_url") or fields.get("sourceUrl") or "").strip()
        try:
            duration_seconds = int(fields["durationSeconds"]) if fields.get("durationSeconds") else None
        except ValueError:
            raise HTTPException(status_code=400, detail="durationSeconds must be an integer") from None
        if not title or not artist:
            raise HTTPException(status_code=400, detail="title and artist are required")
        if len(title) > 200 or len(artist) > 120:
            raise HTTPException(status_code=400, detail="title or artist too long")

        if source_url:
            # Легальный путь для библиотеки SoundCloud: только ссылка, без аудио.
            if not source_url.startswith("https://soundcloud.com/"):
                raise HTTPException(status_code=400, detail="only https://soundcloud.com/ links are allowed")
            artist_id, _ = _upsert_artist(db, artist, "soundcloud")
            track_id = _new_id("trk")
            now = utcnow_iso()
            db.execute(
                "INSERT INTO tracks (id, artist_id, title, genre, duration_seconds, source_kind, source_ref,"
                " is_playable, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)",
                (track_id, artist_id, title, genre, duration_seconds or 0, "soundcloud", source_url, 1, now, now),
            )
            return {
                "id": track_id,
                "title": title,
                "sourceKind": "soundcloud",
                "streamType": "embed",
                "durationSeconds": duration_seconds or 0,
            }

        upload = files.get("file")
        if upload is None:
            raise HTTPException(status_code=400, detail="file is required")
        filename, raw = upload
        if not raw:
            raise HTTPException(status_code=400, detail="empty file")
        if not filename.lower().endswith(".wav") or raw[:4] != b"RIFF":
            raise HTTPException(status_code=400, detail="only WAV uploads are supported in MVP (RIFF header expected)")

        stored = storage.save_audio(raw, filename or "upload.wav")
        try:
            dur = int(round(wav_duration(stored)))
        except Exception:  # noqa: BLE001 — битый WAV
            storage.delete_audio(stored.name)
            raise HTTPException(status_code=400, detail="corrupted WAV file") from None

        artist_id, _ = _upsert_artist(db, artist, "local")
        track_id = _new_id("trk")
        now = utcnow_iso()
        db.execute(
            "INSERT INTO tracks (id, artist_id, title, genre, duration_seconds, source_kind, source_ref,"
            " audio_url, is_playable, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (
                track_id,
                artist_id,
                title,
                genre,
                duration_seconds or dur,
                "local",
                stored.name,
                f"/audio/{stored.name}",
                1,
                now,
                now,
            ),
        )
        return {
            "id": track_id,
            "title": title,
            "sourceKind": "local",
            "streamType": "direct",
            "durationSeconds": duration_seconds or dur,
        }

    return app


def _upsert_artist(db: Database, name: str, source_kind: str) -> tuple[str, str]:
    row = db.query_one("SELECT id, name FROM artists WHERE name = ? AND source_kind = ?", (name, source_kind))
    if row:
        return row["id"], row["name"]
    artist_id = _new_id("art")
    db.execute(
        "INSERT INTO artists (id, name, source_kind, created_at) VALUES (?,?,?,?)",
        (artist_id, name, source_kind, utcnow_iso()),
    )
    return artist_id, name


def idle_dep() -> None:  # pragma: no cover - зарезервировано для будущих сервисов
    return None


__all__ = ["create_app"]
