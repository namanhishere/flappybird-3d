#!/usr/bin/env python3
"""Generate the game's four sound effects as plain 16-bit mono WAV files.

Every clip is synthesised from scratch -- no sample library, no third-party
asset, and therefore no licence to track. Re-run this script to regenerate
them; output is deterministic, so re-running never produces a diff.

    python3 tools/gen_audio.py
"""

import math
import os
import struct
import wave

SAMPLE_RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")


def envelope(i, total, attack=0.01, release=0.6):
    """A simple attack/decay shape, so clips do not click on start or end."""
    t = i / SAMPLE_RATE
    duration = total / SAMPLE_RATE
    if t < attack:
        return t / attack
    fall = (t - attack) / max(duration - attack, 1e-6)
    return math.exp(-fall / max(release, 1e-6))


def tone(start_hz, end_hz, duration, volume=0.5, harmonics=(1.0,), attack=0.005, release=0.35):
    """A swept tone. Positive and negative sweeps read as 'up' and 'down'."""
    total = int(SAMPLE_RATE * duration)
    samples = []
    phase = 0.0
    for i in range(total):
        t = i / total
        hz = start_hz + (end_hz - start_hz) * t
        phase += 2.0 * math.pi * hz / SAMPLE_RATE
        value = sum(amp * math.sin(phase * n) for n, amp in enumerate(harmonics, start=1))
        samples.append(value * envelope(i, total, attack, release) * volume)
    return samples


def noise(duration, volume=0.5, attack=0.002, release=0.12, seed=1234):
    """Deterministic white noise, used for the impact thud."""
    total = int(SAMPLE_RATE * duration)
    state = seed
    samples = []
    for i in range(total):
        # xorshift keeps the noise reproducible without the random module.
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        value = ((state & 0xFFFF) / 32768.0) - 1.0
        samples.append(value * envelope(i, total, attack, release) * volume)
    return samples


def mix(*tracks):
    """Sum several clips sample-wise, then normalise to avoid clipping."""
    length = max(len(t) for t in tracks)
    out = [0.0] * length
    for track in tracks:
        for i, value in enumerate(track):
            out[i] += value
    peak = max((abs(v) for v in out), default=0.0)
    if peak > 0.0:
        out = [v / peak * 0.85 for v in out]
    return out


def write_wav(name, samples):
    path = os.path.normpath(os.path.join(OUT_DIR, name))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(v * 32767)))) for v in samples
    )
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(frames)
    print(f"wrote {path} ({len(samples) / SAMPLE_RATE:.2f}s)")


def main():
    # Flap: a short upward chirp with a breathy second harmonic.
    write_wav("flap.wav", mix(
        tone(320, 620, 0.13, volume=0.5, harmonics=(1.0, 0.25), release=0.3),
        noise(0.07, volume=0.12, release=0.2, seed=99),
    ))

    # Hit: a low thud plus a short noise burst.
    write_wav("hit.wav", mix(
        tone(180, 70, 0.26, volume=0.6, harmonics=(1.0, 0.4), release=0.3),
        noise(0.18, volume=0.35, release=0.1, seed=4242),
    ))

    # Score: a bright two-note ding.
    write_wav("score.wav", mix(
        tone(880, 880, 0.09, volume=0.4, release=0.5),
        [0.0] * int(SAMPLE_RATE * 0.06) + tone(1320, 1320, 0.16, volume=0.4, release=0.4),
    ))

    # Game over: a descending minor figure.
    half = int(SAMPLE_RATE * 0.14)
    write_wav("game_over.wav", mix(
        tone(523, 523, 0.14, volume=0.4, release=0.5),
        [0.0] * half + tone(392, 392, 0.16, volume=0.4, release=0.5),
        [0.0] * (half * 2) + tone(262, 220, 0.42, volume=0.45, release=0.4),
    ))


if __name__ == "__main__":
    main()
