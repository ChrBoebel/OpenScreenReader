# Local Whisper Turbo dictation

Owner request, 2026-10-13: selectable local dictation models, including Whisper
Turbo. This is ASR only; Supertonic remains the reading voice.

## Packaged asset provenance

- Model: [mlx-community/whisper-large-v3-turbo-4bit](https://huggingface.co/mlx-community/whisper-large-v3-turbo-4bit),
  revision `0f058d38170d183f9fdee07908f5b515d91793a8`.
- Upstream: [OpenAI Whisper large-v3-turbo](https://huggingface.co/openai/whisper-large-v3-turbo).
  The conversion card declares Apache-2.0; OpenAI's upstream weights/code are MIT.
  Preserve both the Apache-2.0 license and OpenAI copyright/MIT notice, alongside
  the unchanged conversion card. Its stated converter is mlx-audio-plus 0.1.4;
  the app continues using its existing mlx-whisper runtime.
- MLX 4-bit weights, group size 64: 463,462,982 bytes; SHA-256
  `e2d6146b49644c13ed7467060d3c43c402bbdfca1f01f1c21f6fbeda23b6567e`.
  The upstream `model.safetensors` is packaged byte-for-byte under the name
  `weights.safetensors` expected by mlx-whisper. No tensor conversion is applied.
- Exact file inventory, source name, sizes and hashes:
  `Runtime/Dictation/whisper-turbo-manifest.json`. Small upstream files are also
  checked against the pinned Git blob IDs. The packager copies only this inventory.
- Runtime: bundled `mlx-whisper==0.4.3` (MIT), MLX 0.32.3 and CPython 3.12.15,
  built by `scripts/build-python-runtime.py` ([runtime build](../runtime-build.md)).
  No new runtime network dependency. Package license files and
  Whisper tokenizer/audio assets are retained in the existing Python bundle.
  The additional tokenizer in the model repository is not used or packaged.

Source, revision, size, SHA-256 and license were recorded before fetching the
weights. Download/verification is a development packaging step; the app never
downloads models. Do not commit weights to Git.

The smaller quantized variant reduces storage and model memory. It is not a claim
of equal recognition quality to FP16. German and English sample checks must pass
with the real sandboxed runtime before installation; broader quality and complete
redistribution audits remain release gates for this private development build.

## FP16 candidate investigated, not packaged

The initial candidate was `mlx-community/whisper-large-v3-turbo`, revision
`a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb`, MIT upstream, 1,613,977,612-byte
`weights.safetensors`, SHA-256
`951ed3fc1203e6a62467abb2144a96ce7eafca8fa77e3704fdb8635ff3e7f8a6`.
Its unusually slow download was stopped before completion. It is not a fallback.
