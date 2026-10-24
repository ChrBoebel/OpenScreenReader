# Pinned runtime build inputs

Build inputs, not approval to distribute (`release/release-approval*.json` decide that).
They are downloaded only while building, by `scripts/build-python-runtime.py` and
`scripts/assemble-release-runtime.py`; the installed app never installs Python
packages or fetches runtime dependencies. No weights or generated runtimes belong
in Git. See [docs/runtime-build.md](../../docs/runtime-build.md) for the build.

| File | Pins |
| --- | --- |
| `python.json` | CPython 3.12.15 from python-build-standalone 20261013 per architecture: URL, size, SHA-256 |
| `whisper-turbo-cpp-manifest.json` | Intel Whisper Turbo model: GGML q5_0 file at an exact Hugging Face revision, 574,041,195 bytes, SHA-256, MIT |
| `whisper-cpp-source.json`, `LICENSE-whisper.cpp` | whisper.cpp 1.9.5 source archive (exact commit, size, SHA-256) and its license |
| `release-inputs.json` | Inputs no other manifest records: the Supertonic `helper.py`, `LICENSE` and `README.md` at the upstream commit, and the two Google FLEURS archives holding the demo clips listed in `Runtime/Dictation/demo-manifest.json` |

| Target | Reading | Default dictation | Optional dictation |
| --- | --- | --- | --- |
| arm64 | Supertonic 3 / ONNX Runtime 1.23.2 | Whisper Turbo / MLX 0.32.3 | Qwen3-ASR and Whisper Large v3 (MLX), installed on request; revalidate with this runtime |
| x86_64 | Supertonic 3 / ONNX Runtime 1.23.2 | Whisper large-v3-turbo GGML q5_0 / whisper.cpp 1.9.5 CPU | None; `runtime-backends.json` hides the other models |

Intel uses the same upstream Whisper Turbo family with a different quantization,
not identical MLX weights. The bridge (`Runtime/WhisperCpp/bridge.cpp`) is project
code built by `scripts/build-whisper-cpp.sh`, which verifies the source archive and
license before extracting, builds for macOS 14 with Metal and host-specific CPU
optimizations disabled, and records source, bridge, build script and output hashes.

## Remaining gates

- Clean macOS 14 tests on Apple Silicon and native Intel; Rosetta is not evidence
  of Intel hardware performance or compatibility with macOS 14.
- Stable reading under CPU load; one Intel/Rosetta probe underrun was observed.
- Intel public packaging stays blocked until `release/release-approval-x86_64.json`
  is complete.

References: [MLX installation](https://ml-explore.github.io/mlx/build/html/install.html),
[whisper.cpp](https://github.com/ggml-org/whisper.cpp),
[python-build-standalone](https://github.com/astral-sh/python-build-standalone).
