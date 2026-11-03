#!/usr/bin/env python3
"""Synthesizes Plaza Brawler's sound effects into assets/sfx/*.wav (16-bit mono, 22050 Hz).

Standard library only, fixed random seed, so running it again gives byte-identical files. The sounds are
original (made by this script, no samples), released as CC0 1.0; see assets/sfx/CREDITS.md.

    python3 tools/sfx_gen.py
"""
import math
import os
import random
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


def hit():
    """Punchy thump: a falling sine (160 -> 55 Hz) under a short low-passed noise burst."""
    rng = random.Random(1)
    n = int(RATE * 0.12)
    out, lp, ph = [], 0.0, 0.0
    for i in range(n):
        f = 55 + 105 * (1 - i / n) ** 3
        ph += 2 * math.pi * f / RATE
        lp += 0.35 * (rng.uniform(-1, 1) - lp)
        noise = lp * (1 - i / n) ** 6
        out.append(math.sin(ph) * env(i, n, 0.002, 2.2) + 0.8 * noise)
    return out


def block():
    """Hard 'clack': two short square-ish partials (1.2 kHz, 1.9 kHz) with a quick decay."""
    n = int(RATE * 0.07)
    out = []
    for i in range(n):
        t = i / RATE
        s = math.copysign(1, math.sin(2 * math.pi * 1200 * t)) * 0.4 + math.sin(2 * math.pi * 1900 * t) * 0.6
        out.append(s * env(i, n, 0.001, 4.0))
    return out


def ko():
    """Low boom plus a falling tone (440 -> 110 Hz) over ~0.7 s."""
    rng = random.Random(2)
    n = int(RATE * 0.7)
    out, lp, ph = [], 0.0, 0.0
    for i in range(n):
        x = i / n
        f = 110 + 330 * (1 - x) ** 2
        ph += 2 * math.pi * f / RATE
        lp += 0.08 * (rng.uniform(-1, 1) - lp)
        tone = (math.sin(ph) + 0.3 * math.sin(2 * ph)) * env(i, n, 0.005, 1.4)
        boom = lp * 4 * (1 - x) ** 8
        out.append(tone + boom)
    return out


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
    write("hit.wav", hit())
    write("block.wav", block(), gain=0.6)
    write("ko.wav", ko())
    write("select.wav", select(), gain=0.5)
