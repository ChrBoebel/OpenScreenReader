# Saywing 0.1.5 / build 9 — private candidate with completed Rust notices

Later owner decision: [publish an Apple Silicon beta after the HTTPS test](beta-publication-2026-10-15.md). The private-candidate status below describes this checkpoint.

This checkpoint supersedes the open Rust-notice and missing-new-notice findings in
the build-8 report. Both new architecture packages are built and Developer ID signed.
Apple accepted both build-9 packages. Both DMG tickets are stapled and validated,
both apps and DMGs pass Gatekeeper, and both final update metadata sets are verified.
Nothing was published, committed, pushed, merged or deployed. Public gates remain closed.

## Rust dependency and original-notice evidence

- All four bundled Rust extensions are bound to signature-normalized code hashes
  in `licenses/rust-license-coverage.json`. Packaging rejects changed or unreviewed
  Rust libraries and incomplete coverage. Three new negative regression tests pass.
- The original tiktoken 0.14.0 wheel had no complete resolved dependency evidence.
  It is replaced by a local build of unchanged, SHA-256-pinned MIT source with
  a retained Cargo.lock and Rust 1.99.0. Compilation used `--locked --offline`,
  the bundled CPython 3.12.15, the ARM target and macOS 14 minimum.
- Exact source locks and macOS feature graphs cover tokenizers, safetensors,
  hf-xet and rebuilt tiktoken: respectively 128, 41, 242 and 25 active packages
  including workspace roots. Every active registry package has original notices.
  The conservative complete-lock inventories retain 1,069 distinct Rust notices.
- The four formerly unnoted hf-xet lock entries are absent from its active macOS
  source graph. Binary-observed versions of the three retained upstream wheels
  match their source locks. This is source/notice coverage for hash-pinned wheels,
  not an independent reproducible-build attestation for those three binaries.
- Complete compiler-distributed standard-library copyright inventories and original
  MIT/Apache texts for Rust 1.95.0, 1.98.0 and 1.99.0 are included, with pinned
  official archive URLs/hashes. Root licenses and the tokenizer rebuild recipe are
  under `Licenses/RustBuild` inside the app.

Actual tokenizer comparison: **5,014 German/English/public-Unicode cases** and
**51,865 vocabulary entries** produce exactly the same result digest before/after
replacement. The rebuilt source app also passed all 12 real dictation checks.
Logs and comparison JSON: `.build/rust-license-build/`.

## Contents and execution of the final signed apps

| Check | Apple Silicon | Intel |
|---|---:|---:|
| Original notice files, all SHA-256 verified | 1,330 | 88 |
| Included source archives/build-control inputs, all size/hash verified | 20 | 20 |
| Audited native files (architecture and minimum macOS 14) | 222 | 184 |
| Actual sandboxed default dictation checks | 12 passed | 12 passed via Rosetta |
| Isolated 2× speech playback | 0 underruns | 0 underruns via Rosetta |

Both complete runtime receipts and the Rust code hashes pass on the actual signed
apps. All four source locks, rebuild evidence and updated full-app LGPL replacement
instructions are included. The earlier real modified-libsndfile full-app test
remains applicable; no libsndfile code changed for build 9.

Playback processed 30.218 source-audio seconds with maximum queue 7.939 seconds;
the clipboard remained unchanged. An initial Intel run concurrently with real
Intel dictation and ARM signing had 3 underruns (19.106 missing seconds). Its log
is retained as `final-build9-intel-playback-under-load.log`. The repeat without
parallel model work passed. This establishes the isolated path, not immunity to
CPU contention or speed guarantees for all physical Intel Macs.

Both Xcode Release architecture builds pass. **28 release tests pass.** No Swift
production code changed in this license-only follow-up; the previous 190 app-test
results remain the applicable app-code verification, including the previously
recorded permission-dependent skips. No skipped check is counted as passed.

Actual browser check of the final ARM HTML document: all 1,330 notice sections
render, German/English Supertonic scope is readable, original model terms and
Rust rebuild/license texts expand offline, and there are zero remote resources.
Evidence: `offline-license-ui-check.json` beside the ARM app.

The final Intel build 9 also passed actual native Settings and Setup interactions
under Rosetta: readable model-scope notices and enabled license buttons opened
the exact bundled HTML file with the expected title. Permission steps were skipped
without granting access or completing setup. Browser policy prevented direct
observation of this file page in that interaction; no alternate access was used.
Evidence: `native-license-ui-check.json` beside the Intel app.

