# Saywing

<p align="center">
  <img src="docs/brand-identity/assets/saywing-app-icon.png" alt="Saywing app icon" width="160">
</p>

**Read aloud & dictate on your Mac. Hear text. Write with your voice.**

*Vorlesen & Diktieren für macOS. Text hören. Mit der Stimme schreiben.*

Saywing is an open-source macOS menu bar app for local screen reading and dictation. Press a shortcut, drag over any text on screen, and hear it read aloud by a local neural voice. Or hold a key, speak German or English, and have the text pasted into the field you are typing in. Recognition and speech run on your Mac; nothing you read or say is uploaded.

The project was previously called OpenScreenReader. The repository, Xcode project and scheme, Swift modules, bundle identifier and `Application Support` directory keep that technical name so existing settings and installations stay compatible.

> **Saywing is not a screen reader in the VoiceOver sense** and is not a replacement for VoiceOver. It reads selected regions of the screen aloud; it does not navigate interfaces, announce controls or provide full non-visual operation of macOS.

## Status

**Beta.** Saywing is usable day to day by its developers, but it is young software:

- The development target is Apple Silicon. Intel (x86_64) builds exist, but they have only been tested under Rosetta, not on physical Intel hardware.
- macOS 14 is the minimum deployment target. Physical testing on macOS 14 and 15 is still incomplete; most testing happened on macOS 26.
- A fresh-Mac permission walkthrough, a full matrix of target apps for dictation, and a live VoiceOver/keyboard review are still open.
- Building the speech and dictation runtimes from public sources is not yet a single reproducible step (see [Building from source](#building-from-source)).

See the [roadmap](docs/roadmap.md) for open gates and [CHANGELOG.md](CHANGELOG.md) for notable changes.

## Features

**Read aloud**

- Default shortcut **⌥R** (configurable) starts a region selection on any display. Drag as with ⌘⇧4: hold Space to move, Shift to lock an edge, Option to grow it around the starting point. A single click reads only the paragraph under the pointer.
- Text is recognized locally with Apple Vision (German and English) and spoken automatically with the local [Supertonic 3](https://huggingface.co/Supertone/supertonic-3) voice M1. There is no cloud or system-voice fallback.
- Press the shortcut again while speaking to queue another region (up to five texts). A small floating capsule offers Stop, Pause/Resume, speed (0.75× to 2×, pitch-preserving), Next and a queue view. You can dock it at the bottom, left or right edge.
- **Escape** or any Stop control cancels the whole pipeline immediately, including queued and prepared audio.

**Dictate**

- Hold **Fn** to dictate and release to insert. Double-tap Fn or press **Fn + Space** for hands-free recording; **⌥⇧Space** is a toggle for keyboards without Fn. **Escape** discards.
- Speech is recognized locally with **Whisper large-v3-turbo**, which ships with the app. On Apple Silicon you can install **Qwen3-ASR 0.6B** or **Whisper Large v3** later, but only after you explicitly confirm a download. An optional local vocabulary helps with names and terms.
- Text is inserted with a short clipboard paste. Saywing restores your previous clipboard after 1 s (2 s optional), but only if nothing else has been copied in the meantime. Saywing never pastes into a target that changed during recognition.

**Meeting transcript (macOS 26 or later)**

- An explicitly started, consented live transcript of **Me** (microphone) and **Others** (other apps' audio, captured through a private Core Audio tap that excludes Saywing). It uses Apple's on-device speech recognition with already-installed languages only. No audio is saved, and the transcript leaves memory only through Copy or Save. See [ADR 0006](docs/decisions/0006-local-meeting-transcript.md).

**General**

- Guided setup that explains each macOS permission before requesting it, plus a real reading test.
- English and German interface, following the macOS language.
- VoiceOver labels and actions; respects Reduce Motion, Reduce Transparency and Increase Contrast.
- Signed in-app updates via [Sparkle](https://sparkle-project.org). Automatic update checks can be disabled.

## Privacy

Saywing handles potentially sensitive screen content and speech, so privacy is treated as a testable requirement. The details are in [docs/privacy.md](docs/privacy.md). In short:

- **Local processing.** OCR, speech synthesis, dictation and meeting transcription run on your Mac. There is no cloud OCR, TTS or ASR, no account, and no telemetry.
- **No history.** Screenshots, recognized text, dictated text and audio stay in memory for the active operation only. Nothing is written to disk unless you explicitly save a meeting transcript.
- **Clipboard.** Reading never writes to the clipboard. Dictation uses it briefly to paste, as described above.
- **Network.** The app makes exactly two kinds of network requests:
  1. **Sparkle update checks.** These are transparent and can be disabled, and an update is installed only after you confirm it. Updates are signed and no content is uploaded.
  2. **Model downloads you confirm.** Optional dictation models are fetched from pinned Hugging Face revisions, and every file is SHA-256-verified against a manifest bundled with the app before use.

  There is no other runtime network access. The speech and dictation workers run under a macOS sandbox profile that denies network access and file writes.
- **Permissions.** Each permission is requested only when you start the feature that needs it:
  - Screen Recording (reading)
  - Input Monitoring (Escape while another app is active)
  - Microphone and Accessibility (dictation and paste)
  - System audio recording (meeting transcript)

## Requirements

- macOS 14 Sonoma or later. The meeting transcript requires macOS 26.
- Apple Silicon is recommended. Intel builds use whisper.cpp for dictation and offer only the bundled Whisper Turbo model.
- For development:
  - Xcode 26 with the macOS 26 SDK. CI runs on GitHub's `macos-26` image. The Swift package uses swift-tools-version 6.2.
  - Python 3.11 or later to run the Python tests and scripts. The bundled runtimes themselves use CPython 3.12.
  - Ruby, which ships with macOS, for some development scripts.

## Building from source

### Build and test the app

```sh
git clone https://github.com/ChrBoebel/OpenScreenReader.git
cd OpenScreenReader

# Core package tests
swift test

# App unit and UI tests (keep DerivedData outside ~/Documents; see CONTRIBUTING.md)
xcodebuild test -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -destination 'platform=macOS' -derivedDataPath /tmp/saywing-dd

# Release build without signing
xcodebuild build -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /tmp/saywing-dd CODE_SIGNING_ALLOWED=NO
```

This produces a working `Saywing.app` with the menu bar, setup, region selection and OCR. **Model weights and the Python runtimes are not part of the Git repository.** Without them, the app reports that the speech or dictation runtime is unavailable instead of falling back to another voice.

### Speech and dictation runtimes

The runtimes are assembled from pinned, hash-verified inputs:

- The **Supertonic 3 model** and its inference helper are pinned with per-file hashes and licenses in [`docs/research/supertonic-comparison-manifest.json`](docs/research/supertonic-comparison-manifest.json).
- The **dictation models** are pinned in [`Runtime/Dictation/`](Runtime/Dictation) (`*-manifest.json`).
- **Python environments** (CPython 3.12.15 from python-build-standalone, plus exact wheels) are locked in [`Runtime/Portable/`](Runtime/Portable/README.md).

The available developer scripts are described in [docs/development-packaging.md](docs/development-packaging.md) and [Runtime/Portable/README.md](Runtime/Portable/README.md):

- `scripts/portable_runtime.py` builds the locked Python environments.
- `scripts/assemble-portable-resources.py` places the runtimes and verified models into an app bundle.
- `scripts/install-supertonic-runtime.rb` installs a local development speech runtime under `~/Library/Application Support/OpenScreenReader`.

**Not yet reproducible from public sources in one step:** obtaining and staging the Supertonic and Whisper model files, and the full assembly of the dictation runtime, still require manual preparation. A reproducible runtime build is in progress; check [docs/development-packaging.md](docs/development-packaging.md) for its current state. None of these scripts runs inside the app, and none is invoked automatically.

## Documentation

- [Product vision](docs/product-vision.md)
- [UX requirements](docs/ux-requirements.md)
- [Architecture](docs/architecture.md)
- [Privacy requirements](docs/privacy.md)
- [Research summary: market and local TTS](docs/research/market-and-tts-findings.md)
- [Roadmap](docs/roadmap.md)
- [Architecture decision records](docs/decisions/README.md)
- [Development packaging](docs/development-packaging.md) and [release and updates](docs/release-and-updates.md)
- [Model and runtime provenance](docs/research/)
- [Brand system](docs/brand-identity/BRAND_SYSTEM.md)
- [Contributing](CONTRIBUTING.md), [Security policy](SECURITY.md), [Code of conduct](CODE_OF_CONDUCT.md)

Some design documents are still written in German; English translations are planned.

## License

- **Source code:** Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
- **Bundled models have their own licenses:**
  - **Supertonic 3** (speech model and voices) is licensed under the **BigScience OpenRAIL-M** license, which includes use restrictions. See [docs/licenses/SUPERTONIC-MODEL-TERMS.md](docs/licenses/SUPERTONIC-MODEL-TERMS.md).
  - **Whisper** (OpenAI Whisper large-v3-turbo and large-v3) is licensed under MIT.
  - **Qwen3-ASR** is licensed under Apache-2.0.
- Third-party code, runtimes and libraries keep their own licenses. Their notices are collected in [docs/licenses/](docs/licenses).
