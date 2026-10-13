> **Historische Markenentwicklung:** Die Namens-, Logo- und Farbentscheidungen wurden am 13.10.2026 durch [Saywing / Quiet Owl](BRAND_SYSTEM.md) ersetzt. Frühere Produkt- und Modellannahmen sind keine aktuelle Freigabe.

# OpenScreenReader Brandbook

- Status: evidence-based working draft
- Session: `OpenScreenReader-brand-2026-09`
- Participant: Christopher, represented in this pass by an explicitly delegated founder proxy
- Scope: strategic verbal identity plus approved visual direction
- Product stage: foundation and architecture validation; no working application has been released

This draft synthesizes confirmed founder directives and existing repository documentation. Direct evidence, interpretation, provisional recommendations, and open decisions are intentionally distinguished. It contains no inferred founder biography, diagnosis, or customer testimony.

## Executive identity

**OpenScreenReader is a free, open-source macOS screen-to-speech utility being built to let people select any visible text, hear it in a natural local voice, and keep sensitive screen content under their control.**

Its distinctive territory is the intersection of:

1. one-gesture, system-like macOS interaction;
2. modern natural speech processed locally;
3. inspectable privacy and user control through open source.

The user benefit leads. The portfolio value is a legitimate secondary project purpose, not the headline promise.

## Evidence status

### Confirmed founder direction

- Free and open source; also intended as a portfolio project.
- OCR and TTS content remains local to the user.
- Users retain control of their data.
- No cloud TTS, account requirement, or telemetry.
- Native-feeling flow: hotkey, select region, automatic natural speech, immediate stop.
- Apple system voices are not considered natural enough for the intended experience.
- The project should show that accessibility, privacy, and high-quality local AI can coexist.

### Confirmed product documentation

- No persistent screenshot, OCR-text, or audio history; no automatic clipboard write.
- No silent cloud fallback.
- Explicit bundled-model, install-size, license, and permission disclosures.
- Immediate cancellation is a pipeline-wide requirement.
- Qwen3-TTS 0.6B 4-bit is the primary candidate, but the architecture remains provisional and provider-based.
- The product is not a complete replacement for VoiceOver.

### Provisional strategic choices in this draft

- “Screen-to-speech utility” as the category.
- Privacy-conscious Mac users with recurring reading friction as the primary launch audience.
- Caregiver + Sage as the archetype blend.
- Product-first, founder-transparent as the founder-brand model.
- “Select any text. Hear it naturally. Keep it local.” as the leading positioning line.

These choices remain subject to founder approval and user validation.

## Purpose: Why / How / What

### Why

Make visible information easier to access without taking control of sensitive screen data away from the user.

### How

Combine a one-gesture native macOS interaction, fully local OCR and natural local TTS, immediate cancellation, transient content handling, and an inspectable open-source implementation.

### What

A focused macOS menu bar utility that reads a user-selected screen region aloud.

### Root value

**Access without surrender:** people should not have to trade privacy, autonomy, or workflow continuity for more natural reading support.

This root value is a synthesis of the founder answer and project privacy requirements.

## Positioning

### Recommended positioning statement

For Mac users who want visible text read aloud without uploading screen content, OpenScreenReader is a local screen-to-speech utility that turns a selected region into natural speech in one flow. Unlike system-voice OCR tools or cloud TTS platforms, it combines a native macOS interaction, modern on-device speech, immediate cancellation, and open-source inspectability without accounts or default telemetry.

### Market frame

- **Against local OCR utilities:** add natural local speech and an automatic listening flow.
- **Against cloud TTS platforms:** remove account, upload, subscription-workflow, and persistent-library assumptions.
- **Against macOS system speech alone:** aim for materially more natural voice quality.
- **Alongside complete screenreaders:** solve a narrower region-to-speech job without claiming semantic navigation or blind system operation.

### Leading line and alternatives

