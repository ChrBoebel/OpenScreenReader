# Intel beta publication decision — 2026-10-15

After being told that the protected HTTPS update passed under Rosetta but no
physical Intel Mac test exists, the owner explicitly requested publication:
“ich will die intel version trozdem veröffentlichen auf meiner webseite”.

This authorizes an Intel **beta** despite the documented device-matrix gap.
`clean_mac` remains false. The architecture-bound owner exception covers only
that gate; licenses, offline/privacy and the actual signed HTTPS update must
still pass independently. The existing ARM exception cannot approve Intel.

Evidence remains scoped: x86_64 Release build targeting macOS 14, all 184 native
files audited, 88 original notices, 12 offline dictation checks, isolated 2×
speech with no underruns, and actual production-host Sparkle 8→9 installation
under Rosetta with full DMG hash, app seal, Gatekeeper and runtime receipts.
See `intel-release-readiness-2026-10-15.md` and
`intel-https-update-2026-10-15.json` for the complete results.

The website must disclose that Intel has only been tested under Rosetta; native
Intel, macOS 14 and fresh-account permission tests remain outstanding. Optional
MLX dictation models remain Apple-Silicon-only; Intel bundles Whisper Turbo.

Publication uses a fresh main-branch CI build, Developer ID signing, Apple
notarization, signed Sparkle metadata and the separate Intel download namespace.
The accepted private Intel build9 DMG supplies only the SHA-256-pinned runtime.
Never relabel the private candidate or reuse the ARM feed for Intel.

The prior instruction kept app PR #13 open and authorized only the website merge.
The exact publication PRs still require the explicit merge approval required by
AGENTS.md. Record the resulting CI and public-package verification after release.
