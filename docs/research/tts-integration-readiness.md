# Speech integration readiness — 2026-09-05

The owner requested automatic reading after OCR. Qwen3-TTS 0.6B CustomVoice 4-bit remains the intended provider; system speech has not been substituted. No model or runtime was downloaded in this investigation, and the production OCR flow is unchanged.

## Repository findings

- The app currently discards recognized content after publishing counts. A speech integration must transfer text directly into the current operation, retain it only until completion/cancellation, and complete the coordinator only after playback drains.
- Keep the Escape monitor alive during synthesis and playback. The existing 15-second capture/OCR timeout cannot cover a longer reading: cancel that timer after OCR and use separate bounded startup/progress handling for speech.
- A repeated shortcut must revoke the operation and stop audio synchronously before waiting for model cancellation. Late audio must be rejected using the generation and worker epoch. A non-cooperative model must not block the next cancellation action.
- The approved model directory was not present at the standard Hugging Face cache path checked on this Mac. This is not a claim that every directory on the machine was searched.

## Native candidate to evaluate before choosing Python

The upstream [mlx-audio-swift Qwen3-TTS documentation](https://github.com/Blaizzy/mlx-audio-swift/blob/main/Sources/MLXAudioTTS/Models/Qwen3TTS/README.md) exposes CustomVoice conditioning and an audio-chunk streaming API. The current [package manifest](https://github.com/Blaizzy/mlx-audio-swift/blob/main/Package.swift) targets macOS 14 and depends on MLX and Hugging Face Swift packages. These mutable upstream references are research pointers, **not approved or pinned build inputs**.

Before integration, select an immutable revision, inspect the exact local-directory loading and cancellation paths, and audit the complete dependency/license closure. Do not use the README's repository-loading or WAV-writing convenience examples in the app: runtime network downloads and persistent generated audio conflict with project requirements. Streaming support in upstream documentation is not evidence of latency, correctness, or compatibility with the exact selected 4-bit conversion on this Mac.

## Pending owner choice and gates

The owner has been asked to approve downloading the roughly 1.7 GB candidate plus its runtime after source/license review, or explicitly choose installed macOS voices as an interim alternative. Until that choice arrives, neither a large download nor an alternative speech provider is assumed authorized.

ADR 0003's provenance, packaging, signing/notarization, offline, voice-rights, and quality gates remain open. A locally signed development experiment is not a public-release approval. Before an approved download, record exact sources/revisions, artifact sizes/hashes, licenses, a dependency lock, and conversion provenance; weights stay outside Git. Public redistribution remains a separate decision.
