Rust build and original-license evidence for Saywing

The Apple Silicon dictation runtime contains three Rust extensions, each unmodified from
its hash-pinned PyPI wheel: tokenizers 0.23.3, safetensors 0.8.0 and tiktoken 0.14.0.
The Intel runtimes and the speech runtimes contain no Rust code.

The adjacent Cargo.lock files are dependency inventories. The *-source.json files record
source URLs, SHA-256, the selected macOS package graphs, root licenses and the compiler
standard-library notices. Crate versions visible in each binary were cross-checked
against these locks:

- tokenizers (Rust 1.99.0) and safetensors (Rust 1.95.0): every observed version is in
  the upstream source lock.
- tiktoken (Rust 1.97.1): the source archive has no Cargo.lock. tiktoken-Cargo.lock is
  the reference lock of the rebuild recipe below. The upstream wheel was resolved with
  fancy-regex 0.19.0 and pyo3 0.29.2 instead; tiktoken-source.json lists those versions,
  and their original notices are included.

The offline license index retains all original dependency notices, conservatively
including non-macOS and build-only entries. No extra licensing restrictions are imposed
on those components. No independent reproducible-build attestation is claimed for the
upstream wheels.

Rebuilding tiktoken from its original source (build-time internet fetches the pinned
crates; the application worker remains offline):
1. Obtain tiktoken-0.14.0.tar.gz from the URL in CorrespondingSource/sources.json (or
   under the written offer in CorrespondingSource/README.md), verify its size and SHA-256
   and extract it. Copy the included tiktoken-Cargo.lock to that source as Cargo.lock.
2. Install Rust 1.99.0 from the exact components in toolchain-inputs.json into a
   separate development directory and verify each component's SHA-256.
   rustc -Vv must report commit b940084d7eb6a299eb4bfeb8e34901bc051e7ac4.
3. Add that toolchain's bin directory to PATH. Set a separate CARGO_HOME and
   CARGO_TARGET_DIR. Set MACOSX_DEPLOYMENT_TARGET=14.0 and PYO3_PYTHON to the
   bundled ARM CPython 3.12.15 executable in a development app copy.
4. From the source directory run:
   cargo fetch --locked --target aarch64-apple-darwin
   cargo rustc --locked --offline --release --lib --features python --target aarch64-apple-darwin -- -C link-arg=-undefined -C link-arg=dynamic_lookup
5. The output is aarch64-apple-darwin/release/libtiktoken.dylib under CARGO_TARGET_DIR.
   In a separate app copy, it replaces
   Dictation/Python/lib/python3.12/site-packages/tiktoken/_tiktoken.cpython-312-darwin.so.
   Local modifications require re-signing and a receipt refresh as described in
   CorrespondingSource/README.md. Original signing keys are not necessary.

The release build keeps a hash of each reviewed Rust binary after removing its code
signature from a temporary copy. This binds license coverage to the actual code while
allowing Developer ID re-signing. It is not a claim that another machine or toolchain
produces byte-identical output.
