# Reproducible Python worker runtimes

Saywing's dictation worker (`Runtime/Dictation/worker.py`) and Supertonic speech worker
(`Runtime/Supertonic/worker.py`) run in bundled CPython interpreters. Both are built by
`scripts/build-python-runtime.py` from pinned, hash-verified inputs. Network access is used
**only while building**; the app never downloads or installs Python packages.

## Inputs

| Input | Pin |
| --- | --- |
| CPython | 3.12.15, python-build-standalone release 20261013, `install_only_stripped`; URL, size and SHA-256 per architecture in `Runtime/Portable/python.json` |
| Dictation, Apple Silicon | `Runtime/Dictation/requirements-lock.txt` (24 packages) |
| Dictation, Intel | `Runtime/Dictation/requirements-lock-x86_64.txt` (NumPy 2.2.6, SciPy 1.17.1; recognition uses the whisper.cpp bridge, `scripts/build-whisper-cpp.sh`) |
| Speech, both architectures | `Runtime/Supertonic/requirements-lock.txt` (NumPy 2.2.6, ONNX Runtime 1.23.2) |

Each lock pins exact versions with SHA-256 hashes of the macOS 14 wheels. The builder
installs them with `pip --require-hashes --no-deps --only-binary :all:` and explicit
`--platform macosx_14_0_<arch>` tags, so a newer build host cannot select wheels that need
a newer macOS. `mlx-whisper` stays at 0.4.3 because `scripts/patch-dictation-runtime.py`
is gated on that release's exact `transcribe.py` SHA-256.

### Why these packages

The locks contain only what the workers import, not the packages' declared dependency
closures (installed with `--no-deps`):

- A real Whisper Turbo transcription with the previous runtime, recording `sys.modules`,
  imported only: MLX, mlx-metal, mlx-whisper, NumPy, SciPy, tiktoken, regex, tqdm,
  huggingface_hub and its HTTP stack (httpx2, httpcore2, anyio, h11, idna, truststore,
  charset-normalizer), PyYAML, filelock and typing_extensions.
- The Qwen3-ASR path additionally needs mlx-audio, Transformers, tokenizers and packaging.
  Transformers refuses to import without the `safetensors` distribution, so it stays even
  though it is not imported.
- A real Supertonic synthesis imported only NumPy and ONNX Runtime; ONNX Runtime's other
  declared dependencies (coloredlogs, flatbuffers, protobuf, sympy, ...) are for its tools.

Not shipped any more: torch, numba/llvmlite (only used for word timestamps, which Saywing
disables), fsspec, hf-xet, requests, soundfile/libsndfile, sounddevice, miniaudio, pip,
setuptools, the unrelated document/image tool chain that came with a copied prototype
environment (including the non-redistributable `artifact_tool_v2` with `node_modules/@oai`),
and duplicate NumPy installs.

## Build

Prerequisites: macOS, `/usr/bin/curl`, a host Python 3.11+ with pip (it only downloads and
unpacks wheels; it never runs inside the app). Rosetta is needed only to *test* Intel
runtimes on Apple Silicon. Output directories must be new.

```sh
python3 scripts/build-python-runtime.py --runtime dictation --architecture arm64  --cache .build/runtime-cache --output .build/runtime/dictation-arm64
python3 scripts/build-python-runtime.py --runtime dictation --architecture x86_64 --cache .build/runtime-cache --output .build/runtime/dictation-x86_64
python3 scripts/build-python-runtime.py --runtime speech    --architecture arm64  --cache .build/runtime-cache --output .build/runtime/speech-arm64
python3 scripts/build-python-runtime.py --runtime speech    --architecture x86_64 --cache .build/runtime-cache --output .build/runtime/speech-x86_64
```

Hosts contacted: `github.com` (redirecting to `release-assets.githubusercontent.com` /
`objects.githubusercontent.com`) for CPython, `pypi.org` and `files.pythonhosted.org` for
wheels. If pip cannot reach the macOS trust store (seen in sandboxed shells as
`OSStatus -26276`), set `PIP_USE_DEPRECATED=legacy-certs`; integrity still comes from the
pinned hashes.

The builder:

1. downloads CPython over HTTPS and verifies size and SHA-256 **before** extracting
   (path-traversal and external-symlink checks as in `scripts/portable_runtime.py`);
2. removes pip/ensurepip, the test suite, IDLE, tkinter with Tcl/Tk, dbm, lib2to3, headers,
   man pages, static `config-3.12-darwin` files and every executable except `python3`;
