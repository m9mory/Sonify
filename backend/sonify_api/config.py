"""Конфигурация из переменных окружения."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
REPO_SCHEMA = BACKEND_DIR.parent / "docs" / "DATABASE.sql"


def _bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _path_env(name: str, default: Path) -> Path:
    raw = os.getenv(name)
    return Path(raw).expanduser().resolve() if raw else default.resolve()


@dataclass(frozen=True)
class Settings:
    env: str
    host: str
    port: int
    db_path: Path
    audio_dir: Path
    static_dir: Path
    admin_token: str
    max_upload_bytes: int
    public_base_url: str | None
    seed: bool
    soundcloud_embeds: bool

    @classmethod
    def from_env(cls) -> "Settings":
        var = _path_env("SONIFY_VAR_DIR", BACKEND_DIR / "var")
        return cls(
            env=os.getenv("SONIFY_ENV", "dev"),
            host=os.getenv("SONIFY_HOST", "127.0.0.1"),
            port=int(os.getenv("SONIFY_PORT", "8080")),
            db_path=Path(os.getenv("SONIFY_DB_PATH") or var / "sonify.db").expanduser().resolve(),
            audio_dir=Path(os.getenv("SONIFY_AUDIO_DIR") or var / "audio").expanduser().resolve(),
            static_dir=Path(os.getenv("SONIFY_STATIC_DIR") or var).expanduser().resolve(),
            admin_token=os.getenv("ADMIN_TOKEN", "dev-admin-token"),
            max_upload_bytes=int(os.getenv("MAX_UPLOAD_BYTES", str(200 * 1024 * 1024))),
            public_base_url=(os.getenv("PUBLIC_BASE_URL") or None),
            seed=_bool("SONIFY_SEED", True),
            soundcloud_embeds=_bool("ENABLE_SOUNDCLOUD_EMBEDS", True),
        )
