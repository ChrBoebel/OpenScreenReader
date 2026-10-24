# German listening comparison — 2026-09-05

A comparison of Serena, Ryan, and Aiden was requested after an accent was reported. This is a listening experiment, not a decision to replace the default voice. The installed app and worker remain unchanged.

All variants use the existing verified `mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit` revision `08c72cad5e2fd0f41730c8bd1f28149585e46361`, explicit `German`, seed 42, temperature 0.9, top-p 1.0, repetition penalty 1.05, and the existing segmentation/streaming path. A fixed seed controls one source of variation; reproducibility across devices/runtime versions is not asserted.

Public test text:

> Guten Morgen. Heute lesen wir einen deutschen Text über Bücher, schöne Städte und frische Brötchen. Der nächste Zug fährt um fünfzehn Uhr dreißig nach München.

`SpeechWorkerRequest` adds optional validated voice/language/seed fields. Original text-only requests still select Serena and detect language per segment. No app preferences, permission settings, model weights, or runtime installation are changed for this comparison.

## Reproduction and privacy boundary

1. Build the existing pinned native runtime as described in [runtime evaluation](swift-runtime-evaluation.md).
2. Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/verify-speech-request.sh`.
3. Run `ruby scripts/compare-german-voices.rb /absolute/build/products/OpenScreenReaderSpeechWorker /absolute/pinned/model/directory`.

The explicit comparison script rechecks all pinned model files and the prepared tokenizer. It accepts **no arbitrary text or audio** and synthesizes only the fixture above. The worker remains under the network/file-write deny profile. The parent deliberately exports three temporary, owner-only WAV files plus a manifest in a fresh temporary directory (`openscreenreader-stimmen-*` under the system temporary directory), outside Git. This is an explicitly requested public test export, not an app history feature. WAV files concatenate the actual PCM chunks without inserted transport pauses, use 24 kHz mono PCM16, and apply no voice-specific gain or resampling. They should be removed when the comparison is done; no automatic deletion occurs before listening.

Checks cover default compatibility, all three selected voices, explicit German for ambiguous input, seed parsing, and rejection of invalid voice/language/seed options. The Release worker build passed. An initial export failed because this Mac's Ruby does not accept mode `xb`; exclusive creation now uses `File::CREAT | File::EXCL`, preserving the no-overwrite guarantee.

The generated sample manifest records duration, peak amplitude, worker hash, and each WAV hash. Finite, non-silent PCM and successful worker completion are checked before each export. These checks do not judge accent, pronunciation, word fidelity, or listener preference; the choice is made after listening.

Actual comparison completed: Serena 17.76 s, Ryan 21.52 s, Aiden 14.32 s. All three WAV files passed `afinfo` inspection (24 kHz, mono, PCM16) and their manifest hash checks. All 44 installed runtime receipt entries still matched, confirming the comparison build was not installed over the app's worker. No app/UI regression run is claimed: this turn changed only the separately built development worker and comparison tooling, not app sources or the running installation.

## Lower-temperature repeat

After unwanted non-speech sounds were heard, all three voices were requested again at a lower temperature. The comparison tool now accepts an optional third argument, e.g. `ruby scripts/compare-german-voices.rb WORKER MODEL_DIRECTORY 0.5`. The request validates finite temperatures in `[0, 1]` and retains `0.9` when omitted. This repeat changes only temperature to `0.5`; the fixture text, explicit German, seed 42, top-p, repetition penalty, segmentation, and decoder remain unchanged. The temperature is recorded with each sample in the temporary manifest.

Tests passed for the old default, explicit `0.5`, and invalid values; Ruby syntax and invalid-CLI-value rejection passed, and the native Release worker build passed. No installed app/runtime settings were changed. Reduced unwanted sounds are a listening hypothesis, not a result established by successful synthesis or file checks.

The repeat completed for all three voices: Serena 12.00 s, Ryan 14.64 s, Aiden 16.72 s. Each manifest entry records temperature `0.5`; all WAV files passed `afinfo` and SHA-256 checks. Installed runtime receipt hashes still matched. The previous comparison files were preserved for listening alongside the new ones.

## Further reduction to 0.2

The next requested repeat used the existing script and separately built worker with temperature `0.2`, otherwise unchanged settings. All three real syntheses completed: Serena 13.84 s, Ryan 24.72 s, Aiden 11.60 s. All three manifests/hashes matched; Aiden also passed `afinfo` as 24 kHz mono PCM16. Files remained in the temporary comparison directory, outside Git and app history. The 44 installed runtime receipt hashes still matched. Lower temperature is not evidence of improved pronunciation, fewer non-speech sounds, or faithful reading; listening evaluation is still needed, particularly for Ryan's longer output.

The same public fixture was also generated with the alternative [Supertonic 3 provider candidate](supertonic-listening-comparison.md), outside the installed application. Neither comparison changes the app's default voice or sampling settings.