The current local website build was checked in German and English: its privacy
section shows the model-use notice and original-license link. Downloads remained
disabled. The source also includes the notice below an enabled download. The
original model-license SHA-256 matches the bundled text. The temporary preview
was stopped; production was not changed. Evidence:
`.build/final-build9-license-presentation.json`.

The technical license inventory, packaging and presentation review is complete.
This records the engineering review and its evidence, not an external legal opinion.

The earlier unsigned development-copy launch was blocked by macOS. The owner
confirmed choosing Trash, explaining its removal. The copy was recreated and
fully Developer-ID signed before the successful tokenizer/dictation checks.
The original accepted build-8 apps and DMGs were not changed.

## Private artifacts and Apple processing

- ARM: `.build/rc-final-arm64-build9/publish/Saywing-0.1.5-9.dmg`
  Submission: `031d9b93-9282-4d6c-9c49-7fb81f478139`.
- Intel: `.build/rc-final-x86_64-build9/publish/Saywing-0.1.5-9.dmg`
  Submission: `b4698f3a-a99a-4698-92e0-ddfe07e26f7a`.
- Each directory retains native audit, verified content inventory, appcast,
  final metadata and Apple status. The manifest retains historical before-stapling
  hashes separately from the final bytes for both architectures.
- A replacement ARM CI runtime ZIP is prepared locally as
  `.build/saywing-runtime-arm64-build9.zip`, with CRC validation and SHA-256 in the
  adjacent JSON. It is not uploaded; the existing GitHub runtime pin is unchanged.

The ARM and Intel feeds retain separate HTTPS paths. Intel production routing
is not deployed. Both post-staple DMGs have verified enclosure signatures, signed
appcasts, sizes, SHA-256 sums and latest.json metadata.

The actual ARM build-8→9 update passed using the official Sparkle 2.10.0 CLI
against a signed localhost feed and the final stapled DMG. Sparkle downloaded,
extracted and installed the update in an isolated stopped copy. The resulting
0.1.5/build-9 app passes strict signature and Gatekeeper checks; its executable
matches the accepted candidate. All 1,330 installed notice hashes and the Rust
code/coverage proof pass. The temporary server was stopped. Evidence:
`.build/final-update-build9/result.json`, `probe.log`, `install.log`, and
`verification.log`. This proves local installation, not production HTTPS or a
GUI restart for build 9; earlier GUI restart evidence applies to earlier builds.

## Remaining release gates

1. Actual native Intel/macOS 14 and fresh-account permission tests. Owner-reported
   ARM install/read/dictate/offline success remains recorded with its known scope;
   it does not establish an OS version or the full permission matrix.
2. Protected production HTTPS update verification, reviewed feature-branch source
   integration and the new private CI runtime pin. Public feed/deployment flags
   must remain disabled until explicitly authorized for publication.

`license_review`, `offline_privacy` and the scoped local `update_roundtrip` are
true. `clean_mac` remains false, keeping the aggregate public release gate closed.

The current request does not authorize publication. No production settings, private
website download, stored signing credentials or existing accepted package were altered.

## Intel Apple acceptance and final metadata

Apple accepted submission `b4698f3a-a99a-4698-92e0-ddfe07e26f7a`.
The DMG ticket is stapled and validated; both DMG and app are accepted by
Gatekeeper as Notarized Developer ID. The appcast and enclosure signatures were
regenerated and verified after stapling. Final Intel DMG: **1,099,185,763 bytes**,
SHA-256 `6825053c756c51defb3b50232b1a9b37121f419d00f7851a243b2b267a07065f`.
This is Apple notarization, not license approval or physical-Intel test evidence.

## ARM Apple acceptance and final metadata

Apple accepted submission `031d9b93-9282-4d6c-9c49-7fb81f478139`.
The ticket is stapled and validated; both app and DMG are accepted by Gatekeeper
as Notarized Developer ID. Final ARM DMG: **1,354,130,605 bytes**,
SHA-256 `4d3f4bdd0681c4197e3242731d0e6628b609b73674470674511bfa779c392e3e`.
The signed appcast and enclosure, latest.json and SHA256SUMS describe these final
bytes. The successful build-8→9 installation used this exact DMG.
