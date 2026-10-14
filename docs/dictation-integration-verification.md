# Saywing dictation integration — 2026-10-13

Owner-approved integration of the independent Qwen3-ASR prototype, with clipboard paste and restoration. Implemented on `codex/qwen-dictation-integration` on top of the existing uncommitted Saywing branding/capsule work. No commit, push or publication. Qwen3-ASR recognizes German/English; Supertonic remains the reading voice.

## User flow

Open Saywing → menu bar → **Diktieren einrichten & testen…**. Grant **Mikrofon freigeben** once. The **Aufnahme im Testfeld** button records into the window's scratch field. For external apps, grant **Bedienungshilfen …**, click the target text field, and hold **Fn** to dictate/release to insert. Double-tap **Fn** or use **Fn+Space** for hands-free, then tap Fn to finish. **⌥⇧Space** remains a start/stop alternative. **Esc** discards. Quit the former Qwen Dictation Lab first so the shortcut is available.

Recording starts only on an explicit action, lasts at most 60 seconds and shows a nonactivating status panel. Text appears after stopping. German/English autodetection is the default, with explicit language choices. The model prepares automatically on launch, stays warm while the app is open, and reloads automatically after wake/session reactivation. There are no manual load/unload buttons. It may need a few seconds after launch; cold dictation audio waits in bounded RAM. Sleep, inactive session and quit release it. Reading stops before recording; a reading shortcut cancels dictation. Paste does not send Return. The clipboard is restored after one second (two optional) only if still owned; a newer copy wins. Changed targets keep the result for explicit copying in the dictation window. Demo buttons transcribe public samples and never open the microphone.

## Actual verification

Machine: Apple M4, 16 GB, macOS 26.6.2; Xcode Swift 6.

- Debug app build and app tests: **99 Swift Testing tests across 7 suites passed**, plus the configured XCTest paths. The explicitly skipped existing permission-dependent Escape test is not counted as a pass.
- **9 focused lifecycle/integration tests passed** after the GUI-target correction, including a regression for the explicitly bound internal test field. At that integration checkpoint they covered no worker/microphone at startup (worker policy superseded by automatic preparation below), rejecting late cancelled results, discarding pending cold-start audio, deferring PCM until the model is ready, Escape conflict, fatal model failure, cancellation before switching to reading, stopping reading before dictation's activation callback, and reserving the dictation shortcut (several assertions share a test).
- **15** real private-pasteboard/core checks: multiple original clipboard items/formats, Unicode, exact restoration, newer copies winning, empty board, oversize refusal before mutation, generation isolation, RAM discard and 60-second cap. No normal clipboard use in this set.
- **8** Python protocol tests passed, including bad samples/rates/languages, duration, silence, resampling and model integrity errors.
- **8** actual bundled-Qwen checks passed under the deny-network/deny-write profile. Public German FLEURS audio processed through a synthetic 48-kHz microphone-format input and resampling, English through the warm model, silence with no text, invalid samples rejected, active inference terminated, network and write attempts denied. Model load **8.81 s**, cancellation **37.5 ms** in this single run; not general latency guarantees.
- Real bundled Supertonic regression: generated **4.0 s** of finite, non-silent PCM, first audio **1.35 s**, bounded protocol and invalid-request handling passed. Its network/write denials passed. This generated test audio in memory without playing it or recording a microphone.
- Swift Package core test: **1 passed**.
- Full GUI check in the Release bundle via normal LaunchServices start: both public DE/EN samples → actual Qwen → scratch selection replacement, exact readback and full original clipboard restoration passed. Zero failures; dictation shortcut registered. No microphone or Accessibility grant was present. Settings visibly exposes the integrated dictation entry.
- Release app compiled; native dependency and outer bundle ad-hoc signatures verified with `codesign --verify --deep --strict`.

Raw local results live in ignored `.build/saywing-dictation/verification/` and Xcode's `/tmp/saywing-dictation-build/Logs/Test/`. Public test transcripts are not personal dictation history.

## GUI findings corrected during validation

