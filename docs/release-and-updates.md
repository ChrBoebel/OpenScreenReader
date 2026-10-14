# Saywing distribution and updates

Prepared 2026-10-14 on `codex/release-updates`; the focused PR branch is
`codex/saywing-release-pipeline`, based on current main. The owner subsequently authorized
Railway/GitHub setup and transfer of the existing Saywing signing credentials
to the main-only `saywing-release` environment. No public release, repository
visibility change, release activation or website deployment has been performed. The owner selected existing website hosting: Railway project
`Chr Webseite`, service `Webeseite_Chrisboebel`, domain `www.christopherboebel.com`.

## Existing Apple setup

The project chat **Veröffentlichung vorbereiten** already completed a private
Developer ID test: Apple's submission `79cc4b87-30c7-4c1e-a04f-6d5f95f14a43` was
Accepted, the ticket was stapled, and Gatekeeper accepted the app. That test
predates integrated dictation and does not cover this release candidate.

- Team: `S28WSHSSJD`.
- Identity: `Developer ID Application: Christopher Böbel (S28WSHSSJD)`.
- Local keychain profile: `Saywing-Notary-S28WSHSSJD`.
- Existing evidence: the `saywing-notarization-test` artifact attached to that chat.

No new Apple membership or certificate is necessary while this identity remains
valid. Every changed distributable still needs signing and notarization.

The corrected dictation/update candidate was also accepted by Apple: submission
`8e9a1173-4654-4002-9cd5-04ce2baa719f`. Both its app and DMG are stapled and pass
Gatekeeper as `Notarized Developer ID`; see the dated verification log. Its feed
still deliberately uses an invalid test host, so this candidate is not the
public release.

## Update behavior

Sparkle **2.10.0**, exact revision
`eef1a539a373c1f1a320624b1130fc5de7b2e100`, is resolved through the committed
Xcode `Package.resolved`. Its MIT and bundled dependency notices are preserved in
`docs/licenses/Sparkle-2.10.0.txt` and copied into release apps.

- A configured release starts Sparkle at app launch and schedules checks every
  four hours while the app remains running. Sparkle respects the last check time;
  restarting repeatedly does not force a request every time.
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

The public key is `UkAO/uyBRKSNY0+0gLVrnxa6vaXaVE4cJueFv1JVIT0=`. The private key
was generated in the local login keychain under Sparkle account `saywing`; it is
not in the repository. Back it up securely before relying on public updates.
Do not generate a replacement for every release.

## Local preparation

Select Xcode, not the standalone command-line tools:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
swift run OpenScreenReaderCoreBehaviorChecks
python3 -m unittest discover -s Tests/Release -v
python3 scripts/check-localization.py
xcodebuild -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -destination 'platform=macOS' -derivedDataPath .build/release-checks \
  test -only-testing:OpenScreenReaderAppTests
```

Use the prepared website endpoints (the local private test deliberately used an invalid example host):

```sh
python3 scripts/release.py \
  --runtime-app /Applications/Saywing.app \
  --output .build/release-0.1.1 \
  --version 0.1.1 --build 2 \
  --feed-url https://www.christopherboebel.com/downloads/saywing/appcast.xml \
  --download-url-prefix https://www.christopherboebel.com/downloads/saywing \
  --public-key 'UkAO/uyBRKSNY0+0gLVrnxa6vaXaVE4cJueFv1JVIT0=' \
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
`--public-release`, requiring every gate in `release-approval.json`, removes it.
That flag also requires notarization. **Preparation never publishes anything.**

## Main-branch automation

`.github/workflows/release.yml` runs core tests, release tests, localization,
app tests and a Release build for PRs and changes to `main`. Packaging only runs
on `main`, after those checks, when `SAYWING_RELEASE_ENABLED=true` and all recorded
release gates pass. Signing secrets are never available to the PR job.

The disposable Apple Silicon runner uses a temporary keychain, restores its
previous keychain settings and removes credentials on completion/failure.
No self-hosted runner with a personal login keychain is required. The workflow
uses increasing run numbers for the display/build versions. Keep this workflow
identity stable; when replacing it, choose a build number above all shipped
versions. A rollback is another release with a higher build number.

Repository/environment variables:

| Variable | Meaning |
| --- | --- |
| `SAYWING_RELEASE_ENABLED` | Repository variable, currently `false`; enable after gates, credentials and hosting are ready |
| `SAYWING_RUNTIME_SHA256` | Exact SHA-256 of the approved ZIP containing `Saywing.app`, stored privately at `saywing/runtime/<sha256>.zip` |
| `SAYWING_PUBLISH_ENABLED` | Enable upload only after the website routes and bucket have passed a live smoke test |
| `SAYWING_S3_ENDPOINT` | HTTPS endpoint shown by the Railway bucket |
| `SAYWING_S3_BUCKET` | Bucket name from Railway |
| `SAYWING_S3_REGION` | Bucket region; defaults to `auto` |

Secrets in the `saywing-release` environment:

