# Release preparation verification — 2026-10-14

Scope: current uncommitted `codex/release-updates` working tree, including pre-existing
owner work. Website changes are separate in `Webseite`, branch `codex/saywing-downloads`.
No commits, pushes, merges, public release, bucket creation or production deployment.

## Executed checks

- `swift test`: 4 tests in 2 suites passed, including three update-policy tests.
- `swift run OpenScreenReaderCoreBehaviorChecks`: 11 checks passed.
- App target: 175 tests in 13 suites passed (`app-tests-retry.log`).
- Debug and Release app builds: succeeded.
- Python release/publisher/packaging tests: 10 passed. Publisher tests use an in-memory S3
  double to check ordering, idempotence, stale main, failed verification,
  downgrade prevention and immutable-object conflicts; they do not prove Railway
  compatibility or a successful upload.
- Localization validation and Git whitespace checks passed.
- Workflow YAML parsed successfully. No GitHub Actions run has been triggered.
- Pinned publisher boto3 installed in an isolated environment; SDK model accepts
  `IfMatch`, `IfNoneMatch`, content length and metadata. No live S3 call made.
- Website: five download-route tests passed with Node 22; lint, TypeScript and
  production build passed. Actual local HTTP checks returned 503/no-store for an
  unconfigured feed and 404 for a file outside the allowlist.
- Website dependencies: locked Next.js/eslint-config-next 16.4.1 and Sharp
  0.35.5; updated affected transitive production packages within existing ranges.
  Final `npm audit --omit=dev`: zero reported vulnerabilities. The full install
  still reports 11 development-tool findings (10 high, 1 moderate); no forced
  major upgrades were applied as part of the download integration.
- Website pages were opened in the browser: German unavailable state, real
  language-switch interaction and English unavailable state all rendered.
- Update settings were opened in the real running Debug app: German labels,
  disabled check button/toggle, no-server explanation and privacy text displayed.
  The dedicated XCTest UI test could not initialize macOS automation mode and
  timed out. It is **not recorded as passing**; manual UI inspection is separate.

## Real signed private package

Artifact directory: `.build/release-preparation/private-package-2/`.
The package contains Supertonic and Whisper Turbo (no optional ASR weights).
The existing installed app served only as the verified runtime source.

- Source receipt verification: Speech 3,976 entries; Dictation 32,423 entries.
- Pinned Supertonic manifest/file verification passed.
- Developer ID signing completed for native libraries, executables, frameworks,
  Sparkle XPC helpers and the enclosing app.
- Strict/deep code signature verification, post-signing runtime receipts, model
  verification and app permission checks passed.
- DMG was created and signed; approximately 1.4 GiB.
- Sparkle appcast signature verification passed during package generation.
- Independent Ed25519 verification using only the public key and OpenSSL 3.6.4
  accepted the exact signed feed bytes and rejected a modified version title.
  The additional Sparkle CLI tamper check waited for keychain access and was
  cancelled; no keychain permission was changed and no private key exported.
  This cryptographic check does not replace the pending native updater roundtrip.
- The private test feed deliberately points at `updates.example.invalid`; it is
  not a distributable public release and retains its development notice.
- Actual speech playback against the signed bundled runtime completed with zero
  underruns. Playback cancellation had zero late chunks and stopped synchronously
  in 11.43 ms; model-load cancellation stopped in 0.065 ms. Clipboard unchanged.

Local logs live under `.build/release-preparation/` (ignored, never commit models,
app bundles, private keys or large build output). The earlier Apple Accepted
submission from another chat predates this package; it must not be presented as
validation of the current dictation/update build.

## Hardened dictation correction

The additional real worker test exposed an eager Numba/LLVM JIT import that macOS
killed under Hardened Runtime. This was not detected by the earlier signature
verification. The packaging correction defers the unused word-timing import and
is pinned to the exact MIT-licensed mlx-whisper 0.4.3 source hash; see
[patch analysis](research/whisper-hardened-runtime-patch.md).

Corrected and re-signed app: `.build/release-preparation/private-package-3/Saywing.app`.
Strict/deep verification passed, including a final repeat after all runtime
tests; both receipt inventories remained unchanged and valid. Signature checks
required access to the macOS trust store outside the tool filesystem sandbox.
Real sandboxed inference passed **10 checks per
model for all three models**: Whisper Turbo, Qwen3-ASR and Whisper Large v3. Only
Whisper Turbo is bundled in the corrected app; the optional-model tests use the
already installed, manifest-verified weights from the owner's source app. No
weights were downloaded or added to Git. Network and write denial remained active.
Logs: `signed-dictation-tests-fixed.log`, `signed-qwen-tests-fixed.log`, and
`signed-whisper-large-tests-fixed.log` in `.build/release-preparation/`.

The first DMG submission predates this fix and is superseded. Its appcast is a
private proof of signing only. The corrected private DMG is `.build/release-preparation/private-package-3/Saywing-fixed-test.dmg`.
Apple submission `8e9a1173-4654-4002-9cd5-04ce2baa719f` was received at
2026-10-14 19:42:00 UTC and is now **Accepted**, confirmed with a fresh
`notarytool info` query. The corrected DMG and app were both stapled successfully;
DMG ticket validation passed, and Gatekeeper accepted both as
`source=Notarized Developer ID`. Final public packaging will generate a fresh
appcast after stapling. This private candidate still uses the invalid example
feed, so it must not become the public download.