3. installs the hash-locked wheels into `site-packages`, removes console scripts and
   bytecode (workers run with `-B`); package directories are otherwise unchanged
   (SciPy 1.17 imports `numpy._core.tests`, so test packages are not pruned);
4. fails if the installed set differs from the lock, or on forbidden content:
   `artifact_tool*`, torch, pip/setuptools/wheel, or any `@oai` or `node_modules` path;
5. writes `installed-packages.json` (name, version, license, license-file and vendored
   native-library paths relative to the runtime, wheel SHA-256, PyPI source page; it fails
   on any absolute path), `THIRD-PARTY-NOTICES.txt` (CPython and its components from
   `docs/licenses/Python-3.12.15*`, every package's license files, upstream texts from
   `docs/licenses` where a wheel ships none, and a copyleft/source-availability section) and
   `runtime-provenance.json` (lock hash, CPython pin, pip version, native audit);
6. audits every Mach-O file for the target architecture, macOS 14 minimum and no
   non-system absolute load paths.

To change a version, edit the pin and refresh hashes (this re-resolves the macOS 14 wheels):

```sh
python3 scripts/build-python-runtime.py --runtime dictation --update-hashes --cache .build/runtime-cache
```

Then rebuild and commit the regenerated `Runtime/Dictation/installed-packages.json`
(copy it from the arm64 dictation output). New versions without an SPDX expression fall
back to their metadata license until added to `REVIEWED_LICENSES` after review.

## Bundle

`scripts/bundle-dictation-runtime.py` accepts only such a runtime as `RESOURCES/Python`:
it re-runs the forbidden-content and inventory checks, requires the runtime inventory to
equal the committed `Runtime/Dictation/installed-packages.json`, copies it and
`THIRD-PARTY-NOTICES.txt` (plus the Google FLEURS CC BY 4.0 attribution for the demo clips)
into `Dictation/`, and applies the mlx-whisper hardened-runtime patch. A copied prototype
environment is rejected (for example `Forbidden package: torch-2.14.1.dist-info`).
`--development-only` and `--public-release` select the receipt wording; `scripts/release.py`
passes `--public-release` for public releases. The speech side is checked for the same
forbidden content when reused with `--speech-from`.

For local development speech, install the built speech runtime with
`ruby scripts/install-supertonic-runtime.rb VERIFIED_COMPARISON_ROOT .build/runtime/speech-arm64`.

## Verification, 2026-10-23

Built on Apple Silicon (macOS 26) from the pins above. Sizes compared with the earlier
runtimes:

| Runtime | Before | Now |
| --- | --- | --- |
| Dictation arm64 | 1.4 GB (copied prototype; installed portable candidate 1.1 GB) | 385 MB |
| Dictation x86_64 | — | 145 MB |
| Speech arm64 | 174 MB | 128 MB |
| Speech x86_64 | — | 141 MB |

- `Tests/Dictation/test_worker.py` (20 tests) passed with the arm64 and, under Rosetta, the
  x86_64 dictation runtime; `Tests/Fixtures/test_supertonic_worker.py` (9 tests) passed with
  both speech runtimes.
- Real Supertonic synthesis through the worker's session protocol (German and English) with
  both speech runtimes; x86_64 under Rosetta, which is not evidence for Intel hardware.
- The dictation runtime, after bundling (patch applied), verified the bundled Whisper Turbo
  model with the worker's own verifier, resampled the FLEURS clip with SciPy, built the
  Whisper tokenizer with tiktoken, imported the complete mlx-whisper and mlx-audio Qwen
  loader paths, and ran the Qwen3-ASR tokenizer and Whisper feature extractor from the
  installed model without torch.
- No `artifact_tool*`, `@oai`, `node_modules`, torch, numba, pip or Tcl/Tk in any output.

**Not yet run:** a real MLX transcription with this runtime. MLX needs a Metal device,
which the sandboxed build shell used here does not provide, so MLX itself was replaced by
an import stub for the import-closure check above. Before release, run on an Apple Silicon
Mac with a bundled app:

```sh
python3 Tests/Dictation/integration_worker.py /path/Saywing.app/Contents/Resources/Dictation /tmp/saywing-check whisper-turbo
```

(`integration_worker.py` itself reads the demo WAVs with `soundfile`; run it with a Python
that has NumPy and soundfile, not the bundled worker runtime.)
