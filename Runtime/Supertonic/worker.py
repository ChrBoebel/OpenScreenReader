#!/usr/bin/env python3
"""Disposable local Supertonic worker: bounded JSON/PCM over anonymous pipes.

Run with Python -I -B under the app's deny-network/deny-write sandbox. No model
or dependency downloader is present. The parent owns cancellation and kills this
single process; this worker never launches child processes or persists content.
"""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys

SAMPLE_RATE = 44100
MAX_PACKET_FRAMES = 24000


def read_request(source):
    line = source.readline(64002)
    if len(line) > 64001 or not line.endswith(b"\n"):
        raise ValueError("Invalid request frame")
    request = json.loads(line)
    if not isinstance(request, dict) or set(request) != {"text", "language"}:
        raise ValueError("Invalid fields")
    text, language = request["text"], request["language"]
    if not isinstance(text, str) or not text.strip() or len(text) > 8000:
        raise ValueError("Invalid text")
    if language not in ("de", "en"):
        raise ValueError("Invalid language")
    return text, language


def segments(text):
    result = []
    for sentence in re.split(r"(?<=[.!?])\s+", text.strip()):
        remaining = sentence.strip()
        while len(remaining) > 240:
            boundary = remaining.rfind(" ", 1, 241)
            boundary = boundary if boundary > 0 else 240
            result.append(remaining[:boundary])
            remaining = remaining[boundary:].lstrip()
        if remaining:
            result.append(remaining)
    return result


def send(output, packet):
    output.write(json.dumps(packet, separators=(",", ":")).encode() + b"\n")
    output.flush()


def await_ack(source):
    if source.readline(6) != b"next\n":
        raise ValueError("Parent disconnected")


def file_hash(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def load_verified_helper(model):
    root = Path(__file__).resolve().parent
    manifest = json.loads((root / "model-manifest.json").read_text())
    for entry in manifest["files"]:
        path = (model / entry["path"]).resolve()
        if not path.is_relative_to(model) or path.stat().st_size != entry["bytes"]:
            raise ValueError("Model size mismatch")
        if "sha256" in entry:
            valid = file_hash(path) == entry["sha256"]
        else:
            blob = f"blob {entry['bytes']}\0".encode() + path.read_bytes()
            valid = hashlib.sha1(blob).hexdigest() == entry["git_blob"]
        if not valid:
            raise ValueError("Model hash mismatch")
    helper_path = root / "upstream/helper.py"
    if file_hash(helper_path) != manifest["runtime_source"]["sha256"]:
        raise ValueError("Helper hash mismatch")
    spec = importlib.util.spec_from_file_location("supertonic_helper", helper_path)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    return helper


def run(source, output, model):
    text, language = read_request(source)
    helper = load_verified_helper(model)
    import numpy as np

    tts = helper.load_text_to_speech(str(model / "onnx"), use_gpu=False)
    if tts.sample_rate != SAMPLE_RATE:
        raise ValueError("Wrong model sample rate")
    style = helper.load_voice_style([str(model / "voice_styles/M1.json")])
    np.random.seed(42)
    send(output, {"kind": "ready", "sampleRate": SAMPLE_RATE})
    for segment in segments(text):
        wav, duration = tts(segment, language, style, 8, speed=1.0)
        seconds = float(duration[0])
        if not np.isfinite(seconds) or not 0 < seconds <= 120:
            raise ValueError("Invalid duration")
        frames = int(SAMPLE_RATE * seconds)
        if wav.ndim != 2 or wav.shape[0] != 1 or wav.shape[1] < frames or frames == 0:
            raise ValueError("Incomplete audio")
        audio = wav[0, :frames]
        if not np.isfinite(audio).all() or np.max(np.abs(audio)) <= 0.0001:
            raise ValueError("Invalid audio")
        for offset in range(0, frames, MAX_PACKET_FRAMES):
            pcm = audio[offset:offset + MAX_PACKET_FRAMES].astype("<f4").tobytes()
            send(output, {"kind": "audio", "sampleRate": SAMPLE_RATE,
                          "pcm": base64.b64encode(pcm).decode("ascii")})
            await_ack(source)
    send(output, {"kind": "end"})


def main():
    # Hide native-library prints and traceback content before importing upstream.
    output = os.fdopen(os.dup(sys.stdout.fileno()), "wb", buffering=0)
    with open(os.devnull, "wb") as null:
        os.dup2(null.fileno(), sys.stdout.fileno())
        os.dup2(null.fileno(), sys.stderr.fileno())
    try:
        if len(sys.argv) != 3 or sys.argv[1] != "--model":
            raise ValueError("Invalid arguments")
        run(sys.stdin.buffer, output, Path(sys.argv[2]).resolve())
    except Exception:
        try:
            send(output, {"kind": "error"})
        except OSError:
            pass
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
