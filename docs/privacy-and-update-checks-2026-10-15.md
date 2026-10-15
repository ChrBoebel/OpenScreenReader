# ARM release checks — 2026-10-15

## Scope and result

The bundled defaults in private ARM version 0.1.4/build 7 passed the functional
privacy checks below. The actual Sparkle installer replaced an isolated signed
version-6 copy with the accepted version-7 package and relaunched it. These are
completed checks, not a claim that the app has been publicly released or that
all supported hardware/permissions/UI combinations have been exercised.

## Privacy evidence

- The owner confirmed installation, reading and dictation on a second Mac, then
  confirmed both functions after restarting with networking disabled.
- Repeated `Tests/Dictation/integration_worker.py` against the actual signed
  ARM package: **12 checks passed**, including real DE/EN inference, 48-kHz input,
  language/vocabulary, silence/malformed input, cancellation, and actual denied
  network/file writes. Evidence: `.build/privacy-release-checks.log` and
  `.build/privacy-release-checks/whisper-turbo-worker-integration-result.json`.
  Test recordings/text are fixed public fixtures, not microphone/user content.
- Actual signed speech worker under its deny-network/deny-file-write profile:
  long 2x playback passed with 56 chunks, zero underruns, 30.218 s of source audio,
  maximum 7.939 s queued, unchanged clipboard. Evidence:
  `.build/privacy-speech-idle-check.log`. A prior run concurrent with compilation
  and App tests had 2 underruns / 4.975 s missing; keep that failed result in
  `.build/privacy-speech-check.log`. The idle repeat does not establish behavior
  under CPU contention or remove that performance limitation.
- Current app suite: **190 tests in 14 suites passed**; separately, two live
  XCTest checks skipped because the test host lacks Screen Recording/Input
  Monitoring. The real capture denial was checked. A live optional-model network
  install test was also skipped. Evidence: `.build/privacy-app-tests.log` and its
  xcresult path. These skips are not counted as passed device permission tests.
- Manual source trace: ScreenCaptureService retains pixels in memory for Vision;
  VisionOCRService has no file/network export; LocalSpeechService uses anonymous
  pipes, bounded RAM queues and a network/file-write-denied worker with stderr
  sent to null. DictationWorker has the same restrictions and generation checks.
  DictationCore's clipboard transaction restores only while it still owns the
  pasteboard. App tests cover new copies winning, cancellation/stale results,
  no recording on controller construction, and release of captured content.
- The only normal runtime network paths found in application source are the
  explicitly authorized model downloader (ephemeral URLSession, pinned hashes,
  constrained HTTPS redirects, explicit install) and Sparkle. No content upload
  or telemetry client was found. Persisted values are configuration, explicitly
  entered vocabulary and model-install intent, not recording/OCR/audio history.
  `--dictation-smoke` is an explicit test mode whose JSON report contains status
  booleans/counts only. It is not a normal recording-history path.

This supports the `offline_privacy` gate for the bundled ARM defaults using
real worker execution, owner device testing and source/data-flow review. It is
not a whole-system packet/filesystem trace, a promise about operating-system
swap/crash behavior, or a completed fresh-account permission matrix. Those are
not interchangeable kinds of evidence. Actual macOS 14 execution remains open.

## Signed update installation and relaunch

- A separate APFS-cloned build-7 app was assigned version 0.1.3/build 6 and
  re-signed with the same Developer ID. It was not separately notarized.
  It lived at `.build/update-roundtrip/Saywing.app`; `/Applications/Saywing.app`
  was not the update target.
- A freshly Ed25519-signed appcast referenced the unchanged accepted build-7
  DMG, with its original valid enclosure signature. An exact-path-only server
  bound **127.0.0.1:6631**, not a public network interface.
- Native UI automation timed out. The owner reported a prompt/install/relaunch,
  but at that point the server had no requests and the test app remained build6.
  That report is therefore not used as proof of the local UI roundtrip; the Mac
  involved has been asked for and remains unconfirmed.
- Built the unmodified **Sparkle 2.10.0** official `sparkle-cli` sources already
  pinned in `.build/packages/checkouts/Sparkle` with upstream compiler macros and
  linked the pinned framework. Its probe reported `Update available!`.
- Its actual `--check-immediately` run downloaded, extracted and installed the
  DMG and reported `Installation Finished`. The running app changed from PID
  69361 to PID 72820. On-disk metadata is now **0.1.4/build 7**; the executable
  hash matches the accepted build-7 source. `codesign --verify --deep --strict`
  passed and Gatekeeper returned **accepted / Notarized Developer ID**.
- Evidence: `.build/update-roundtrip/{probe.log,install.log,result.json}`.

This closes the actual signed two-version **installer and relaunch** check.
The production HTTPS transport, in-app Update Available UI, busy-operation UI
and the next package containing the new license UI still require final checks.
Unit tests cover the busy-install continuation and stale cancellation; do not
present those as real in-app UI observations. Both production flags and the
public pointer/feed remain disabled. No CI release or public deployment occurred.

## License progress and remaining work

New packaging collects **243 original notice files** into an offline HTML index,
with escaped text and no scripts/external resource loads. The UI exposes it in
Settings / Read Aloud and the reading-model setup step in German and English.
Flatbuffers 25.12.19 and tokenizers 0.23.3 supplements have exact source/hash
records. Fourteen CPython/native dependency license files came from the full
matching 3.12.15+20261013 ARM build archive, including builtin modules; provenance
is retained in `docs/licenses/Python-3.12.15/`. The index is generated before
signing, never injected into an accepted artifact. The Release build, localization
check and 24 release tests pass, including seven notice tests.

The resource stage contains all 11 pinned corresponding-source inputs: seven
native-library archives, three exact upstream build-control files, and the
setuptools-vendored autocommand 2.2.2 source archive. All six bundled autocommand
Python files match that source byte for byte. GPLv3's original text accompanies
its existing LGPLv3 notice. Sources are size/hash-verified before copying; public
packaging fails closed if any required source is absent. These checks establish
archive inclusion, not that a rebuilt library has been exercised in the app.

The website now links the exact pinned Supertonic terms in DE/EN. Its production
build, lint and typecheck pass. A local production-server check returned HTTP 200
for both language pages and the license file, whose SHA-256 matches the original.
Evidence: `/tmp/saywing-license-website-{build,lint,types}.log` and
`/tmp/saywing-license-website-http-check.json`. These changes are not deployed.

Remaining: verify the native-library rebuild/replacement procedure, complete
compiled dependency notice coverage (including tokenizers' Rust dependencies),
and review the final downstream terms presentation. The full license gate
remains false. The newly modified app has not been re-signed/notarized yet.
No blanket redistribution approval is inferred from the number of notice files.

## Owner confirmation and test cleanup

The owner explicitly confirmed restart and version 0.1.4 in response to the
installation instruction. This is retained as owner-reported UI evidence; the
earlier host mismatch described above remains unresolved, so it is not relabeled
as a directly observed UI run on this host. The independently verified CLI result
continues to establish the actual local installer/relaunch transition.

After preserving the result, only the identified test app (PID 72820), its worker
(PID 72827) and loopback server (PID 69412) were terminated. The updated test copy,
logs and accepted candidate were retained. The normal installed app was untouched.
