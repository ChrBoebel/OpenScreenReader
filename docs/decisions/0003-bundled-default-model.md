# ADR 0003: Bundled default speech model

- Status: Accepted, subject to release gates M0, P, and M1
- Date: 2026-09-04

## Context

A separate first-run model download adds a large trust and decision point before the core user benefit. The desired experience is one website download followed by immediate local use after normal macOS installation and permission onboarding.

The current candidate `mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit` reports an approximately 1.69 GB payload. Its page reports Apache-2.0 and says it was converted with mlx-audio 0.3.0, but a name and mutable repository branch are not sufficient release provenance.

## Decision

- The macOS MVP release should contain one pinned and verified default model inside the signed application resources.
- Model weights remain outside Git.
- A release staging task uses an immutable allowlist of revisions, files, sizes, and SHA-256 hashes.
- The shipped dependency closure, conversion path, tokenizer, voices, runtime, and model require archived license evidence and an SBOM.
- No model, package, or update download occurs in the MVP runtime.
- The application exposes model name, version, source, size, license, and integrity status without asking the user to select a model.
- The provider architecture continues to support a different model or platform artifact later.

## Release gates

- M0: provenance, dependency, voice-rights, and license approval before weight download;
- P: a minimal hermetic worker signs, notarizes, survives browser quarantine, and runs on a clean Mac without system Python or Homebrew;
- M1: the real packaged model passes German/English fidelity, blinded naturalness, latency, cancellation, memory, privacy, and offline tests.

The mlx-audio v0.3.0 TTS extras include `espeakng-loader`; eSpeak NG is GPL-3.0-or-later. The release must prove that the Qwen path excludes it, replace it, or receive an explicit project-level GPL decision before integration.

## Consequences

- First use is simpler and fully offline.
- The DMG and installed app are large, and full manual upgrades may transfer model data again.
- If a self-contained notarized DMG cannot pass the gates, model delivery returns to an explicit owner decision; a PKG or runtime download is not adopted silently.

## Update 2026-10-23: Supertonic 3 is the bundled default

By the owner's 2026-09-05 listening decision the bundled default speech model is
Supertonic 3 (`Supertone/supertonic-3`, revision
`3cadd1ee6394adea1bd021217a0e650ede09a323`, voice M1), not the Qwen3-TTS
candidate above. Gate M0 as written was scoped to Qwen-TTS; the Qwen eSpeak NG
question applies only if Qwen-TTS is reconsidered. Qwen remains comparison-only
and is never an automatic fallback.

Supertonic 3 model files and voice styles are licensed under the BigScience
Open RAIL-M License (August 18, 2022), not Apache-2.0. Its pinned license is kept
unchanged in `docs/licenses/Supertonic-3-Open-RAIL-M.txt`; the binding use
restrictions for builds that include the model are in
`docs/licenses/SUPERTONIC-MODEL-TERMS.md`. Every build now bundles both files and
shows them in Settings > Read Aloud > Model Terms and in setup.

None of the following license gates is claimed as passed by this update; each
still needs evidence and the owner's decision:

- OpenRAIL-M §4(a)/(b) and §5: the use-based restrictions are included as an
  enforceable provision and a copy of the license reaches every recipient, both
  in the app (in place since this update) and in the distributed DMG or other
  download channel (not yet in place);
- third-party notices for the bundled Python/ONNX speech runtime and the
  dictation runtimes are complete and match the shipped files;
- the provenance of the bundled CPython interpreter (source, build, patches and
  licenses) is documented for every architecture;
- upstream Supertonic maintenance has ended (announced 2026-07-23); the
  maintenance risk remains an explicit release decision.
