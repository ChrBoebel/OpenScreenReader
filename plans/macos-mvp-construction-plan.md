# OpenScreenReader macOS MVP construction plan

Status: approved for staged execution
Scope: native Swift/AppKit macOS MVP, with a bundled local TTS model and Windows-ready boundaries
Execution mode: direct local changes; no commits, pushes, releases, or model downloads without explicit owner approval

## Execution log

- 2026-09-04: source-of-truth documents and ADRs were reconciled with the native Swift, bundled-model, no-runtime-network, macOS 14, Apple Silicon, and single-display-drag decisions.
- 2026-09-04: SwiftPM foundation created with `OpenScreenReaderCore` and a dependency-free behavior-check executable.
- 2026-09-04: the coordinator foundation passed eleven behavior checks and a production build. It covers generation and worker-epoch validity, legal forward transitions, cancellation from every active phase, 500 repeated cancellation cycles, atomic revocation, deterministic cleanup instructions, a cleanup barrier before replacement starts, atomic publication of replacement epochs, supersession, and exactly-once terminal acceptance. Adapter-level task and resource cancellation remains for the corresponding integration gates.
- 2026-09-04: Xcode 26.6 and its license were validated without changing the global developer directory. A native macOS 14 menu-bar-only app target, shared scheme, local `OpenScreenReaderCore` dependency, settings scene, and hosted Swift Testing target now build. App tests verify the status contract, idle coordinator, and `LSUIElement` bundle policy.
- 2026-09-04: the native menu-bar shell passed an XCUITest smoke test covering its accessible status item, menu, settings entry, and cancellation entry point. Step 1 is complete.
- 2026-09-04: the first Step 3 slice added a fixed global `⌃⌥R` hotkey, conflict reporting, one overlay panel per active display, display-local drag selection, Retina/global-coordinate conversion, invalid-rectangle rejection, display-change cancellation, and stale-callback protection. Native UI tests exercise menu invocation, drag completion, local `Esc`, and repeated-hotkey cancellation from Finder.
- Current gap: Step 3 remains open. Shortcut reconfiguration, rotated-display coverage, the bare-global-`Esc` permission spike after the overlay closes, VoiceOver review, and the physical multi-monitor/secure-input permission matrix are still pending. Computer Use can inspect ordinary app windows, but its current bridge cannot attach to this intentionally windowless `LSUIElement` menu-bar surface; native XCUITests provide the automated interaction evidence for this slice.

## Outcome

Deliver a signed and notarized Apple Silicon macOS menu bar app whose complete user flow is:

```text
global hotkey
  -> drag a screen region
  -> capture only that region
  -> recognize German/English text locally
  -> stream natural local speech automatically
  -> stop the entire active pipeline with Esc or the repeated hotkey
```

The public installer should contain the selected TTS model so the first successful use does not require a separate model decision or download. Model weights remain outside Git and are injected reproducibly into the signed release payload from a pinned, hashed source.

## Non-negotiable acceptance rules

- No cloud OCR, cloud TTS, silent fallback, account, or default telemetry.
- No persistent screenshot, recognized-text, or generated-audio history.
- No automatic clipboard writes.
- Every asynchronous stage carries an operation generation ID and supports cancellation.
- Results and audio from stale generations are discarded.
- Cancellation atomically revokes the active generation before any asynchronous stop work begins.
- All result delivery passes through one serialized generation/worker-epoch gate.
- `Esc` and the repeated global hotkey stop selection, capture/OCR work, synthesis, queued chunks, and playback.
- The app captures only the selected region and excludes its own overlay and cursor.
- The app remains usable with VoiceOver labels and keyboard navigation.
- Tests and a build must pass at every gate before the next dependent step begins.
- Real limitations are reported; mocked results never replace a blocked real-device check.

## Model packaging decision

Confirmed product choice: ship `Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit` with the macOS release if it passes the release gates. The currently published MLX conversion reports an approximately 1.69 GB payload and Apache-2.0 licensing, but neither `main` nor an unpinned download is acceptable for a release.

Before bundling, the release process must record:

- upstream and converted model repositories;
- exact immutable revisions;
- every shipped filename and SHA-256 hash;
- compressed and installed size;
- model, conversion, runtime, tokenizer, and voice licenses;
- the exact runtime version used to load the model;
- redistribution notices and source links.

