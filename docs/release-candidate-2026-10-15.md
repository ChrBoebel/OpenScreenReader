# Private release candidate — 2026-10-15

Latest checkpoint: [build 9 with completed Rust evidence](release-build9-checks-2026-10-15.md). Earlier findings below are historical where superseded there.

Status: **NOT approved for public release**. The owner requested private release
preparation and verification, and explicitly prohibited public publication.
This record supersedes the deployment/merge status in the earlier preparation notes.

**Current checkpoint (2026-10-15):** corrected private **build 7** for both ARM
and Intel is accepted by Apple, stapled and Gatekeeper-verified. The owner
authorized a password-protected ARM download through the website; public release
is still prohibited. See the final sections for current results. Earlier build-5
and withdrawn build-6 findings below are historical and must not be treated as
the current candidate state. A source-only Intel speech improvement is newer
than build 7 and still needs another signed/notarized package.

## Target and provenance

The owner clarified on 2026-10-15 that Saywing must support **Intel Macs and
Apple-Silicon Macs**. iPhone/iPad are not in scope. The existing macOS 14 baseline
remains the provisional target; raising it has not been approved. “All Macs” is
not a claim that every historical Mac or macOS version is compatible.

The initial diagnostic candidate was **0.1.4 (5)**, built without source changes
from merged main `ebb7f6055da69d6e521ac15950921f9b331aa84f` in the separate
`codex/release-candidate-2026-10-15` worktree. It is **arm64 only** and does not
satisfy the expanded target. Build 5 follows workflow run 4; later public builds
must have a higher build number.

- Local artifact directory: `.build/rc-2026-10-15/`.
- Evidence directory: `.build/rc-validation/`.
- Runtime source: the existing receipt-verified `private-package-3/Saywing.app`
  in the primary checkout. No model weights were downloaded.
- Default bundled models: Supertonic 3 and Whisper Turbo. Qwen and Whisper Large
  model weights are not bundled in this candidate.
- Developer ID: Christopher Böbel, team `S28WSHSSJD`.
- Feed: `https://www.christopherboebel.com/downloads/saywing/appcast.xml`.
- The development notice remains. `--public-release` was not used.
- Existing installed apps, credentials, production storage and publication flags
  were not changed. No commit, push or public release was performed.

## Checks completed on this Mac

Test host: macOS 26.6.2 (25G83), Apple Silicon. This is not a fresh-machine test.

| Check | Actual result |
| --- | --- |
| Release app build | Passed |
| Swift core tests | 4 tests passed |
| Core behavior checks | 11 checks passed |
| Python release tests | 10 tests passed; publisher tests use test doubles, not public storage |
| Localization | Passed |
| App tests | 189 tests in 14 suites passed locally |
| Nested Developer ID signing and permission metadata | Passed, including audio-input entitlement |
| Real packaged speech | Completed, 7 chunks, 0 underruns, clipboard unchanged |
| Speech cancellation | No late chunks; synchronous stop 11.57 ms |
| Model-loading cancellation | No late chunks; synchronous stop 0.045 ms |
| Dictation core | 15 checks passed, including clipboard ownership/restoration |
| Packaged Whisper Turbo integration | 12 checks passed: German/English, vocabulary, silence/malformed input, cancellation, denied network and file writes |
| Whisper model loading / cancellation | 1.19 seconds / 33.37 ms |
| Native dependency scan | 380 native files; no non-system absolute **load dependencies** found |

The first speech probe invocation used the runtime subdirectory instead of the
Speech resource root and failed configuration. The corrected invocation above
passed. Scripts lack executable mode and were invoked with `bash`.
Native scanning distinguishes LC_ID_DYLIB names from actual LC_LOAD_DYLIB
commands; build-machine library IDs alone are not missing dependencies.
The scan does not replace testing @rpath resolution on a fresh Mac.

## Blocking findings

### 1. Advertised macOS requirement is contradicted by the package