| Secret | Meaning |
| --- | --- |
| `SAYWING_CERTIFICATE_P12` | Base64-encoded Developer ID certificate **and private key** |
| `SAYWING_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `SAYWING_SPARKLE_PRIVATE_KEY` | Sparkle key exported securely from account `saywing` |
| `SAYWING_APPLE_ID` | Apple account for notarization |
| `SAYWING_APPLE_APP_PASSWORD` | Its app-specific password |
| `SAYWING_S3_ACCESS_KEY_ID` | Railway bucket access key |
| `SAYWING_S3_SECRET_ACCESS_KEY` | Railway bucket secret key |

All seven credentials, including storage, Sparkle, Developer ID and validated
Apple notarization credentials, are installed in the main-only GitHub environment
with explicit owner approval.
The local originals remain intact. Never commit P12 files, private keys or
passwords. See the dated verification log for the remaining configuration.

The runtime archive must have independent interpreter/build provenance, all
transitive license notices, and the exact pinned models recorded in the repo.
A checksum verifies the chosen archive, not legal permission or reproducibility.
CI fetches that archive explicitly and checks its hash before unpacking. No
runtime or model binaries belong in Git.

## Existing website hosting: Railway

The source repository is private. Downloads are prepared in the existing website
repository `/Users/christopherbobel/Documents/Coding/Webseite`, branch
`codex/saywing-downloads`. Nothing has been deployed or merged.

Prepared public addresses:

- German download page: `https://www.christopherboebel.com/de/saywing`
- English download page: `https://www.christopherboebel.com/en/saywing`
- Stable download button: `https://www.christopherboebel.com/downloads/saywing/latest.dmg`
- Signed update feed: `https://www.christopherboebel.com/downloads/saywing/appcast.xml`
- Version metadata: `https://www.christopherboebel.com/downloads/saywing/latest.json`
- Immutable archives: `/downloads/saywing/Saywing-<version>-<build>.dmg`

Railway buckets are private and S3-compatible. The website route reads small
metadata files and returns their exact bytes with `Cache-Control: no-store`.
Large downloads redirect to a fresh, one-hour, read-only presigned GET URL. The
permanent appcast URL contains no expiring token. HEAD requests return object
metadata directly, because a GET signature cannot authenticate a HEAD request.
Only the explicitly named release files are routable; no bucket listing or write
endpoint is exposed. The pages show an unavailable state until a valid release
exists and remain excluded from indexing until launch.

`scripts/publish-release.py` stores files under `saywing/releases/<build>/` using
conditional writes. It refuses replacements and downgrades, downloads the whole
DMG through the unauthenticated website URL and checks size/SHA-256, rechecks that
the source commit is still main, then conditionally replaces a single
`saywing/current.json` pointer. Feed and latest metadata resolve through that
pointer. Upload failures leave the previous pointer intact; old files remain for
clients with cached feeds. The publisher supports archives up to 5 GiB; larger
packages fail explicitly instead of silently losing the conditional-write guard.
A separate upload flag allows CI to produce a private artifact before going live.

Configured infrastructure:

- Private bucket `saywing-downloads` in Amsterdam, ID
  `a517a442-11e6-44bd-b591-de5e971ac00a`, S3 name
  `saywing-downloads-g6qfesx`, endpoint `https://t3.storageapi.dev`.
- Website server variables reference the bucket's ENDPOINT, BUCKET,
  ACCESS_KEY_ID and SECRET_ACCESS_KEY. Set `SAYWING_S3_REGION=auto` explicitly:
  Railway's REGION reference currently returns `ams`, whereas its S3 credential
  API specifies `auto`. Do not use a NEXT_PUBLIC prefix. Changes were saved with
  `--skip-deploys`; no website deployment was triggered.
- Both Python CI clients explicitly use virtual-host S3 addressing.
- The private CI runtime archive (1,268,196,231 bytes) was uploaded and fully
  read back to verify SHA-256. GitHub pins
  `9ed1188992172b114c032ce30f8e00626599c2d53c4df922e390bf8a65a7ca6b`.
- GitHub environment `saywing-release` permits only the `main` branch (no tags).
  The two repository activation flags are `false`.
- Live conditional PUT/ETag, anonymous access denial and presigned HTTPS download
  checks passed. The temporary test object was removed.

Remaining activation steps:

1. Review/commit/push the app and website branches and merge their PRs only when
   authorized. Website main is connected to Railway's automatic deployment. Deploy the routes before
   the first app upload. Confirm missing downloads return 404/503, not a login.
2. Validate a real hosted package job after the app workflow is merged. Keep
   the workflow's repository-level release flag separate from environment variables
   because the job condition is evaluated
   before environment variables become available.
3. Verify the complete live website download/redirect path. Existing storage
   smoke tests do not establish that the new website routes are deployed.
4. Complete the release gates below, then enable release and publication flags.
   Main updates will run verification → signing → Apple notarization → upload →
   full public download verification → feed promotion. On failure the job reports
   an error and the previous download remains current.
5. After the first public release, enable indexing and link the Saywing download
   page from the appropriate website navigation/project listing.

The website stores no model weights in Git and no app archives in its deploy
filesystem. Storage/egress billing follows the user's Railway account. Signed
bucket download URLs are bearer URLs for public app files only, not private
runtime archives or credentials. CI runtime-source archives stay under the private
`saywing/runtime/` prefix, which the public route never exposes. CI uses S3
credentials and verifies the pinned SHA-256 before unpacking the archive.

## Remaining public-release gates

`release-approval.json` deliberately records all gates as incomplete until there
is evidence: complete license chain, fresh-Mac install/permissions, packaged
offline/data-flow verification, and a real signed two-version update roundtrip.
The earlier Apple acceptance establishes signing feasibility, not these gates.

Primary references: [Apple Developer ID](https://developer.apple.com/developer-id/),
[Sparkle setup](https://sparkle-project.org/documentation/),
[publishing updates](https://sparkle-project.org/documentation/publishing/),
[Railway storage buckets](https://docs.railway.com/guides/storage-buckets).