The weights must not be committed to Git. A release-only staging task downloads the pinned artifacts with explicit approval, validates their hashes, and copies them into the app bundle or installer staging directory before signing. Development and CI use a fake provider and tiny licensed fixtures.

Gate M tests the preferred MVP layout: model under the signed app's `Contents/Resources/Models` directory, producing a single self-contained app in a DMG. If bundle size, notarization, updates, or runtime access make that layout impractical, Gate M blocks and the owner chooses a separately planned delivery policy. A PKG is not an automatic fallback because it introduces its own admin, path, ACL, atomic-install, upgrade, and uninstall requirements.

The provider and model-manager interfaces must still support external models later. Bundling is a release policy, not a permanent architectural coupling.

The owner confirmed the bundled-model choice, and the README, product vision, privacy requirements, architecture, UX requirements, and roadmap now share that MVP policy. The MVP runtime makes no model-download or update-check network requests; update delivery is deferred until a separately approved network and signing design exists.

## Dependency graph

```text
0 Foundation/toolchain
  -> 1 App shell
  -> 2 Pipeline state machine and privacy canaries
       -> Track A: 3 Hotkey/selection -> 4 Region capture -> 5 OCR/text
       -> Track B: 6 Audio/contracts -> 7 Worker protocol -> 8 M0 -> P -> M1

Track A step 5 + Track B Gate M1
  -> 9 End-to-end UX
  -> 10 Privacy, accessibility, and performance qualification
  -> 11 Signed release and clean-machine install

Steps 3-5 and 6-8 are independent after their shared coordinator and data contracts exist.
Step 9 may not begin until both tracks pass.
Windows research may proceed independently, but Windows product code starts only after Gate M1 proves a viable macOS TTS package.
```

## Universal verification loop

Every implementation step follows the same loop:

1. Add or update a failing test for the observable behavior.
2. Implement the smallest behavior that makes it pass.
3. Run the focused test.
4. Run the full test suite.
5. Run a Debug build of the affected app and worker targets.
6. Exercise the affected user-visible flow when permissions and hardware allow it.
7. Record measured output, known gaps, and any plan change before proceeding.

Expected baseline commands once the Xcode project exists:

```sh
xcodebuild test -scheme OpenScreenReader -destination 'platform=macOS'
xcodebuild build -scheme OpenScreenReader -configuration Debug -destination 'platform=macOS'
```

Release-specific checks are introduced in steps 8 and 11. Commands must be adjusted to the actual generated project and scheme rather than reported as successful before they exist.

## Step 0 - Resolve foundations and make the toolchain executable

Context: the repository currently contains plans and product documentation only. Swift 6.2 is installed, but the active developer directory points at Command Line Tools and `xcodebuild` cannot currently run.

Tasks:

- Install or select a full compatible Xcode installation.
- Confirm the bundle identifier, minimum macOS version, Apple Silicon baseline, and supported-memory baseline.
- Choose an Xcode application project with local Swift packages only where they create a real testable boundary.
- Decide the Developer ID owner shown to users and the direct-download release domain.
- Confirm access to the Developer ID, Team ID, signing certificate, and notarization credentials needed for early packaging spikes; keep all credentials outside the repository.
- Create short architecture decisions for project layout, cancellation semantics, worker boundary, and bundled-model policy.
- Reconcile every source-of-truth document with the confirmed bundled-model policy and its zero-runtime-download consequence.
- Decide and document the MVP multi-monitor contract: recommended default is selection on any connected display while constraining one drag to its start display; cross-display stitching is a later feature unless explicitly approved now.
- Define a language-neutral canonical model ID distinct from a macOS MLX artifact ID so a later Windows provider can implement the same product model independently.
- Define test fixtures that contain no private screenshots, copyrighted customer material, or generated model output requiring redistribution review.
- Define a release dependency policy: optional dependency groups are never installed wholesale; only packages proven necessary for the selected Qwen execution path may enter the bundle.

Verification:

- `xcodebuild -version` succeeds.
- A minimal Swift command or test target builds with the selected Xcode.
- All decisions are explicit and consistent with the product, privacy, and UX documents.

Exit criteria: there are no unresolved choices that would change the initial project structure, supported deployment target, model delivery policy, or multi-monitor capture contract.

Rollback: documentation-only; revise decisions before scaffolding code.