1. **Recommended working line:** “Select any text. Hear it naturally. Keep it local.”
2. Existing concise promise: “Select. Listen. Stay private.”
3. German working line: “Markieren. Zuhören. Komplett lokal und Open Source.”

None is final until terminology, claim evidence, and German/English hierarchy are approved.

## Audience and job

### Provisional primary audience

Privacy-conscious Mac users with recurring reading friction who want to listen to short passages across applications without adopting a complete screenreader or cloud document workflow.

Reading friction can arise from context, format, fatigue, attention, preference, or disability. Brand communication should not assign diagnoses to users or collapse diverse accessibility needs into one persona.

### Secondary candidate segments

- People with dyslexia, ADHD, low vision, or other reading-access needs who want lightweight listening support.
- Knowledge workers handling passages in PDFs, slides, tickets, chats, videos, and graphical interfaces.
- Privacy-sensitive professionals in research, medicine, law, or organizations.
- German- and English-speaking users; language learners are a later candidate audience.

### Core job-to-be-done

> When useful text is visible anywhere on my Mac, help me hear the relevant passage immediately so I can keep moving without sending it to another service.

### Desired user outcome

The user remains in context, hears the selected passage naturally, understands what the app is doing, and can stop the entire operation at once.

## Promise and pillars

### Brand promise

**Visible text becomes natural speech in one local, user-controlled flow.**

### Pillar 1: Immediate access

- One global hotkey.
- Free region selection across screens.
- Automatic speech without an extra click.
- Immediate cancellation with `Esc` or the repeated hotkey.

### Pillar 2: Natural local speech

- Modern neural TTS is the quality direction.
- Streaming and low perceived latency matter more than model novelty.
- Text fidelity takes precedence over beautiful but inaccurate prosody.
- Model architecture remains provider-based and evidence-led.

### Pillar 3: Verifiable privacy and control

- Local OCR and TTS after installation of the bundled-model release.
- No account, cloud fallback, default telemetry, automatic clipboard write, or content history.
- Screenshots, recognized text, and audio are transient by default.
- Permissions, downloads, sources, licenses, storage, and network behavior are disclosed.
- Open source makes inspection possible, but does not justify absolute security claims.

### Pillar 4: Native restraint

- Menu bar rather than permanent main window.
- Small, non-modal status feedback.
- Keyboard access and VoiceOver labels from the beginning.
- Advanced implementation should recede behind one understandable action.

## Brand boundaries

OpenScreenReader is not:

- a complete replacement for VoiceOver;
- semantic screen navigation or full blind system operation;
- a document library, cloud voice platform, transcription archive, translator, summarizer, or chat assistant;
- a justification for capturing more of the screen than the user selects;
- “100% secure,” universally accurate, or guaranteed to read every layout;
- shipped or production-proven until the required spikes, tests, signing, privacy verification, and release work are complete.

## Personality and archetype

### Archetype system

- **Primary — Caregiver:** helpful, protective of user boundaries, and focused on practical access.
- **Secondary — Sage:** transparent, evidence-based, and candid about trade-offs and limitations.
- **Supporting — Creator:** makes advanced local technology feel like a coherent native tool.

The Caregiver expression must be enabling rather than paternalistic. The Sage expression must be clear rather than dense. The Creator expression must serve the job rather than celebrate AI novelty.

### Five defining traits

1. Calm
2. Capable
3. Respectful
4. Transparent
5. Quietly modern

### Traits to avoid

Intrusive, patronizing, alarmist, opaque, corporate-cloud-like, overexcited about AI, or absolute in security claims.

## Voice and tone

### Voice

OpenScreenReader sounds quietly capable, openly accountable, and warmly precise.

- Use plain, short, concrete language.
- Lead with the user action and outcome.
- Explain data flow and permissions exactly when relevant.
- Separate what works now, what is planned, and what remains a hypothesis.
- Respect user agency; do not presume impairment or dependence.
- Use “AI” and model names as supporting explanations, not as the protagonist.

### Tone shifts

