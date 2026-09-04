# Native Qwen development runtime — 2026-09-05

This is a local development experiment, not the signed/bundled MVP or a release approval. The owner approved model and runtime installation for evaluation. No Python environment, eSpeak dependency, system-voice fallback, cloud inference, or new macOS permission is introduced.

## Pinned source and dependency boundary

The source is [mlx-audio-swift at bf14ae0c26e4e85553dd989571cae29d70fa6735](https://github.com/Blaizzy/mlx-audio-swift/tree/bf14ae0c26e4e85553dd989571cae29d70fa6735), MIT, copyright 2025 Prince Canuma. Its codeload tar.gz SHA-256 is `086e188dc8e4957c34ee703a130e4b7accc70049c0ef65cd7e7cc8ed590c8bbc`.

The full upstream package is **not** used. Its Swift Hugging Face dependency pulls `swift-xet` 0.2.3 (`341bfd4172f6a57119bfd49bafa11cf5d21fab75`), whose checked-out source contains no license file or license declaration in its README/source. That dependency is excluded rather than assumed to be MIT. The final runtime package has no `swift-huggingface`, Xet, HTTP client, general model downloader, or G2P target.

`scripts/prepare-runtime.rb` checks the entire upstream archive hash, copies only Qwen3TTS, its Mimi codec primitives, DSP, and generation types into the ignored `Runtime/.generated` directory, and retains the MIT notice. Its mechanical modifications to `Qwen3TTS.swift` remove the remote loader, automatic tokenizer writing, and destructive cache deletion. The tokenizer conversion is exposed solely for explicit install-time preparation. It does not change the model math or claim compatibility before a real run. Modified source is reconstructible from the script and pinned archive; no weights enter Git.

The Tokenizers product still depends on swift-transformers' `Hub` module for configuration parsing. The local loader uses an explicit offline `HubApi` with an empty credential, avoiding its default cached-token lookup; its local-folder path never invokes snapshot downloading. The OS network deny rule applies even to linked helpers. This is not a claim that all third-party network-related code was removed from the binary.

`Runtime/Package.resolved` records the exact repository revisions. The selected package closure is:

| Package | Version | Declared license |
| --- | --- | --- |
| mlx-swift | 0.31.4 | MIT |
| mlx-swift-lm | 3.31.4 | MIT |
| swift-transformers | 1.1.9 | Apache-2.0 |
| swift-jinja | 2.4.2 | Apache-2.0 |
| swift-collections | 1.6.0 | Apache-2.0 with runtime exception |
| swift-crypto | 4.5.2 | Apache-2.0 |
| swift-asn1 | 1.7.2 | Apache-2.0; resolved but not selected by macOS Crypto |
| swift-numerics | 1.1.1 | Apache-2.0 with runtime exception |
| swift-syntax | 603.0.2 | Apache-2.0 with runtime exception; resolved, no macro target selected |
| yyjson | 0.12.0 | MIT |

The Apache terms were compared against the repository's complete Apache-2.0 text after whitespace normalization; all seven Apache packages match sections 1–9. MLX additionally vendors MLX (Apple MIT), mlx-c (MIT), nlohmann/json (MIT), fmt (MIT with optional object-code exception), metal-cpp (Apache-2.0), and PocketFFT (BSD-3-Clause, recorded in MLX's acknowledgements). Swift Crypto's selected macOS `Crypto` target uses CryptoKit, not its conditional BoringSSL/XKCP targets; do not generalize this closure to Linux or CryptoExtras. `scripts/runtime-notices.rb` verifies checkout revisions against the lock and collects 21 license/notice/acknowledgement files plus the Qwen subset's MIT license. Public redistribution still requires the final artifact/SBOM, model conversion provenance, voice-rights, signing, and packaging review described in ADR 0003.

## Execution design

- One disposable native worker per reading; model reuse across sentences, not across separate screen selections. Warm-start performance is not claimed.
- Text enters over an anonymous pipe, never command-line arguments, a socket, clipboard, or file. PCM exits as bounded JSON/base64 packets with an acknowledgement after admission to the bounded playback queue (originally after playback; corrected below). Tokens and upstream diagnostics are not exported.
- Local model-directory loading only. The app launches the worker under a development Seatbelt profile denying network access and file writes except `/dev/null`. This is additional containment, not a production sandbox/notarization solution.
- Audio is played in memory with AVAudioEngine. Cancellation silences the player before awaiting coordinator transitions and kills the disposable child. Both operation-context and playback-generation guards reject late results.
- Separate startup (90 seconds) and audio-progress (30 seconds) timeouts replace the capture/OCR timer after recognition. The prototype limits a selection to 8,000 characters and segments long sentences; token-limit exhaustion is an error, not successful completion.
- Default evaluation preset: Serena; German/English language detection per segment. No voice cloning. Other-language quality is not asserted.

## Reproduction

