"""Загрузить трек на Sonify: python scripts/upload_track.py --file track.wav --title "..." --artist "..."

Без зависимостей (stdlib). Для SoundCloud-эмбеда: --source-url https://soundcloud.com/<artist>/<track>.
"""

from __future__ import annotations

import argparse
import json
import os
import urllib.request
import uuid
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser(description="Upload a track to Sonify backend")
    ap.add_argument("--api", default=os.getenv("SONIFY_API", "http://127.0.0.1:8080"))
    ap.add_argument("--token", default=os.getenv("ADMIN_TOKEN", "dev-admin-token"))
    ap.add_argument("--file", type=Path, help="WAV file to upload")
    ap.add_argument("--source-url", help="SoundCloud track URL (embed source, no audio upload)")
    ap.add_argument("--title", required=True)
    ap.add_argument("--artist", required=True)
    ap.add_argument("--genre")
    args = ap.parse_args()

    if not args.file and not args.source_url:
        ap.error("either --file or --source-url is required")

    boundary = "----sonify" + uuid.uuid4().hex
    fields = {"title": args.title, "artist": args.artist}
    if args.genre:
        fields["genre"] = args.genre
    if args.source_url:
        fields["source_url"] = args.source_url

    parts: list[bytes] = []
    for k, v in fields.items():
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode())
    if args.file:
        data = args.file.read_bytes()
        parts.append(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{args.file.name}\"\r\n"
            f"Content-Type: audio/wav\r\n\r\n".encode() + data + b"\r\n"
        )
    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)

    req = urllib.request.Request(args.api.rstrip("/") + "/api/v1/admin/tracks", data=body, method="POST")
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    req.add_header("X-Admin-Token", args.token)
    with urllib.request.urlopen(req, timeout=120) as r:
        print(json.dumps(json.loads(r.read()), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