- **Promise:** crisp and benefit-led.
- **Onboarding:** welcoming and minimal.
- **Permission or download:** candid, consent-led, and specific.
- **Active use:** nearly invisible.
- **Error:** neutral, clear, and actionable.
- **Technical documentation:** precise, testable, and explicit about uncertainty.

### Language examples

Prefer:

- “Select any text. Hear it naturally. Keep it local.”
- “OCR and speech run locally after installation.”
- “OpenScreenReader reads the region you select.”
- “No text or screenshots are uploaded.” only after this behavior is implemented and verified.

Avoid:

- “Revolutionary AI accessibility.”
- “We see everything so you don’t have to.”
- “Your data is always 100% safe.”
- Any wording that implies complete VoiceOver replacement.

## Narrative

Text appears in slides, tickets, chats, PDFs, images, and interfaces—not always in a convenient document. Hearing one passage should not require copying it into another service or sending a screenshot away. OpenScreenReader is being built as a small native macOS utility: select what matters, hear it in a natural local voice, and stop it instantly. Its open-source implementation is intended to make the privacy promise inspectable rather than merely asserted.

### Narrative roles

- **Protagonist:** the user who wants to keep reading, working, or understanding on their terms.
- **Problem:** friction and compromise between quick screen access, natural speech, and privacy.
- **Guide/tool:** OpenScreenReader, narrowly focused and invoked only when wanted.
- **Resolution:** visible information becomes hearable while context and control remain with the user.
- **Proof:** measured behavior, source transparency, user validation, and honest limitations.

## Kapferer identity prism

| Facet | Working definition |
| --- | --- |
| Physique | Native macOS menu-bar presence, region-selection gesture, minimal status feedback, and the approved Owl Frame app logo in Local Ink, Voice Mint, Mint Light, and Warm Paper. |
| Personality | Calm, capable, respectful, transparent, quietly modern. |
| Culture | Accessibility, local-first privacy, user agency, open-source inspectability, and evidence before claims. |
| Relationship | Invited helper: appears on command, handles only the selected content, explains trust-sensitive actions, and stops immediately. |
| Reflection | A Mac user who values easier listening, low friction, natural speech, and control—without being reduced to a diagnosis. |
| Self-image | “I can make information work for me without handing my private screen content to a service.” |

## Aaker brand system

### Core identity

- Local screen-to-speech.
- Natural listening with minimal interaction.
- Inspectable privacy and user control.
- Focused native macOS utility.

### Extended identity

- Free and open source.
- German and English first.
- Immediate end-to-end cancellation.
- Provider-based local voice architecture.
- Accessibility-aware but explicitly not a full screenreader.
- Technically candid portfolio project with product-first communication.

### Value proposition

- **Functional:** hear short visible passages across app boundaries quickly.
- **Emotional:** feel less friction and less uncertainty about where sensitive content goes.
- **Self-expressive:** choose tools that align accessibility, privacy, openness, and user control.

### Reasons to believe

Current reasons to believe are design commitments and benchmark evidence, not shipped guarantees:

- Apple Vision provides a planned local OCR path.
- Local TTS prototypes have been benchmarked on Apple M4 hardware.
- Qwen3-TTS demonstrated a 0.226-second warm first audio block in one documented run.
- Privacy requirements define concrete network, storage, clipboard, and lifecycle behavior.
- Architecture includes cancellation IDs, stale-result protection, and provider boundaries.
- Public source can support auditability once implementation exists.

## Founder and product relationship

Use a **product-first, founder-transparent** structure.

- OpenScreenReader owns the user promise and trust contract.
- Christopher is visibly accountable as creator and may document decisions, tests, and learning.
- The portfolio story supports but does not outrank the user outcome.
- Do not imply founder diagnoses, credentials, or lived accessibility experience that are not on record.
- Let tests, users, and inspectable implementation—not founder authority—substantiate product claims.

## Experience principles

