# Sonify — архитектура

## 1. Стек

| Слой | Выбор | Почему |
|---|---|---|
| Backend | **Python 3.11+ / FastAPI / Uvicorn** | Асинхронный, быстрый старт, один `pip install -e .` — поднимается в среде без Docker и без доступа к реестру npm. |
| БД | **SQLite через stdlib `sqlite3`** в MVP, **PostgreSQL** в docker-compose | Одна и та же схема (`docs/DATABASE.sql`), по умолчанию 0 зависимостей. Переход — `DATABASE_URL=postgresql://...` (см. §7). |
| Кэш | **Redis** (опционально, `REDIS_URL`), in-process TTL-LRU если Redis нет | Тестовое окружение стартует без Redis. |
| Аудио-хранилище | **S3-совместимое** (MinIO локально, R2/S3 в проде) через boto3; в MVP — локальный `backend/var/audio` | Тот же интерфейс `Storage`, переключение одной переменной `STORAGE=local\|s3`. |
| Веб/админка | *этап 3*: React + Vite + TanStack Query | В MVP скелете не нужна: загрузка через API + `scripts/upload.sh`. |
| iOS | **SwiftUI, iOS 17.0+** | Нужны `@Observable`, `AVAudioUnitEQ` + `AVAudioEngine`, `ContentUnavailableView`, `.searchable` improvements. |
| CI | **GitHub Actions** (`macos-15`, `ubuntu-latest`) | Xcode только на macOS-раннере (Xcode 16.x), локально на Windows iOS не собрать. |

### Минимальная версия iOS — 17.0
18.0 отрезало бы слишком много устройств (iPhone XS/11 поддерживают 18, но 17 покрывает ~95% активных), мёртвым грузом для MVP является любой API 17+ (`@Observable`, `onChange(of:)` двухпараметровый, `scrollPosition`). 17.0 — оптимально.

## 2. Источник контента: слой абстракции `TrackSource`

Главный риск проекта — юридический и «жизненный» (приватный api-v2 ломается). Поэтому источник трека — не «место, откуда берём mp3», а явная модель данных:

```
tracks.source_kind ∈ { local | soundcloud }
tracks.source_ref  — для soundcloud: канонический URL трека
```

и серверная абстракция:

```python
class TrackSource(Protocol):
    kind: str
    def resolve_stream(self, track) -> StreamDescriptor: ...   # что отдать плееру
```

Реализации:

| kind | `resolve_stream` возвращает | Плеер на iOS | Статус |
|---|---|---|---|
| `local` | `{type: "direct", url: <signed url>}` | нативный `AVPlayer` | MVP, основной |
| `soundcloud` | `{type: "embed", embed_url: https://w.soundcloud.com/player/?url=...}` (официальный Widget API) | `WKWebView`-эмбед; нативный плеер, эквалайзер и оффлайн для таких треков не применяются | MVP, легальный путь к библиотеке SC |

**Риск DMCA / приватного API.** Перехват `api-v2.soundcloud.com` и стриминг аудио через собственный прокси — нарушение ToS и авторских прав; такой режим **не реализован**. Если понадобится эксперимент — он делается отдельной реализацией `SoundCloudV2Source` (флаг `ENABLE_SC_V2=1`, только личный деплой) и **не** коммитится в основную ветку. Точка расширения — `sonify_api/sources.py` (`register_source`), чтобы замена была в 10 строк.

## 3. Архитектура iOS-клиента

Слои (зависимости строго вниз):

```
App/                 SonifyApp, AppEnvironment (DI-контейнер)
Features/Library/    TrackListView, TrackRowView, LibraryViewModel
Features/Player/     PlayerView, PlayerViewModel, MiniPlayerBar
Features/Search/     SearchView (этап 2)
Domain/              Track, Artist, Page<T>, Lyrics — чистые модели + протоколы репозиториев
Data/                APIClient (URLSession), DTO + мапперы, TrackRepositoryImpl, AudioCache
Core/                HTTP (транспорт, ошибки, retry), KeychainStore, Formatters
```

