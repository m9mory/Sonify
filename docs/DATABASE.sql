-- Sonify — схема БД (совместима с SQLite и PostgreSQL)
-- SQLite применяется приложением автоматически (backend/sonify_api/db.py),
-- PostgreSQL — при первом старте контейнера (infra/db/01_schema.sql).

CREATE TABLE IF NOT EXISTS users (
    id           TEXT PRIMARY KEY,
    email        TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    avatar_url   TEXT,
    role         TEXT NOT NULL DEFAULT 'listener',  -- listener | artist | admin
    created_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS artists (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    bio        TEXT,
    avatar_url TEXT,
    source_kind TEXT NOT NULL DEFAULT 'local',       -- local | soundcloud
    source_ref TEXT,                                   -- sc: permalink / sc user id
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_artists_name ON artists(name);

CREATE TABLE IF NOT EXISTS tracks (
    id               TEXT PRIMARY KEY,
    artist_id        TEXT NOT NULL REFERENCES artists(id) ON DELETE CASCADE,
    title            TEXT NOT NULL,
    genre            TEXT,
    duration_seconds INTEGER NOT NULL DEFAULT 0,
    artwork_url      TEXT,
    source_kind      TEXT NOT NULL DEFAULT 'local',  -- local | soundcloud
    source_ref       TEXT,                            -- local: имя файла; sc: URL трека
    audio_url        TEXT,                            -- local: /audio/<file> или S3 key
    is_playable      INTEGER NOT NULL DEFAULT 1,
    like_count       INTEGER NOT NULL DEFAULT 0,
    play_count       INTEGER NOT NULL DEFAULT 0,
    moderation_status TEXT NOT NULL DEFAULT 'approved', -- pending | approved | rejected | takedown
    created_at       TEXT NOT NULL,
    updated_at       TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tracks_created  ON tracks(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tracks_artist   ON tracks(artist_id);
CREATE INDEX IF NOT EXISTS idx_tracks_genre    ON tracks(genre);
CREATE INDEX IF NOT EXISTS idx_tracks_source   ON tracks(source_kind);

CREATE TABLE IF NOT EXISTS lyrics (
    track_id  TEXT PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
    plain     TEXT,
    synced    TEXT,            -- JSON: [{"t":12.5,"line":"..."}]
    language  TEXT,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS playlists (
    id          TEXT PRIMARY KEY,
    owner_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title       TEXT NOT NULL,
    description TEXT,
    cover_url   TEXT,
    is_public   INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_playlists_owner ON playlists(owner_id);

CREATE TABLE IF NOT EXISTS playlist_tracks (
    playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    track_id    TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    position    INTEGER NOT NULL DEFAULT 0,
    added_at    TEXT NOT NULL,
    PRIMARY KEY (playlist_id, track_id)
);

CREATE TABLE IF NOT EXISTS likes (
    user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    track_id   TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL,
    PRIMARY KEY (user_id, track_id)
);
CREATE INDEX IF NOT EXISTS idx_likes_track ON likes(track_id);

CREATE TABLE IF NOT EXISTS play_history (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,  -- в PG: BIGSERIAL (см. infra/db/01_schema.sql)
    user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    track_id      TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    position_seconds REAL NOT NULL DEFAULT 0,
    completed     INTEGER NOT NULL DEFAULT 0,
    played_at     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_play_history_user  ON play_history(user_id, played_at DESC);
CREATE INDEX IF NOT EXISTS idx_play_history_track ON play_history(track_id);

CREATE TABLE IF NOT EXISTS recommendations (
    id         TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    track_id   TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    score      REAL NOT NULL DEFAULT 0,
    reason     TEXT,                    -- same_genre | liked_by_similar | trending
    expires_at TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_reco_user_score ON recommendations(user_id, score DESC);