1. **One intent, one flow.** The product should preserve the direct path from selection to listening.
2. **Control is immediate.** Cancellation must stop selection, OCR, synthesis, queues, and audio without stale results resurfacing.
3. **Privacy is behavior.** Default storage, network, clipboard, logging, and crash-report behavior must match the promise.
4. **Trust moments are visible.** Permissions and downloads need concise, specific explanations.
5. **Naturalness never excuses inaccuracy.** Numbers, names, URLs, codes, and mixed-language text require fidelity.
6. **Native means restrained.** The experience should fit macOS conventions and avoid becoming a platform for adjacent features.

## Claim-readiness guardrail

| Claim | Current status | Required before public present-tense use |
| --- | --- | --- |
| “Works offline after installation” | Intended requirement | Bundled packaged-build offline test and network denial |
| “No text or screenshots are uploaded” | Intended requirement | Runtime data-flow audit and dependency verification |
| “No telemetry in the official build” | Intended requirement | Release configuration and network audit |
| “Natural voice” | Direction supported by founder preference and model research | Comparative listening validation with target users |
| “Starts immediately” | Performance target | Repeated end-to-end measurements on supported Macs |
| “Stops immediately” | Performance target under 100 ms | End-to-end cancellation tests including stale results |
| “Any visible text” | Aspirational shorthand | OCR coverage definition and transparent limitations |

Until these gates pass, public copy should use development language such as “being built,” “designed to,” or “intended to.”

## Open decisions

### Identity-critical before launch communication

1. Confirm or revise the leading purpose, positioning line, and “screen-to-speech utility” category.
2. Validate whether the name “OpenScreenReader” creates unacceptable expectations of a complete screenreader.
3. Select one primary launch audience and test the promise and workflow with representative users.
4. Decide whether accessibility, privacy, or productivity leads the top-level story.
5. Choose the launch-language hierarchy and finalize German/English terminology.
6. Define measurable acceptance thresholds for naturalness, immediacy, offline behavior, and cancellation claims.
7. Produce the approved Owl Frame app logo as precise vector geometry, Icon Composer layers, and a tested monochrome menu-bar derivative. The visual direction and core palette are defined in `BRAND_SYSTEM.md`; production assets remain outstanding.

### Founder and project model

8. Decide how prominently Christopher appears in product channels and where the portfolio case study lives.
9. Clarify the durable meaning of “free,” including official binary distribution and possible maintenance funding.
10. Define contribution governance, decision rights, and maintainer succession if community participation grows.

### Product and trust details affecting the brand

11. Resolve packaging, signing, model licensing, supported macOS versions, and hardware expectations.
12. Decide whether privacy-sensitive professional sectors are illustrative use cases or supported target markets with stronger assurance obligations.
13. Establish the threshold for changing pre-release language into present-tense product claims.
14. Gather real user language and stories; none should be fabricated from this synthesis.

## Working one-page brief

- **Brand:** OpenScreenReader
- **Category:** local screen-to-speech utility for macOS, provisional
- **Purpose:** make visible information easier to access without surrendering control of sensitive screen data
- **Audience:** privacy-conscious Mac users with recurring reading friction, provisional
- **Promise:** visible text becomes natural speech in one local, user-controlled flow
- **Difference:** one-gesture screen selection + natural local speech + open-source, testable privacy
- **Personality:** calm, capable, respectful, transparent, quietly modern
- **Voice:** plain, concise, candid, agency-respecting
- **Leading line:** “Select any text. Hear it naturally. Keep it local.”, provisional
- **Non-negotiables:** local OCR/TTS after download, no account/cloud fallback/default telemetry/history, immediate cancellation, no VoiceOver-replacement claim
- **Founder model:** product-first, founder-transparent, provisional
- **Visual identity:** Owl Frame app logo; Local Ink `#0B1724`, Voice Mint `#55E0BE`, Mint Light `#B8F7E7`, Warm Paper `#F7F4ED`
- **Current communication status:** describe an intended product under validation, not a released capability
