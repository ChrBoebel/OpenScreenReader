# Contributing to Saywing

Thank you for helping build a private, local and accessible macOS text-and-voice tool. The repository, Xcode project, scheme and module identifiers keep the former name OpenScreenReader for compatibility; the product name is Saywing.

## Before contributing

Read:

- [`docs/product-vision.md`](docs/product-vision.md)
- [`docs/ux-requirements.md`](docs/ux-requirements.md)
- [`docs/architecture.md`](docs/architecture.md)
- [`docs/privacy.md`](docs/privacy.md)
- [`AGENTS.md`](AGENTS.md): product invariants and engineering rules that apply to every change, whoever writes it.

For larger changes, open an issue first so the approach can be discussed before you invest time. Report security problems privately as described in [SECURITY.md](SECURITY.md), not in public issues. Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).

## Non-negotiable principles

- OCR, TTS and ASR stay local. There is no silent cloud fallback.
- No account requirement and no telemetry.
- No persistent capture, text or audio history by default.
- The only runtime network access is Sparkle update checks, which users can disable, and model downloads that users explicitly confirm. Any new network path needs an explicit project decision.
- New dependencies need an explicit license and privacy review.
- Accessibility and immediate cancellation are functional requirements.

## Development setup

You need:

- macOS 14 or later. Developing on macOS 26 is recommended, because the meeting transcript needs macOS 26 APIs.
- Xcode 26. If `xcode-select` points to the Command Line Tools, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Python 3.11 or later for the Python tests and scripts.

**Keep DerivedData and SwiftPM scratch directories outside `~/Documents`.** Builds and tests under `~/Documents` can hang because of file-provider and privacy checks. The commands below use `/tmp`.

### Tests and builds

```sh
# Core Swift package
swift test --scratch-path /tmp/saywing-spm
swift run --scratch-path /tmp/saywing-spm OpenScreenReaderCoreBehaviorChecks

# App unit and UI tests
xcodebuild test -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -destination 'platform=macOS' -derivedDataPath /tmp/saywing-dd

# Release build without signing
xcodebuild build -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /tmp/saywing-dd CODE_SIGNING_ALLOWED=NO

# Python tests (release tooling, dictation worker protocol, Supertonic worker protocol)
python3.11 -m unittest discover -s Tests/Release -v
python3.11 -m unittest discover -s Tests/Dictation -p 'test_*.py'
python3.11 -m unittest discover -s Tests/Fixtures -p 'test_*.py'

# Localization coverage
python3.11 scripts/check-localization.py
```

Environment variables for `xcodebuild test` must carry the `TEST_RUNNER_` prefix to reach the test process.

Notes on the test suite:

- The Xcode tests use local ad-hoc signing because the UI test launches the real menu bar app. No Apple Developer account is needed.
- Tests that depend on Screen Recording or Input Monitoring skip or fail when the test host lacks those grants. That is an environment issue, not a pass: report such tests as skipped.
- The real Supertonic UI tests skip when no development speech runtime is installed. They also need the fixed-text fixture app: run `bash scripts/build-speech-fixture.sh` first.
- `bash scripts/verify-speech-playback.sh` exercises complete playback and immediate cancellation with a fixed public German sentence. It plays audio and records nothing.
- `scripts/verify-dictation.sh /path/to/Saywing.app/Contents/Resources/Dictation` runs the dictation worker checks against a bundled runtime.

Speech and dictation runtimes are not in Git. See [README.md](README.md#building-from-source) and [docs/development-packaging.md](docs/development-packaging.md).

### Optional stable local Debug signing

Ad-hoc builds can lose effective Screen Recording and Input Monitoring access after a rebuild. For local development, a self-signed **Code Signing** certificate in your login keychain gives the app a certificate-based designated requirement instead of a changing code hash. Never export its private key, and never commit certificates, keychain files or machine-specific signing settings.

Use the same identity on every Debug rebuild. Replace the placeholder with the certificate's SHA-1 fingerprint:

```sh
OSR_CODE_SIGN_IDENTITY='YOUR_LOCAL_CODE_SIGNING_CERTIFICATE_SHA1'
xcodebuild -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/saywing-dd \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$OSR_CODE_SIGN_IDENTITY" build-for-testing

xcodebuild -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -destination 'platform=macOS' -derivedDataPath /tmp/saywing-dd test-without-building
```

Debug deliberately disables Hardened Runtime. A self-signed identity has no Apple Team ID, so runtime library validation would otherwise reject the embedded Debug library at launch. **Release keeps Hardened Runtime enabled.** This Debug configuration is not a distribution configuration, and it changes no macOS-wide security or certificate-trust settings. See Apple's [library validation requirements](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.disable-library-validation) and the [code signing guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html).

After switching signing identities, grant permissions to the exact Debug app and relaunch it if macOS requires it. An enabled switch in System Settings or a valid signature alone does not prove effective access; the live capture tests do. Use `test-without-building` to check the binary that currently has the permissions.

The executable `OpenScreenReaderCoreBehaviorChecks` target is a migration safety net. Move each case into `OpenScreenReaderCoreTests`, then remove the executable target once equivalent tests pass.

## Branches and pull requests

Changes reach `main` only through pull requests:

1. Start a focused feature branch from the current `main` with a short descriptive name, for example `fix/escape-during-ocr` or `feat/queue-preview`.
2. Make small, meaningful commits in the existing conventional style (`feat: …`, `fix: …`, `docs: …`, `chore: …`). Before pushing, review the diff for secrets, model weights and generated user content.
3. Open a pull request against `main` using the PR template. Describe the change, the verification you actually ran, any skipped checks and the remaining risks.
4. A maintainer reviews and merges. Do not rewrite published history.

Documentation-only changes need a content review and `git diff --check`; an app build or UI test is not required when no code, configuration or assets changed. Behavior changes need the relevant tests, a build, and real UI checks where possible. Never report a skipped or blocked check as passed.

General expectations:

- Keep changes focused and add tests with behavior changes. Test-driven development is preferred for observable behavior.
- Give every asynchronous operation explicit cancellation and stale-result protection.
- Record decisions that affect privacy, packaging or licensing as an ADR in [`docs/decisions/`](docs/decisions/README.md).
- Do not commit model weights, generated audio, screenshots, recognized text, credentials or `.env` files.
- Stage release model weights only from pinned, hashed, license-approved sources outside Git. Document the source, exact revision, size, hash and license.
- Do not copy code from other repositories without verifying a compatible license. GPL code needs an explicit project-level licensing decision.
- Do not claim support for hardware or macOS versions that have not been tested.

## Licensing

Contributions to project code and documentation are accepted under the Apache License 2.0. Third-party code, model weights, voices and assets keep their own licenses and must be attributed.
