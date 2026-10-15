Rust build and original-license evidence for Saywing

The adjacent Cargo.lock files are exact dependency inventories. The corresponding
*-source.json files record source URLs, SHA-256, selected macOS package graphs,
root licenses and compiler standard-library notices. The offline license index
retains all original dependency notices, conservatively including non-macOS and
build-only entries. No extra licensing restrictions are imposed on those components.

The tiktoken 0.14.0 source archive has no upstream Cargo.lock. This release uses an
unchanged-source local build with the included tiktoken-Cargo.lock, instead of the
previous binary wheel. Its complete build dependencies and original notices are
recorded. The root source is MIT licensed. The source itself was not edited.

Rebuild recipe (build-time internet is allowed to fetch the pinned dependencies;
the application worker remains offline):
1. Verify and extract tiktoken-0.14.0.tar.gz from CorrespondingSource against
   sources.json. Copy the included tiktoken-Cargo.lock to that source as Cargo.lock.
2. Install Rust 1.99.0 from the exact components in toolchain-inputs.json into a
   separate development directory. Verify each component's SHA-256. Do not use
   an unpinned newer toolchain. rustc -Vv must report commit
   b940084d7eb6a299eb4bfeb8e34901bc051e7ac4.
3. Add that toolchain's bin directory to PATH. Set a separate CARGO_HOME and
   CARGO_TARGET_DIR. Set MACOSX_DEPLOYMENT_TARGET=14.0 and PYO3_PYTHON to the
   bundled ARM CPython 3.12.15 executable in a development app copy.
4. From the source directory run:
   cargo fetch --locked --target aarch64-apple-darwin
   cargo metadata --locked --offline --format-version 1 --features python --filter-platform aarch64-apple-darwin
   cargo rustc --locked --offline --release --lib --features python --target aarch64-apple-darwin -- -C link-arg=-undefined -C link-arg=dynamic_lookup
5. The output is aarch64-apple-darwin/release/libtiktoken.dylib under CARGO_TARGET_DIR.
   In a separate app copy, it replaces
   Dictation/Python/lib/python3.12/site-packages/tiktoken/_tiktoken.cpython-312-darwin.so.
   Local modifications require re-signing and receipt refresh as described in
   CorrespondingSource/README.md. Original signing keys are not necessary.

The release build retains a hash of each reviewed native file after removing
its code signature from a temporary copy. This binds license coverage to the
actual code while allowing Developer ID re-signing. It is not a claim that an
arbitrary machine/toolchain will produce byte-identical compiler output.

The three retained upstream wheels (tokenizers, safetensors, hf-xet) are pinned
by their original archive hashes. Their shipped source lock inventories and
macOS graph are covered; observed binary crate versions match those locks.
Their original compiler standard-library notices are included too. No independent
reproducible build attestation is claimed for those upstream wheels.
