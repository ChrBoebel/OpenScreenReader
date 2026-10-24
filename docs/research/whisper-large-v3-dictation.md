# Local Whisper Large v3 dictation

Project decision, 2026-10-14: add Whisper Large v3 (8-bit) as a selectable local
dictation model next to Qwen3-ASR and Whisper Turbo. This is ASR only; Supertonic
remains the reading voice. It is an explicit choice, never a fallback.

## Why this variant

Large v3 is the full-size multilingual Whisper (32 decoder layers instead of
Turbo's 4), so it is expected to be more accurate and noticeably slower than
Turbo. 8-bit was chosen as the balance between quality and memory on a 16 GB
Apple-silicon Mac; FP16 (3.1 GB) was not packaged. Distil-Whisper is English-only
and therefore unsuitable for German dictation.

## Packaged asset provenance

- Model: [mlx-community/whisper-large-v3-8bit](https://huggingface.co/mlx-community/whisper-large-v3-8bit),
  revision `7fede54fd97b154a4f5e476646484fc023b1bcdf`.
- Upstream: [OpenAI Whisper large-v3](https://huggingface.co/openai/whisper-large-v3).
  The conversion card declares Apache-2.0; OpenAI's upstream code/weights are MIT.
  Preserve both the Apache-2.0 license and OpenAI copyright/MIT notice, alongside
  the unchanged conversion card. Its stated converter is mlx-audio-plus 0.1.4,
  the same as the packaged Whisper Turbo; the app keeps its existing mlx-whisper
  runtime.
- MLX 8-bit weights, group size 64: 1,644,890,344 bytes; SHA-256
  `473df949b32adeac800472dce346678f241030f410e365fe422d29b3262fe0b3`.
  The upstream `model.safetensors` is packaged byte-for-byte under the name
  `weights.safetensors` expected by mlx-whisper. No tensor conversion is applied.
- Exact file inventory, source name, sizes and hashes:
  `Runtime/Dictation/whisper-large-v3-manifest.json`. Small upstream files are
  checked against the pinned Git blob IDs. The packager copies only this inventory.
  The repository's `multilingual.tiktoken` is not used or packaged; the runtime
  uses its bundled Whisper tokenizer.
- Runtime: existing bundled `mlx-whisper==0.4.3` (MIT), MLX 0.32.3 and private
  CPython 3.12.14. No new runtime network dependency.

Source, revision, size, SHA-256 and license were recorded before fetching the
weights. Do not commit weights to Git.

Since 2026-10-14 (project decision) default builds do not bundle this model. The app
downloads exactly these pinned files only after the user confirms "Install
Whisper Large v3…" in Settings, verifies size and SHA-256 against this bundled
manifest, copies the two license texts from the app bundle, and only then moves
the folder to `~/Library/Application Support/Saywing/DictationModels/WhisperLargeV3`.
Private builds may still bundle it with `--whisper-large-model`.

Quantization reduces storage and memory. It is not a claim of equal recognition
quality to FP16. German and English sample checks must pass with the real
sandboxed runtime before installation; broader quality and complete
redistribution audits remain release gates for this private development build.

## Verification — 2026-10-14

Machine: Apple M4, 16 GB, macOS 26.6.2.

- The pinned download matched the declared size and SHA-256; temporary range
  chunks were removed afterwards.
- A new Swift test first failed to compile without the model case, then passed.
  It covers the selectable entry, persistence/restoration and starting the
  matching worker without recording. Full app suite: **150 tests in 10 suites
  passed** (two permission-dependent XCTest checks skipped, not counted as passes).
- A new Python test (routing to `WhisperLargeV3` and its own manifest, no
  cross-model fallback) first failed with `unknown_model`; **11 Python tests passed**
  afterwards.
- Release build with both Whisper models packaged: deep signature and Audio Input
  entitlement checks passed. Against that bundle, `scripts/verify-dictation.sh`
  passed 15 core checks, 11 Python checks and **10 real offline sandbox checks for
  each of Qwen3-ASR, Whisper Turbo and Whisper Large v3** (automatic and explicit
  German/English, 48 kHz resampling, silence, malformed PCM, cancellation within
  one second, OS-denied network and writes).
- Single-run measurements on the public demo clips (warm model, not a controlled
  benchmark):

  | Model | Load | 17.9 s German | 10.6 s English | 30 s German | Peak MLX memory |
  |---|---|---|---|---|---|
  | Whisper Turbo 4-bit | 4.9 s | 2.4 s | 1.2 s | 3.1 s | 1.14 GB |
  | Whisper Large v3 8-bit | 2.9 s | 1.8 s | 1.7 s | 4.8 s | 2.33 GB |

  Sandbox-integration load for Large v3 was 13.2 s (cold file cache). No live
  microphone or quality comparison beyond the two public samples is implied.
