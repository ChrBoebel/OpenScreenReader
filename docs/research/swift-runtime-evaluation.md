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
- Text enters over an anonymous pipe, never command-line arguments, a socket, clipboard, or file. PCM exits as bounded JSON/base64 packets with an acknowledgement after each played buffer. Tokens and upstream diagnostics are not exported.
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

App playback/UI results and remaining integration gaps are recorded separately below when verified. Naturalness, German/English fidelity, speed controls, warm-worker reuse, bounded upstream stream buffering, memory/energy measurements, audio-device changes, and release packaging remain open. The upstream generator can queue the remainder of a bounded segment while the worker waits for playback acknowledgement; the one-packet pipe limit is not a claim that the upstream generator itself is back-pressured.
