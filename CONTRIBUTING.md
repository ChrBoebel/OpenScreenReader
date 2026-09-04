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
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build-speech-fixture.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OpenScreenReader.xcodeproj -scheme OpenScreenReader -destination 'platform=macOS,arch=arm64'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project OpenScreenReader.xcodeproj -scheme OpenScreenReader -configuration Release -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

The Xcode test command uses local ad-hoc signing because the UI test launches and exercises the real menu bar application. It does not require an Apple Developer account.

On a Mac with existing app permissions, use the stable Debug signing override below instead of changing its identity. The two real Qwen UI tests skip explicitly when no development runtime is installed. They require the separate fixed-text fixture built above and use the actual local model/audio path; see [runtime setup and test evidence](docs/research/swift-runtime-evaluation.md). `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/verify-speech-playback.sh` additionally exercises complete playback and immediate cancellation without recording audio; it audibly plays a fixed public German sentence.

### Optional stable local Debug signing

Ad-hoc builds can lose effective Screen Recording and Input Monitoring access after a rebuild. For local development, an explicitly owner-created self-signed **Code Signing** certificate in the login keychain can give the app a certificate-based designated requirement instead of a changing code hash. Do not export its private key or commit certificates, keychain files, or machine-specific signing settings.

Use the same identity on every Debug rebuild (replace the placeholder with the certificate's SHA-1 fingerprint):

```sh
OSR_CODE_SIGN_IDENTITY='YOUR_LOCAL_CODE_SIGNING_CERTIFICATE_SHA1'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$OSR_CODE_SIGN_IDENTITY" build-for-testing

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -destination 'platform=macOS,arch=arm64' test-without-building
```

Debug deliberately disables Hardened Runtime: a self-signed identity has no Apple Team ID, so runtime library validation otherwise rejects the embedded Debug library at launch. **Release keeps Hardened Runtime enabled.** This local Debug configuration is not a distribution configuration; it changes no macOS-wide security or certificate-trust settings. See Apple's [library validation requirements](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.disable-library-validation) and [code-signing guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html).

After switching signing identities, grant permissions to the exact Debug app and relaunch it if macOS requires it. An enabled Settings switch or valid signature alone does not prove effective access; use the live tests in [capture verification](docs/capture-verification.md). Keep using `test-without-building` when checking the currently permission-enabled binary. Stable requirements across builds and permission persistence are separate checks, not guaranteed by this setup.

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