The explicit GUI self-test originally opened an AppKit window while SwiftUI was constructing its StateObject; it now starts on the next main-loop turn. The app's internal scratch target is bound directly to its NSTextView and can finish when another app is in front; it still rejects changes to its original text/selection. The explicit test-field button always targets that field. This does not relax the foreground/window/field checks for external paste.

## Packaging findings

The original development venv receipt rejected its changed external Python link. Its check was retained. The new offline packager instead reuses the installed app's self-contained Speech runtime after verifying its outer signature, entire SHA-256 inventory, model revision and equality with the project worker. The Qwen runtime comes from the tested prototype; model files are checked against the pinned repository manifest. Unneeded external pkgconfig/manual symlinks are omitted. No packages or models are downloaded.

`bundle-dictation-runtime.py` can attach ASR to an already packaged app, or also reuse a verified speech bundle:

```sh
python3 scripts/bundle-dictation-runtime.py /absolute/new/Saywing.app /absolute/existing/QwenResources --speech-from /Applications/Saywing.app --whisper-model /absolute/verified/WhisperTurbo [--with-qwen] [--whisper-large-model /absolute/verified/WhisperLargeV3] --development-only
```

Both providers are self-contained program resources. No model weights/runtime binaries are tracked in Git. [Sources, model hashes and licensing gates](research/qwen-dictation-runtime.md).

## Remaining limits

No live microphone was recorded by the integration checks. The owner tried the separate prototype; that is not a new integrated microphone test. External paste had been verified with TextEdit in the prototype; do not infer browser/Electron/Word/universal text-field support from it. Permission identity can differ between direct developer launch and normal app launch. The installed app needs its own microphone/Accessibility grants.

The bundle is a local development app, not a public/notarized release. Fresh-Mac validation, complete transitive redistribution/license audit, Developer ID/notarization, language/long-session quality and broad target-app/keyboard/display testing remain open. A crash within the clipboard interval cannot guarantee restoration, and clipboard managers may observe transient text.

## Repeating the checks

With the bundled runtime present and Xcode selected, run `bash scripts/verify-dictation.sh /absolute/Saywing.app/Contents/Resources/Dictation` for the private-pasteboard, protocol and actual model checks. App lifecycle checks are in `DictationIntegrationTests` within the Xcode app test target. Explicit `--dictation-smoke` starts the two public GUI examples and writes only boolean/status results beside the test bundle; normal launch does neither. `--dictation-setup` opens the setup window without requesting permissions or recording.

## Installed local build

Installed at `/Applications/Saywing.app`. After relocation, the setup window opened and the bundled Qwen model reached **Bereit** with no microphone recording and no permission grant. The previous installed app is preserved at `.build/saywing-dictation/previous/Saywing.app`. A temporary installation copy exceeded free disk space; only that incomplete copy was removed, and the verified app was moved into place without another full duplicate. The former prototype was closed to release its hotkey.

## Automatic model preparation follow-up — 2026-10-13

The owner requested removal of repeated manual model loading. Saywing now schedules preparation on the next main-loop turn at normal startup, retains the ready worker through idle time and reading, and prepares it again after sleep/session reactivation. Cancelling active inference invalidates the old request before preparing a fresh worker; switching to reading still stops active inference immediately. No recording or permission request is part of preparation. The manual load/unload controls and five-minute idle unload were removed. Fatal failures remain visible and do not start a retry loop; the next explicit dictation action can retry.

Five new lifecycle tests failed against the previous behavior, then all **14 lifecycle/integration tests passed** after the change. These include idempotent preparation without recording, retaining an idle model during reading, waiting for both wake and active session, shutdown blocking deferred preparation, and rejecting the cancelled result while preparing the next model. Debug test build and Release build passed. Wake/session notifications in these tests are synthetic; the user's Mac was not put to sleep. The model/runtime files were unchanged.

