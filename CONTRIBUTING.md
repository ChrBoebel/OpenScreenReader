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

The project is currently in its foundation phase. A platform-neutral Swift package contains the first cancellable-pipeline contracts. Xcode 26.6 is installed locally and is selected per command so other development processes keep their own toolchain choice.

Run the Apple test target, current behavior checks, and production build with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift run OpenScreenReaderCoreBehaviorChecks
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build -c release --target OpenScreenReaderCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OpenScreenReader.xcodeproj -scheme OpenScreenReader -destination 'platform=macOS,arch=arm64'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project OpenScreenReader.xcodeproj -scheme OpenScreenReader -configuration Release -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

The Xcode test command uses local ad-hoc signing because the UI test launches and exercises the real menu bar application. It does not require an Apple Developer account.

The executable behavior-check target predates the full Xcode installation and remains temporarily as a migration safety net. Move each case into `OpenScreenReaderCoreTests`, then remove the executable target once equivalent Apple tests pass. The active global `xcode-select` still points to standalone Command Line Tools, so keep using the explicit `DEVELOPER_DIR` prefix until the owner chooses otherwise.

Until then:

- keep changes focused;
- add tests with behavior changes;
- document architecture decisions that affect privacy, packaging, or licenses;
- do not commit model weights, generated audio, screenshots, credentials, or `.env` files;
- stage release model weights only from pinned, hashed, license-approved sources outside Git;
- do not claim support for hardware or macOS versions that have not been tested.

## Licensing

Contributions to project code and documentation are accepted under Apache License 2.0. Third-party code, model weights, voices, and assets must retain compatible licensing and attribution.
