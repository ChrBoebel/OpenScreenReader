# Module 20: Positioning

- Status: complete from available evidence
- Frameworks: Dunford “Obviously Awesome”, Moore positioning template, competitive contrast

## Raw

### Confirmed founder directives

- Free and open source.
- Local OCR and TTS; no cloud TTS, accounts, or telemetry.
- Natural voice quality is important because existing Apple system voices are not natural enough.
- The interaction should feel like a small native macOS system function.

### Existing project evidence

- The identified market splits between fast local screen-OCR utilities with system voices and natural TTS platforms built around cloud, accounts, subscriptions, documents, or browsers (`docs/research/market-and-tts-findings.md`).
- Direct UX benchmark: TextSniper. Voice-quality benchmark: Speechify (`docs/research/market-and-tts-findings.md`).
- Differentiating intersection: “TextSniper-like one-gesture interaction + natural local speech + verifiable open-source privacy.”
- The product is not a complete screenreader, document library, cloud-TTS platform, translation tool, summarizer, or chat product.

## Synthesis

### Positioning components

- **Best-fit users:** Mac users who want short, visible passages read aloud with low friction and who value natural speech and control of screen data.
- **Main alternatives:** macOS system speech, local OCR/capture utilities, cloud TTS/document platforms, larger accessibility suites, or manually copying text into another app.
- **Unique attributes:** arbitrary region selection, automatic local OCR-to-speech, modern local neural voice, immediate end-to-end cancellation, no account or telemetry, open-source auditability.
- **Value delivered:** fast listening across app boundaries without a cloud workflow or silent data transfer.
- **Category:** local screen-to-speech utility for macOS. Avoid claiming to be a complete screenreader.

### Moore-style positioning statement

For Mac users who want visible text read aloud without uploading screen content, OpenScreenReader is a local screen-to-speech utility that turns a selected region into natural speech in one flow. Unlike system-voice OCR tools or cloud TTS platforms, it combines a native macOS interaction, modern on-device speech, immediate cancellation, and open-source inspectability without accounts or default telemetry.

### Three candidate positioning lines

1. **Select any text. Hear it naturally. Keep it local.**
2. **Natural screen-to-speech for Mac—local, open, and one gesture away.**
3. **The private, open-source way to listen to any visible text on your Mac.**

Candidate 1 is the most concrete and least likely to imply full VoiceOver-style navigation.

### Competitive contrast

The useful admired-but-wrong models are document-centric natural TTS platforms: they demonstrate desirable voice quality but conflict with the desired account-free, local, transient workflow. Local OCR utilities demonstrate the right interaction speed but not the intended voice quality. This contrast comes from the market research, not a new founder preference.

### Productive tensions

- The name “OpenScreenReader” can imply a complete assistive screenreader, while the intended product is a focused region-to-speech utility.
- “Natural” is a comparative quality promise that must be substantiated through listening tests.
- “Works offline after installation” is true only after the bundled-model release passes packaged-build offline and network tests.

### Open decisions

- Validate whether the product name creates unacceptable expectation mismatch with VoiceOver users.
- Choose the final category phrase: “screen-to-speech utility,” “screen reader utility,” or another tested term.
- Set measurable evidence for the public “natural” and speed claims.
- Decide whether English or German leads launch communication.
