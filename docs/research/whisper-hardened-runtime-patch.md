# Whisper packaging correction for Hardened Runtime

Observed 2026-10-14 in a real Developer ID-signed private app. Plain Python,
NumPy and MLX imported, but starting the actual Whisper worker was killed with
`SIGKILL (Code Signature Invalid)`, `CODESIGNING / Invalid Page`.
The crash stack reached `LLVMPY_TryAllocateExecutableMemory` from Numba/LLVM.
This is a signing/runtime compatibility failure, not an ASR accuracy failure.

The pinned `mlx-whisper` **0.4.3** eagerly imports `timing.py`, which imports Numba
and probes executable JIT memory. Saywing already calls Whisper with
`word_timestamps=False` and never uses that optional timing implementation.

`scripts/patch-dictation-runtime.py` moves the single timing import into the
existing `if word_timestamps:` branch before packaging receipts and signing.
It checks the exact upstream source SHA-256, package version and MIT metadata,
and refuses unknown source instead of applying a guessed patch. An already
patched source is accepted only if reversing exactly that edit reproduces the
approved upstream hash. The bundled patch record contains both hashes.

- Upstream `transcribe.py` SHA-256:
  `21f015e0d56c5e6194d07d86d772730940fff52d8f06d55838ae92ebccc24fbb`.
- Source: [Apple's mlx-examples Whisper implementation](https://github.com/ml-explore/mlx-examples/tree/main/whisper).
- License: MIT, verified against installed 0.4.3 package metadata and the
  [upstream license](https://github.com/ml-explore/mlx-examples/blob/main/LICENSE).
- Complete copyright/permission notice: `docs/licenses/mlx-examples-MIT.txt`,
  SHA-256 `ccfab7ccb2ea306f71531c8ca77bb55507606cd90768b1e32b8b52ab5b48cf01`;
  packaging copies it to `Dictation/Licenses/LICENSE-mlx-examples`.
- No model weights, model revision, Python permissions, signing entitlements or
  sandbox policy changed. Word timestamps remain disabled in Saywing.

The corrected app was re-signed with the existing Developer ID, its strict/deep
signature verified, and the actual bundled Whisper Turbo worker passed all ten
integration checks: offline/no-write loading, German 48 kHz, English warm model,
explicit German/English, silence, malformed samples, inference cancellation,
network denial and write denial. This test uses bundled public audio fixtures,
not a microphone recording or user text. The packaging helper was also applied
twice to an isolated copy of the exact upstream source to verify idempotence.

The first notarization submission predates this correction and must not be used
as evidence for the corrected bundle; the corrected DMG was notarized separately.
Hosted CI builds/signs this correction but does not prove on-device MLX
inference; the real Apple Silicon runtime test remains a separate release check.
