"""Сид-данные для MVP: треки генерируются как WAV на stdlib и кладутся в audio_dir,
плюс 2 трека SoundCloud (embed) для проверки второго источника.
Идемпотентно: если в таблице tracks что-то есть — ничего не делает.
"""

from __future__ import annotations

import json
import uuid
from urllib.parse import quote

from .db import Database, utcnow_iso
from .storage import Storage
from .wavutil import render_wav

SEED = [
    # (title, artist, genre, duration, seed, lyrics)
    (
        "Neon Drift",
        "Lumen",
        "synthwave",
        32,
        1,
        [
            {"t": 0.0, "line": "Неоновый дрейф по пустому шоссе"},
            {"t": 8.0, "line": "Фары рисуют город на стекле"},
            {"t": 16.0, "line": "Мы едем туда, где нет часов"},
            {"t": 24.0, "line": "И темнота звучит светлее"},
        ],
    ),
    (
        "Midnight Tape",
        "Kira Voss",
        "lo-fi",
        28,
        2,
        [
            {"t": 0.0, "line": "Кассета крутится медленнее сердца"},
            {"t": 9.0, "line": "Тихий шум и тёплый дождь"},
            {"t": 18.0, "line": "Запиши меня на стороне B"},
        ],
    ),
    (
        "Glass Gardens",
        "Aster Field",
        "ambient",
        36,
        3,
        None,
    ),
    (
        "Slow Motion",
        "Mira Cult",
        "house",
        30,
        4,
        [
            {"t": 0.0, "line": "Всё в замедленной съёмке"},
            {"t": 10.0, "line": "Бас держит нас на земле"},
            {"t": 20.0, "line": "Мы танцуем вполоборота"},
        ],
    ),
    (
        "Static Bloom",
        "Lowkey Prince",
        "trap",
        26,
        5,
        None,
    ),
    (
        "Afterglow",
        "Lumen",
        "synthwave",
        34,
        1,
        None,
    ),
]

SOUNDCLOUD_TRACKS = [
    ("SoundCloud: Deep Focus Mix", "SoundCloud Selects", "https://soundcloud.com/forss/flickermood"),
    ("SoundCloud: Late Night Set", "SoundCloud Selects", "https://soundcloud.com/tycho/daydream"),
]


def seed_if_empty(db: Database, storage: Storage) -> None:
    row = db.query_one("SELECT COUNT(*) AS c FROM tracks")
    if row and row["c"] > 0:
        return

    now = utcnow_iso()
    artist_ids: dict[str, str] = {}
    for i, (title, artist_name, genre, duration, seed, lyrics) in enumerate(SEED):
        artist_id = artist_ids.get(artist_name)
        if artist_id is None:
            artist_id = f"art_{uuid.uuid4().hex[:12]}"
            artist_ids[artist_name] = artist_id
            db.execute(
                "INSERT INTO artists (id, name, source_kind, created_at) VALUES (?,?,?,?)",
                (artist_id, artist_name, "local", now),
            )

        track_id = f"trk_{uuid.uuid4().hex[:12]}"
        fname = f"seed_{i + 1}.wav"
        path = storage.audio_dir / fname
        if not path.is_file():
            render_wav(path, duration, genre=genre, seed=seed)

        db.execute(
            "INSERT INTO tracks (id, artist_id, title, genre, duration_seconds, source_kind, source_ref,"
            " audio_url, is_playable, like_count, play_count, created_at, updated_at)"
            " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (track_id, artist_id, title, genre, duration, "local", fname, f"/audio/{fname}", 1, 10 + i * 7, 120 + i * 30, now, now),
        )
        if lyrics:
            db.execute(
                "INSERT INTO lyrics (track_id, plain, synced, language, updated_at) VALUES (?,?,?,?,?)",
                (
                    track_id,
                    "\n".join(line["line"] for line in lyrics),
                    json.dumps([{"t": line["t"], "line": line["line"]} for line in lyrics], ensure_ascii=False),
                    "ru",
                    now,
                ),
            )

    sc_artist = "art_sc_selects"
    db.execute(
        "INSERT INTO artists (id, name, source_kind, created_at) VALUES (?,?,?,?)",
        (sc_artist, "SoundCloud Selects", "soundcloud", now),
    )
    for title, _, sc_url in SOUNDCLOUD_TRACKS:
        db.execute(
            "INSERT INTO tracks (id, artist_id, title, genre, duration_seconds, source_kind, source_ref,"
            " is_playable, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)",
            (f"trk_{uuid.uuid4().hex[:12]}", sc_artist, title, None, 0, "soundcloud", sc_url, 1, now, now),
        )
