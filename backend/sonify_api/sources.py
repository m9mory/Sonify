"""Абстракция источника треков.

Плееру не важно, откуда звук: POST /tracks/{id}/stream отвечает
StreamDescriptor и iOS выбирает нативный AVPlayer или официальный
SoundCloud-эмбед. Чтобы добавить источник, реализуй TrackSource и
зарегистрируй его в build_default_sources().
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from urllib.parse import quote

from .config import Settings


class SourceError(Exception):
    def __init__(self, code: str, message: str, status: int = 400) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


@dataclass
class StreamDescriptor:
    type: str  # direct | embed | unavailable
    url: str | None = None
    embed_url: str | None = None
    mime: str = "audio/wav"
    expires_in: int | None = None

    def to_dict(self) -> dict:
        return {k: v for k, v in asdict(self).items() if v is not None}


@dataclass(frozen=True)
class TrackRecord:
    id: str
    title: str
    artist_id: str
    artist_name: str
    genre: str | None
    duration_seconds: int
    artwork_url: str | None
    source_kind: str
    source_ref: str | None
    audio_url: str | None
    is_playable: bool
    like_count: int
    play_count: int
    created_at: str
    lyrics_available: bool = False
    extra: dict = field(default_factory=dict)


class TrackSource:
    kind: str = "base"

    def resolve_stream(self, track: TrackRecord) -> StreamDescriptor:
        raise NotImplementedError


class LocalSource(TrackSource):
    """Треки, загруженные на Sonify (S3/MinIO в проде, локальный диск в MVP)."""

    kind = "local"

    def __init__(self, settings: Settings, url_signer=None) -> None:
        self.settings = settings
        self.url_signer = url_signer

    def resolve_stream(self, track: TrackRecord) -> StreamDescriptor:
        if not track.is_playable or not track.audio_url:
            return StreamDescriptor(type="unavailable")
        if self.url_signer is not None:
            url = self.url_signer(track.audio_url)
        else:
            url = track.audio_url
        return StreamDescriptor(type="direct", url=url, mime="audio/wav")


class SoundCloudEmbedSource(TrackSource):
    """Официальный SoundCloud Widget — без перехвата приватного API.

    Если клиент передан и есть client_id, можно получать длительность и метаданные
    через публичный /resolve; без него достаточно source_ref (URL трека).
    """

    kind = "soundcloud"

    def __init__(self, settings: Settings, client=None) -> None:
        self.settings = settings
        self.client = client

    def resolve_stream(self, track: TrackRecord) -> StreamDescriptor:
        if not self.settings.soundcloud_embeds or not track.source_ref:
            return StreamDescriptor(type="unavailable")
        embed = "https://w.soundcloud.com/player/?url=" + quote(track.source_ref, safe="") + "&auto_play=true"
        return StreamDescriptor(type="embed", embed_url=embed)


def build_default_sources(settings: Settings) -> dict[str, TrackSource]:
    sources: dict[str, TrackSource] = {}
    local = LocalSource(settings)
    sources[local.kind] = local
    sc = SoundCloudEmbedSource(settings)
    sources[sc.kind] = sc
    return sources