## Step 1 - Create the native menu bar shell

Context: OpenScreenReader must feel like a small macOS system utility and must not open a permanent main window.

Tasks:

- Create the Xcode project and `OpenScreenReader` app target.
- Add a SwiftUI menu bar scene and settings scene; use AppKit only where SwiftUI is insufficient.
- Configure a menu-bar-only application without an ordinary Dock presence.
- Add basic states and labels: Ready, Selecting, Recognizing, Speaking, Stopped, and actionable Error.
- Add unit, launch, and minimal UI smoke tests.

Verification:

- Unit and UI smoke tests pass.
- Debug and Release configurations build.
- The app launches as a menu bar utility and quits cleanly without a main window.
- Menu items and controls have VoiceOver-readable labels.

Exit criteria: a stable native shell exists with no capture, OCR, or TTS implementation hidden inside it.

Rollback: remove only the generated app target and project files; documentation remains valid.

## Step 2 - Build the cancellable pipeline state machine first

Context: cancellation is a product invariant, not cleanup to add after integration. All later services must plug into one operation coordinator.

Tasks:

- Define explicit pipeline states and legal transitions.
- Assign a monotonically increasing generation ID to each start request.
- Represent the active generation separately from the last issued ID; cancel atomically clears/revokes the active generation even when no replacement request starts.
- Define cancellation ownership for selection, capture, OCR, segmentation, TTS, audio queue, and playback.
- Route callbacks, buffers, statuses, and errors through one serialized result gate that validates active generation and worker process epoch.
- Make a repeated hotkey equivalent to cancel while a generation is active.
- Define cancel ordering: revoke generation; silence audio and dismiss overlay; cancel cooperative Swift/OS tasks; send worker cancellation; enforce a short acknowledgement deadline; kill and replace a non-cooperative worker.
- Use deterministic fakes to test races and out-of-order completion.
- Introduce privacy canaries for filesystem writes, clipboard contents, log redaction, and unexpected network access; extend them at every later gate.

Verification:

- Tests cover cancellation in every state.
- Tests prove a new request supersedes an old request.
- Tests prove delayed stale OCR and TTS callbacks cannot restart playback or alter current status.
- Tests prove callbacks arriving after cancel but before any new start are rejected.
- Tests prove output from a terminated worker epoch is rejected even if an operation ID is reused or malformed.
- Tests cover a non-cooperative task and worker that ignore cancellation.
- A cancellation-storm test leaves the coordinator idle without leaked tasks.
- Tests prove every generation emits at most one terminal state.
- Canary tests establish the baseline for no content persistence, clipboard mutation, content logging, or undeclared network activity.

Exit criteria: every future asynchronous module has a defined cancellable contract and stale-result rule. Cancellation guarantees immediate loss of observable effect; underlying Apple/ML compute may finish later if its API is non-cooperative, but its output can no longer reach status, logs, queues, or audio.

Rollback: contracts are isolated from platform services and can be replaced without touching UI or model code.

## Step 3 - Add global hotkey, global cancellation input, and multi-monitor selection

Context: the primary interaction must work while another application has focus and on displays with different scale factors. The repeated hotkey can be globally registered, but receiving bare `Esc` while OCR/TTS runs in the background may require Input Monitoring or Accessibility permission. This must be proven early rather than discovered during release onboarding.

Tasks:

- Implement configurable global-hotkey registration and conflict reporting.
- Build an AppKit overlay/panel per active display.
- Implement drag selection, coordinate conversion, zero-area rejection, and the approved single-display or cross-display contract.
- Make `Esc` and the repeated hotkey cancel selection immediately.
- Spike a narrowly scoped CGEventTap/global event-monitor path for `Esc` after the overlay closes; activate it only while a generation is cancellable and tear it down immediately afterward.
- Test whether the global `Esc` path requires Input Monitoring or Accessibility on minimum/current macOS, and document secure-input limitations, denial, revocation, and remediation UX.
- Ensure overlays disappear before capture begins.

Verification:

- Unit tests cover coordinate conversion, negative display origins, Retina scaling, rotation, display reconfiguration, and invalid rectangles.
- Integration tests cover hotkey registration success, conflict, reconfiguration, and cancellation.
- Manual matrix: one display, two displays, mixed scaling, rotation, display left/right/above primary, keyboard-only cancel, secure input, and permission denial/revocation.
- VoiceOver does not get trapped in or confused by the transient overlay.

