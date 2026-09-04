# Contributing to OpenScreenReader

Thank you for helping build a private, local, and accessible macOS reading tool.

## Before contributing

Read:

- `docs/product-vision.md`
- `docs/ux-requirements.md`
- `docs/architecture.md`
- `docs/privacy.md`
- `AGENTS.md`

## Non-negotiable principles

- OCR and TTS remain local after installation of the official bundled-model release.
- No silent cloud fallback.
- No account requirement or default telemetry.
- No persistent capture history by default.
- New dependencies need explicit license and privacy review.
- Accessibility and immediate cancellation are functional requirements.

## Development workflow

The project is currently in its foundation phase. A platform-neutral Swift package contains the first cancellable-pipeline contracts while the native application target waits for a full Xcode installation.

Run the current behavior checks and production build with:

```sh
swift run OpenScreenReaderCoreBehaviorChecks
swift build -c release --target OpenScreenReaderCore
```

The currently selected standalone Command Line Tools installation does not expose `XCTest` or `Swift Testing` to SwiftPM. The executable behavior-check target is a temporary, dependency-free test harness for this bootstrap phase. Move these cases into the Xcode unit-test target when the application project is created; do not treat the harness as a replacement for unit and UI tests.

Until then:

- keep changes focused;
- add tests with behavior changes;
- document architecture decisions that affect privacy, packaging, or licenses;
- do not commit model weights, generated audio, screenshots, credentials, or `.env` files;
- stage release model weights only from pinned, hashed, license-approved sources outside Git;
- do not claim support for hardware or macOS versions that have not been tested.

## Licensing

Contributions to project code and documentation are accepted under Apache License 2.0. Third-party code, model weights, voices, and assets must retain compatible licensing and attribution.
