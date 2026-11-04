"""Pydantic-схемы ответов API (контракт backend ↔ iOS, см. docs/API.md)."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class ArtistOut(BaseModel):
    id: str
    name: str
    avatar_url: str | None = Field(None, alias="avatarUrl")

    model_config = {"populate_by_name": True}


class TrackOut(BaseModel):
    id: str
    title: str
    artist: ArtistOut
    artwork_url: str | None = Field(None, alias="artworkUrl")
    duration_seconds: int = Field(alias="durationSeconds")
    genre: str | None = None
    source_kind: Literal["local", "soundcloud"] = Field(alias="sourceKind")
    stream_type: Literal["direct", "embed", "unavailable"] = Field(alias="streamType")
    playable: bool
    like_count: int = Field(alias="likeCount")
    created_at: str = Field(alias="createdAt")

    model_config = {"populate_by_name": True}


class PageOut(BaseModel):
    items: list[TrackOut]
    next_cursor: str | None = Field(None, alias="nextCursor")

    model_config = {"populate_by_name": True}


class HealthOut(BaseModel):
    status: str
    version: str
    db: str
    uptimeSeconds: int


class StreamOut(BaseModel):
    type: Literal["direct", "embed", "unavailable"]
    url: str | None = None
    embedUrl: str | None = None
    mime: str | None = None
    expiresIn: int | None = None


class LyricsOut(BaseModel):
    trackId: str
    plain: str | None = None
    synced: list[dict] | None = None


class UploadResultOut(BaseModel):
    id: str
    title: str
    sourceKind: str
    streamType: str
    durationSeconds: int


class ErrorBody(BaseModel):
    code: str
    message: str


class ErrorOut(BaseModel):
    error: ErrorBody