Exit criteria (Gate E): selection produces one topology-aware capture request or a clean cancellation, never both; global `Esc` behavior and its permission cost are measured and owner-approved. If the permission cost is unacceptable, amend the global-`Esc` invariant before dependent integration continues; the repeated hotkey remains the permission-minimizing global cancel path.

Rollback: hotkey and overlay are separate adapters behind coordinator protocols.

## Step 4 - Capture only the selected region

Context: capture scope is both a privacy boundary and a correctness requirement.

Tasks:

- Implement ScreenCaptureKit region capture with an explicit source rectangle.
- Carry display identity, topology revision, logical-point rectangle, backing-pixel rectangle, and scale through the capture request. Reject or recompute when topology changes mid-selection.
- If cross-display selection is approved, split the logical rectangle into per-display intersections, capture each display-local source rectangle, and stitch deterministically before OCR; never pass a global rectangle directly as one display-local `sourceRect`.
- Exclude the app's overlay/windows and cursor.
- Request Screen Recording permission only when capture is first invoked.
- Normalize output dimensions and color representation for Vision without writing an image file.
- Release image memory after OCR consumes it.

Verification:

- Unit tests validate region math and pixel dimensions with injected display metadata, including rotation and topology changes.
- Image comparison tests confirm the selected boundaries and absence of overlay/cursor fixtures.
- A denied-permission test produces an actionable message and no retry loop.
- Manual tests inspect multi-monitor edges and mixed scaling.
- A filesystem check confirms no screenshots or temporary images are created.

Exit criteria: one in-memory image containing only the requested region is delivered to OCR.

Rollback: fall back from newer screenshot APIs to another documented local Apple capture API only through the same service contract.

## Step 5 - Implement Vision OCR and a fidelity-first text pipeline

Context: German and English OCR must preserve meaning, especially for numbers, money, dates, URLs, email addresses, identifiers, and mixed-language text.

Tasks:

- Implement local Vision text recognition with explicit supported-language handling.
- Define deterministic reading-order behavior for paragraphs and simple columns.
- Build normalization and sentence segmentation as pure tested transformations.
- Store OCR inputs and expected normalized/segmented outputs as portable JSON test vectors with platform-neutral coordinates and Unicode normalization rules for later Windows reuse.
- Add a fidelity mode that avoids unsafe rewriting.
- Treat empty or unreadable OCR as a non-speaking result with helpful feedback.

Verification:

- Golden-image tests cover German, English, mixed language, two columns, punctuation, hyphenation, URLs, email, prices, dates, and product codes.
- Pure text tests cover normalization and segmentation edge cases.
- Tests prove no TTS request is created for empty output.
- Real Vision tests run on committed synthetic/licensed fixtures, not mocked OCR results alone.

Exit criteria: OCR output is stable enough to feed a fake voice without silent semantic changes.

Rollback: reading-order and normalization strategies remain replaceable pure components.

## Step 6 - Implement audio playback and provider-neutral TTS contracts

Context: playback must begin from streamed chunks and become silent within the stated cancellation target.

Tasks:

- Define `TTSProvider` capabilities, load/unload, streaming, cancellation, health, metadata, and license reporting.
- Keep the public provider contract platform-neutral: canonical model ID, language/voice capabilities, explicit PCM format, bounded chunk sizes, stable error codes, cancellation acknowledgement, and process epoch.
- Implement an AVFoundation playback controller for queued PCM chunks.
- Attach generation IDs to every chunk.
- Add a deterministic fake provider that streams generated test tones or licensed tiny fixtures.
- Instrument first-chunk latency and cancel-to-silence latency.

Verification:

- Tests cover chunk order, backpressure, underrun, provider failure, cancellation, and stale chunks.
- Automated timing tests use tolerances appropriate for CI; hardware acceptance uses measured real time.
- Repeated start/stop tests do not leak buffers or play old audio.
- Debug build demonstrates streaming playback without Qwen.

Exit criteria: the complete pipeline works with a fake TTS provider and can be stopped reliably.

Rollback: audio and provider contracts do not depend on Python, MLX, or a particular model.

## Step 7 - Define and prove the local worker protocol

Context: the Python/MLX worker is a hypothesis. The protocol must be proven before the model and runtime are embedded into the product.

Tasks:

