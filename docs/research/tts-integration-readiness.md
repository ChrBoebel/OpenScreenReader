# Speech integration readiness — 2026-09-05

The owner requested automatic reading after OCR. Qwen3-TTS 0.6B CustomVoice 4-bit remains the intended provider; system speech has not been substituted. The initial investigation downloaded nothing; the owner subsequently approved the development model download described below. The production OCR flow is unchanged and no inference runtime has been installed.

## Repository findings

- The app currently discards recognized content after publishing counts. A speech integration must transfer text directly into the current operation, retain it only until completion/cancellation, and complete the coordinator only after playback drains.
- Keep the Escape monitor alive during synthesis and playback. The existing 15-second capture/OCR timeout cannot cover a longer reading: cancel that timer after OCR and use separate bounded startup/progress handling for speech.
- A repeated shortcut must revoke the operation and stop audio synchronously before waiting for model cancellation. Late audio must be rejected using the generation and worker epoch. A non-cooperative model must not block the next cancellation action.
- The approved model directory was not present at the standard Hugging Face cache path checked on this Mac. This is not a claim that every directory on the machine was searched.

## Native candidate to evaluate before choosing Python

The upstream [mlx-audio-swift Qwen3-TTS documentation](https://github.com/Blaizzy/mlx-audio-swift/blob/main/Sources/MLXAudioTTS/Models/Qwen3TTS/README.md) exposes CustomVoice conditioning and an audio-chunk streaming API. The current [package manifest](https://github.com/Blaizzy/mlx-audio-swift/blob/main/Package.swift) targets macOS 14 and depends on MLX and Hugging Face Swift packages. These mutable upstream references are research pointers, **not approved or pinned build inputs**.

Before integration, select an immutable revision, inspect the exact local-directory loading and cancellation paths, and audit the complete dependency/license closure. Do not use the README's repository-loading or WAV-writing convenience examples in the app: runtime network downloads and persistent generated audio conflict with project requirements. Streaming support in upstream documentation is not evidence of latency, correctness, or compatibility with the exact selected 4-bit conversion on this Mac.

## Owner-approved development download and open gates

The owner explicitly approved beginning the local Qwen download on 2026-09-05. This authorizes isolated development staging before the public packaging gates, not a release or a substitution with system speech. The [download manifest](qwen-download-manifest.json) pins the MLX revision, every file size, published LFS SHA-256 hashes, and Git blob hashes for the small files. The payload totals 1,693,604,738 bytes (approximately 1.69 GB).

Both the pinned MLX model card and the official source-model card declare Apache-2.0; the full Alibaba Cloud Apache-2.0 license was read at the official code revision linked in the manifest. Neither Hugging Face snapshot contains a standalone LICENSE file. The MLX card reports conversion with mlx-audio 0.3.0 but does not identify the exact upstream input revision or conversion command. The observed upstream revision is recorded as evidence, not falsely asserted as the conversion input. This is sufficient evidence to stage the explicitly requested public artifact for local evaluation, not to close the project's provenance or voice-rights release gate.

This first download installs **data only**, using existing curl/jq/git tools. No Python/MLX/Swift inference runtime or transitive package is installed, loaded, or executed; a runtime dependency lock and its full license audit are still required before the subsequent runtime installation. The downloaded weights are not bundled into the app and must not be used as release-approved artifacts.

The development-only helper `bash scripts/download-qwen.sh ABSOLUTE_DIRECTORY_OUTSIDE_GIT` downloads the allowlisted files at their immutable revision, verifies byte sizes and published hashes, and renames `.part` files only after validation. It refuses Git worktree destinations and refuses to overwrite an existing invalid final file. `--verify-only` checks the files without network access. The actual development staging directory is `~/Library/Application Support/OpenScreenReader/DevelopmentModels/qwen3-tts-0.6b-customvoice-4bit-08c72cad`. An `evidence/` subdirectory archives the upstream model card, full official license, and pinned model API metadata; no credentials are used.

### Download verification

The owner-approved data download completed on 2026-09-05: all **14 files / 1,693,604,738 bytes** passed their expected size and upstream hash checks. The helper then passed a complete `--verify-only` run locally without network access. Both large weight files match the publisher's LFS SHA-256 values; the other files match their published Git blob IDs. The [SHA-256 receipt](qwen-download-sha256.txt) records independently computed SHA-256 values for all downloaded files, including those small files for which the API published only Git blob IDs. No `.part` files remain.

The archived upstream model card matches Git blob `ed613da23a5e133a506b13b79055854938b9e67c`. The archived official license has SHA-256 `a44a6081c73ad75f0255bb2bb5cab74ef1829565a895a24e53a4f11290ab7655`. The pinned API response matches all 14 manifest paths, sizes, hashes, and the selected revision. Shell syntax, manifest validation, an expected missing-file verification failure, and rejection of a Git-worktree destination were checked. A separate `shasum -a 256 -c` run passed all 14 entries of the receipt. No app sources, runtime packages, signing settings, or permissions changed in the download step; app/UI regression tests are not evidence for this data-only action and were not rerun.

ADR 0003's complete provenance, packaging, signing/notarization, offline inference, voice-rights, and quality gates remain open. The download and hash checks are not a public-release approval. Before runtime installation or release, finish the dependency lock, full license closure, and conversion-provenance review. Public redistribution remains a separate decision.