The updated Release executable was installed into `/Applications/Saywing.app` while preserving the bundled runtime/model resources; the previous executable/signature receipt is in ignored `.build/saywing-dictation/previous-autoload/`. The outer ad-hoc signature was renewed and `codesign --verify --deep --strict` passed. A normal launch with no setup/smoke flags automatically spawned the bundled Qwen worker. A subsequent setup-window launch visibly transitioned from **Diktieren wird vorbereitet …** to **Bereit**, with both demo buttons enabled, no manual model buttons, no recording and microphone permission still ungranted. Live microphone and real sleep/wake were not exercised in this follow-up.

## Microphone permission packaging correction — 2026-10-13

The owner reported that Saywing did not appear in macOS's microphone list after requesting access. Inspection found a microphone usage description but **no entitlements** in the installed hardened-runtime signature. The app and both packaging scripts now sign with `OpenScreenReaderApp/Saywing.entitlements`, declaring only `com.apple.security.device.audio-input`. This is Apple's [Audio Input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input); it enables the app's request and does not substitute for user consent.

`scripts/verify-app-permissions.py APP` checks the actual signed artifact's entitlement and usage description. It failed on the previous installed app, then passed on the rebuilt Release app. Both packaging scripts run this check after outer signing to prevent losing the entitlement when bundling models. Release build, Ruby/Python syntax and diff checks passed. The installed executable and signature receipt were backed up under ignored `.build/saywing-dictation/previous-microphone-fix/` before correcting its signature. No TCC database modification, permission reset or microphone recording is part of this repair.

After relaunch, the installed signature prerequisite check and deep signature verification passed. The app's live permission status subsequently changed to **Mikrofon: freigegeben** during the user's setup interaction; no recording was started. The repaired signature was treated as a changed app identity for Accessibility: **Andere Apps: Bedienungshilfen erforderlich** was shown again, requiring the owner to re-enable Saywing there. This development-signing limitation is not a microphone denial.

## Hotkey microphone crash correction — 2026-10-13

Two user-triggered installed-app crashes (20:00 and 20:01 local time) faulted on `RealtimeMessenger.mServiceQueue` in `closure #1 in MicrophoneRecorder.start()`, preceded by `swift_task_checkIsolatedSwift` / `_dispatch_assert_queue_fail`. The inline AVAudioEngine tap inherited MainActor isolation although AVAudioEngine invokes it on its audio queue.

The production tap is now created by an explicitly nonisolated factory, with an explicitly Sendable callback capturing only the lock-protected `AudioAccumulator`. PCM is consumed synchronously on the callback thread; no AppKit, MainActor state or buffer transfer to an asynchronous task is involved. The recorder's engine lifecycle remains on MainActor.

A new regression invokes the same callback from a detached background task using a real AVAudioPCMBuffer containing synthetic stereo samples. It checks exact mono conversion/sample rate and verifies that callbacks arriving after cancellation cannot retain audio or RMS. All **15** focused dictation lifecycle tests passed. The initial extraction into a returning factory already passed this test; it is not claimed as an automated reproduction of the original inline crash. The actual installed-app crash reports are the evidence for the original failure. No live microphone was recorded during these checks.

Release build and installed bundle deep signature verification passed; the Audio Input entitlement is retained. The corrected executable is installed and the setup window opened. This new ad-hoc code identity reports both microphone and Accessibility as not granted again, so real hotkey/microphone verification remains with the owner after re-granting access. The earlier executable/signature is preserved in ignored `.build/saywing-dictation/previous-audiotap-fix/`.

## Fn shortcuts and two-key reading — 2026-10-13