- Define a versioned language-neutral wire schema for readiness, model load/unload, synthesis, streamed chunks, cancel acknowledgement, health, and shutdown.
- Specify PCM sample type, sample rate, channels, byte order, framing, maximum message/chunk sizes, stable errors, timeouts, request generation, and worker process epoch.
- Bind communication locally only; prefer pipes or another interface that cannot listen on an external network address.
- Validate request IDs, message sizes, audio formats, timeouts, and process ownership.
- Send OCR text in framed standard input/IPC messages only, never in process arguments or environment variables.
- Implement worker crash detection and restart without crashing the menu bar app.
- Build a fake executable worker for deterministic integration tests.

Verification:

- Contract tests run the same cases against in-process and executable fakes.
- Tests cover malformed frames, truncated output, timeout, crash, cancellation race, and stale chunks.
- Portable JSON protocol vectors are consumable by a future non-Swift Windows implementation.
- Network observation confirms the fake worker opens no external listener.
- Parent exit and explicit shutdown leave no orphan worker process.

Exit criteria: Swift-to-worker streaming and cancellation are reliable without involving model behavior.

Rollback: the versioned contract permits replacing the process transport or embedding MLX directly.

## Step 8 - Run the real Qwen, runtime, and bundled-model spike

Context: this is the decisive architecture and distribution gate. Do not turn the prototype runtime into production architecture until packaging, signing, latency, memory, cancellation, offline operation, and licenses are proven together.

Run three ordered sub-gates:

- Gate M0 - provenance and license: approve exact sources, immutable revisions, expected sizes/hashes when available, lockfile, dependency closure, SBOM plan, voice rights, and the absence of unapproved GPL/AGPL components before any weight download.
- Gate P - packaging: build the smallest hermetic embedded CPython/MLX worker without the full model, then sign, notarize, browser-download, quarantine, and run it on a clean supported Mac.
- Gate M1 - model qualification: only after M0 and P pass, stage the approved weights and test real quality, fidelity, latency, cancellation, memory, privacy, and offline behavior in the self-contained DMG.

Tasks:

- Pin the exact Qwen model conversion, tokenizer, MLX, mlx-audio, Python, and all native runtime dependencies.
- Produce the complete artifact/hash/license manifest and SBOM before downloading or redistributing weights.
- Do not accept a repository license label alone: archive exact-revision license texts and source cards, verify every file against an allowlist and SHA-256, identify the upstream revision and conversion command, and either reproduce the MLX conversion internally or record an explicit provenance-risk acceptance.
- Decide and document redistribution and user rights for the shipped default voice, not only the base model weights.
- Resolve the known phonemizer licensing hazard before integration: mlx-audio v0.3.0's broad TTS extras include `espeakng-loader`, while eSpeak NG is GPL-3.0-or-later. Prove that the selected Qwen path excludes it, replace that path with a compatible component, or obtain an explicit project-level GPL decision; never ship it accidentally through an extras install.
- Generate a fully pinned lockfile before the first approved artifact download. Model name and reported aggregate size are not provenance because published conversion contents have changed between revisions.
- Compare a bundled Python/MLX worker with a more directly embedded MLX/Swift path where practical.
- Measure cold start, warm first chunk, sustained synthesis, peak memory, energy, cancel latency, and unload behavior.
- Build a German/English fidelity corpus covering numbers, dates, currencies, URLs, email addresses, abbreviations, names, identifiers, mixed language, and long sentences.
- Run a blinded listening comparison against selected Apple system voices; define acceptance thresholds for naturalness, intelligibility, omissions/substitutions, and the default Qwen speaker before adopting the model.
- Stage the approximately 1.69 GB candidate model outside Git and test the self-contained app/DMG layout from Gate M.
- Build a hermetic runtime containing its own pinned interpreter/runtime and wheels; it must not depend on system Python, Homebrew, user site-packages, environment variables, or runtime package/model downloads.
- Start embedded Python in isolated mode, disable user-site imports and bytecode writes, place Mach-O code only in standard executable/framework bundle locations, and keep scripts/models in Resources.
- Verify architecture slices, deployment targets, code signatures, and runtime search paths for every native binary; reject dependencies on `/opt/homebrew`, `/usr/local`, the build working directory, or user-specific paths.
- Disable bytecode generation and inventory all cache, temporary-file, log, and crash paths during startup, load, synthesis, failure, cancellation, and crash. Audio generation remains in memory.
- Sign every executable and nested native library, assemble the candidate DMG, notarize it, and test offline.
- Sign nested Mach-O files from the inside out with minimal entitlements, avoid JIT or disabled-library-validation exceptions unless a measured runtime need is documented, inspect the complete notary log even on success, and verify that Distribution contains no fake provider, test fixture, diagnostic content, or developer path.
- Decide the warm-model retention policy from measurements rather than preference.