`mlx/core.cpython-312-darwin.so`, `mlx/lib/libmlx.dylib` and
`mlx/lib/libjaccl.dylib` declare `LC_BUILD_VERSION`, platform macOS, **minos 26.2**.
The app and generated distribution metadata advertise 14.0. Do not ship this
combination, even after Apple notarization. The evidence is in
`native-load-audit.json` and `native-load-audit.log`.

Use independently sourced libraries built for the supported baseline and test on
that actual OS. Editing the binary's minimum-version declaration is not a fix.
MLX's general installation documentation names macOS 14; that does not override
the higher requirement embedded in these particular binaries.

### 2. Intel support is absent

The release script explicitly builds `ARCHS=arm64`; the dictation worker imports
MLX for every model. The official MLX macOS installation path requires Apple
Silicon. A universal outer app alone cannot make that runtime run on Intel.

A possible implementation route is a separately validated local Whisper backend
such as whisper.cpp, which lists Intel and ARM macOS support. No alternative
backend, extra model, or silent fallback has been integrated or approved as
working. Preserve the selected Whisper Turbo default, local-only behavior,
explicit cancellation and model provenance. Supertonic/ONNX, interpreter and
all native dependencies also need suitable Intel builds. Optional Qwen support
needs its own compatibility decision and evidence.

Require real fresh-machine evidence on Intel and Apple Silicon, including the
oldest supported macOS. A successful M4 or Rosetta run does not prove Intel
hardware or minimum-OS compatibility.

### 3. Runtime provenance and redistribution inventory are incomplete

The actual package contains 9 speech and 99 dictation Python distributions.
27 dictation distributions are absent from `Runtime/Dictation/requirements-lock.txt`.
They include document/PDF/spreadsheet tools unrelated to the declared dictation
runtime. `artifact_tool_v2` 2.8.93 has no license expression, license classifier
or license file in its dist-info metadata. This does not prove an infringement;
it means redistribution permission is not established by this inventory.

`license-inventory.json` records every detected distribution, dependencies and
notice paths. Missing notice files in dist-info are not automatically missing
licenses: ONNX has notices in its package directory and mlx-whisper has the
separately preserved upstream MIT notice. Each missing/ambiguous entry requires
inspection. The soxr metadata declares LGPL-2.1-or-later and needs an applicable
redistribution review. This inventory is not a completed license approval.

Rebuild a minimal, independently pinned Python/native runtime; retain the full
license/notice chain and exact source/build/wheel hashes. The inherited runtime
has no independently established interpreter build provenance. Update the private
CI runtime archive and its hash only after the replacement passes validation.

Supertonic's pinned Open RAIL-M terms and upstream maintenance risk also remain
release gates. The source license includes downstream-use requirements; retained
license files alone are not evidence that the distribution workflow meets them.

### 4. Main CI is still red despite local success

