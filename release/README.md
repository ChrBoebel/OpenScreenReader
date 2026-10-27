# Release approval records

Machine-readable gates that `scripts/release.py --public-release`, `scripts/prepare-release-ci.py` and `scripts/publish-release.py` check before a build may be published. Notarization alone does not open them.

| File | Architecture |
|---|---|
| [`release-approval.json`](release-approval.json) | Apple Silicon (arm64) |
| [`release-approval-x86_64.json`](release-approval-x86_64.json) | Intel (x86_64) |

Each gate (`license_review`, `clean_mac`, `offline_privacy`, `update_roundtrip`) must be `true` before a public release can be built. Only `clean_mac` (the fresh-device test matrix) may instead be covered by a documented beta exception for one architecture; licensing, privacy and update checks never can. `license_review` is `true` for both architectures since 2026-10-25 (maintainer decision without external counsel; accepted residual risks in [ADR 0003](../docs/decisions/0003-bundled-default-model.md)). `clean_mac` stays `false`, so publications remain beta builds under the documented exception.

The records are historical: their `evidence` fields name verification documents from the private development phase that are not part of the public repository. Changes to this folder require review by the code owners (see [`.github/CODEOWNERS`](../.github/CODEOWNERS)). The procedure is described in [docs/release-and-updates.md](../docs/release-and-updates.md).
