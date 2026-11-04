#!/usr/bin/env python3
"""Synthesizes Plaza Brawler's menu-select blip into assets/sfx/select.wav (16-bit mono, 22050 Hz).

The fight sounds (hit, heavy, block, KO) are recorded CC0 samples from Kenney's Impact Sounds pack, not
made here; see assets/sfx/CREDITS.md.

Standard library only and deterministic, so running it again gives a byte-identical file. The blip is
original (made by this script, no samples), released as CC0 1.0; see assets/sfx/CREDITS.md.

    python3 tools/sfx_gen.py
"""
import math
import os
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")


def env(i, n, attack=0.004, power=2.0):
    """Fast attack, curved decay. i/n -> 0..1 gain."""
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * (1.0 - i / n) ** power


def write(name, samples, gain=0.9):
    peak = max(1e-9, max(abs(s) for s in samples))
    data = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s / peak * gain)) * 32767)) for s in samples
    )
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(f"{path}: {len(samples) / RATE * 1000:.0f} ms, {len(data) + 44} bytes")


def select():
    """Short two-step blip (880 Hz then 1320 Hz)."""
    n = int(RATE * 0.08)
    out = []
    for i in range(n):
        t = i / RATE
        f = 880 if i < n // 2 else 1320
        out.append(math.sin(2 * math.pi * f * t) * env(i, n, 0.002, 1.5))
    return out


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write("select.wav", select(), gain=0.5)
