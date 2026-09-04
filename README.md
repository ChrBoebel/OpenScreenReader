# OpenScreenReader

<p align="center">
  <img src="docs/brand-identity/assets/open-screen-reader-app-icon.png" alt="OpenScreenReader owl app logo" width="160">
</p>

**Select. Listen. Stay private.**

OpenScreenReader is a planned open-source macOS menu bar app that reads any visible text aloud with natural, fully local AI voices.

> Status: native macOS menu bar app with a configurable global hotkey, region selection, in-memory ScreenCaptureKit capture, and local German/English OCR using Apple Vision. The menu reports recognized character/line counts or an empty result; image and text content are discarded after recognition. Speech is not implemented. Capture, OCR fixtures, and a manual global Escape-delivery probe have passed on the development Mac. The integration remains experimental: the Finder-hotkey UI test has been intermittent, and the broader permission/display/layout matrix is not yet verified. No application has been released yet.

## Product promise

Default shortcut: **⌘⇧Y (Command + Shift + Y)** starts region selection; pressing the selected shortcut again or Escape cancels. To change it, open the menu bar icon → **Settings… → Keyboard shortcut**, choose modifiers and a key, then **Apply Shortcut**. The choice takes effect immediately and is saved locally across restarts. **Restore Default** returns to ⌘⇧Y. Changes are blocked during an active operation so its cancellation shortcut remains available.

Supported keys are A–Z, 0–9, and Space, combined with Command, Option, or Control; Shift is optional. Failed registration leaves the previous shortcut active and does not save the rejected choice. System-wide registrations are checked through Carbon, but ordinary app commands and services cannot all be detected: Command-only choices require confirmation, and the default overlaps macOS’s “Make Sticky” service. Keys are resolved from the current keyboard layout when registered; restart the app or apply the shortcut again after changing layouts.

Implementation checks and remaining limitations are recorded in [Shortcut verification](docs/shortcut-verification.md).

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
- [Local OCR implementation and verification](docs/ocr-verification.md)
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