Main run [38644066854](https://github.com/ChrBoebel/OpenScreenReader/actions/runs/38644066854)
failed after the merge:

- OCR's unchanged-clipboard expectation observed changeCount 0 → 1. A parallel
  dictation insertion test uses the real general pasteboard; cross-test interference
  is a supported explanation, but not a verified fix.
- `queueCaptureTimeoutDoesNotInterruptSpeechOrAcceptItsLateResult` never reached
  its initial speech state. Its fixture applies a 120 ms timeout to that initial
  capture/OCR as well as the intended suspended queue capture. CI contention is
  a supported explanation, but not a verified fix.

Do not treat the local green run as a repaired hosted CI run. Isolate shared
pasteboard tests and make timeout synchronization deterministic, then run CI on
reviewed changes. No test expectation was removed or weakened in this preparation.

### 5. Remaining real-world checks

- Fresh-Mac installation, TCC permission denial/grant/restart, real microphone,
  reading and target-app paste behavior: owner-assisted, not yet done.
- Whole-app offline/data-flow review: worker enforcement passed, but this does
  not cover all UI/preferences/update/model-install paths.
- Signed two-version Sparkle download/install/relaunch: not performed. Feed/archive
  signature verification is only part of this gate. Use a private staging path
  without changing public release pointers; exercise busy deferral, opt-out,
  offline behavior and rejection of tampered updates.
- GitHub-hosted packaging/signing/storage path: not enabled or exercised end to end.

## Apple status and distribution artifacts

The app archive was submitted once as `c0461afc-1eac-4e5e-a549-c4fba7f21ce0`.
Its last queried state was **In Progress**. The packaging process waits for that
existing submission; do not resubmit on an interrupted tool call. The DMG and
signed appcast are not complete until `release-result.json` exists and the
packaging command succeeds. Later results are appended below.

## Owner assistance

A second Mac mini, probably M4, is available. Confirm its exact macOS version via
Apple menu → About This Mac. The current diagnostic package needs at least 26.2
for its dictation runtime, regardless of its misleading 14.0 metadata. Use the
[second-Mac checklist](release-test-second-mac-de.md) only after a completed,
stapled test DMG is available. Intel and oldest-supported-OS tests will still be
needed after the compatibility work.

## Primary references checked 2026-10-15

- [MLX installation and architecture requirements](https://ml-explore.github.io/mlx/build/html/install.html)
- [whisper.cpp supported platforms](https://github.com/ggml-org/whisper.cpp)
- [Pinned Supertonic model license](https://huggingface.co/Supertone/supertonic-3/blob/3cadd1ee6394adea1bd021217a0e650ede09a323/LICENSE)
- [Sparkle signed update publishing](https://sparkle-project.org/documentation/publishing/)

## Latest verification checkpoint

Post-runtime verification passed: all 3,976 speech and 32,409 dictation receipt
entries match; the pinned speech model and strict deep app signature also pass.
Evidence: `.build/rc-validation/post-runtime-integrity.log`.
The app declares the real production feed, the expected public key,
`SURequireSignedFeed=true` and `SUVerifyUpdateBeforeExtraction=true`.

Apple was queried again for the same submission and still reports **In Progress**;
see `.build/rc-validation/notary-status.json`. The original packaging process is
still waiting (30-minute notary wait limit). A completed DMG or Apple acceptance
must not be inferred from the app having a Developer ID signature.

Both repository variables, `SAYWING_RELEASE_ENABLED` and
`SAYWING_PUBLISH_ENABLED`, were rechecked as `false`. The public `latest.json`
endpoint still returns HTTP 404. The four existing approval booleans remain false.
No public artifact or pointer was written.

Disposition: private diagnostic candidate prepared and checked as far as the
available machine permits; **final release candidate withheld** because of the
compatibility, provenance/license, hosted-CI, fresh-Mac and update-roundtrip gates
above. The new Intel requirement calls for runtime implementation work, not just
a successful test on the owner's M4.


## Portability follow-up — private build 6

Work remains uncommitted on `codex/release-candidate-2026-10-15`. No push,
public deployment, model publication or change to release gates was performed.

- Four clean Python runtimes are built from independent CPython 3.12.15 archives
  and exact SHA-256-pinned wheel closures: reading has 9 packages on each
  architecture, ARM dictation 52, Intel dictation 5. The inherited unpinned
  `artifact_tool_v2` and unrelated development packages are absent.
- Every runtime passed native architecture and actual Mach-O minimum-version
  checks against macOS 14. This is binary inspection, not execution on macOS 14.
- Intel dictation uses pinned MIT whisper.cpp 1.9.5, a bounded in-process C ABI,
  and Whisper large-v3-turbo q5_0 (574,041,195 bytes). Source/revision/hash/license
  were documented before download. No MLX fallback or runtime network was added.
- Default-model integration: **12/12 checks on ARM, 12/12 on Intel via Rosetta**.
  Both exercised real public German/English audio, 48 kHz resampling, language
  selection, vocabulary, malformed/silent input, cancellation and denied network
  and writes. Logs: `.build/runtime-portability/{arm64,intel}-integration.log`.
- ARM reading: 7 chunks, 0 underruns, cancellation 11.82 ms, loading cancellation
  0.060 ms, no late chunks, clipboard unchanged. Intel reading initially had a
  0.56-second underrun while the Release build ran concurrently; do not claim
  stable Intel playback from the successful transcription tests.
- Unsupported optional models are explicitly unavailable on Intel. Existing
  Qwen/Large preferences cannot cause an incompatible download or worker start.
  ARM optional-model execution still needs revalidation with this new closure.
- Observable model-availability regression was reproduced (2 assertions failed),
  then fixed. Worker tests: 20 passed under the packaged Python 3.12 runtime.
  The system Python 3.9 run failed 4 tests because `hashlib.file_digest` requires
  Python 3.11+; it is not the shipped interpreter.
- App tests: **190 passed in 14 suites**, after fixing queue timeout timing,
  deterministic paste callback scheduling, and serializing the real OCR clipboard
  assertion with the dictation paste test. Initial compile/test attempts and the
  original timing failure remain in logs, not counted as successes.
- Core: 4 tests and 11 behavior checks passed. Release: 16 unit tests passed.
  Localization passed. Publisher unit tests used test doubles; their printed
  “Published” line did not contact storage or publish any artifact.
- CI now builds both architectures at macOS 14. It has not been pushed or run on
  GitHub. Local Intel and ARM Release builds are being packaged separately.
- Apple accepted the OLD build-5 submission `c0461afc-1eac-4e5e-a549-c4fba7f21ce0`.
  This does not notarize either new architecture/runtime package.

Reproduction and pinned inputs: `Runtime/Portable/README.md`. Evidence and private
resources: `.build/runtime-portability/`, `.build/portable-{arm64,x86_64}/`.
New distributions are under `.build/rc-portable-{arm64,x86_64}/`; consult their
actual result files and final checks, not directory existence, for success.

Remaining release gates: clean macOS 14 / native Intel tests; stable Intel reading;
new package notarization/Gatekeeper; complete license and notice review; optional
ARM models; end-to-end update round-trip; architecture-specific download, feed
and storage routing. The existing website/feed metadata is ARM-only. The private
packages currently have the same version/build filename in separate local folders
and must never be uploaded together to the existing single endpoint.


### Corrected private build 7 — SDK and signing follow-up

Both build-6 packages were withdrawn locally and their DMGs removed. Post-signing
Intel integration exposed a real failure: SciPy 1.15.3's `_arpack` had a valid
Developer-ID signature but `sdk n/a` / VersionSDK=0, so hardened dyld rejected it.
The issue reproduced even without the worker sandbox. A stricter preflight also
found an SDK-less GCC runtime in the ARM SciPy wheel, despite successful execution.
No SDK or minimum-version header was forged and no library-validation entitlement
was weakened. Both locks now pin official SciPy 1.17.1 macOS-14 wheels. Their actual
native SDK metadata passed the expanded check. The regression was reproduced red
before the fix; release tests now total **17 passing**.

Apple documents this class of failure under old SDK / hardened library validation:
https://developer.apple.com/forums/thread/670761 . Binary evidence is retained in
`.build/runtime-portability/debug-signed-worker.log`; isolated system-sandbox
`codesign` failures were not mistaken for invalid signatures: verification with
keychain access confirmed the Developer-ID signature was valid on disk.

Corrected inputs: `.build/portable-{arm64,x86_64}-v2/Saywing.app`.
Corrected outputs: `.build/rc-portable-{arm64,x86_64}-v2/`, version 0.1.4 build 7.
Release metadata explicitly marks the source tree dirty. A later public build
must exceed **7**, including when CI run numbers are used to generate versions.
Do not reuse the superseded build-6 results as proof for build 7.

Intel reading via Rosetta also repeated its continuity failure without the
concurrent compile: one 0.49-second gap. Treat native Intel playback performance
as an open gate; it is not fixed by the SciPy dictation change. No acoustic model
quality setting or app playback semantics was silently reduced to mask it.


### Final execution checks on corrected, Developer-ID-signed build 7

Both corrected signed dictation bundles passed **12/12 real integration checks**.
ARM: model load 1.662 s, cancellation 38.24 ms. Intel via Rosetta: model load
2.294 s, cancellation 44.26 ms. Both passed German/English, explicit language,
vocabulary, silence, malformed inputs, and actual sandbox denial of network and
file writes. Evidence: `signed-{arm64,x86_64}-v2-integration.log` and the matching
`*-checks/whisper-turbo-worker-integration-result.json` files under
`.build/runtime-portability/`. Test audio/transcripts in those records are public
fixtures, not user recordings. Worker regression tests with the final SciPy
closure: 20/20 passed. App code remains at the tested 190-test state.

The corrected Intel DMG is submitted privately to Apple; submission metadata is
stored in `.build/rc-portable-x86_64-v2/notary-submission.json` when the upload
finishes. An empty file means the upload has not yet returned a submission result,
not that Apple accepted it. No public upload or release flag was changed.


### Final package integrity and pending Apple submissions

Both corrected Release builds completed. Developer-ID-signing, signed Sparkle
appcast verification, post-test runtime receipts, pinned speech model hashes and
final DMG SHA-256/size checks passed for both architectures. Current private DMGs:

- ARM: `.build/rc-portable-arm64-v2/publish/Saywing-0.1.4-7.dmg`
- Intel: `.build/rc-portable-x86_64-v2/publish/Saywing-0.1.4-7.dmg`

Signed ARM speech completed with 7 chunks, **0 underruns**, clipboard unchanged;
stop 10.86 ms and model-loading cancellation 0.132 ms, with no late chunks.
Evidence: `.build/runtime-portability/signed-speech-arm64-v2.log`.

Apple's history currently lists two new build-7 entries as **In Progress**:

- `ffb2fa6b-d011-4d73-920d-0f5a342cd8a4`, created 2026-10-14T23:32:02.603Z.
- `91bfd3a8-2207-41c0-ae74-56cb3b78d976`, created 2026-10-14T23:34:28.487Z.

The Intel command was started first, then ARM. Both upload commands are still
running and have not yet written their per-architecture submission receipt.
Confirm the ID mapping from those receipts before stapling; **do not resubmit**
while these jobs exist. The history snapshot is `notary-history-final.json`.
No new candidate is claimed notarized. `release-result.json` still correctly has
`notarized: false` and `public_release_approved: false`.

After Apple accepts a DMG: staple and validate it, then regenerate the signed
appcast, SHA256SUMS and latest.json because stapling changes DMG bytes. Keep all
files private. These are separate architecture packages with colliding filenames
and unfinished public routing. Apple acceptance alone does not close the actual
macOS-14 / Intel, playback, privacy, license, optional-model or update gates.

Temporary image/source-resource copies were removed after successful consumption
to preserve disk space. Final signed apps, DMGs, pinned downloaded inputs and all
checks remain. Superseded build-6 app/DMG copies were removed after the recorded
withdrawal; their logs/results remain. No installed app was replaced.

Website design is independently prepared on `codex/saywing-download-design`:
http://127.0.0.1:6626/de/saywing?preview=apple-download-3 . Download remains disabled.
Both repositories remain uncommitted/unpushed; no public release or deployment.

## Apple acceptance and private website test — 2026-10-15

Both corrected build-7 DMGs are now **Accepted** by Apple. The per-architecture
`notary-submission.json` receipts establish the mapping: ARM `91bfd3a8-2207-41c0-ae74-56cb3b78d976`,
Intel `ffb2fa6b-d011-4d73-920d-0f5a342cd8a4`.
Both DMGs were stapled and successfully validated. Gatekeeper accepted the DMGs
and the apps inside their read-only mounted volumes as **Notarized Developer ID**;
deep strict app signatures also passed. Volumes were detached without installing
or launching either app. The signed Sparkle feeds and DMG enclosure signatures
were regenerated/verified after stapling, and size/SHA256 metadata was refreshed.
Each candidate's `notary-validation.json` records the results. `notarized` is now
true, scoped to the submitted DMG with its nested app; `public_release_approved`
remains false. Nothing was submitted again.

The owner requested testing the actual website download and explicitly approved
activating a password-protected test download. This is separate from public
release approval. The website now prepares `/downloads/saywing/private/arm64`
and `/downloads/saywing/private/x86_64`, requiring HTTP Basic authentication
before any storage access. Server configuration contains only a SHA256 digest of
a high-entropy credential; plaintext credentials are not in either repository.
Downloads use the private `saywing/private-candidates/` namespace and five-minute
presigned storage URLs, never `saywing/releases/` or the public current pointer.
The ARM build-7 package is the selected upload for the owner's M4 test. Intel's
route has no candidate selected. Missing configuration fails closed, unnotarized
or mismatched metadata is rejected, and HEAD is authenticated without issuing a
GET link. Authorization, no-store/noindex, namespace isolation, metadata mismatch
and sanitized-error tests pass (10 download tests plus 20 existing security tests).
Node22 production build/TypeScript/lint passed, and a real local production server
returned 401 for unauthenticated ARM/Intel GET/HEAD. Live results follow below.

The website deployment is an explicitly approved manual Railway deployment of
the current uncommitted source, including the owner-approved minimal design and
shared header/footer. This does not commit, push or merge either branch. A future
GitHub deployment must include these changes deliberately to retain the test route.
The public app release flags and four release approval booleans remain disabled.

### Intel speech investigation

Three fixed public sentences, three repetitions per setting, were measured with
the unchanged Supertonic model, M1 voice, eight steps and 1x synthesis speed.
The default ONNX thread pools took 1.589–1.675 s for the second short sentence;
four threads with idle spinning disabled took 1.147–1.225 s. The pinned upstream
helper remains unmodified: project code supplies bounded session options using
its existing loader primitives. ARM retains its original loader/settings.
Reference: https://onnxruntime.ai/docs/performance/tune-performance/threading.html .
Raw evidence: `.build/runtime-portability/tts-intel-{default,nospin,threads2,threads4}.json`.
This is a Rosetta diagnostic, not a native Intel performance certification.

The regression tests failed before implementation and then passed (9 worker
checks). A separate cloned speech-resource test directory uses the modified worker;
the notarized build-7 apps/DMGs are unchanged. Real short playback: 7 chunks,
zero underruns, stop 11.62 ms, loading cancellation 0.061 ms, no late chunks and
unchanged clipboard. Real long playback: 58 chunks / 30.22 audio seconds, zero
underruns, maximum queued 7.94 seconds (within the existing eight-second cap).
No voice quality, segmentation, playback preroll or memory limit was reduced.
The source correction still requires a new signed/notarized Intel build (>7),
plus actual native Intel and macOS14 testing. Do not attribute this correction
to the existing accepted Intel build7.

The additional long **2x playback check failed**: one 0.556-second underrun with
an x86_64-compiled Swift playback probe and Intel Python under Rosetta. Do not
claim the Intel continuity gate fully closed. Default-speed improvement is
verified; faster playback and native hardware remain open. The nine worker
regressions passed under both ARM and Intel Python.

Railway deployment `0bdf2b34-6795-4d00-89d4-d8f90189a893` is **SUCCESS**.
Live anonymous private-route requests return 401/Basic challenge with
`private, no-store`; public `latest.json` and the exact build-7 versioned DMG
return 404. The public Saywing page returns 200 with a disabled download button
and noindex. GitHub SAYWING_RELEASE_ENABLED and SAYWING_PUBLISH_ENABLED were
rechecked as **false**. Private upload/full-download verification follows.

Mechanical final license inventory: `.build/runtime-portability/final-license-inventory.json`.
Top-level package counts remain speech9 per architecture, ARM dictation52,
Intel dictation5. An additional12 vendored metadata records inside the pinned
setuptools wheel are explicitly identified, not unpinned top-level additions.
ONNX notices reside in its package directory; MLX Whisper's upstream notice is
retained separately as LICENSE-mlx-examples. Flatbuffers and tokenizers lack a
license file in their dist-info directories and still require source/notice-chain
review; this alone is not a legal conclusion about permission to distribute.
The complete license gate remains false.

### Completed private website download

The final Railway deployment `9d4badb6-2523-4976-91d7-5943f30f4e86` is SUCCESS.
A real HTTP check caught the global Next.js Referrer-Policy overriding the route's
no-referrer. A private-path-only header rule fixed this; local production HTTP
and the final live authenticated redirect both verified no-referrer. Other site
headers/styles are unchanged by that correction.

The accepted ARM DMG was uploaded only to
`saywing/private-candidates/7/arm64/Saywing-0.1.4-7.dmg`, fully read back and hashed,
and selected only through the ARM private candidate pointer. A second independent
full download through the real website authentication/redirect path matched
1,322,296,833 bytes and SHA256
`6d858c9fbac1609816ac78663f9a212650db585ff9dcb40c1cf48e1b47e84d30`.
Evidence: `.build/private-website-download-check.json` (2026-10-15T00:11:42Z).
Anonymous and wrong-password website access return401; unsigned storage access
returns403; public latest metadata, appcast and exact build7 DMG return404.
The temporary artifact URL expires in300seconds. No public pointer/feed was written.
The owner's M4 installation test can now proceed through the private website link.

Remaining gates: actual macOS14/nativeIntel/freshMac permission/offline tests;
Intel continuity at2x (source fix is not yet in a new signed package); optional
ARM model execution; complete license review; signed two-version update roundtrip;
reviewed/pushed CI and dual-architecture public delivery. No commit/push/merge
was performed. Private test availability is not public release approval.

### Owner-confirmed second-Mac test and public-beta request

On 2026-10-15 the owner confirmed installation, reading, and dictation on the
second Mac through the protected ARM download. Exact macOS/chip, clean-account
permissions, and offline operation were not confirmed by that answer. Basic
functional success is recorded; the broad clean_mac/offline_privacy booleans
remain false until their documented checks are evidenced.

The owner requested publication. A focused review found outstanding downstream
Supertonic terms, runtime notice/source obligations, and stale private-package
notices; see `public-beta-readiness-2026-10-15.md`. The exact pinned Supertonic
license was copied to `docs/licenses/Supertonic-3-Open-RAIL-M.txt` and its SHA-256
verified. This does not claim complete license clearance. No public release
flags, storage pointers, production files, signatures, commits or pushes were
changed for this review. Offline retesting has been requested from the owner.

### Owner-confirmed offline functionality

On 2026-10-15 the owner answered "Ja, beides funktioniert offline" to the
requested second-Mac procedure: disable Wi-Fi/disconnect Ethernet, restart
Saywing, then test reading and dictation. Both bundled default functions are
therefore recorded as passing an owner-reported offline device test for the
protected ARM build 7. This closes the outstanding basic offline-functionality
question. It does not establish fresh-account permission-denial behavior,
absence of all persistent data, macOS14 execution, or the two-version update
roundtrip. The broader release-approval booleans remain unchanged until their
full documented gates are evidenced. No public deployment or release activated.

### Completed ARM privacy and signed-update checks

See `privacy-and-update-checks-2026-10-15.md`: 12 real signed-worker checks,
190 app tests (explicit permission/network skips retained), owner-confirmed
offline use, manual source/data-flow review, and a real Sparkle signed-feed/DMG
installation with verified relaunch from private build6 to accepted build7.
The offline_privacy and update_roundtrip gates now record this ARM-scoped
evidence; license_review and clean_mac remain false, so publication stays blocked.
The update was performed by Sparkle's official CLI; the owner's UI report could
not initially be reconciled with this host, and production HTTPS/in-app UI tests
remain separate final checks. No public endpoint or activation flag was changed.

Packaging now collects 243 original license notices into a local HTML index;
Settings and setup link it in DE/EN. Exact Flatbuffers/tokenizers and 14 Python
license supplements are preserved with provenance. Release build/localization
and 24 release tests pass. Remaining native corresponding-source obligations are
explicitly tracked, not declared complete. No new signed/notarized release exists
for these source changes yet.


### License-source staging and owner update confirmation

All 11 pinned source/archive/build-control inputs are included in the unsigned
resource stage. The six vendored autocommand Python files match the pinned sdist.
Website build/lint/typecheck and local DE/EN license-link/hash checks pass; no
website deployment occurred. The owner confirmed restart and version 0.1.4;
this is owner-reported UI evidence separate from the independently verified
local Sparkle CLI transition. Test-only app/worker/server processes were stopped.
See the privacy/update report for exact remaining scope and evidence.


### Reconfirmed compatibility target and binary audit

The owner reconfirmed support for all Intel and Apple-Silicon Macs rather than
providing the second device's OS/first-use permission details. The existing
minimum target remains macOS 14; this answer is not evidence of a completed
macOS 14 or fresh-account device test and does not waive the remaining gates.

Repeated the native-binary audit on both accepted build-7 apps: ARM passed for
222 native files; Intel passed for 184. Every discovered Mach-O binary contains
the requested architecture; recorded minimum OS versions do not exceed macOS 14,
SDK validation passes, and no disallowed absolute dylib dependency or external
symlink was found. Evidence: `/tmp/saywing-dual-architecture-check.json`.
This static audit does not establish actual execution, symbol availability or
playback continuity on every supported device. Existing Intel performance and
native macOS 14 execution gaps remain open. No release flag was changed.


### Build 8 preparation: Intel continuity and expanded notices

The x86_64 fast-preroll regression failed before the change. The player now
accumulates up to six source seconds at 2x on Intel, within the existing fixed
eight-second capacity; normal-speed and ARM startup behavior are unchanged.
Two real x86_64 playback runs under Rosetta passed at 2x: 30.218 s source audio,
zero underruns, maximum queued 7.939 s. Stop took 11.93 ms; loading cancellation
0.102 ms, no late chunks, clipboard unchanged. Evidence:
`.build/runtime-portability/speech-intel-headroom-*.log`. This is not native Intel
hardware certification; initial fast-rate playback may start later.

The separate fast-preroll/tail-drain probe passed for ARM and x86_64. The 190 app
tests in 14 suites passed, with the same explicit permission/network skips;
25 release tests and localization passed. Release packaging now verifies source
receipts before replacing only project-owned workers, records their hashes, and
uses independent APFS clones where available to avoid redundant model storage.

The license supplement review now includes exact Cargo-lock archive checksums
for tokenizers, safetensors and hf-xet, corresponding sources for potential
MPL/CDDL components, and matching Intel Python build license texts. Notices from
all lock entries are conservatively retained; that does not prove every optional
or target-specific crate is compiled into macOS. A built compatible libsndfile
replacement passed an actual bundled-Python/SoundFile in-memory WAV roundtrip
without the official signing key. See `licenses/libsndfile-native-source-review.json`.

Open license items remain specific: tiktoken's PyPI source lacks the resolved
Cargo lock for its binary; a small number of other lock entries lack complete
original notices (recorded in `licenses/rust-dependency-review.json`); and a full
modified-app receipt/seal workflow remains untested. The license gate stays false.
Private 0.1.5/build8 packages are being prepared. No public activation, commit,
push, merge, or production website deployment has been performed.
