# Supertonic 3 listening experiment — 2026-09-05

The owner requested a sample from the previously planned alternative model. This is an isolated development comparison, not a switch of the installed app, a silent fallback, or a release decision. The public German fixture is identical to [the Qwen comparison](german-voice-comparison.md). Both F1 (the previous research voice) and M1 (a male comparison to Aiden) are planned. These are **machine-generated voices**, not recordings of a person reading the fixture.

## Before-download record

Official model source: [Supertone/supertonic-3](https://huggingface.co/Supertone/supertonic-3/tree/3cadd1ee6394adea1bd021217a0e650ede09a323), revision `3cadd1ee6394adea1bd021217a0e650ede09a323`. The allowlist, exact sizes, upstream SHA-256 values for weights, and Git blob identifiers for small files are in [the manifest](supertonic-comparison-manifest.json). Only four ONNX models, configuration/indexer, two stock voice styles, README, and license are required (about 399 MB). No reference recordings, voice cloning, extra model variants, or cloud inference are used. Model files must stay outside Git and outside the installed app.

The complete pinned model LICENSE was read before downloading weights: BigScience Open RAIL-M dated August 18, 2022, **not MIT**. Its use restrictions and attribution/redistribution obligations must be carried forward for any future distribution; the project's Apache-2.0 license does not replace it. The requested public test text is unrelated to restricted uses. A full product licensing/distribution gate remains open.

Official inference helper source: [supertone-inc/supertonic](https://github.com/supertone-inc/supertonic/tree/7e2804f96016a7028cb1ed627353c61c1e9dd281), revision `7e2804f96016a7028cb1ed627353c61c1e9dd281`, `py/helper.py`. Its complete MIT license and helper were inspected before local reuse. Retain the upstream LICENSE beside the unchanged downloaded helper. The helper reads local ONNX/JSON files; the inspected synthesis path does not download anything.

The [upstream July 23 notice](https://github.com/supertone-inc/supertonic/blob/7e2804f96016a7028cb1ed627353c61c1e9dd281/README.md) announces discontinuation of development and official support. This newly checked maintenance risk must be considered before adopting Supertonic in the app.

Runtime plan: an isolated temporary Python environment with pinned ONNX Runtime `1.23.2` (PyPI reports MIT) and its dependencies. This patch release differs from upstream example's `1.23.1`; no claim of reproducing the earlier MLX benchmark is made. No packages are installed into system Python or the app. The CPython 3.12 macOS ARM64 wheel is 17,195,929 bytes, SHA-256 `b8f029a6b98d3cf5be564d52802bb50a8489ab73409fa9db0bf583eabb7c2321`. Actual resolved dependency versions and receipts will be retained with test artifacts. Distribution of this runtime is not authorized by this experiment.

Supertonic's official interface uses denoising steps and speed, not Qwen's sampling temperature. Planned comparison: explicit `de`, seed 42, 8 denoising steps, speed 1.0. Do not label it “temperature 0.2” or imply equivalent sampling controls. Actual synthesis is to run with networking denied; only requested public-fixture WAV exports may persist. Success and audible quality remain unverified until execution/listening.

## Actual execution and verification

The planned experiment completed locally on this Mac. Model assets and the unchanged helper plus its license are staged only in a temporary working directory outside Git (`$WORK` below); all ten allowlisted model files passed their size and upstream hash checks before inference. `receipt.json` there records SHA-256 for every downloaded file, including small files. The helper's measured SHA-256 is now also pinned in the committed manifest. Model weights, Python packages, upstream code, and generated audio are not committed or installed into the application.

The isolated Python 3.12.14 environment resolved: ONNX Runtime 1.23.2, NumPy 2.2.6, coloredlogs 15.0.1, flatbuffers 25.12.19, humanfriendly 10.0, mpmath 1.3.0, packaging 26.3, protobuf 7.36.1, sympy 1.14.0. Upstream package notices remain in that environment. This is a development dependency record, not a complete redistribution/license-chain audit.

Run the fixed-fixture generator only with the model prepared separately and an existing empty output directory. The actual command was (with `WORK` set to the absolute path of the temporary working directory):

```sh
PYTHONDONTWRITEBYTECODE=1 /usr/bin/sandbox-exec \
  -p "(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (literal \"/dev/null\") (subpath \"$WORK/samples\"))" \
  "$WORK/venv/bin/python" \
  scripts/compare-supertonic.py \
  "$WORK" \
  "$WORK/samples"
```

This script has no downloader or arbitrary-text input. It validates assets before importing the pinned helper, sets a 180-second deadline, bounds audio to 120 seconds, rejects non-finite/silent PCM, and exclusively creates WAV files without overwriting existing ones. It is a synchronous offline experiment, not an implementation of app cancellation/streaming. `Ctrl-C` terminates the test; already exported public-fixture files are retained for listening. No app provider was added.

Actual CPU model load: 0.307 seconds (one run). F1: 11.059 seconds of audio, synthesized in 2.677 seconds. M1: 11.071 seconds of audio, synthesized in 2.477 seconds. Both are 44.1 kHz mono PCM16, with no voice-specific gain or resampling, explicit German, seed 42, eight steps, speed 1.0. Both WAV files passed `afinfo` and independent SHA-256 comparison against the generated manifest. Qwen uses a different model, sample rate, segmentation, and inference runtime, so this is a listening comparison, not a controlled temperature-only comparison across providers.

Export safety tests were written first, failed before implementation, then passed (three tests: malformed/non-finite/silent PCM rejection, clamping without gain, exclusive no-overwrite creation). Actual model synthesis passed separately under the deny-network profile. No Swift source/target changed, so no new app build or UI regression is claimed. All 44 installed Qwen runtime receipt hashes remain unchanged. Audible accent, unwanted sounds, and word fidelity still require listening; timings and valid PCM do not establish quality.
