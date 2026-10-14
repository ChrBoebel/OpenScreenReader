# Local Qwen dictation runtime

Owner decision, 2026-10-13: integrate the tested local German/English dictation prototype into Saywing. Clipboard paste followed by restoration is explicitly authorized for dictation. This does not change the Supertonic reading provider or authorize clipboard writes during OCR/reading.

## Pinned assets

- ASR: [mlx-community/Qwen3-ASR-0.6B-8bit](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit), revision `89e96d92ba34aca20b3e29fb10cc284097d1219f`, Apache-2.0 per the model source.
- Upstream: [Qwen/Qwen3-ASR-0.6B](https://huggingface.co/Qwen/Qwen3-ASR-0.6B), revision `5eb144179a02acc5e5ba31e748d22b0cf3e303b0`.
- Weight size: 1,006,229,426 bytes; SHA-256 `b5bfe4abc1b4c6e58b633096682ec2b6297298add1527119936107d211adf0e8`.
- Each model/tokenizer file's size and verified hash: `Runtime/Dictation/model-manifest.json`. Checked at packaging and every model start. No remote model code or runtime downloads.
- Existing private CPython 3.12.14 runtime, mlx-audio 0.5.8 (MIT), MLX 0.32.3, NumPy, SciPy, Transformers and transitive dependencies; the tested runtime is reused from the independent prototype. `requirements-lock.txt` records the original environment and `installed-packages.json` records bundled metadata. Package and interpreter license files remain in the bundle. No weights or dependency binaries are committed to Git.
- Public demonstration audio: [Google FLEURS](https://huggingface.co/datasets/google/fleurs), CC BY 4.0, revision `70bb2e84b976b7e960aa89f1c648e09c59f894dd`. Two unchanged German/US-English samples. Original IDs, references, byte sizes and hashes accompany them in `Demos/manifest.json`. Demo buttons transcribe these files without activating the microphone.

## Architecture and lifecycle

`DictationController` owns the native setup/test window and nonactivating recording indicator. `AppModel` serializes the transition from reading to dictation and stops speech before the recording callback. Starting reading cancels dictation immediately, before selection begins. Dictation has its own Option–Shift–Space registration. Escape is registered only for an active dictation; inability to acquire it prevents recording. The prototype must be closed to free its identical shortcut.

`DictationTranscribing` separates the controller from the local Qwen process. Swift 6 main-actor isolation guards UI and worker session state. Typed worker packets travel over anonymous pipes with a session UUID, request UUID, bounds and timeouts. Stop invalidates the session before terminating the worker, with a kill deadline. Cold-start microphone PCM remains in bounded RAM until the model is ready. No recording on launch or permission grant. Audio length is capped at 60 seconds. Owner decision 2026-10-13: prepare the worker automatically on app launch and retain it in idle memory, including while reading. Active dictation inference is still cancelled before reading; a later dictation starts a stopped worker automatically. Sleep, inactive user session and quit unload it. Wake/session activation automatically prepare it again only when both are available. Preparation is idempotent and blocked after shutdown, never opens the microphone, and does not retry fatal failures in a loop. Keeping the model warm trades retained RAM for faster repeated dictation.

The Python subprocess uses isolated imports, no bytecode, offline flags and an OS profile denying networking and file writes except `/dev/null`. PCM, transcripts and clipboard snapshots have no file/history path. The last transcript and test field are session-local. Model choice, language selection and restore delay are the dictation preferences. ASR output is direct transcription, without an extra rewrite model.

## Paste contract

Capture the target app, AX field, window, original text and selection when available. Validate again after recognition and immediately before one Cmd+V. The V key is resolved from the active keyboard layout. Secure/unknown fields are rejected. Changed targets retain the result in the dictation window for explicit copying; no blind retry or Return key.

Save every readable format of all clipboard items up to 16 MiB. Unreadable/oversize data aborts before mutation. Restore after 1 second (optional 2), only while both changeCount and a unique ownership marker still match. New user/other-app copies win. Cancel and normal quit restore an owned clipboard immediately. A hard crash in the short paste interval cannot guarantee restoration; clipboard managers may observe the text despite the concealed marker. Exact readback alone earns the “Eingefügt” status.

## Private packaging

Build the app, run the existing offline Supertonic packager, then attach the already verified dictation resources:

```sh
ruby scripts/package-development-app.rb /absolute/Release/Saywing.app --development-only
python3 scripts/bundle-dictation-runtime.py /absolute/staged/Saywing.app /absolute/existing/DictationResources --whisper-model /absolute/verified/WhisperTurbo [--with-qwen] [--whisper-large-model /absolute/verified/WhisperLargeV3] --development-only
```

Alternatively, pass `--speech-from /Applications/Saywing.app` to the dictation packager with a fresh built app to reuse an already bundled Speech runtime. It verifies that app’s signature, receipt, revision and worker before copying; this avoids depending on a changed development-venv interpreter. Build-time pkgconfig and manual-alias symlinks are omitted from Python resources.

The second command verifies the pinned model, copies the private Python/model/demo closure, rejects escaping symlinks, preserves licenses, signs native dependencies and creates a post-signing SHA-256 inventory. Bundle resources are the only ASR source; a missing/broken bundle fails visibly with no developer-path fallback.

This local integration is not a public release: full transitive redistribution/license-chain audit, independently pinned interpreter build provenance, Developer ID/notarization, fresh-Mac testing and broader target-app compatibility remain release gates. Qwen3-ASR is speech recognition; it is unrelated to the rejected Qwen3-TTS voice comparison.

## Selectable ASR models — 2026-10-13

The owner added Whisper large-v3-turbo as a second explicit choice. See
[its pinned source, license and checks](whisper-turbo-dictation.md). The shared
private Python runtime is reused; each worker process loads only the selected
backend. There is no fallback between models. Model changes are blocked during
active dictation, terminate the previous worker, invalidate its callbacks and
warm the new model automatically. `dictationModel.v1` stores only the enum ID.
