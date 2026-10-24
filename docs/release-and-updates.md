# Saywing distribution and updates

This document describes how Saywing is signed, notarized, packaged, published and
updated. Owner-specific values (signing identity, team ID, download URL, release
repository) are defaults in the scripts and can be overridden through environment
variables or GitHub repository variables; nothing private is required to read,
build or test the source.

## Signing identity

Every distributable is signed with a Developer ID Application certificate and
notarized by Apple. The owner defaults are:

- Team ID: `S28WSHSSJD` (override: `SAYWING_TEAM_ID`).
- Identity: `Developer ID Application: Christopher Böbel (S28WSHSSJD)`
  (override: `SAYWING_SIGNING_IDENTITY` or `--identity`).
- Local notarytool keychain profile: `Saywing-Notary-S28WSHSSJD`
  (override: `SAYWING_NOTARY_PROFILE` or `--notary-profile`).

Every changed distributable needs fresh signing and notarization.

## Update behavior

Sparkle **2.10.0**, exact revision
`eef1a539a373c1f1a320624b1130fc5de7b2e100`, is resolved through the committed
Xcode `Package.resolved`. Its MIT and bundled dependency notices are preserved in
`docs/licenses/Sparkle-2.10.0.txt` and copied into release apps.

- A configured release starts Sparkle at app launch and immediately requests a
  background check when automatic checks are enabled (owner request 2026-10-15),
  even if the last check was recent. This call runs in the same runloop turn as
  startup, as required by Sparkle. Sparkle then maintains the four-hour schedule.
  A saved opt-out is respected. No-update and network-error cases stay quiet;
  available, non-skipped versions use the existing native update window.
- Settings → General offers an automatic-check toggle and manual check button.
- Available versions use Sparkle's native update window and a menu item. A check
  or installation is deferred while reading, selecting, recognizing, dictating
  or installing a model. If work starts during an update download, relaunch is
  held; **Install Update and Restart…** continues it once the app is idle.
- Downloads/installations require the user's action. Automatic download and
  silent installation are disabled. Offline failures do not affect local use.
- Optional system profiling is disabled and its key allowlist is empty. External
  release-note fetching is disabled. Public HTTPS addresses contain no tokens.
  The server necessarily sees the IP address and ordinary HTTP metadata, including
  Sparkle's user-agent; no screenshots, OCR text, dictation or audio is attached.
- Update archives are Ed25519-signed, verified before extraction, and the appcast
  itself must also be signed. The app and DMG use Developer ID signatures.
- Builds without a valid HTTPS feed and 32-byte public key never start Sparkle.
  UI/test processes explicitly disable it. Local developer builds have no feed.

The owner's Sparkle public key is `UkAO/uyBRKSNY0+0gLVrnxa6vaXaVE4cJueFv1JVIT0=`
(override in CI: `SAYWING_SPARKLE_PUBLIC_KEY`). The private key lives in the
maintainer's keychain under Sparkle account `saywing` and in the release
environment secret; it is never in the repository. Back it up securely before
relying on public updates. Do not generate a replacement for every release.

## Local preparation

CI pins Xcode **26.6** (`XCODE_VERSION` in `.github/workflows/ci.yml` and
`release.yml`). Locally, select Xcode rather than the standalone command-line
tools:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
swift run OpenScreenReaderCoreBehaviorChecks
python3 -m unittest discover -s Tests/Release -v
python3 scripts/check-localization.py
xcodebuild -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -destination 'platform=macOS' -derivedDataPath /tmp/saywing-release-checks \
  test -only-testing:OpenScreenReaderAppTests
```

Build a signed, notarized candidate against your download location:

```sh
export SAYWING_PUBLIC_DOWNLOAD_PREFIX=https://downloads.example.com/saywing
python3 scripts/release.py \
  --runtime-app /Applications/Saywing.app \
  --output .build/release-0.1.1 \
  --version 0.1.1 --build 2 \
  --feed-url "$SAYWING_PUBLIC_DOWNLOAD_PREFIX/appcast.xml" \
  --download-url-prefix "$SAYWING_PUBLIC_DOWNLOAD_PREFIX" \
  --public-key '<base64 Sparkle public key>' \
  --notarize
