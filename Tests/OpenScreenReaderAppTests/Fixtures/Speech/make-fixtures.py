#!/usr/bin/env python3
"""Rebuilds the room-echo speech fixtures from the LibriVox MP3s.

Usage: make-fixtures.py <directory with the downloaded MP3s>

Each source is checked against its SHA-256, decoded, mixed to mono and resampled
to 8 kHz by macOS `afconvert`, then cut to the listed range, scaled to an RMS of
0.1 (-20 dBFS) and written as 16-bit PCM WAV next to this script. Only the
Python standard library and macOS tools are used. The committed WAV files are
authoritative; another macOS release may decode the MP3s slightly differently.
"""
import hashlib
import math
import pathlib
import struct
import subprocess
import sys
import tempfile
import wave

RATE = 8_000
TARGET_RMS = 0.1

SOURCES = {
    "kinderundhausmaerchen1_02_jorindejoringel_grimm_64kb.mp3":
        "4e6eb46c31cf5abb9ce2826a1f6fe90eb886eb150d8b03fb3480b785d3cd7219",
    "kinderundhausmaerchen1_49_grossvaterundenkel_grimm_64kb.mp3":
        "e43eca076b33e2b1e6e7aa9f929b629d06b5ea38c1e67cd41b4fde15f5266de0",
}

# name: (source, start seconds, end seconds)
FIXTURES = {
    "others-elli": ("kinderundhausmaerchen1_02_jorindejoringel_grimm_64kb.mp3", 186.95, 206.35),
    "mine-karlsson-1": ("kinderundhausmaerchen1_49_grossvaterundenkel_grimm_64kb.mp3", 105.5, 110.6),
    "mine-karlsson-2": ("kinderundhausmaerchen1_49_grossvaterundenkel_grimm_64kb.mp3", 30.9, 35.3),
}


def decoded(mp3: pathlib.Path, scratch: pathlib.Path) -> list[float]:
    """Mono 8 kHz samples in [-1, 1) via afconvert (32-bit integer PCM)."""
    output = scratch / (mp3.stem + ".wav")
    subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI32@{RATE}", "-c", "1", str(mp3), str(output)],
                   check=True)
    with wave.open(str(output), "rb") as reader:
        assert reader.getnchannels() == 1 and reader.getsampwidth() == 4 and reader.getframerate() == RATE
        frames = reader.readframes(reader.getnframes())
    return [value / 2**31 for value in struct.unpack(f"<{len(frames) // 4}i", frames)]


def write(path: pathlib.Path, samples: list[float]) -> None:
    rms = math.sqrt(sum(value * value for value in samples) / len(samples))
    gain = TARGET_RMS / rms
    pcm = [max(-32768, min(32767, round(value * gain * 32768))) for value in samples]
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(RATE)
        writer.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    sources = pathlib.Path(sys.argv[1])
    here = pathlib.Path(__file__).resolve().parent
    for name, digest in SOURCES.items():
        actual = hashlib.sha256((sources / name).read_bytes()).hexdigest()
        if actual != digest:
            print(f"{name}: SHA-256 {actual}, expected {digest}")
            return 1
    with tempfile.TemporaryDirectory() as scratch:
        audio = {name: decoded(sources / name, pathlib.Path(scratch)) for name in SOURCES}
        for name, (source, start, end) in FIXTURES.items():
            samples = audio[source][round(start * RATE):round(end * RATE)]
            path = here / f"{name}.wav"
            write(path, samples)
            data = path.read_bytes()
            print(f"{path.name}: {len(samples) / RATE:.2f} s, {len(data)} bytes, "
                  f"SHA-256 {hashlib.sha256(data).hexdigest()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
