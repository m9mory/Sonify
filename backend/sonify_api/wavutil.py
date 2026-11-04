"""Генерация и анализ WAV для сид-треков (полностью на stdlib).

Пишет mono-compatible stereo PCM 16-bit. Сэмплы собираются пакетно
(`array`), а не побайтно — сид из нескольких треков занимает доли секунды.
"""

from __future__ import annotations

import math
import random
import struct
import wave
from array import array
from pathlib import Path

MELODY = {
    "synthwave": [0, 3, 7, 10, 12, 10, 7, 3],
    "lo-fi": [0, 2, 3, 7, 10, 7, 3, 2],
    "ambient": [0, 4, 7, 11, 12, 11, 7, 4],
    "house": [0, 7, 12, 7, 3, 10, 12, 7],
    "trap": [0, 5, 7, 10, 12, 10, 7, 5],
}
ROOTS_HZ = [55.0, 61.735, 65.406, 73.416, 82.407, 87.307]


def render_wav(path: Path, duration: float, genre: str = "synthwave", seed: int = 1, sample_rate: int = 22050) -> None:
    melody = MELODY.get(genre, MELODY["synthwave"])
    root = ROOTS_HZ[seed % len(ROOTS_HZ)]
    beat = 60.0 / 96.0
    rng = random.Random(seed)
    total = int(duration * sample_rate)
    step_len = beat / 4.0  # 16-е доли для лёгкой пульсации

    samples = array("h", bytes(total * 4))
    two_pi = 2.0 * math.pi
    idx = 0
    for n in range(total):
        t = n / sample_rate
        pos = t % beat
        note = melody[int(t / beat) % len(melody)]
        freq = root * 2 ** (note / 12.0)
        env = math.exp(-pos / (beat * 0.8))
        pulse = 0.5 + 0.5 * math.cos(two_pi * (t % step_len) / step_len)
        tone = math.sin(two_pi * freq * t) * 0.55
        sub = math.sin(two_pi * (freq / 4.0) * t) * 0.25
        sparkle = math.sin(two_pi * freq * 2 * t) * 0.08 * pulse
        noise = (rng.random() * 2.0 - 1.0) * 0.015
        v = (tone + sub + sparkle + noise) * env
        s = int(max(-1.0, min(1.0, v)) * 32767)
        samples[idx] = s
        samples[idx + 1] = s
        idx += 2

    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def wav_duration(path: Path) -> float:
    with wave.open(str(path), "rb") as w:
        return w.getnframes() / float(w.getframerate())