```

This always creates a separate directory and refuses to overwrite it. It verifies
both source runtime receipts and the pinned speech model, builds current source,
bundles only Whisper Turbo plus Supertonic, preserves model notices, signs native
code and Sparkle helpers from the inside out, refreshes affected receipt hashes,
then seals the outer app. A source-hash-pinned packaging correction defers
Whisper’s unused word-timestamp JIT import; the MIT notice and patch provenance
are bundled. See [the real signed-runtime failure and fix](research/whisper-hardened-runtime-patch.md). The installed source app is never modified. No model
download occurs in this command. `--derived-data` and `--packages` can reuse
existing build caches.

`--notarize` submits the app archive and final DMG to Apple, requires Accepted,
staples and validates the tickets, and checks Gatekeeper. A timeout preserves the
submission log; query that existing submission rather than immediately uploading
again. Feed generation/signing happens after the final DMG bytes are fixed.

The `publish/` directory contains the versioned DMG, signed `appcast.xml`,
`SHA256SUMS`, and `latest.json` with the download URL, version, size, architecture
and checksum. Private test packages retain the development notice. Only
`--public-release`, requiring the architecture-specific approval record, removes it.
ARM uses `release-approval.json`; Intel uses `release-approval-x86_64.json`.
The documented ARM beta exception covers only its fresh-device testing gap.
That flag also requires notarization. **Preparation never publishes anything.**

## GitHub automation

### CI (`.github/workflows/ci.yml`)

Runs on every pull request to `main` and every push to `main`, without secrets:

- `verify`: Swift package tests, behavior checks, release-script tests,
  localization check, app tests and Release builds for arm64 and x86_64 on the
  pinned Xcode.
- `python-workers`: the speech and dictation worker unit tests
  (`Tests/Dictation`, `Tests/Fixtures/test_supertonic_*.py`) on Python 3.12 with
  hash-locked numpy/scipy from `scripts/ci-test-requirements.txt`. No models and
  no network beyond installing those pinned wheels.

Superseded pull-request runs are cancelled; runs on `main` always finish.

### Release (`.github/workflows/release.yml`)

Releases never start automatically. A maintainer starts **Saywing release** from
the Actions tab (`workflow_dispatch`) on `main` and types `release` into the
confirmation input. The jobs then run in this order:

1. `gate` fails immediately unless the ref is `main`, the repository variable
   `SAYWING_RELEASE_ENABLED` is `true`, and the confirmation matches.
2. `verify` re-runs the complete CI workflow on the dispatched commit.
3. `package` (environment `saywing-release`, waits for reviewer approval) fetches
   the hash-pinned runtime archive, imports the signing credentials into a
   temporary keychain, builds, signs, notarizes and creates the signed appcast,
   then always removes the temporary credentials.
4. `publish` (environment `saywing-release`, a second approval; only when
   `SAYWING_PUBLISH_ENABLED=true`) runs on a separate Linux runner that never
   receives signing secrets — only storage credentials and the read-only job
   token. It uploads immutable files, downloads the whole DMG through the public
   URL and checks size and SHA-256, rechecks that the source commit is still the
   head of `main`, then promotes the release pointer.

Version and build numbers derive from the workflow run number
(`0.1.<run>` / build `<run + 100>`). Keep the workflow file name `release.yml`
so the sequence keeps increasing; when replacing it, choose a build number above
all shipped versions. A rollback is another release with a higher build number.
Only one release runs at a time and none is cancelled automatically. GitHub keeps
at most one pending run per concurrency group, so a third dispatch while one is
running and one is queued replaces the queued one.

**Artifacts.** Artifacts of a public repository can be downloaded by any GitHub
user. When publication is enabled, the DMG is uploaded only as a one-day
(`retention-days: 1`) handoff from `package` to `publish`; it is the same file
that becomes public minutes later. When publication is disabled, only
`appcast.xml`, `latest.json`, `SHA256SUMS` and `release-result.json` are retained
(seven days); the notarized DMG is not uploaded. Build private candidates locally
with `scripts/release.py` instead.

**Supply chain.** All actions are pinned to full commit SHAs. The storage client
(`boto3` and its complete dependency closure) is installed from
`scripts/release-requirements.txt` with `pip install --require-hashes --no-deps`
into an isolated virtual environment. Workflows grant only `contents: read`,
check out without persisted credentials, and never interpolate `${{ }}`
expressions into shell scripts; values reach scripts only through environment
variables.

### Variables and secrets

Repository variables (set the activation flags at repository level: job
conditions are evaluated before environment variables become available):

| Variable | Meaning |
| --- | --- |
| `SAYWING_RELEASE_ENABLED` | `true` allows the release workflow to package |
| `SAYWING_PUBLISH_ENABLED` | `true` enables the publish job; only after the download routes and bucket passed a live smoke test |
| `SAYWING_INTEL_RELEASE_ENABLED` | Opt-in for the Intel matrix leg; leave unset/false until separately approved |
| `SAYWING_RUNTIME_SHA256` | Exact SHA-256 of the approved ARM runtime archive in the private bucket |
| `SAYWING_RUNTIME_FORMAT` | ARM archive format, `dmg` or `zip` (default `zip`) |
| `SAYWING_INTEL_RUNTIME_SHA256` | Independent Intel DMG pin; no fallback to the ARM pin |
| `SAYWING_S3_ENDPOINT` | HTTPS endpoint of the S3-compatible bucket |
| `SAYWING_S3_BUCKET` | Bucket name |
| `SAYWING_S3_REGION` | Bucket region; defaults to `auto` |
| `SAYWING_PUBLIC_DOWNLOAD_PREFIX` | Public HTTPS download base (owner default in `scripts/release.py`) |
| `SAYWING_SPARKLE_PUBLIC_KEY` | Sparkle Ed25519 public key (owner default above) |
| `SAYWING_SIGNING_IDENTITY` | Developer ID Application identity (owner default above) |
| `SAYWING_TEAM_ID` | Apple team ID for Apple-ID notarization (owner default above) |
| `SAYWING_RELEASE_REPOSITORY` | `owner/repo` allowed to publish (default `ChrBoebel/OpenScreenReader`) |

Secrets in the `saywing-release` environment:

| Secret | Meaning |
| --- | --- |
| `SAYWING_CERTIFICATE_P12` | Base64-encoded Developer ID certificate **and private key** |
| `SAYWING_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `SAYWING_SPARKLE_PRIVATE_KEY` | Sparkle key exported securely from account `saywing` |
| `SAYWING_NOTARY_API_KEY` | Preferred: App Store Connect API key (`.p8` file contents) |
| `SAYWING_NOTARY_API_KEY_ID` | Its key ID |
| `SAYWING_NOTARY_API_ISSUER` | Its issuer ID (team keys only; omit for individual keys) |
| `SAYWING_APPLE_ID` | Fallback when no API key is set: Apple account for notarization |
| `SAYWING_APPLE_APP_PASSWORD` | Fallback: its app-specific password |
| `SAYWING_S3_ACCESS_KEY_ID` | Storage access key |
| `SAYWING_S3_SECRET_ACCESS_KEY` | Storage secret key |

