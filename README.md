# Sonify

Музыкальный стриминг без боли SoundCloud: работает из РФ без VPN, современный интерфейс,
толковые рекомендации, тексты и эквалайзер.

**Сейчас в репозитории — рабочий MVP-скелет:** бэкенд (FastAPI) с реальными API,
iOS-приложение (SwiftUI) со списком треков, плеером и эквалайзером, docker-compose,
CI на GitHub Actions. План по этапам — [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

| Компонент | Статус |
|---|---|
| `backend/` — REST API, SQLite, сид-треки, загрузка | ✅ работает, покрыт black-box смоук-тестом |
| `ios/` — SwiftUI 17+, список, плеер, EQ, кэш | 🧪 собирается в GitHub Actions (macOS) |
| `infra/` — docker-compose (api + postgres + redis + minio) | ✅ описано, образ собирается в CI |
| `web/` — админка | ⏳ этап 3 |

---

## 1. Как поднять бэкенд

Нужен Python 3.11+ и пакеты `fastapi` + `uvicorn` (работает на 3.11 и 3.12):
SQLite создаётся автоматически, аудио-сид генерируется на stdlib — ни Docker, ни БД не нужны.

**Способ A — без установки пакета (быстрее всего):**

```bash
python backend/run.py            # http://127.0.0.1:8080
# порт/хост: python backend/run.py --host 0.0.0.0 --port 9000
```

**Способ B — как обычный пакет:**

```bash
cd backend
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -e .
python -m uvicorn sonify_api.main:app --host 127.0.0.1 --port 8080
```

Проверка:

```bash
curl http://127.0.0.1:8080/health
# {"status":"ok","version":"0.1.0","db":"ok","uptimeSeconds":3}

curl "http://127.0.0.1:8080/api/v1/tracks?limit=5"
# {"items":[{"id":"trk_...","title":"Glass Gardens","artist":{...},"sourceKind":"local", ...}],"nextCursor":"o:5"}
```

Swagger: <http://127.0.0.1:8080/docs> · OpenAPI: `/openapi.json`

Первый старт занимает ~10 секунд: генерируются 6 WAV-треков (сид). Повторные старты мгновенные,
данные лежат в `backend/var/` (`sonify.db` + `audio/`). Удалите папку, чтобы пересеять.

### Переменные окружения

| Переменная | По умолчанию | Зачем |
|---|---|---|
| `SONIFY_HOST` / `SONIFY_PORT` | `127.0.0.1` / `8080` | адрес сервера |
| `SONIFY_VAR_DIR` | `backend/var` | каталог БД и аудио |
| `SONIFY_SEED` | `1` | `0` — не генерировать сид |
| `ADMIN_TOKEN` | `dev-admin-token` | токен для `POST /admin/tracks` |
| `PUBLIC_BASE_URL` | — | публичный адрес для аудио-ссылок (CDN) |
| `ENABLE_SOUNDCLOUD_EMBEDS` | `1` | отдавать embed-URL для SoundCloud-треков |

Запуск для симулятора iOS — сервер должен слушать `127.0.0.1` или `0.0.0.0`
(для устройства в Wi-Fi — только `0.0.0.0` и IP компьютера).

### Проверка одной командой

```bash
cd backend
python smoke_test.py   # поднимает реальный uvicorn на свободном порту и проверяет контракт
```

Ожидаемо: `SMOKE PASSED` (health, пагинация, стрим 302, Range, тексты, embed, загрузка, защита от path traversal).

### Загрузить свой трек

MVP принимает WAV (RIFF, PCM/float, любая канальность/частота):

```bash
python scripts/upload_track.py --file my_track.wav --title "My Track" --artist "Me" --genre demo
```

Или добавить SoundCloud-трек легально, без загрузки аудио (играется официальным плеером):

```bash
python scripts/upload_track.py --source-url "https://soundcloud.com/artist/track" \
    --title "SC Track" --artist "Artist"
```

### Docker

```bash
docker compose -f infra/docker-compose.yml up --build
```

Поднимает api (`:8080`), postgres (`:5432`, схема из `infra/db/01_schema.sql` применяется
автоматически), redis (`:6379`) и minio (`:9000`/`:9001`, `minioadmin`/`minioadmin`).
API в MVP использует SQLite в томе `api-var`; переменные `DATABASE_URL`, `REDIS_URL`, `S3_*`
уже проброшены под этап 2 (перевод на Postgres/S3).

---

## 2. Как запустить iOS-приложение

Требуется macOS + Xcode 16 (iOS 17+). На Windows iOS не собрать — только через CI.

```bash
cd ios
brew install xcodegen
xcodegen generate          # создаёт Sonify.xcodeproj из project.yml
open Sonify.xcodeproj
```

В Xcode: схема **Sonify** → симулятор iPhone → Run. Приложение ходит на
`http://127.0.0.1:8080/api/v1` (задано в `Info.plist` → `SONIFY_API_BASE_URL`).

- **Симулятор:** бэкенд на компьютере, `127.0.0.1` работает как есть.
- **Физическое устройство:** поменяйте URL на `http://<ip-мака-в-wi-fi>:8080/api/v1`
  и запустите бэкенд с `--host 0.0.0.0`. Нужен Pro-аккаунт для подписи.
- URL можно переопределить launch-аргументом `-SONIFY_API_BASE_URL http://.../api/v1`.

### Чем проверить сборку и тесты

```bash
cd ios
xcodebuild build -project Sonify.xcodeproj -scheme Sonify \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO

xcodebuild test -project Sonify.xcodeproj -scheme Sonify \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

### CI (без Mac)

`.github/workflows/ios.yml` собирает и тестирует проект на `macos-15` (Xcode 16.4),
плюс поднимает бэкенд внутри раннера — интеграционные тесты iOS ходят на живой API.
Для запуска: запушить репозиторий на GitHub → вкладка **Actions** → workflow **iOS**.
`xcodebuild -list`, логи сборки и `.xcresult` сохраняются как артефакт.

---

## 3. Что уже умеет iOS-клиент

- лента треков с курсорной пагинацией и pull-to-refresh;
- поиск с дебаунсом (300 мс);
- нативный плеер: play/pause, next/prev, перемотка, shuffle, repeat, очередь;
- **10-полосный эквалайзер** на `AVAudioUnitEQ` с пресетами (Flat/Bass/Vocal/Electronic/Lo-Fi) и ручными ползунками;
- фоновое воспроизведение, экран блокировки (`MPNowPlayingInfoCenter`), кнопки на наушниках, обработка звонков и выдёргивания наушников;
- дисковый кэш аудио с LRU (500 МБ) — повторное проигрывание мгновенное и работает оффлайн для уже сыгранного;
- SoundCloud-треки играются официальным виджетом в `WKWebView` (без перехвата потоков);
- понятные ошибки: оффлайн, 401, 404, 5xx; кнопка «Повторить».

Подробности архитектуры и план этапов — [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
контракт API — [docs/API.md](docs/API.md), схема БД — [docs/DATABASE.sql](docs/DATABASE.sql).

---

## 4. Структура

```
sonify/
├── backend/            FastAPI: app.py, sources.py, storage.py, seed.py, schemas.py
│   ├── run.py          запуск без установки пакета
│   ├── smoke_test.py   black-box проверка контракта
│   └── var/            (создаётся) SQLite + аудио
├── ios/                project.yml (XcodeGen) + Sonify/ (App, Core, Data, Domain, Features, Tests)
├── infra/              Dockerfile, docker-compose.yml, db/01_schema.sql (PostgreSQL)
├── scripts/            upload_track.py
├── docs/               ARCHITECTURE.md, API.md, DATABASE.sql
└── .github/workflows/  ios.yml, backend.yml
```

## 5. Про источник контента и риски

Основной путь MVP — **свои загрузки** (`local`) и **официальные SoundCloud-эмбеды**
(`soundcloud`). Приватный `api-v2` с перехватом потоков **не используется**: это нарушает
ToS SoundCloud и создаёт DMCA-риск. Источник инкапсулирован в `backend/sonify_api/sources.py`
(`TrackSource` / `StreamDescriptor`), поэтому добавление или замена источника — это
новая реализация класса + регистрация, без изменений в iOS-клиенте.
