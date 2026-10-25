# Saywing distribution and updates

This document describes how Saywing is signed, notarized, packaged, published and
updated. Maintainer-specific values (signing identity, team ID, download URL, release
repository) are defaults in the scripts and can be overridden through environment
variables or GitHub repository variables; nothing private is required to read,
build or test the source.

## Signing identity

Every distributable is signed with a Developer ID Application certificate and
notarized by Apple. The project defaults are:

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
  background check when automatic checks are enabled (project decision 2026-10-15),
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

The project's Sparkle public key is `UkAO/uyBRKSNY0+0gLVrnxa6vaXaVE4cJueFv1JVIT0=`
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

Build a signed, notarized candidate against your download location. The runtime
input is assembled from pinned public sources first
([docs/runtime-build.md](runtime-build.md#release-input-and-ci)):

```sh
export SAYWING_PUBLIC_DOWNLOAD_PREFIX=https://downloads.example.com/saywing
python3 scripts/assemble-release-runtime.py --architecture arm64 --development-only \
  --cache .build/runtime-cache --output .build/runtime-arm64/Saywing.app
python3 scripts/release.py \
  --runtime-app .build/runtime-arm64/Saywing.app \
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
are bundled. See [the real signed-runtime failure and fix](research/whisper-hardened-runtime-patch.md). The runtime input is never modified. No model
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
ARM uses [`release/release-approval.json`](../release/release-approval.json); Intel uses [`release/release-approval-x86_64.json`](../release/release-approval-x86_64.json).
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
3. `package` (environment `saywing-release`, waits for reviewer approval) checks
   the release-approval record, builds the speech and dictation runtimes and
   downloads the pinned models from public sources with
   `scripts/assemble-release-runtime.py` (every input size- and SHA-256-verified;
   [details](runtime-build.md#release-input-and-ci)), imports the signing
   credentials into a temporary keychain, builds, signs, notarizes and creates the
   signed appcast, then always removes the temporary credentials. It holds no
   storage credentials.
4. `publish` (environment `saywing-release`, a second approval; only when
   `SAYWING_PUBLISH_ENABLED=true`) runs on a separate Linux runner that never
   receives signing secrets — only storage credentials and the read-only job
   token. It archives the corresponding sources and downloads each of them through
   its public URL (size and SHA-256), uploads immutable files, downloads the whole
   DMG through the public URL and checks size and SHA-256, rechecks that the source
   commit is still the head of `main`, then promotes the release pointer.

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
(`boto3` and its complete dependency closure) is installed only in the `publish`
job, from `scripts/release-requirements.txt` with
`pip install --require-hashes --no-deps` into an isolated virtual environment.
Runtime wheels are installed with `--require-hashes` from the committed locks; the
`package` job's download cache is re-verified on every use. Workflows grant only `contents: read`,
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
| `SAYWING_S3_ENDPOINT` | HTTPS endpoint of the S3-compatible bucket (publish job only) |
| `SAYWING_S3_BUCKET` | Bucket name (publish job only) |
| `SAYWING_S3_REGION` | Bucket region; defaults to `auto` (publish job only) |
| `SAYWING_PUBLIC_DOWNLOAD_PREFIX` | Public HTTPS download base (project default in `scripts/release.py`) |
| `SAYWING_PUBLIC_SOURCE_PREFIX` | Public HTTPS base of the corresponding-source route; empty means `SAYWING_PUBLIC_DOWNLOAD_PREFIX`. Package and publish jobs must use the same value |
| `SAYWING_SPARKLE_PUBLIC_KEY` | Sparkle Ed25519 public key (project default above) |
| `SAYWING_SIGNING_IDENTITY` | Developer ID Application identity (project default above) |
| `SAYWING_TEAM_ID` | Apple team ID for Apple-ID notarization (project default above) |
| `SAYWING_RELEASE_REPOSITORY` | `owner/repo` allowed to publish (default `ChrBoebel/saywing`) |

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
| `SAYWING_S3_ACCESS_KEY_ID` | Storage access key (publish job only) |
| `SAYWING_S3_SECRET_ACCESS_KEY` | Storage secret key (publish job only) |

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

### GitHub settings the maintainer must configure

These settings cannot be expressed in the repository and must be set manually:

- **Environment `saywing-release`** (Settings → Environments): deployment
  branches limited to `main` (no tags); required reviewer = the maintainer; enable
  "Prevent self-review" only if a second maintainer exists; disable "Allow
  administrators to bypass configured protection rules". Store the secrets above
  only in this environment, not as repository secrets.
- **Branch protection / ruleset for `main`**: require a pull request before
  merging, require the status checks `verify` and `python-workers` to pass, and
  block force pushes and deletions. This is the current single-maintainer
  configuration. Once a second maintainer exists, also require review from Code
  Owners (`.github/CODEOWNERS`), require branches to be up to date and include
  administrators; with one maintainer these settings would block every merge.
- **Actions** (Settings → Actions → General): require approval for workflows from
  fork pull requests (at least for first-time contributors; "all outside
  collaborators" is safer); keep the default `GITHUB_TOKEN` permission read-only;
  do not allow Actions to create or approve pull requests; allow only
  GitHub-owned actions and require them to be pinned by full commit SHA.

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

Before any release file is uploaded, the same script archives the corresponding
sources the signed app points to (see below) under `corresponding-source/` in the
release's storage namespace, then downloads each of them through its public URL. The
website route serves the content-addressed objects
`corresponding-source/sha256/<sha256>/<file>` publicly, like the DMG; it does not serve
the per-build manifests or a listing. Keep the prefix out of any lifecycle or expiry
rule.

Release runtimes are not stored anywhere: every release builds them from the
pinned public inputs described in [docs/runtime-build.md](runtime-build.md). No
runtime or model binaries belong in Git. Pins prove which bytes were used, not
legal permission; the license review stays a release gate.

## Licenses in the app and the DMG

`scripts/bundle_notices.py` runs inside `scripts/release.py` before signing:

- It copies the reviewed notices into `Contents/Resources/Licenses`.
- It writes the offline index `THIRD-PARTY-NOTICES.html`.
- It writes exact source pointers, the directions to the public copies and a written
  source offer into `Contents/Resources/CorrespondingSource`:
  - `sources.json` holds the records of `docs/licenses/native-corresponding-sources.json` for
    the architecture. Each record also has `mirror_url`, its public copy on the download
    host, next to the upstream `url`;
  - `README.md` is `docs/licenses/CorrespondingSource-README.md`.

The source archives themselves are not shipped in the app. This was decided on 2026-10-24;
since 2026-10-25 they are served publicly from the download host instead of only being
offered ([ADR 0007](decisions/0007-gcc-runtime-libraries.md) and its amendment).

**Public source URL.** For every record:

```text
<public source prefix>[/x86_64]/corresponding-source/sha256/<sha256>/<file>
```

The public source prefix is `SAYWING_PUBLIC_SOURCE_PREFIX`, by default the public download
prefix (`https://www.christopherboebel.com/downloads/saywing`). Intel builds add `/x86_64`,
like their DMG URL. The address maps one to one to the archived object
`<storage prefix>/corresponding-source/sha256/<sha256>/<file>` (storage prefix `saywing` or
`saywing/x86_64`).

The step fails in these cases:

- one of SciPy's GNU runtime libraries is not declared, is missing, is a static archive or is
  not a separate dylib. These are `libquadmath` (LGPL-2.1), and `libgfortran` and `libgcc_s`
  (GPL-3.0 with the GCC Runtime Library Exception). The LGPL requires that users can replace
  them.
- a source record lacks an HTTPS URL, size, SHA-256 or license;
- a copyleft record has no public URL (`mirror_url`) for its archived object;
- a copyleft record's license text is not shipped as a notice;
- any listed source archive, or any other file besides `README.md` and `sources.json`, is in
  `CorrespondingSource/`.

The tested replacement procedure is in `docs/licenses/CorrespondingSource-README.md`.

**libquadmath under LGPL-3.0.** libquadmath is licensed under the GNU LGPL version 2.1 or
(at your option) any later version; the Saywing maintainers distribute it under the GNU LGPL
version 3 (which incorporates the GNU GPL version 3), effective for all Saywing builds
including 0.1.17. `Licenses/GCC-13.4.0/COPYING3.LIB` ships next to the LGPL-2.1 text.

**Written offer.** In addition to the public copies, the offer is in
`CorrespondingSource/README.md` and in the notice index:

- It is valid for at least three years from the date the maintainers distributed the
  respective build, or longer while they support that build.
- It is made to any third party.
- It is free as a download, or on a physical medium for no more than the cost of distribution.
- Requests go through the repository issue tracker or the contact on the maintainer's GitHub
  profile.

Forks that distribute their own builds must replace this offer and its contact with their
own.

**Archiving and serving the sources.** `scripts/release.py` copies the app's `sources.json`
into `release-result.json`. The `publish` job then archives the sources before it uploads the
DMG, appcast or metadata:

1. It checks that list against the repository.
2. For each file, it either reuses an archived copy or downloads the file over HTTPS only and
   verifies its size and SHA-256.
3. It stores the files with conditional, immutable writes:
   - files: `<storage prefix>/corresponding-source/sha256/<sha256>/<file>`;
   - per-build manifest: `<storage prefix>/corresponding-source/builds/<build>.json`.

4. It downloads every source through its `mirror_url` without credentials, HTTPS only, and
   checks status 200, size and SHA-256 (streamed).

The storage prefix is `saywing` or `saywing/x86_64`. If a source cannot be archived or is not
publicly downloadable with the expected bytes, nothing of the release is uploaded and
`current.json` stays unchanged. Only the release scripts use the network for this; the app
never does.

To answer a request under the written offer:

1. Read the build's manifest.
2. Download the listed objects with the storage credentials.
3. Check each SHA-256.
4. Send the files, or a time-limited link to them.

The exact files can also be fetched and verified locally (build-time network only) with:

```sh
python3 scripts/bundle_notices.py --fetch-sources
```

Every DMG has a `Licenses` folder beside `Saywing.app` with `LICENSE`, `NOTICE`, a
`README.txt` (`docs/licenses/DMG-README.txt`) that limits Apache-2.0 to the source code,
`SUPERTONIC-MODEL-TERMS.md`, the complete `Supertonic-3-Open-RAIL-M.txt` and the app's
`THIRD-PARTY-NOTICES.html`. `release.py` stops before building if one of these documents is
missing.

The app asks for explicit acceptance of the Supertonic 3 model terms before the read-aloud
voice is used (setup, and Settings › Read Aloud › Voice). The acceptance is stored locally
with the SHA-256 of the bundled terms, so a changed terms text is asked again.

Before every public release, check that the pinned Supertonic 3 revision is still the latest
upstream revision (Open RAIL-M paragraph 7: reasonable efforts to use the latest version), or
record why not:

```sh
curl -s https://huggingface.co/api/models/Supertone/supertonic-3 | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["sha"])'
```

The result must equal the pinned revision in `docs/licenses/SUPERTONIC-MODEL-TERMS.md`.

## Remaining public-release gates

`license_review` is `false` in both approval records (project decisions 2026-10-24; see
`license_review_note` and the 2026-10-24 status in
[ADR 0003](decisions/0003-bundled-default-model.md)).

Done:

- the Supertonic model terms in the DMG;
- notices for the rebuilt minimal runtimes;
- the GCC runtime library decision with the per-build source archive, public source copies
  verified by the publish job, the written offer and the LGPL-3.0 election for libquadmath
  ([ADR 0007](decisions/0007-gcc-runtime-libraries.md) and its 2026-10-25 amendment);
- the interpreter provenance record (`Runtime/Portable/python-provenance.json`,
  [Interpreter provenance](research/interpreter-provenance.md)). It covers the
  python-build-standalone commit, the build recipe, the CPython patch set and the
  dependency sources. It also records the check that each pinned stripped archive and the
  full archive whose licenses are shipped come from the same build.

Still open:

- the maintainer's legal review of the model terms. They now name the distributor, require
  explicit in-app acceptance, end on breach of Attachment A, cover shared audio and
  redistribution channels, have an equally binding German version with a translated
  Attachment A, choose German law with the consumer proviso and limit the distributor's
  liability as German law allows. Open: whether Supertone can enforce against end users,
  whether model weights are protected by copyright, whether the maintainer acts as a
  business ("Unternehmer"), and the quality of the Attachment A translation;
- the website route that serves `corresponding-source/sha256/...` from the download host.
  It lives outside this repository. Until it is live, the four source files of the
  2026-10-15 betas (0.1.17, build 117, arm64 and x86_64) are not public there, and the
  publish job stops by design. The betas stay online by maintainer decision; record when
  the route went live ([ADR 0007](decisions/0007-gcc-runtime-libraries.md), amendment);
- the legal review of the remaining copyleft questions in the ADR 0007 amendment: the
  retroactive LGPL-3.0 election for the betas under German law, the unrecorded Homebrew
  bottle revision, and Stephen L. Moshier's copyright in some libquadmath files.

The 2026-10-15 review covered the earlier runtime. No public release can be built until the
maintainer closes this gate; the beta exception covers only `clean_mac`.

`release-approval.json` also records the ARM beta privacy and production HTTPS update
evidence, plus the approved exception for incomplete fresh-device testing. Intel has
its own record, `release-approval-x86_64.json`; neither the ARM evidence nor its exception
opens the Intel gate. Apple notarization alone does not satisfy these gates.

Primary references: [Apple Developer ID](https://developer.apple.com/developer-id/),
[notarytool](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[Sparkle setup](https://sparkle-project.org/documentation/),
[publishing updates](https://sparkle-project.org/documentation/publishing/),
[GitHub deployment environments](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment).
