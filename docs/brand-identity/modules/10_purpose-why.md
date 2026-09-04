# Module 10: Purpose / Why

- Status: complete from available evidence
- Participant: Christopher, represented by an explicitly delegated founder proxy
- Frameworks: Sinek Golden Circle, Lencioni, Laddering / 5 Whys
- Evidence rule: Founder instructions and project documents are treated as evidence; interpretation is labelled as synthesis.

## Raw

### Direct founder answer, supplied verbatim through the delegated proxy

> OpenScreenReader soll existieren, weil Menschen jeden sichtbaren Text auf ihrem Mac unmittelbar hören können sollten, ohne ihre Bildschirminhalte an einen Cloud-Dienst abzugeben oder sich mit umständlichen Zwischenschritten und unnatürlich klingenden Systemstimmen abzufinden. Eine natürlich klingende Vorlesefunktion soll sich wie eine einfache, verlässliche macOS-Systemfunktion anfühlen und zugleich durch offenen Quellcode überprüfbar machen, dass Screenshots und erkannter Text beim Nutzer bleiben. Das Projekt soll praktisch helfen und als kostenloses Open-Source-Portfolio-Projekt zeigen, dass gute Accessibility, Datenschutz und hochwertige lokale KI zusammenpassen.

### Confirmed founder directives, supplied by the delegated proxy

- The app is intended to be free and open source and to serve as a portfolio project.
- OCR and TTS data should remain local to the user.
- Users should retain full control over their data.
- The interaction should feel like an unobtrusive macOS system function: hotkey, select region, automatic natural speech, immediate stop with `Esc` or the hotkey.
- Existing Apple system voices do not sound natural enough to Christopher.
- Cloud TTS, accounts, and telemetry are unwanted.

### Existing project evidence

- Product promise: “Select. Listen. Stay private.” (`README.md`)
- Positioning: “Markieren. Zuhören. Komplett lokal und Open Source.” (`docs/product-vision.md`)
- Privacy is defined as a technical invariant rather than a marketing option (`docs/privacy.md`).
- The project is explicitly not a complete replacement for VoiceOver (`docs/product-vision.md`).

## Synthesis

### Evidence-based laddering / 5-Whys trace

1. People should be able to hear any visible text because reading support should work across applications and formats.
2. It should happen in one short interaction because extra copying, dialogs, and context switching reduce practical accessibility.
3. It should sound natural because a technically available voice is not necessarily comfortable or useful enough for sustained listening.
4. It should remain local and inspectable because screen regions can contain highly sensitive information and convenience should not require surrendering control.
5. **Inferred root value:** technology should expand access without forcing a trade between dignity, autonomy, and privacy.

The fifth level is an interpretation grounded in the founder answer and privacy documentation, not a separate biographical claim.

### Golden Circle

- **Why:** Make visible information easier to access without taking control of sensitive screen data away from the user.
- **How:** Combine a one-gesture native macOS interaction, fully local OCR and natural local TTS, immediate cancellation, and inspectable open-source implementation.
- **What:** A free macOS menu bar utility that reads a selected screen region aloud.

### Three candidate purpose formulations

1. **Access without surrender:** OpenScreenReader makes visible text immediately hearable without asking people to surrender their screen data, attention, or control.
2. **Natural listening, locally:** OpenScreenReader exists to make natural-sounding reading support feel like a simple local capability of every Mac.
3. **Proof through product:** OpenScreenReader demonstrates that useful accessibility, strong privacy, and high-quality local AI can coexist in a free open-source product.

### Working formulation

Candidate 1 is the strongest user-facing purpose. Candidate 3 is a credible secondary project purpose and portfolio rationale, but should not displace the user benefit in external messaging.

### Projective check: brand obituary

If the project disappeared, the evidence suggests users would miss the ability to select sensitive or inconveniently placed text and hear it naturally without uploading it or building a document workflow. This is a document-based projection, not a recorded customer statement.

### Productive tensions

- Natural neural voice quality versus local latency, memory, energy use, and package complexity.
- System-like invisibility versus honest permission, bundled-model, size, and license disclosure.
- Portfolio proof for the founder versus durable usefulness and trust for users.

### Open decisions

- Decide whether “access without surrender” is the final purpose line or only an internal strategic shorthand.
- Decide how prominently the portfolio-project motivation belongs in public-facing brand material.
- Define what “free” means long term: free official binaries, free source only, or another sustainable distribution model.
