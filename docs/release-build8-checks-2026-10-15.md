# Saywing 0.1.5 / build 8 — private release candidate

Latest checkpoint: [build 9 with completed Rust evidence](release-build9-checks-2026-10-15.md). Earlier findings below are historical where superseded there.

Status: Apple accepted **both** architecture packages. Both DMG tickets are
stapled and validated; Gatekeeper accepts both DMGs and nested apps as Notarized
Developer ID. All update feeds, enclosure signatures, SHA256SUMS and latest.json
were regenerated and verified against the final post-staple bytes. Nothing was
published, committed, pushed or merged. Public release approval remains false.

## Artifacts

- ARM: `.build/rc-final-arm64-build8/publish/Saywing-0.1.5-8.dmg`
- Intel: `.build/rc-final-x86_64-build8/publish/Saywing-0.1.5-8.dmg`
- Each directory has a private signed appcast, current SHA256SUMS and latest.json.
- `release-result.json` records acceptance, final byte/hash values and false public approval.
- Source snapshot: `.build/final-build8-source.tar.gz`; hash and file inventory
  count are in `.build/final-build8-source.json`. It contains no ignored runtime
  or model-weight files and does not substitute for a reviewed feature-branch PR.

ARM uses the existing ARM feed URL. Intel uses its own future
`/downloads/saywing/x86_64/appcast.xml`, so it cannot consume ARM packages.
That Intel production route has not been implemented/deployed or enabled by this
preparation. No live public update transport is claimed from a local feed check.

## Verified on the actual signed package resources

- Native binary checks: 222 ARM and 184 Intel files, architecture present, macOS
  minimum no newer than 14, accepted SDK metadata, no disallowed absolute native
  dependencies or escaping symlinks.
- Every runtime receipt and both project-owned worker files verified. Packaging
  now refreshes those workers from current source only after verifying inputs.
- ARM: 1,272 original license notices, all notice hashes verified.
- Intel: 83 original license notices, all notice hashes verified.
- Both carry all 16 pinned corresponding-source/archive/build-control inputs.
- Real 2x playback on both signed resource sets: 30.218 seconds source audio,
  zero underruns, maximum queue 7.939 seconds, clipboard unchanged. Intel runs
  through Rosetta. Earlier repeated Intel checks and cancellation passed too.
- Both actual dictation backends passed all 12 integration checks: public German
  and English fixtures, input/vocabulary validation, silence, cancellation and
  real OS-denied network and file writes. No user recording was used.
- 190 app tests in 14 suites and 25 release tests pass; localization passes.
  Two permission-dependent XCTest checks and the live optional-model network
  install remain explicit skips, not successful real-device tests.

Logs: `.build/final-{arm,intel}-playback.log`,
`.build/final-{arm,intel}-dictation.log`, `.build/final-candidate-app-tests.log`,
`.build/release-checks-final.log`; package-content-check.json beside each app.

## Intel correction

The fast-preroll regression failed before the fix. At 2x, Intel now waits for six
source seconds (three playback seconds), within the unchanged eight-second cap.
Normal-speed and ARM start behavior remain unchanged. Short texts drain at the
end of synthesis even below the threshold. The tradeoff is later startup for
fast Intel playback. No voice/model/quality parameter or playback rate is reduced.
A Rosetta test does not certify all physical Intel CPUs or actual macOS 14.

## License progress and remaining scope

Exact Cargo-lock archives for tokenizers, safetensors and hf-xet were checksum
verified; 1,028 distinct Rust notice files were added to source provenance and
ARM packaging. These form a conservative superset, including optional/build-only
and non-macOS entries. MPL/CDDL source archives were retained too. Matching Intel
Python build licenses are included, separate from the ARM provenance.

The bundled Python/SoundFile actually loaded a newly compiled libsndfile with
changed codec configuration and passed an in-memory WAV roundtrip. The test used
only local ad-hoc signing, not the official signing key. Its proof and limitations
are in `.build/lgpl-replacement-proof/result.json` and
`licenses/libsndfile-native-source-review.json`.

