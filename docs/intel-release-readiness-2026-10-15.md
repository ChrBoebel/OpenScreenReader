# Intel release readiness — 2026-10-15

The Intel candidate remains private. This report supersedes the Intel routing and
local-update gaps in `release-build9-checks-2026-10-15.md`; its source, model,
license and notarization evidence still applies. The public ARM beta is separate.
The owner reports that no physical Intel Mac is currently available.

## Verified candidate

Saywing 0.1.5, build 9, x86_64, macOS 14 minimum. Existing accepted DMG:
`.build/rc-final-x86_64-build9/publish/Saywing-0.1.5-9.dmg`.

- Apple submission: `b4698f3a-a99a-4698-92e0-ddfe07e26f7a`, accepted and stapled.
- Size: 1,099,185,763 bytes.
- SHA-256: `6825053c756c51defb3b50232b1a9b37121f419d00f7851a243b2b267a07065f`.
- Default TTS: bundled Supertonic 3; dictation: bundled Whisper Turbo with whisper.cpp.
- 88 original license notices and the corresponding-source material remain bundled.
- Whisper build cache confirms `GGML_NATIVE`, AVX, AVX2, AVX512 and FMA are OFF;
  deployment target is 14.0. This avoids an accidental host-specific ISA requirement;
  it does not establish performance on every Intel CPU.

## Actual update and offline execution

The official pinned Sparkle 2.10.0 CLI was compiled for x86_64 and run under
Rosetta. It probed a signed loopback feed, downloaded the exact final stapled DMG
and installed build 9 over a separate stopped build 8 copy. The installed
executable matches the accepted candidate; strict app-seal and Gatekeeper checks
pass; all 88 notice hashes match. The permanent embedded feed is
`https://www.christopherboebel.com/downloads/saywing/x86_64/appcast.xml`.

Evidence: `intel-update-loopback-2026-10-15.json`; raw logs are in
`.build/intel-update-build9/`. The temporary loopback server was stopped.
This is real installation evidence, not a production HTTPS, physical Intel,
GUI relaunch or fresh-account permission test.

The updated copy passed all 12 dictation integration checks with packaged public
German/English demo audio, including 48 kHz input, explicit language, vocabulary,
silence, malformed samples, cancellation, denied network and denied file writes.
No microphone recording or user text was used. Evidence:
`intel-dictation-update-check-2026-10-15.json`.

The updated bundled speech runtime also passed isolated real x86_64 playback at
2×: 48 chunks, zero underruns, zero missing audio, maximum 7.9393 source seconds
queued (8-second limit). Playback stop took 11.42 ms; loading cancellation took
0.10 ms; no late chunks or clipboard changes. An initial playback run exited
without diagnostic output; a test-only diagnostic improvement and full rerun
passed. Its original cause is unproven. Raw logs: `.build/intel-release-checks/`
(`speech-2x-recheck.log`, `speech-cancel.log`, `speech-cancel-loading.log`).

## Prepared source changes

App branch: `codex/intel-release-readiness`.
Website branch: `codex/intel-download-routing`.

- ARM keeps `/downloads/saywing/` and storage prefix `saywing`.
- Intel uses `/downloads/saywing/x86_64/` and `saywing/x86_64`.
- Publisher checks architecture, exact URL, digest, increasing build and current
  main; immutable uploads and conditional promotion remain architecture-specific.
- Website serves separate signed feeds without modifying their bytes. Intel gets
  a download button only after valid public Intel metadata exists. Protected
  validation capabilities now select the manifest's allowlisted architecture.
- CI defaults to ARM only. Repository variable `SAYWING_INTEL_RELEASE_ENABLED=true`
  explicitly opts into a second matrix job. The Intel runtime requires its own
  `SAYWING_INTEL_RUNTIME_SHA256`; a missing pin fails rather than selecting ARM.
- Intel approval is read only from `release-approval-x86_64.json`. The ARM beta
  device-test exception cannot satisfy the Intel gate.

The current source also builds successfully as an x86_64 Release app with Xcode
and `MACOSX_DEPLOYMENT_TARGET=14.0`. The updated signed candidate passes the
full audit of all 184 Mach-O files and both runtime receipts. Raw evidence:
`.build/intel-release-checks/xcode-build.log`, `native-audit.json` and
`native-audit.log`. The unsigned build is only a build check, not a distribution.

Release unit tests: 38 passed, including cross-architecture pointer rejection,
independent Intel promotion/retry/downgrade, and fail-closed approval checks.
Website: 19 download tests, 20 dependency-security tests, lint, TypeScript and
production build passed. Local browser smoke check confirmed the no-storage
state hides downloads and retains the approved header/footer.

## Remaining gates and activation order

1. Integrate the website route after explicit commit/push/merge approval, then use
   a short-lived protected HTTPS feed to repeat the real Intel installation from
   the existing domain. Keep Intel files under `saywing/private-candidates/` for
   this test; do not put them in publicly accessible `releases/` yet.
2. Record the resulting exact feed, full download hash, installation and seal
   evidence before setting Intel `update_roundtrip=true`.
3. Obtain a physical Intel Mac running macOS 14 or later, preferably a fresh
   account. Test first launch, permission refusal/grant, OCR-to-speech, microphone
   dictation/paste/clipboard restoration, stop/cancel, offline restart, licensing
   UI and update/relaunch. Rosetta does not replace this evidence. Keep
   `clean_mac=false` until verified; no Intel beta exception has been approved.
4. Once approved, privately pin the accepted Intel runtime at
   `saywing/runtime/<sha256>.dmg`; set the matching Intel runtime variable. Integrate
   app source through a reviewed PR. Enable Intel CI only after its approval gates
   and publication authorization are satisfied. Build/sign/notarize fresh outputs
   from main; do not relabel the private candidate's metadata as a public release.
5. Verify the real public Intel feed, DMG and website choice after publication;
   confirm the existing ARM pointer and download are unchanged.

No new model weights or dependencies were introduced for this work. Production
flags, public pointers and existing accepted package contents were not changed
by the local preparation described above.