**Плеер.** `PlayerService` — `@Observable` singleton:
- `AVPlayer` для `direct`-треков; очередь `PlaybackQueue` (next/prev/shuffle/repeat);
- **эквалайзер**: `AVAudioEngine` с графом `AVPlayer` через `AVAudioPlayerNode` невозможен, поэтому используем `AVAudioEngine` + `AVAudioUnitEQ` (10 полос, 31.5 Hz…16 kHz, `AVAudioUnitEQ(numberOfBands: 10)`) и `AVAudioPlayerNode` со стримингом файла из локального кэша; пресеты: Flat / Bass / Vocal / Electronic;
- для `embed`-треков — `WKWebView` с официальным плеером, управление кнопками на странице; EQ/оффлайн недоступны (честно показать бейдж в UI);
- фон/лока: `UIBackgroundModes=audio`, `AVAudioSession(.playback)`, `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` (play/pause/next/seek), `UIApplication.beginReceivingRemoteControlEvents`;
- `AudioSession` обрабатывает прерывания (звонок) и `routeChange` (наушники выдернуты → пауза).

**Кэш / оффлайн.**
1. Метаморф: `NSCache` (список треков, обложки).
2. Диск: `AudioCache` — файлы в `Caches/audio`, LRU по суммарному размеру (по умолчанию 500 МБ); `URLCache` для JSON с `ETag`.
3. Оффлайн-библиотека: отметка «скачать» → файл переносится в `Application Support/offline`, запись в SwiftData, подписка на `NWPathMonitor` (при offline — только скачанное).
4. Токен — Keychain (`kSecClassGenericPassword`), access refresh.

**Сеть.** `async/await` + `URLSession`; `RequestBuilder` собирает `GET /api/v1/...` с `Authorization: Bearer`; retry: 3 попытки с джиттером на 408/429/5xx и сетевых ошибках; `DecodingError` логируется с ключом.

## 4. Структура монорепо

```
sonify/
├── backend/              # FastAPI, схема SQL, storage, sources, тесты
├── ios/                  # Xcode-проект (project.yml → xcodegen) + SonifyTests
├── web/                  # этап 3 (пока пусто, см. README)
├── infra/
│   ├── docker-compose.yml   # api + postgres + redis + minio
│   └── db/                  # init-скрипты (SQLite→PG миграция, этап 2)
├── .github/workflows/    # ios.yml (macOS), backend.yml (ubuntu)
├── docs/                 # ARCHITECTURE.md, API.md, DATABASE.sql
├── scripts/              # upload_track.py, gen_db.py
└── README.md
```

## 5. План MVP по этапам

| Этап | Объём | Выход |
|---|---|---|
| **0. Скелет (этот)** | backend + `/health`, `/tracks`, загрузка, iOS-список + плеер + EQ, CI, docker-compose | end-to-end демо на сид-треках |
| **1. Контент** | наполнение библиотеки SoundCloud-эмбедами, собственные загрузки, поиск/лента, артисты | приложение с реальной библиотекой |
| **2. Аккаунты и вовлечение** | auth + refresh (Этап 2), лайки, плейлисты, история, рекомендации (assoc/embedding), мобильная синхронизация | персонализация |
| **3. Веб/админка** | React-админка: загрузка, модерация, метаданные, обложки, баннеры, статистика | управление библиотекой |
| **4. Полировка iOS** | оффлайн-библиотека, синхронизированные тексты, EQ-пресеты, Widgets, CarPlay-макет | релиз в App Store |
| **5. Прод** | R2/S3 + CDN, Postgres + PgBouncer, Redis, Sentry, метрики, rate-limit, health-алерты | стабильный сервис |

## 6. Нефункциональные ориентиры
- p95 `GET /tracks?limit=20` < 150 мс (индекс + кэш 30 c).
- Аудио: MP3/AAC 128–320 kbps, отдача через подписанные URL/CDN, `Range`-запросы поддержаны.
- Безопасность: JWT (15 мин) + refresh (30 дней, ротация), rate-limit по IP на `/auth/*`, CORS только для веб-админки, загрузка > 200 МБ отклоняется.
- Логи: JSON, request-id, без записи токенов.

## 7. Переход SQLite → Postgres
`docs/DATABASE.sql` — синтаксис, совместимый с обоими (TEXT/INTEGER/REAL, `WITHOUT ROWID` нет, `AUTOINCREMENT` заменён на `SERIAL`-секцию только для PG). Автоматически: `scripts/gen_db.py` создаёт SQLite-файл; `infra/db/01_schema.sql` (PG-вариант) применяется контейнером postgres при первом старте.