Verification:

- Repeated benchmark runs report distributions, hardware, OS, versions, input text, and methodology.
- Warm first-audio target is evaluated against 500 ms; cancel-to-silence against 100 ms.
- German/English fidelity and blinded naturalness thresholds pass with the selected default speaker; latency alone cannot pass Gate M.
- Network monitoring shows no connection during OCR or synthesis.
- Hash verification fails closed after intentional corruption.
- The packaged build runs on a clean supported Mac without a development environment.
- License review explicitly approves redistribution of every shipped component.
- Fresh-user canaries show no Python bytecode, model cache, screenshot, OCR text, audio, or content-bearing crash/log residue.

Exit criteria (Gate M): owner accepts one measured implementation and the self-contained DMG layout. If it does not pass, stop and revise the model/runtime or delivery decision rather than silently switching installers or building the MVP on an unproven worker.

Rollback: remove staged artifacts; no weights live in Git. Provider contracts and fake end-to-end flow remain usable.

## Step 9 - Integrate the real end-to-end user experience

Context: only after Gate M passes should the real provider become the default application flow.

Tasks:

- Connect hotkey, overlay, region capture, OCR, segmentation, real TTS streaming, and playback through the coordinator.
- Add concise permission onboarding and model/license information without asking the user to choose a model.
- Add settings for hotkey, bundled voice, speed, and model warm/unload policy.
- Keep active feedback small and non-modal.
- Make every error actionable without exposing screen text in logs.

Verification:

- End-to-end automation uses injected capture/OCR/TTS fakes for deterministic state assertions.
- Real manual flow covers PDFs, browsers, presentations, chat, images, and video frames.
- Cancellation is exercised during selection, OCR, first synthesis, later synthesis, and playback.
- Relaunch works offline with the bundled model.

Exit criteria: representative users can complete select-to-listen and stop without setup knowledge or extra model decisions.

Rollback: a feature flag can select the fake provider in development without shipping it as a silent runtime fallback.

## Step 10 - Qualify privacy, accessibility, performance, and resilience

Context: these are release-blocking behaviors, not documentation polish.

Tasks:

- Build an automated privacy harness for filesystem, clipboard, logs, and declared network events.
- Extend the canaries introduced in step 2 and run them against startup, model load, success, failure, cancel, worker crash/restart, and app crash with fresh user/cache state and network denied.
- Audit crash/error reporting paths for screenshot, OCR text, and audio leakage.
- Run VoiceOver and keyboard-only audits for menu, settings, permission onboarding, status, and errors.
- Run soak, rapid-cancel, low-disk, low-memory, worker-crash, sleep/wake, display-change, and permission-revocation scenarios.
- Measure cold/warm latency, memory, and energy on every supported hardware tier.

Verification:

- No persistent user content or automatic clipboard mutation is observed.
- Offline operation succeeds after installation.
- Accessibility findings have tests where automatable and recorded manual evidence otherwise.
- Performance claims are based on repeated packaged-build measurements.

Exit criteria: every present-tense privacy and performance claim has corresponding evidence or is removed from release copy.

Rollback: disable or narrow unsupported behavior; never weaken privacy defaults to pass a release gate.

## Step 11 - Produce and test the direct-download release

Context: the target experience is a professional download from the project website, independent of the Mac App Store.

Tasks:

- Build the Developer ID-signed, hardened, notarized, and stapled self-contained DMG accepted at Gate M.
- Include the bundled model, third-party notices, model manifest, licenses, and privacy documentation.
- Host the artifact over HTTPS with version, size, minimum requirements, and SHA-256 shown on the download page.
- Do not include an automatic update check in the MVP. A later updater requires a separate owner-approved network, privacy, signature, rollback, and threat-model workstream.
- Test download, browser quarantine, first launch, permissions, first speech, offline relaunch, manual upgrade, and uninstall on clean supported Macs.
- Prepare a rollback artifact and release checklist before any public release.

