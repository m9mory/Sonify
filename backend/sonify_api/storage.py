"""Хранилище аудио. MVP — локальный диск; в проде тот же интерфейс для S3/MinIO."""

from __future__ import annotations

import re
import uuid
from pathlib import Path

SAFE_NAME_RE = re.compile(r"[^A-Za-z0-9._-]")


class Storage:
    def __init__(self, audio_dir: Path, static_dir: Path) -> None:
        self.audio_dir = Path(audio_dir)
        self.static_dir = Path(static_dir)

    def ensure(self) -> None:
        self.audio_dir.mkdir(parents=True, exist_ok=True)
        (self.static_dir / "artwork").mkdir(parents=True, exist_ok=True)

    def save_audio(self, raw: bytes, original_name: str) -> Path:
        suffix = Path(original_name).suffix.lower() or ".wav"
        name = f"{uuid.uuid4().hex}{suffix}"
        target = self.audio_dir / name
        target.write_bytes(raw)
        return target

    def audio_path(self, filename: str) -> Path | None:
        """Возвращает путь только для существующего файла внутри audio_dir (без выхода за его пределы)."""
        if not filename or SAFE_NAME_RE.search(filename):
            return None
        candidate = (self.audio_dir / filename).resolve()
        if self.audio_dir.resolve() not in candidate.parents:
            return None
        return candidate if candidate.is_file() else None

    def delete_audio(self, filename: str) -> None:
        path = self.audio_path(filename)
        if path is not None:
            path.unlink(missing_ok=True)
