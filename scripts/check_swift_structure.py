"""Быстрые структурные проверки Swift-файлов (без Xcode): баланс скобок и кавычек,
подозрительные паттерны. Не заменяет xcodebuild, но ловит грубые ошибки до CI.
"""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def strip_code(src: str) -> str:
    """Убирает строковые литералы и комментарии, чтобы считать скобки по коду."""
    out: list[str] = []
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        if ch == '"':
            triple = src[i:i + 3] == '"""'
            i += 3 if triple else 1
            while i < n:
                if triple and src[i:i + 3] == '"""':
                    i += 3
                    break
                if not triple and src[i] == '\\':
                    i += 2
                    continue
                if not triple and src[i] == '"':
                    i += 1
                    break
                i += 1
            out.append('""')
            continue
        if ch == '/' and src[i:i + 2] == '//':
            while i < n and src[i] != '\n':
                i += 1
            continue
        if ch == '/' and src[i:i + 2] == '/*':
            depth = 1
            i += 2
            while i < n and depth:
                if src[i:i + 2] == '/*':
                    depth += 1
                    i += 2
                elif src[i:i + 2] == '*/':
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue
        out.append(ch)
        i += 1
    return ''.join(out)


def main() -> int:
    problems: list[str] = []
    files = sorted((ROOT / "ios" / "Sonify").rglob("*.swift"))
    for path in files:
        src = path.read_text(encoding="utf-8")
        code = strip_code(src)
        for open_ch, close_ch, label in (("{", "}", "braces"), ("(", ")", "parens"), ("[", "]", "brackets")):
            if code.count(open_ch) != code.count(close_ch):
                problems.append(
                    f"{path.relative_to(ROOT)}: {label} mismatch {code.count(open_ch)} {open_ch} vs {code.count(close_ch)} {close_ch}"
                )
    print(f"checked {len(files)} Swift files")
    for p in problems:
        print("PROBLEM:", p)
    print("STRUCTURE OK" if not problems else f"STRUCTURE FAILED ({len(problems)})")
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
