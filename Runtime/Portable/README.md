# Private macOS 14 runtime candidates

These are pinned build inputs, not approval to distribute. `docs/release-approval.json`
remains false. Build/download commands run only during explicit preparation; the
installed app does not install Python packages or fetch runtime dependencies.

| Target | Reading | Default dictation | Optional dictation |
| --- | --- | --- | --- |
| arm64 | Supertonic 3 / ONNX Runtime 1.23.2 | Whisper Turbo / MLX 0.32.3 | Existing MLX Qwen and Large v3 providers; need revalidation with new runtime |
| x86_64 | Supertonic 3 / ONNX Runtime 1.23.2 | Whisper large-v3-turbo GGML q5_0 / whisper.cpp 1.9.5 CPU | Currently unavailable, explicitly disabled in the model UI |

Intel uses the same upstream Whisper Turbo family with a different quantization,
not identical MLX weights. Its exact revision, 574,041,195-byte size, SHA-256 and
MIT license are in `whisper-turbo-cpp-manifest.json`. The bridge is MIT-compatible
project code; upstream source and license are independently pinned in
`whisper-cpp-source.json` and `LICENSE-whisper.cpp`.

CPython 3.12.15 is independently obtained from python-build-standalone release
20261013. Each architecture/purpose lock records the archive and every wheel,
including exact filename, HTTPS source, size, SHA-256 and declared license. The
builder removes inherited site-packages/pip and installs only this closure.
Upstream license/notice files remain in the runtime. This is provenance evidence,
not a completed review of the entire redistribution license chain.

## Reproduce privately

Use Python 3.12 for assembly/worker checks and Xcode for native builds. No weights
or generated runtimes belong in Git. Output directories must be new.

```sh
python3 scripts/portable_runtime.py --lock Runtime/Portable/speech-arm64.json --cache .build/runtime-cache --output .build/speech-arm64
python3 scripts/portable_runtime.py --lock Runtime/Portable/dictation-arm64.json --cache .build/runtime-cache --output .build/dictation-arm64
python3 scripts/portable_runtime.py --lock Runtime/Portable/speech-x86_64.json --cache .build/runtime-cache --output .build/speech-x86_64
python3 scripts/portable_runtime.py --lock Runtime/Portable/dictation-x86_64.json --cache .build/runtime-cache --output .build/dictation-x86_64
bash scripts/build-whisper-cpp.sh /absolute/pinned-source.tar.gz /absolute/new-build x86_64
```

`build-whisper-cpp.sh` verifies the source archive and license before extracting,
builds for macOS 14 with Metal and host-specific CPU optimizations disabled, and
records source, bridge, build script and output hashes. Obtain the archive from
the exact URL in its manifest. The Intel model is separately hash-verified by
assembly; no implicit model download occurs.

Use `scripts/assemble-portable-resources.py --help` to assemble clean runtimes
with the existing verified Supertonic model, helper, public demo audio and notices.
Intel additionally needs the pinned GGML file and provenanced bridge. It emits
`Speech/`, `Dictation/`, explicit `runtime-backends.json` and integrity receipts
inside a new `Saywing.app/Contents/Resources` directory.

Pass that source app to `scripts/release.py --architecture arm64` or `x86_64`.
The packager checks all Mach-O slices/minimum versions and non-system absolute
load dependencies before signing. It never edits deployment versions in binaries.
An old minos=26.2 runtime now fails packaging even when its receipt is valid.

## Remaining gates

- Actual clean macOS 14 tests on Apple Silicon and native Intel; Rosetta is not
  evidence of Intel hardware performance or compatibility with macOS 14.
- Stable reading under CPU load; one Intel/Rosetta probe underrun was observed.
- New private candidate notarization, Gatekeeper and update round-trip.
- Architecture-specific downloads/feeds and storage paths. Both current private
  packages use the same name/build for diagnostics and MUST NOT be published to
  the existing single ARM endpoint. Intel public packaging is explicitly blocked.
- Complete licenses/third-party notices and optional ARM model revalidation.

References: [MLX installation](https://ml-explore.github.io/mlx/build/html/install.html),
[whisper.cpp](https://github.com/ggml-org/whisper.cpp),
[python-build-standalone](https://github.com/astral-sh/python-build-standalone).
