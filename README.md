# OpenScreenReader

<p align="center">
  <img src="docs/brand-identity/assets/open-screen-reader-app-icon.png" alt="OpenScreenReader owl app logo" width="160">
</p>

**Select. Listen. Stay private.**

OpenScreenReader is a planned open-source macOS menu bar app that reads any visible text aloud with natural, fully local AI voices.

> Status: native macOS menu bar app with a global hotkey, region selection, an in-memory ScreenCaptureKit adapter, permission guidance, and the approved Owl Frame app icon. Permission-enabled capture and Escape-monitor setup have been tested on the development Mac. The integration remains experimental: global Escape delivery and the broader permission/display matrix are not yet verified. OCR, speech, and configurable shortcuts are not implemented. No application has been released yet.

## Product promise

- Press a global keyboard shortcut.
- Drag a rectangle over any visible text.
- Recognize it locally with Apple Vision.
- Start natural speech automatically with a local TTS model.
- Stop immediately with `Esc` or the same shortcut.

The official macOS release is intended to include its default local speech model. After installation, OCR and speech synthesis should work without an internet connection or a separate model setup step. Screenshots, recognized text, and generated audio should remain in memory by default.

## Why this project?

Existing tools generally offer either fast local screen OCR with macOS system voices or natural cloud speech. OpenScreenReader explores the missing combination:

- TextSniper-like one-gesture UX;
- modern on-device neural speech;
- transparent, auditable privacy through open source.

## Planned technology

- SwiftUI and AppKit
- ScreenCaptureKit/CoreGraphics
- Apple Vision (`VNRecognizeTextRequest`)
- MLX-based local TTS worker
- Qwen3-TTS 0.6B 4-bit as the primary candidate
- optional Supertonic provider for a lower-memory mode

The bundled model and runtime will be pinned, hashed, license-audited, and injected into release builds without committing model weights to Git.

The implementation architecture is provisional and must be validated with focused technical spikes before the full MVP is built.

## Documentation

- [Product vision](docs/product-vision.md)
- [UX requirements](docs/ux-requirements.md)
- [Proposed architecture](docs/architecture.md)
- [Privacy principles](docs/privacy.md)
- [Research summary](docs/research/market-and-tts-findings.md)
- [Roadmap](docs/roadmap.md)
- [Architecture decisions](docs/decisions/)
- [Capture implementation and verification](docs/capture-verification.md)
- [Approved brand system](docs/brand-identity/BRAND_SYSTEM.md)
- [Contributing](CONTRIBUTING.md)

## Privacy principles

The official build should have:

- no account requirement;
- no cloud OCR or cloud TTS;
- no telemetry by default;
- no automatic clipboard writes;
- no persistent screenshot, OCR-text, or audio history;
- clear disclosure of every required macOS permission and network request.

The MVP runtime should make no network request. Downloading the signed application from the project website is outside the application runtime.

See [docs/privacy.md](docs/privacy.md) for the enforceable requirements.

## License

The project code and documentation are licensed under the [Apache License 2.0](LICENSE). Model weights, voices, runtimes, and third-party assets retain their own licenses and must be documented separately before distribution.