The remaining license review is not closed: tiktoken's sdist has no resolved
Cargo.lock/SBOM for its shipped binary. Sixteen crate versions are observable in
that binary's diagnostic strings, but that is not a complete dependency graph.
Some missing notices in the conservative inventories concern WASM/Windows/Android
or optional profiling dependencies; source manifests identify those scopes, but
no complete compiled-feature graph was produced. Do not present those entries
as proof of missing notices in the shipping macOS binary either. The full modified-app library replacement/receipt/seal check has now passed as
described below; it is separate from the remaining dependency-provenance review.

## Still required before public release

1. Finish the remaining compiled-dependency license proof.
2. Include the new 22 ARM notices and updated replacement instructions in the next
   signed package; these additions are not inside Apple's unchanged build-8 apps.
3. Actual native Intel/macOS 14 execution and fresh-account permission evidence;
   the owner's ARM functional/offline success is retained with its narrower scope.
4. Final in-app license UI and production HTTPS update path checks, plus reviewed
   source/CI integration. Intel public routing remains separate deployment work.

No release gate is bypassed merely because this candidate has a version number.

## Apple acceptance and final update metadata — follow-up

| Architecture | Apple submission | Final DMG bytes | SHA-256 |
|---|---|---:|---|
| arm64 | 38abb586-4f67-4023-98f7-be3569051472 | 1330203036 | `9a2630d50d4748355ae2d7b9e43cfed7f579c5ec6f5565e10b0fee16552f333d` |
| x86_64 | 86f0b484-b6d5-4a5c-9453-43c9b3a140cc | 1098693121 | `577154373b29563a34e434eda972b3b43be53b1e5d4fb696769ee43d647eaf7a` |

Evidence: `notary-status.json` and `release-result.json` beside each candidate;
`.build/final-build8-metadata.log` and `.build/final-build8-release-manifest.json`.
Apple notarization is not a license approval or proof of execution on every Mac.

The official Sparkle 2.10.0 CLI probed, downloaded and installed the **final stapled
ARM DMG** into a separate build-7 copy. It now reports 0.1.5/build 8; the executable
matches the accepted candidate, the strict app seal is valid and Gatekeeper
accepts it. Only the copied app was targeted. The exact-path local feed was signed
and served on 127.0.0.1; its server was stopped after the test. Production feed
files were not changed by this loopback exercise. This check covers installation,
not GUI presentation, relaunch (target was stopped), or production HTTPS.
Evidence: `.build/final-update-build8/{probe.log,install.log,verification.log,result.json}`.

## Further license evidence — follow-up

- The source inventory now holds **1,050** distinct original Rust notice files.
  Five wasm-tools crates and wasite now have their exact upstream license texts.
  The source-archive commits, URLs and hashes identify the originals.
- All **16** crate versions observed in tiktoken's binary diagnostic paths now
  have exact checksum-verified crate archives and **36** original notices. This
  includes five Rust standard-library dependency paths. It remains a partial
  observation, not a complete resolved dependency graph or binary SBOM.
- The remaining unnoted hf-xet lock entries have exact manifest-edge evidence:
  Android verifier, two Windows import-library targets and symbolic-common via
  symbolic-demangle. The latter relates to optional profiling; no full wheel
  compiled-feature attestation is claimed. See `licenses/remaining-rust-scope.json`.
- **22** notice files are new relative to accepted ARM build8. A private, hashed
  supplement lives in `.build/release-license-supplement-build8/inventory.json`.
  No accepted app or DMG was modified to insert them. The new notice set and
  updated corresponding-source instructions need inclusion before distribution.

The full app-copy replacement test passed: rebuilt libsndfile with a deliberately
changed codec configuration, ad-hoc-signed library and Python loader, two refreshed
receipt entries, valid complete app seal and both runtime receipts. A float-WAV
roundtrip and all 12 sandboxed default dictation checks passed; cancellation took
about 36 ms. The modified app remained alive in `--uitesting` mode. No official
signing key was used. Source records include exact procedure, results and scope in
`licenses/CorrespondingSource-README.md`, `licenses/library-replacement-validation.json`
and `licenses/libsndfile-native-source-review.json`. This closes the technical
library-replacement check; original all-codec bit-for-bit reproduction, real GUI
permissions and the broader license review are distinct claims.

The 25 release tests still pass after these evidence additions. Source supplement
hashes and both final metadata sets were checked. No production code changed in
this follow-up, so the prior 190 app-test results remain the applicable build check.