Never commit P12 files, private keys or passwords.

**Secrets on command lines (residual risk).** On the disposable runner, the
temporary keychain password (random, masked) and the P12 password are passed to
`security` with `-p`/`-P`; `security import` offers no stdin or environment
alternative. The App Store Connect API key path writes the `.p8` key to a
mode-0600 file that is deleted right after `notarytool store-credentials`, so no
notarization secret appears on a command line. The Apple-ID fallback passes the
app-specific password with `--password` because notarytool's alternative is an
interactive prompt. These arguments are visible only to processes in the same
ephemeral job; prefer the API key.

### GitHub settings the owner must configure

These settings cannot be expressed in the repository and must be set manually:

- **Environment `saywing-release`** (Settings → Environments): deployment
  branches limited to `main` (no tags); required reviewer = the owner; enable
  "Prevent self-review" only if a second maintainer exists; disable "Allow
  administrators to bypass configured protection rules". Store the secrets above
  only in this environment, not as repository secrets.
- **Branch protection / ruleset for `main`**: require a pull request before
  merging, require review from Code Owners (`.github/CODEOWNERS`), require the
  status checks `verify` and `python-workers` to pass, require branches to be up
  to date, block force pushes and deletions, and include administrators.
- **Actions** (Settings → Actions → General): require approval for workflows from
  fork pull requests (at least for first-time contributors; "all outside
  collaborators" is safer); keep the default `GITHUB_TOKEN` permission read-only;
  do not allow Actions to create or approve pull requests; optionally restrict
  allowed actions to GitHub-authored actions pinned by SHA.

## Download hosting

Public files are served from an S3-compatible bucket configured through the
repository variables and secrets above. The bucket itself stays private; a small
website route serves the release metadata exactly as stored with
`Cache-Control: no-store` and redirects large downloads to short-lived read-only
signed URLs. The permanent appcast URL contains no expiring token. Only the
explicitly named release files are routable; no bucket listing or write endpoint
is exposed.

`scripts/publish-release.py` stores each release under a build-numbered, immutable
prefix using conditional writes. It refuses replacements and downgrades, downloads
the whole DMG through the unauthenticated public URL and checks size/SHA-256,
rechecks that the source commit is still `main`, then conditionally replaces a
single current-release pointer through which the feed and latest metadata resolve.
Upload failures leave the previous pointer intact; old files remain for clients
with cached feeds. Archives up to 5 GiB are supported; larger packages fail
explicitly instead of silently losing the conditional-write guard. Intel releases
use their own `/x86_64` URL and storage namespace and never touch the ARM pointer.

The CI runtime archive (interpreter, native libraries and pinned models) is kept
under a separate private prefix that the public route never exposes; CI fetches
it with storage credentials and verifies its pinned SHA-256 before unpacking. The
archive must have independent interpreter/build provenance, all transitive license
notices, and the exact pinned models recorded in the repository. A checksum
verifies the chosen archive, not legal permission or reproducibility. No runtime
or model binaries belong in Git. Replacing this private archive with a
reproducible, public runtime build is tracked separately.

## Remaining public-release gates

`release-approval.json` records the ARM beta license, privacy and production HTTPS
update evidence, plus the owner-approved exception for incomplete fresh-device
testing. Intel has its own closed record, `release-approval-x86_64.json`; neither
the ARM evidence nor its exception opens the Intel gate. Apple notarization alone
does not satisfy these gates.

Primary references: [Apple Developer ID](https://developer.apple.com/developer-id/),
[notarytool](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[Sparkle setup](https://sparkle-project.org/documentation/),
[publishing updates](https://sparkle-project.org/documentation/publishing/),
[GitHub deployment environments](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment).
