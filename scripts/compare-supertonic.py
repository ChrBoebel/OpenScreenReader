#!/usr/bin/env python3
"""Explicit fixed-fixture experiment only. Never called by the application.

Run inside sandbox-exec with networking denied. Root must contain the separately
downloaded, verified model, unchanged MIT helper plus LICENSE, and receipt.json.
Only the pre-created output directory needs write permission. No arbitrary text,
user recordings, automatic downloads, or application settings are accepted.
"""
import argparse
import hashlib
import importlib.metadata
import importlib.util
import json
from pathlib import Path
import signal
import time
import wave

import numpy as np

TEXT = (
    "Guten Morgen. Heute lesen wir einen deutschen Text über Bücher, schöne Städte "
    "und frische Brötchen. Der nächste Zug fährt um fünfzehn Uhr dreißig nach München."
)


def pcm16(audio, rate):
    if rate <= 0 or audio.ndim != 1 or not 0 < audio.size <= rate * 120:
        raise ValueError("Invalid audio dimensions or duration")
    if not np.isfinite(audio).all() or np.max(np.abs(audio)) <= 0.0001:
        raise ValueError("Non-finite or silent audio")
    return np.rint(np.clip(audio, -1, 1) * 32767).astype("<i2").tobytes()


def write_wav(path, pcm, rate):
    with path.open("xb") as output:
        with wave.open(output, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(rate)
            wav.writeframes(pcm)


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def verify_assets(root):
    receipt = json.loads((root / "receipt.json").read_text())
    for entry in receipt:
        path = (root / entry["path"]).resolve()
        if not path.is_relative_to(root) or path.stat().st_size != entry["bytes"]:
            raise ValueError("Invalid receipt path or size")
        if sha256(path) != entry["sha256"]:
            raise ValueError("Asset receipt hash mismatch")
    # Independently verify model files against the committed pre-download pins.
    manifest_path = Path(__file__).resolve().parents[1] / "docs/research/supertonic-comparison-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    helper = root / "upstream/helper.py"
    source = manifest["runtime_source"]
    if helper.stat().st_size != source["bytes"] or sha256(helper) != source["sha256"]:
        raise ValueError("Pinned helper hash mismatch")
    for entry in manifest["files"]:
        path = root / "model" / entry["path"]
        if path.stat().st_size != entry["bytes"]:
            raise ValueError("Pinned model size mismatch")
        if "sha256" in entry:
            valid = sha256(path) == entry["sha256"]
        else:
            blob = f"blob {entry['bytes']}\0".encode() + path.read_bytes()
            valid = hashlib.sha1(blob).hexdigest() == entry["git_blob"]
        if not valid:
            raise ValueError("Pinned model hash mismatch")
    return manifest


def deadline_expired(signum, frame):
    raise TimeoutError("Comparison exceeded 180 seconds")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    root, output = args.root.resolve(), args.output.resolve()
    if not output.is_dir() or any(output.iterdir()):
        parser.error("Output must be an existing empty directory")
    signal.signal(signal.SIGALRM, deadline_expired)
    signal.alarm(180)
    manifest = verify_assets(root)
    spec = importlib.util.spec_from_file_location("supertonic_helper", root / "upstream/helper.py")
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    started = time.monotonic()
    tts = helper.load_text_to_speech(str(root / "model/onnx"), use_gpu=False)
    load_seconds = time.monotonic() - started
    results = []
    for voice in ("F1", "M1"):
        style = helper.load_voice_style([str(root / f"model/voice_styles/{voice}.json")])
        np.random.seed(42)
        started = time.monotonic()
        wav, duration = tts(TEXT, "de", style, 8, speed=1.0)
        synthesis_seconds = time.monotonic() - started
        seconds = float(duration[0])
        if not np.isfinite(seconds) or not 0 < seconds <= 120:
            raise ValueError("Invalid predicted duration")
        frame_count = int(tts.sample_rate * seconds)
        if wav.ndim != 2 or wav.shape[0] != 1 or wav.shape[1] < frame_count:
            raise ValueError("Incomplete waveform")
        audio = wav[0, :frame_count]
        pcm = pcm16(audio, tts.sample_rate)
        filename = f"supertonic-{voice.lower()}-de.wav"
        path = output / filename
        write_wav(path, pcm, tts.sample_rate)
        result = dict(voice=voice, language="de", seed=42, denoising_steps=8, speed=1.0,
                      file=filename, sample_rate=tts.sample_rate,
                      audio_seconds=round(frame_count / tts.sample_rate, 3),
                      synthesis_seconds=round(synthesis_seconds, 3),
                      peak=float(np.max(np.abs(audio))), sha256=sha256(path))
        results.append(result)
        print(json.dumps(result), flush=True)
    report = dict(purpose="Owner-requested machine-generated public-fixture comparison",
                  text=TEXT, model_revision=manifest["revision"],
                  source_revision=manifest["runtime_source"]["revision"],
                  helper_sha256=sha256(root / "upstream/helper.py"),
                  load_seconds=round(load_seconds, 3), results=results,
                  packages={name: importlib.metadata.version(name)
                            for name in ("numpy", "onnxruntime")})
    with (output / "comparison.json").open("x") as file:
        json.dump(report, file, ensure_ascii=False, indent=2)
        file.write("\n")
    signal.alarm(0)
    print("PASS: two local samples exported; installed app and runtime unchanged")


if __name__ == "__main__":
    main()