Verification:

- `codesign --verify --deep --strict --verbose=2` succeeds on the shipped app.
- `spctl --assess --type execute --verbose=4` accepts the installed app.
- `xcrun stapler validate` succeeds for the distributable container where supported.
- Gatekeeper shows an identified/notarized application rather than an unidentified-developer failure.
- The app works with the network disabled and does not require Xcode, Python, Homebrew, or command-line tools.
- The clean-machine matrix covers minimum/current macOS, minimum M-series/RAM tier, fresh/denied/revoked permissions, low disk, browser quarantine, stapled offline first launch, physical audio/MLX execution, manual upgrade, and uninstall.
- A mandatory clean-machine scenario that cannot be executed blocks the gate; it is not replaced by a mock or silently skipped.

Exit criteria: a nontechnical tester installs from the website and completes first speech using only the instructions visible in the product.

Rollback: withdraw the artifact from the website and restore the last notarized build; do not silently replace a file at the same versioned URL.

## Windows-ready follow-up

Swift is the macOS implementation choice. Cross-platform readiness comes from contracts and test vectors, not from forcing the UI into Electron.

Starting in step 0 and continuing through Gate M:

- preserve a language-neutral versioned worker protocol and portable OCR/text/TTS fixtures;
- keep canonical product model IDs separate from platform artifacts such as an MLX conversion;
- specify PCM byte order/framing, bounded messages, stable errors, cancellation acknowledgement, and worker epochs independently of Swift types;

After Gate M:

- spike Windows region capture, OCR coverage, global hotkey behavior, audio streaming, and Qwen performance;
- select a Windows inference runtime from measured CPU/GPU/NPU coverage;
- implement a native Windows shell only after defining supported hardware;
- ship a separately signed Windows installer from the same website.

No macOS framework type may leak into shared protocol messages or behavior specifications.

## Parallel work opportunities

- After step 2: coordinate-math tests for step 3 and synthetic OCR fixtures for step 5 are independent.
- After provider contracts stabilize: AVFoundation playback (step 6) and fake executable worker (step 7) can be developed independently.
- During step 8: license/provenance review, benchmark harness work, and signing experiments can proceed independently, but Gate M requires all results together.
- Release website work can begin during step 10, but it must not publish an artifact or unverified claims before step 11 passes.

## Plan mutation protocol

When evidence changes the plan:

1. Record the failed assumption and actual measurement.
2. Identify affected steps and acceptance criteria.
3. Amend this plan and the relevant architecture/privacy decision before implementation continues.
4. Re-run all gates whose assumptions changed.
5. Do not mark a skipped gate as passed; label it blocked, replaced, or intentionally removed with owner approval.

### Mutation 2026-09-04: start the portable coordinator before the app shell

- Failed assumption: a full Xcode installation would be available when execution began; only Swift 6.2 Command Line Tools are currently installed.
- Change: create and test the platform-neutral `OpenScreenReaderCore` Swift package and its cancellation/result-validity coordinator while step 1's native app target waits for Xcode.
- Dependency effect: after step 0 documentation decisions, step 1 (native shell) and the platform-neutral portion of step 2 may proceed independently. Platform integration still requires step 1, and neither step is considered fully passed until `xcodebuild` runs the integrated scheme.
- Verification: `swift test` and `swift build` are real interim gates; they do not substitute for the required Xcode app build or UI tests.

## Known early risks

- The global developer directory still points at Command Line Tools; native build and test commands must explicitly select the installed Xcode toolchain unless the owner changes that system setting.
- Bundling roughly 1.69 GB of model data increases download size, notarization work, and potentially update bandwidth.
- The model page reports Apache-2.0, but the conversion provenance, default-voice rights, exact-revision license files, and complete runtime/tokenizer dependency chain still require verification.
- A Python worker may require complex nested signing and runtime entitlements.
- Global bare-`Esc` cancellation outside the active overlay may require Input Monitoring or Accessibility permission and can be affected by secure input.
- Screen Recording permission and first-open confirmation cannot be eliminated by the implementation language.
- The under-100-ms cancellation target must be measured through real synthesis and audio hardware, not inferred from unit tests.
- Windows will require separate capture/OCR integration and probably a separately validated TTS runtime.
