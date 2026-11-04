# Sonify API — контракт backend ↔ iOS

- Базовый URL: `http://127.0.0.1:8080/api/v1` (iOS Simulator) / `http://<lan-ip>:8080/api/v1` (устройство)
- Формат: JSON, `Content-Type: application/json`, дата — ISO-8601 UTC (`2026-11-04T17:46:02Z`)
- Идентификаторы — строки (`trk_...`, `art_...`, `usr_...`)
- Ошибки: `{"error": {"code": "not_found", "message": "track not found"}}`, HTTP 4xx/5xx
- Списочные ответы: `{"items": [...], "nextCursor": "..." | null}`
- Авторизация (этап 2): `Authorization: Bearer <access_token>`
- `/health` — вне `/api/v1`, без авторизации (для docker/CI)

## Health

`GET /health` → `200`
```json
{"status":"ok","version":"0.1.0","db":"ok","uptimeSeconds":42}
```

## Треки

`GET /api/v1/tracks?limit=20&cursor=...&source=local|soundcloud&artistId=art_1`
→ `200`
```json
{
  "items": [
    {
      "id": "trk_1",
      "title": "Neon Drift",
      "artist": {"id": "art_1", "name": "Lumen", "avatarUrl": null},
      "artworkUrl": null,
      "durationSeconds": 214,
      "genre": "synthwave",
      "sourceKind": "local",
      "streamType": "direct",
      "playable": true,
      "likeCount": 12,
      "createdAt": "2026-11-04T17:46:02Z"
    }
  ],
  "nextCursor": null
}
```
`sourceKind`: `local` | `soundcloud`. `streamType`: `direct` | `embed` | `unavailable` — iOS по нему выбирает `AVPlayer` или `WKWebView`.

`GET /api/v1/tracks/{id}` → `200` — объект трека + `sourceRef`, `lyricsAvailable`, `embedUrl` (для embed).

`GET /api/v1/tracks/{id}/stream` →
- `direct` → `302 Location: <подписанный URL / /audio/{file}>`
- `embed` → `200 {"type":"embed","embedUrl":"https://w.soundcloud.com/player/?url=..."}`

`GET /api/v1/tracks/{id}/lyrics` → `200 {"trackId":"trk_1","plain":null,"synced":[{"t":12.5,"line":"..."}]}` или `404`.

`GET /api/v1/search?q=...&limit=20` → `200` — `{"items":[{"kind":"track|artist","track":{...}}],"nextCursor":null}` (этап 2; в MVP возвращает подстроку по title/artist).

## Артисты

`GET /api/v1/artists/{id}` → `{"id","name","bio","avatarUrl","trackCount"}`
`GET /api/v1/artists/{id}/tracks` → то же, что `/tracks?artistId=...`

## Рекомендации (этап 2)

`GET /api/v1/me/recommendations?limit=20` → `{items, nextCursor}`, `reason`: `"liked_by_similar" | "same_genre" | "trending"`.

## Плейлисты (этап 2)

`GET /api/v1/playlists` · `POST /api/v1/playlists` · `GET /api/v1/playlists/{id}` (с `tracks`) · `PATCH /:id` · `DELETE /:id` · `POST /:id/tracks {trackId, position}` · `DELETE /:id/tracks/{trackId}`

## Лайки / история (этап 2)

`GET /api/v1/me/likes` · `PUT /api/v1/me/likes/{trackId}` (идемпотентно, `204`) · `DELETE` (`204`)
`POST /api/v1/me/history {"trackId","positionSeconds","completed":false}` → `204`
`GET /api/v1/me/history?limit=50` → `{items:[{track,playedAt,positionSeconds}]}`

## Загрузка (админ, этап 0–1)

`POST /api/v1/admin/tracks` — `multipart/form-data`, поля: `file` (audio), `title`, `artistName`, `genre?`, `durationSeconds?`, `artwork?` (image)
Заголовок `X-Admin-Token: <ADMIN_TOKEN>`.
→ `201 {"id":"trk_1","sourceKind":"local","streamType":"direct"}`

## Профиль

`GET /api/v1/me` → `{"id","email","displayName","createdAt"}` (этап 2)
`PATCH /api/v1/me {"displayName"}` → `200`

## Коды ошибок
| code | HTTP |
|---|---|
| `bad_request` | 400 |
| `unauthorized` | 401 |
| `forbidden` | 403 |
| `not_found` | 404 |
| `payload_too_large` | 413 |
| `rate_limited` | 429 |
| `internal` | 500 |

## Соответствие iOS-моделей
`TrackDTO` → `Track` (`Domain/Track.swift`), `sourceKind`/`streamType` — enum `SourceKind`/`StreamType`, неизвестное значение → `.unknown` (декодируется, не падает).
