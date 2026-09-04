# Research summary: market and local TTS

**Research date:** 2026-09-04

## Market finding

The market is split between:

1. fast local screen-OCR utilities that copy text or use macOS system voices;
2. natural TTS platforms that focus on documents, browsers, accounts, and cloud workflows.

No mature open-source macOS app was identified that combines all of the following:

- global shortcut and free region selection;
- German Apple Vision OCR;
- automatic speech without an extra click;
- modern local neural TTS with fast streaming;
- no account, cloud, telemetry, or persistent history;
- a polished, signed macOS release.

## Key competitors and references

- **TextSniper:** the direct UX benchmark. It already supports capture-and-speak and stop-speaking shortcuts, but uses macOS speech voices.
- **Speechify:** the voice-quality benchmark. It provides screenshot-to-listen and natural voices, but is a cloud/account/subscription platform.
- **ClaroRead and Read&Write:** established screenshot-reader workflows inside larger accessibility suites.
- **OpenTextGrabber:** strongest MIT-licensed native reference for hotkey, overlay, capture, and Apple Vision OCR.
- **Screen Reader:** MIT proof of concept with nearly the complete flow, but system speech and limited language support.
- **LuxShot and VOCR:** useful GPL-licensed references; do not copy their code into an Apache-2.0 project without an explicit license decision.
- **VoxScreen:** close Windows concept including repeated-region capture, but no reusable license was identified.
- **TRex, macOCR, and Raycast ScreenOCR:** demand and maturity signals for local screen OCR, but without natural TTS.

Primary research report before repository creation:

`market-research-ocr-tts-macos.md` in the originating BB workspace. Important external facts must be rechecked against upstream sources before release documentation is published.

## Local TTS benchmark on Apple M4, 16 GB

All syntheses ran locally after initial model download. Results are single runs rather than statistical distributions.

| Model | Load | Warm first audio | Full synthesis | Audio length | Throughput | Loaded memory | Peak |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Supertonic 3 F1 | 0.48 s | 1.26 s for a short first sentence | 3.15 s | 15.47 s | 4.91× real time | 0.66 GB RSS | 0.73 GB RSS |
| Qwen3-TTS 0.6B 4-bit Serena | 2.02 s | **0.226 s** | 6.77 s | 17.92 s | 2.65× real time | 1.76 GB MLX + 0.51 GB RSS | 2.31 GB MLX; 0.90 GB RSS |
| Chatterbox Multilingual V3 | 2.71 s | 6.75 s for a short first sentence | 12.61 s | 14.08 s | 1.12× real time | 3.27 GB MLX + 0.65 GB RSS | 4.88 GB MLX; 1.32 GB RSS |

MLX and RSS are two views of unified memory and must not be added naively.

## Model decision

1. **Qwen3-TTS 0.6B 4-bit:** primary candidate because the tested MLX path streams and reached the first audio block in 0.226 seconds when warm.
2. **Supertonic 3:** optional lower-memory provider. Code is MIT; model distribution requires compliance with its OpenRAIL-M license.
3. **Chatterbox Multilingual V3:** not a default provider for the MVP because the tested path starts too slowly and uses more memory.
4. **Thorsten/Piper:** defer until a specific runtime and German phonemizer path has been verified. The model and runtime licenses must be assessed separately.

## Strategic conclusion

OpenScreenReader should not compete as another OCR utility. Its differentiating intersection is:

> TextSniper-like one-gesture interaction + natural local speech + verifiable open-source privacy.

The durable engineering value lies in product integration: cancellation, segmentation, text fidelity, model lifecycle, packaging, permissions, signing, and a reliable global macOS interaction—not merely in running a model locally.