## Remaining live checks

- Public website deployment and complete public-route/redirect behavior.
  Bucket access and conditional writes have now passed live checks below.
- CI credential setup and an actual GitHub-hosted package/publish run.
- Real two-version signed/notarized Sparkle installation and restart, including
  busy reading/dictation, opt-out, offline behavior and tamper rejection.
- Fresh-Mac installation/permissions, complete license chain, and packaged
  offline/privacy verification. `release-approval.json` remains false until each
  has evidence. Passing unit tests or Apple signing does not clear these gates.

## Railway and GitHub setup

On the owner's explicit request, created private Railway bucket
`saywing-downloads` (`a517a442-11e6-44bd-b591-de5e971ac00a`) in Amsterdam in the
existing `Chr Webseite` production environment. Its S3 name is
`saywing-downloads-g6qfesx`, endpoint `https://t3.storageapi.dev`.

The website service has four bucket variable references plus explicit
`SAYWING_S3_REGION=auto`. Railway's REGION reference resolves to the geographical
code `ams`, whereas its credentials API specifies the S3 signing region `auto`.
All credential values were compared in memory, never printed. Variable changes
used `--skip-deploys`; the existing website deployment was not replaced.

Live storage checks used a small uniquely named temporary object, then deleted it:

- Initial `If-None-Match: *` upload succeeded.
- Repeating that condition and supplying a wrong `If-Match` both returned 412.
- Updating with the actual ETag succeeded.
- Presigned HTTPS GET returned the exact bytes.
- The unsigned object URL returned 403 (private access enforced).

The real endpoint also exposed an SDK configuration mismatch: boto3's default
custom-endpoint URLs used path addressing. Both CI clients now explicitly select
virtual-host addressing, matching Railway's current bucket credentials and the
live smoke test. All 10 Python release tests pass after that change.

GitHub Actions is enabled. Environment `saywing-release` permits exactly the
branch `main`, with no wildcard or tag policy. Its storage variables and encrypted
access-key secrets are installed; repository release/publication flags remain
`false`. The existing Sparkle private key was transferred into the encrypted
environment secret after explicit owner approval, with a protected temporary
export removed immediately. No secret values were printed or committed.

The existing Developer ID identity was selected by its exact certificate SHA-1
`AC3EF3F26CF5A1D7AC97F78358E3AEC2519C6132`, exported to a password-protected P12
in memory, and stored as two encrypted GitHub secrets. No other identities were
exported. The owner confirmed macOS Keychain access. The exact Saywing notary
profile was read, its team checked, and its Apple ID/app-specific password were
validated by querying the accepted submission before being transferred to
GitHub. All seven required secret names are now configured; no plaintext
credential files remain.

The actual website download handler was also exercised locally against the real
Railway bucket using Node 22 and its production AWS SDK configuration: absent
appcast GET and HEAD both returned 404 with `Cache-Control: no-store`, and a
private runtime ZIP name was rejected by the public allowlist. This is a real
storage-backed handler test, not evidence of a public website deployment.
Both Python scripts' actual SDK configurations were checked to generate the
required virtual-host URL shape, following the earlier failing check.

## Pinned private CI runtime

The stapled corrected private app was archived without downloading new weights.
The ZIP is stored only at `saywing/runtime/9ed1188992172b114c032ce30f8e00626599c2d53c4df922e390bf8a65a7ca6b.zip` in the private bucket.

- Size: 1,268,196,231 bytes.
- SHA-256: `9ed1188992172b114c032ce30f8e00626599c2d53c4df922e390bf8a65a7ca6b`.
- Conditional initial upload succeeded; the entire remote object was then read
  back and hashed, matching the local SHA-256 and byte length.
- GitHub environment variable `SAYWING_RUNTIME_SHA256` is pinned to this hash.
- No `saywing/current.json` release pointer or public release files were created.
- The existing production website deployment remained `SUCCESS` with the same
  deployment ID after configuration. At this setup checkpoint the app/website code was local and unmerged.

Infrastructure configuration is complete. The remaining items are the authorized
PR/merge workflow, actual GitHub execution and the public-release gates above;
the repository release and publication flags remain false.

## PR preparation on current main

The release delta was isolated from the saved pre-task working tree and applied
in a separate checkout to main commit `6309cd8`. Existing model/setup/branding
work already integrated in main is preserved; unrelated local changes in the
original checkout are not included in this PR. The native startup integration
was reconciled with main's current initialization code.

Verification of this exact PR source: 189 app tests in 14 suites passed, 4 core
tests in 2 suites passed, all 11 core behavior checks passed, all 10 Python
release tests passed, localization passed, and the Release target built
successfully. Logs are under `.build/pr-validation/` in the PR checkout. The
prior private notarization/runtime evidence above predates this main integration;
this PR's source has not been packaged/notarized again. Hosted CI and the genuine
two-version updater/fresh-install/license/privacy gates remain separate.

Website companion: https://github.com/ChrBoebel/Webseite/pull/10. Local Node 22
download tests (5), lint, typecheck and production build pass; production audit
has zero findings. The existing full-dependency CI audit fails on development
packages, including the pre-existing braces/Tailwind chain; that gate is not
weakened or bypassed. Both PRs are intended to remain open for owner review.
