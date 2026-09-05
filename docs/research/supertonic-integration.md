# Supertonic 3 development default — 2026-09-05

## Owner decision and scope

After the [German listening comparison](supertonic-listening-comparison.md), the owner explicitly preferred Supertonic and requested it as the standard model. This supersedes the original Qwen candidate in current product documentation and agent guidance. The first voice is **M1** (announced as the initial choice), with eight denoising steps, speed 1.0, seed 42, and native 44.1 kHz. Qwen remains installed for comparison but the app never selects it, including on failure. This is not a blind claim that every Supertonic utterance is more faithful or natural.

The standard-model decision does **not** approve a portable runtime, model redistribution, notarization, or release. The [existing source/license manifest](supertonic-comparison-manifest.json) pins official model revision `3cadd1ee6394adea1bd021217a0e650ede09a323` and MIT inference helper revision `7e2804f96016a7028cb1ed627353c61c1e9dd281`. The ten model assets total **398,969,192 bytes**; no new model downloads were needed. Model/stock-voice terms are **BigScience Open RAIL-M**. Its restrictions and required downstream notices remain a distribution gate; the application's Apache-2.0 license does not cover the weights. Upstream's discontinuation of development/support remains a maintenance risk accepted for this development choice, not resolved by integration.

## Local installation

`scripts/install-supertonic-runtime.rb VERIFIED_COMPARISON_ROOT PYTHON UV` is an explicit developer operation, never invoked by the app. It checks pinned sizes/hashes, reuses local files, creates a separate environment with `uv --offline` and exact package versions, retains the unchanged upstream helper and MIT LICENSE, records runtime hashes, and refuses to overwrite existing destinations. It cannot silently download missing packages; missing cache data fails the installation. Existing Qwen files are untouched.

Actual installation:

- model: `~/Library/Application Support/OpenScreenReader/DevelopmentModels/supertonic-3-3cadd1ee`;
- runtime: `~/Library/Application Support/OpenScreenReader/SupertonicRuntime`;
- Python: 3.12.14; ONNX Runtime 1.23.2; NumPy 2.2.6;
- complete package pins and per-file hashes: runtime `installation-receipt.json`;
- model and helper integrity: runtime `model-manifest.json`, checked before every synthesis;
- upstream model LICENSE and README retained in the model directory; helper MIT license and ONNX/package notices retained in the runtime.

The environment still relies on the pre-existing external Python base interpreter under the local Codex dependency bundle. It is **not self-contained or portable**. App execution uses the absolute `venv/bin/python3` path; do not rely on activation/console-script paths from this staged venv. Removal of the external interpreter breaks this development runtime. Replacing that dependency with hermetic native ONNX or bundled Python and auditing the complete license/SBOM/signing chain remain release work. No system Python, package installation, or shell is started by the app; the app starts the explicitly installed Python interpreter only.

## Runtime and privacy

`SpeechReading` remains the provider boundary. `SpeechRuntimeConfiguration` selects only Supertonic's local paths and sample rate. Settings shows model/voice, machine-generated speech, license, and installation presence. Presence is not a cryptographic attestation; a corrupt model fails the worker's hash check instead of invoking a fallback.

The app sends bounded text plus an explicit `de`/`en` language code through stdin. The MVP detects English; otherwise it uses German, including ambiguous short text. This is not a claim of arbitrary multilingual detection. Python uses `-I -B`, ignoring user Python import paths and avoiding bytecode writes. The disposable single worker suppresses native stdout/stderr diagnostics before importing upstream code, emits only structured ready/audio/end/error packets, and never logs recognized text. Invalid input produces a generic error.

Synthesis uses sentence-first segments of at most 240 characters; long segments split at whitespace or a bounded character boundary. This simple rule is not a full abbreviation or OCR-normalization solution. The worker returns at most 24,000 Float32 little-endian frames per packet and waits for `next` after each. It bounds individual audio segments and rejects invalid/empty/non-finite waveforms. Audio retains its native 44.1 kHz, avoiding a pitch/speed change. The existing player prebuffers one second and admits up to four seconds; backpressure waits for queue space, not for each packet to finish playing.

The unchanged macOS sandbox profile denies network operations and all file writes except `/dev/null`. Text and audio stay in anonymous pipes/process memory. Only already-installed program/model resources persist. Escape, repeated shortcut, and Stop Reading stop the player first and kill the one owned worker process; no inference children survive. Generations and cancellation checks reject stale results. The app's startup/stall watchdogs remain active. No clipboard write, screenshot/audio history, cloud TTS, or Qwen fallback was added.

## Actual checks

- New Python protocol/segmentation tests failed before the worker existed, then passed: four tests for bounded requests, explicit language, rejected fields, segmentation, packet format, and required acknowledgements.
- New Swift default-model/sample-rate tests initially failed to compile against the old implementation. Debug build-for-testing then passed using the existing stable local signing identity, without resetting macOS permissions.
- 47 Swift Testing app tests plus two live permission/capture XCTest checks passed: `Test-OpenScreenReader-2026.09.05_01-56-09-+0200.xcresult`.
- The separate package Core test passed; all 11 Core behavior checks passed. An initial Xcode invocation named the package-only Core target incorrectly and was corrected; it was not a product failure.
- Real installed worker under deny-network/deny-write sandbox: first PCM at **2.051 s**, **4.000 s** audio for the fixed short fixture, finite/non-silent PCM, bounded frames, generic invalid-language error, no diagnostic text. Loopback connection and file-write probes each received `PermissionError`. Command: `ruby scripts/verify-supertonic-worker.rb`.
- Real long playback: **30.218 s** audio, 58 playback notifications, **zero underruns / zero missing seconds**, maximum queue **3.953 s**. Playback cancellation: **11.996 ms**, no late audio notifications. Clipboard unchanged. Command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/verify-speech-playback.sh --long`.
- The additional real loading-cancellation probe stopped the worker 100 ms after starting the request, before any playback notification: synchronous stop **0.064 ms** and **0.046 ms** in two runs; zero late notifications, clipboard unchanged. These timings measure the local stop call, not a cross-process acknowledgement. A repeated playback stop check measured **11.714 ms**.
- Two actual OCR → Supertonic → audio UI tests passed, including default M1 display and global Escape/repeated-shortcut cancellation with Finder active: `Test-OpenScreenReader-2026.09.05_01-56-52-+0200.xcresult`. These use the public speech fixture, not private screen content. No skips: two tests, zero failures.
- Release build passed with signing disabled for this build-only check. This is not a distributable signed/notarized release. Debug permission identity was preserved.
- All **3,043 Supertonic runtime receipt entries** and all **44 prior Qwen runtime receipt entries** matched after testing. Debug `codesign --verify --strict` reported `CSSMERR_TP_NOT_TRUSTED` for the existing local self-signed certificate; no trust/signing settings were changed. Actual launches and live permission-dependent UI tests passed, but this is not a trusted Developer ID signature.

Computer Use could not obtain a usable state for the windowless app (timeout for the exact Debug path; its bundle ID is ambiguous between Debug and Release). The already owner-authorized native XCUITest path verified actual screen selection and global keys. No successful Computer Use visual session is claimed.

These are single-machine development checks, not statistical latency/quality results. German/English fidelity, abbreviations, mixed-language selections, extended sessions, clean-machine setup, support/maintenance strategy, and release licensing/packaging remain open. Temporary listening WAVs from the prior explicit comparison remain separate from app behavior.