Owner requested Wispr-style dictation shortcuts and explicitly only two keys for reading. Primary reading default is **⌥R**; the previous ⌘⇧Y preference is migrated, while custom combinations stay intact. Fn hold/release, double-tap within 0.5 seconds, Fn+Space hands-free, short-tap discard, quick third-tap discard and Escape cancellation are implemented from the documented interaction behavior, without copying third-party code. Reference: [Wispr's first-dictation instructions](https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation). Our original-target validation, RAM-only audio and clipboard ownership safeguards remain in effect. Fn monitoring requires Accessibility, consumes only its own Fn/Space events, retains no typed text, and queues AX/microphone work outside the tap callback. Disabled monitoring cancels active Fn work. The existing ⌥⇧Space toggle remains available as an alternative. Physical Fn behavior and hardware/system-shortcut conflicts require a real keyboard walkthrough; deterministic gesture tests are not a substitute for it.

Eight new deterministic gesture/default tests cover hold/release, single-tap discard, double-tap lock, third-tap discard, Fn+Space toggle, other Fn chords, stale-release/timeout reset and migrating only the old reading default. The initial default/migration test failed before implementation. After implementation **114 Swift Testing tests across 8 suites passed** (plus the configured XCTest paths; skipped permission-dependent checks are not counted as success). One initial full-suite run hit the existing 120-ms queue-capture timeout before its first fake speech started; the subsequent full run passed unchanged. UI-test expectations were updated to Option+R/Option+J, but no physical Fn or live microphone run is implied by these results.

The Release build was installed, deep signature verification and the microphone entitlement check passed. The installed settings visibly show **Ready ⌥R**, Option selected, R selected, and Command/Shift/Control off. The dictation window visibly shows the new Fn instructions and model **Bereit**. A computer-use Option+R/Escape probe did not produce a visible selection-state change, so it is not counted as a successful native hotkey walkthrough. The new ad-hoc identity again requires microphone and Accessibility grants; the UI correctly reports **Fn nicht aktiv** until access is available. No live Fn recording was performed. Previous executable/signature backup: ignored `.build/saywing-dictation/previous-fn-shortcuts/`.

## Selectable dictation models — 2026-10-13

The dictation setup window now has a persisted **Diktiermodell** popup with
**Qwen3-ASR** and **Whisper Turbo**. A model change terminates the old process,
invalidates its callback generation and prepares the selected model automatically.
Recording/paste in progress disables selection. Launch and wake restore the choice
without opening the microphone. Errors keep the selected provider; no runtime
model download or silent fallback is permitted. Reading still uses Supertonic;
the owner's saved ⌘⇧Y and Fn dictation gestures are unchanged.

Whisper Turbo uses the pinned 4-bit MLX conversion and the existing mlx-whisper
0.4.3 runtime. Its upstream weight file is renamed byte-for-byte for the loader.
The packaging manifest records the original name and digest. Only verified files
and the OpenAI MIT / conversion Apache-2.0 notices enter the app. See
[asset provenance](research/whisper-turbo-dictation.md).

Verification completed before installation:

- New selection tests first failed to compile without `DictationModel`, then all
  **17 focused dictation lifecycle tests passed** after implementation. Coverage
  includes persisted choice, wake restoration, stale messages after switching,
  no microphone on switching, switch refusal during dictation, and no fallback.
- **10 Python protocol/manifest tests passed**, including correct manifest
  routing, unknown-model rejection, and model path containment.
- Release app target: **BUILD SUCCEEDED**. Python syntax and diff checks passed.
- Real Qwen sandbox integration: **10 checks passed** with automatic and explicit
  German/English, 48 kHz resampling, silence, malformed PCM, process cancellation
  and OS-denied network/file writes. Model load: 18.40 s; cancellation: 0.049 s.
- Real Whisper Turbo 4-bit sandbox integration: **all 10 checks passed**, including
  automatic and explicit German/English. Model load: 3.00 s; cancellation: 0.019 s.
  Full weight size and SHA-256 match the pinned upstream metadata. These timings
  are single verification runs, not a controlled model performance benchmark.
- Packaging completed with both models, deep signature verification and the
  signed Audio Input entitlement check passing. The standalone packaged runtime
  also passed **15 private-clipboard/core checks, 10 Python checks and all 10 real
  integration checks for each of Qwen and Whisper Turbo**. Temporary download chunks were
  removed after the complete SHA-256 check; the verified weights remain outside Git.
- Following the owner's explicit approval to terminate Saywing despite possible
  unsaved dictation, the verified build was installed at `/Applications/Saywing.app`.
  The prior app is retained in ignored `.build/saywing-dictation/previous-model-choice/`.
  Installed deep signature verification and Audio Input entitlement checks passed.
- Computer-use access initially timed out; resetting the computer-use connection
  restored access to the new process. This does not establish an app deadlock.
  The installed window showed Qwen ready, then switched to Whisper Turbo, displayed
  automatic loading, and became ready. The model popup was disabled during each
  demo; both German and English public demos were visibly inserted in the test field.
- After normal quit/relaunch, Whisper Turbo remained selected and loaded automatically.
  The existing Accessibility, Input Monitoring and Screen Recording entries were
  renewed for this ad-hoc build. The app subsequently reported microphone and
  Accessibility granted; its Settings preflights confirmed Screen Recording and
  Input Monitoring allowed. The saved reading shortcut still showed **Ready ⌘⇧Y**.
- Final UI: Whisper Turbo selected, **Bereit**, microphone/other-app permissions
  granted, clean test field. No live microphone or physical Fn recording test is
  implied by the public-sample checks.

Logs/results are in ignored `.build/saywing-dictation/verification/`.

## Whisper Large v3 and on-demand model installs — 2026-10-14

Owner requests: add Whisper Large v3 (8-bit), bundle only Whisper Turbo by default
and let users install Qwen3-ASR or Whisper Large v3 explicitly from Settings. The
owner approved the runtime download exception (pinned Hugging Face revision,
SHA-256-verified, only after confirmation). The owner's own installation keeps all
three models bundled. Sources and checks for the new model:
[Whisper Large v3](research/whisper-large-v3-dictation.md); design: architecture
"Modelle bei Bedarf installieren", privacy "Netzwerkzugriffe".

Verification on the development Mac (M4, 16 GB):

- New Swift tests first failed (missing model case/store), then passed: default
  Whisper Turbo, uninstalled models cannot be selected or started, a saved missing
  choice is kept but not started, install → verify → atomic move, hash mismatch and
  cancellation leave nothing behind, leftover staging is removed, redirects only to
  Hugging Face over HTTPS, an installed model is selected and started with its
  model root and no microphone. Full app suite: **159 tests in 11 suites passed**
  (two permission-dependent XCTest checks skipped; the opt-in live test is disabled
  without its environment variable).
- Python worker: **12 tests passed**, including `--model-root` with the bundled manifest
  and rejection of a modified installed file.
- Opt-in live test (`TEST_RUNNER_SAYWING_LIVE_MODEL_INSTALL`) installed the real
  Whisper Large v3 from Hugging Face through `URLSessionModelFetcher` in 360 s; every
  file matched its pinned SHA-256. The sandboxed worker then passed all **10 real
  offline checks** with `--model-root` pointing at that download (load 3.4 s). The
  temporary 1.6 GB copy was deleted afterwards.
- Default package (Turbo only, 2.4 GB): 15 core, 12 Python and 10 Whisper Turbo
  checks passed. Owner package (all three, 4.9 GB): 15 core, 12 Python and 10 real
  checks for each of Whisper Turbo, Qwen3-ASR and Whisper Large v3 passed.
- Installed at `/Applications/Saywing.app` after a normal quit; the previous app is
  retained in ignored `.build/saywing-dictation/previous-model-downloads/`. Deep
  signature and Audio Input entitlement checks passed. After launch the bundled
  Whisper Turbo worker started automatically (saved choice `whisper-turbo`).

After rebasing onto main with the dictation vocabulary (PR #4): **161 app tests in
11 suites** and **19 Python worker tests** passed; the merged worker passed all
**12 real offline checks** (including vocabulary) for Whisper Turbo, Qwen3-ASR and
Whisper Large v3, the latter loaded via `--model-root` from the verified download.
The counts above were recorded before that rebase.

Not verified: the install entries, confirmation dialog and progress row were not
inspected visually (the owner build bundles every model, so no install entry is
shown there); behaviour is covered by the controller/store tests above. No live
microphone recording. The new ad-hoc signature may require re-granting microphone,
Accessibility, Screen Recording and Input Monitoring.
