# Module 60: Narrative / Story

- Status: complete from available evidence
- Frameworks: Neumeier trueline, user-centered brand story arc

## Raw

### Confirmed founder story elements

- Existing Apple system voices do not sound natural enough.
- Cloud TTS, accounts, and telemetry are unwanted.
- The desired alternative is free, open source, local, and as unobtrusive as a macOS system function.
- The project should be practically useful and demonstrate that accessibility, privacy, and high-quality local AI can coexist.

### Existing project evidence

- Market research identifies a gap between fast local OCR utilities and natural cloud TTS platforms.
- The intended flow is hotkey → region selection → local OCR → automatic local speech, with immediate cancellation.
- The project is in foundation and architecture validation; no released working application exists yet (`README.md`).

## Synthesis

### Brand story arc

1. **Current world:** Useful text appears everywhere on a Mac, but listening to it often means copying it, entering a document workflow, accepting system voices, or uploading content.
2. **User tension:** A person wants to hear one passage now, without leaving the current context or exposing potentially sensitive screen content.
3. **Insight:** Natural speech and strong privacy should not be competing product tiers.
4. **Brand role:** OpenScreenReader provides a focused, inspectable local tool—not a hero, cloud platform, or complete accessibility replacement.
5. **User action:** Press a hotkey, select the relevant text, listen, and stop at any time.
6. **Resolution:** The user keeps momentum and control while visible information becomes easier to access.
7. **Proof obligation:** The product must substantiate naturalness, latency, cancellation, offline operation, and ephemeral data handling before telling this as a shipped-product story.

### Three candidate truelines

1. **Any visible text, naturally spoken, without leaving your Mac.**
2. **Accessibility without the cloud in the middle.**
3. **A private path from what you see to what you hear.**

Candidate 1 best joins capability and differentiation. Candidate 2 is sharper but narrows accessibility to privacy contrast. Candidate 3 is emotive but less concrete.

### Short narrative draft

Text does not always arrive in a readable document. It appears in slides, tickets, chats, PDFs, images, and interfaces. Hearing one passage should not require copying it into another service or sending a screenshot away. OpenScreenReader is being built as a small native macOS utility: select what matters, hear it in a natural local voice, and stop it instantly. Its open-source implementation is intended to make the privacy promise inspectable rather than merely asserted.

### Projective check: five-year absence

If OpenScreenReader closed after five years, the distinctive loss implied by the evidence would be a focused, open, local bridge between arbitrary screen text and natural speech—not another general AI assistant or document library. This is a strategic projection, not a user quote.

### Productive tensions

- The desired narrative is compelling, but the app is not released and must be described in future or development tense.
- “Any visible text” is an ambition constrained by OCR accuracy, layout, permissions, and language support.
- Accessibility storytelling must center user agency rather than founder heroism or inspirational framing.

### Open decisions

- Choose a final trueline after product and user validation.
- Decide how much of the origin story should mention dissatisfaction with Apple voices versus the larger market gap.
- Gather real user stories before publishing outcome claims or testimonials.
- Define the threshold at which development-tense messaging may change to present-tense product claims.