Start from the separately verified model download. These are explicit developer operations, not commands called by the app. Xcode and Apple's Metal Toolchain are build prerequisites. On this Mac the missing 687.9 MB Metal Toolchain 17F109 was installed using Apple's documented `xcodebuild -downloadComponent MetalToolchain` command; the tool reported completion. See [Apple's component-installation documentation](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components).

1. Download the pinned source tar.gz from `https://codeload.github.com/Blaizzy/mlx-audio-swift/tar.gz/bf14ae0c26e4e85553dd989571cae29d70fa6735` to a temporary directory outside Git.
2. Run `ruby scripts/prepare-runtime.rb /absolute/path/to/archive.tar.gz`. Existing generated source is not overwritten; the script refuses an unexpected archive hash or patch context.
3. In `Runtime`, run `swift package resolve --force-resolved-versions`, then `xcodebuild -scheme OpenScreenReaderSpeechRuntime -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /absolute/build/directory -disableAutomaticPackageResolution -jobs 4 CODE_SIGN_IDENTITY=- build`. Use the intended Xcode through `DEVELOPER_DIR`. A command-line `swift build` checks Swift/C++ but does **not** compile the Metal resource bundle.
4. Run the built worker once with `--prepare-tokenizer /absolute/model/directory`. This converts public model metadata into `tokenizer.json`, not user content. The generated file is 4,762,740 bytes with SHA-256 `39c94a2d71ba8b0d33757e052581c63feaca79f7639421baedd595493d4fccc3`.
5. From the repository, run `ruby scripts/runtime-notices.rb`, then `ruby scripts/install-development-runtime.rb /absolute/build/directory/Build/Products/Release`. The installer verifies all original model files and the derived tokenizer, refuses to replace an existing runtime, and stages the executable, resource bundles, lock, notices, and an SHA-256 installation receipt. The installed runtime occupies approximately 32 MiB, separately from the 1.69 GB model.
6. Run `ruby scripts/verify-speech-worker.rb /absolute/installed/worker /absolute/model/directory`. This uses a fixed German test sentence, validates finite, non-silent PCM and completion, and prints only counts/timing. It does not save or play audio.

Default staging: `~/Library/Application Support/OpenScreenReader/DevelopmentRuntime` and the already pinned `DevelopmentModels/qwen3-tts-0.6b-customvoice-4bit-08c72cad` sibling. No runtime or weights are committed to Git.

## Actual checks

- Swift/C++ release compilation passed. Xcode Release build with actual Metal kernels passed after installing the missing Apple toolchain. Upstream Metal C++17-extension warnings and an Xcode resource-bundle creator warning remain; these were not represented as a warning-free build.
- Real sandboxed Qwen synthesis passed from the build products: first audio 5.347 s, 182,400 samples / 7.6 s at 24 kHz, peak amplitude 0.6227.
- The same real check passed from the installed directory: first audio 5.081 s, 186,240 samples / 7.76 s, peak 0.6678. Generation is sampled, so waveform length differs between runs. These are single cold-worker measurements, **not** the warm-model 500 ms target or proof of pronunciation/fidelity.
- `codesign --verify --strict` passed for the installed worker's local ad-hoc signature. No notarization/quarantine/clean-Mac distribution test has passed.
- The exact development sandbox profile denied connecting to an otherwise reachable loopback listener (`Operation not permitted`) and denied creating a new empty probe file. Actual synthesis passed under this profile, not merely with an offline environment variable.
- All 14 original model files were reverified before installation. The generated tokenizer is a documented additional model artifact. Ruby syntax checks and repeat notice collection passed; an initial notice-copy retry failed on read-only checkout copies, corrected by comparing and reusing identical existing notices.

## App integration and actual playback

`AppModel` now transfers recognized text directly to the `SpeechReading` boundary and completes only after playback drains. Published UI state contains counts, not text. Empty recognition does not invoke TTS. Startup, playback, and cancellation have separate state/timing guards; Escape monitoring remains active throughout. Settings reports the development installation's availability, not a fresh hash verification. The installer performs the integrity check; runtime revalidation and production packaging remain open.

On the M4 development Mac (macOS 26.6.2, Swift 6.3.3):

- The app's 40 Swift Testing tests and two real capture/permission XCTest checks passed. New behavior tests cover automatic speech, empty OCR, delayed/non-cooperative completion, startup timeout, generic errors without fallback, and Escape/repeated-shortcut cancellation during synthesis/playback.
- Debug tests use the existing local development certificate; its designated requirement was checked unchanged. The app Release build also passed. No permission reset or regrant was performed.
- A standalone probe compiled against the concrete `LocalSpeechService` completed real AVAudioEngine playback. The repeatable `bash scripts/verify-speech-playback.sh` run passed completion (19 chunks) and cancellation (zero late chunks, synchronous `stop()` call 11.651 ms); the clipboard revision remained unchanged. This measures the stop call, not end-to-end keyboard latency or acoustic silence, and is not a naturalness/fidelity assessment.
- Both new native UI tests passed with zero skips in `Test-OpenScreenReader-2026.09.05_01-07-16-+0200.xcresult`: a separate fixed-text window was region-captured, recognized, and reached real Qwen playback; Escape and the repeated default shortcut delivered through foreground Finder each reached **Stopped**. These tests start capture through the menu to isolate speech/cancellation from the separately tested, historically intermittent global-start delivery.
- Menu/settings UI tests also passed separately. The generic Computer Use bridge timed out against the windowless menu bar app; these are native XCUITest results, not a claimed Computer Use pass.
- The final complete Xcode run passed: **50 tests, zero failures, zero skips** (40 Swift Testing cases, two live XCTest checks, eight UI tests; parameterized invocations account for the result bundle's 55 device-level executions). Evidence: `Test-OpenScreenReader-2026.09.05_01-11-21-+0200.xcresult`. Both the custom and default Finder-hotkey tests passed in this run; prior intermittent failures remain relevant. The separate core test, all 11 behavior checks including the cancellation storm, and both Core/App Release builds also passed. A final Computer Use attempt still timed out.

For reproducible real UI checks, first run `bash scripts/build-speech-fixture.sh`, then the Xcode UI tests with the app's stable local signing identity. The fixture is a separate ad-hoc-signed app under ignored `.build`, displays only a fixed public German paragraph, and is terminated after each test. It is necessary because capture intentionally excludes OpenScreenReader's own windows. The Qwen tests explicitly skip when the app reports no development runtime; an installed runtime also requires building this fixture. No model is downloaded by tests.

Initial attempts are not hidden: two runs skipped because the UI runner resolved its sandbox home instead of the app's installation; preflight now reads the app's installation status. A settings-window capture never reached speech because own-app windows are excluded. A subsequent shortcut-start attempt failed overlay/event synthesis; the isolated speech tests now use menu start. These failures do not establish a model or audio failure and do not prove broader hotkey reliability.

Naturalness, German/English fidelity, speed controls, warm-worker reuse, bounded upstream stream buffering, memory/energy measurements, audio-device changes, and release packaging remain open. The upstream generator can queue the remainder of a bounded segment while the worker waits for playback acknowledgement; the one-packet pipe limit is not a claim that the upstream generator itself is back-pressured.

## Choppy playback correction — 2026-09-05

The owner reported audible chopping. The previous completion tests verified playback and cancellation but did **not** check continuity. A new content-free timing probe reproduced the defect: 7.92 seconds of generated speech suffered 24 player-queue underruns, totaling 6.859 seconds of missing scheduled audio. This is a player sample-clock measurement with a 20 ms threshold, not a microphone recording or a measurement of pauses encoded by the model.

Cause: the parent awaited `.dataPlayedBack` before acknowledging a packet. Only then could it receive, parse, and schedule the next packet, guaranteeing an empty playback queue at every boundary. Additionally, base64 was consumed one asynchronously awaited byte at a time on the main actor. Apple supports scheduling buffers consecutively before prior buffers finish; see [AVAudioPlayerNode](https://developer.apple.com/documentation/avfaudio/avaudioplayernode).

The correction acknowledges after scheduling into a queue capped at 96,000 frames (four seconds of 24 kHz mono audio), starts after approximately one second of prebuffering, and drains at end-of-stream. Short utterances below the prebuffer threshold still start and finish. Backpressure now waits only when the queue is full. Stop clears queued audio and resumes pending capacity/drain waits with cancellation; generations reject stale callbacks. The bounded queue adds startup latency but does not introduce history, change the model/voice, rewrite text, or download anything.

Packet framing now reads bounded 16 KiB blocks outside the main actor, retaining the 140,000-byte packet limit. An intermediate `FileHandle.read(upToCount:)` implementation stalled on short packets; it was replaced by a single POSIX read, and a regression test requires a short packet to return while its writer stays open. The owned worker's termination unblocks a pending read. Transport and playback counters are in-memory only and never exported automatically.

The same short fixed-text probe after the correction passed with 8.48 seconds of generated audio, **zero measured underruns**, and zero late chunks after cancellation (12.135 ms synchronous stop call). Waveforms are sampled, so before/after durations differ. All 45 Swift Testing tests plus two real capture/permission tests passed in `Test-OpenScreenReader-2026.09.05_01-21-48-+0200.xcresult`. The five new regression tests cover short-packet delivery, multi-packet framing/truncation, oversized packets, prebuffer/short-tail drain, and full-queue cancellation/reuse. Run `bash scripts/verify-speech-playback.sh --long` for the longer fixed German paragraph; no audio is recorded.

The long probe also passed: 41.84 seconds of generated speech, 130 playback notifications, zero measured underruns, maximum queued audio exactly 4.0 seconds, unchanged clipboard. Its subsequent cancellation check reported zero late chunks and a 12.080 ms synchronous stop call. The App Release build passed (existing AppIntents metadata warning only). Computer Use successfully read the app's Settings window this time; it confirmed the installed runtime and current UI, not acoustic quality. The installed worker/model were unchanged; the worker source edit only corrects its acknowledgement comment.

Both real OCR → Qwen UI tests passed again with the correction in `Test-OpenScreenReader-2026.09.05_01-23-57-+0200.xcresult`: Escape and the repeated shortcut stopped active speech from foreground Finder. The stable Debug designated requirement remained unchanged. A subsequent Computer Use read after the tests timed out again; the successful Settings inspection does not establish reliable automation of the windowless menu bar state. Broader pronunciation/prosody and device testing remain separate from this measured transport/queue fix.
