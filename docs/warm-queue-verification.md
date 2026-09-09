# Warm queue preparation — 2026-09-09

## Scope

One model process per session, one next-text preparation, bounded RAM-only PCM, serial synthesis with priority for the current text, 120 ms cancellable separation on prepared handoff. No model, voice, seed policy, inference-step count, helper, dependency or permission changes. The worker protocol is explicitly version 2 with request IDs; old single-request mode remains compatible. The project-owned worker and its receipt hash were updated explicitly with `scripts/update-supertonic-worker.rb`.

## Actual checks

- New session-protocol test failed before implementation (unsupported `session` argument), then all six Python tests passed. They cover strict fields/IDs, bounds, segmentation, required packet acknowledgements and model/style loading exactly once for two separately tagged requests.
- Swift RAM-channel tests exercise bounded producer backpressure, draining and cancellation of blocked producers/consumers. AppModel queue tests verify that only the next FIFO entry is prepared, it advances when consumed, and full stop discards it.
- Initial real two-text test: 1,238,656 bytes already prepared, 72 ms from handoff call to player start, one worker launch, zero reported underruns in either text, clipboard unchanged. This preceded the intentional 120 ms separation.
- Real two-text test at 2× including the 120 ms separation: 1,238,656 prepared bytes, 181 ms handoff-to-player-start, one worker launch with the same PID, zero reported underruns in either text, clipboard unchanged. Separate cancellation checks: 11.66 ms during playback and 0.06 ms during model loading; no late playback callbacks.
- Real skip to a partially prepared successor at 2×: 384,000 bytes ready, 152 ms to player start, still one worker launch, zero underruns. Real stop while successor audio was already buffered: both RAM buffers cleared, worker gone, clipboard unchanged.
- Two long identical passages at 2× (successor exceeds preparation capacity): 1,319,412 prepared bytes, 152 ms handoff, one worker launch and zero underruns across both passages. Bounded backpressure resumed after promotion and playback drained successfully. This is not a separate linguistic-fidelity audit.
- All 80 Swift app tests passed, including cancellation before the scheduled preparation task can create a worker. Six Python tests passed. The existing real worker verifier passed finite/non-silent PCM, bounded packets, generic errors and enforced network/write denial. These privacy checks exercise the same sandbox profile; they are not a packaged-release audit.
- Late-addition test with zero audio bytes prepared at handoff: 993 ms to player start at 2×, one worker launch, zero underruns in both passages. This demonstrates that warm reuse still helps, but late additions are not instant. The final app-test rerun after watchdog generation protection passed all 80 tests; the two permission-dependent capture/Escape tests were explicitly skipped for the test host.
- Final Release build and strict signature verification passed. Installed `/Applications/OpenScreenReader.app` is byte-for-byte equal to that build; executable SHA-256 `189164da255d901685e160ffa2dc3ccd9cfcb5a034985146ab5a95428d7df6f6`. Previous canonical app was moved to Trash, recoverably. Source/installed worker and its receipt agree on SHA-256 `dd48a6546faab2030e4c649760b61d519fc7bdbdf7c84aba184e10a28f89857a`; model/helper/dependency files were not changed.
- Computer Use was attempted against the installed app and reported that the Mac is locked and cannot be automatically unlocked. The user must unlock it for UI verification. No screen inspection, successful GUI launch or live OCR/queue test is claimed from this attempt.

These timings measure the application's player-start callback, not microphone-recorded first audible phoneme. Model-generated leading/trailing silence and audio-device latency are additional. Fixed public German fixtures were used; no selected/private text, PCM, or screenshots were persisted.

## Limits

Preparation starts after current synthesis has completed, while its buffered tail still plays. A very late addition, long/slow synthesis, skip before current synthesis completes, or an idle worker expiry can still cause waiting. This is not a blanket gapless guarantee. Current transport, next transport and player each admit eight source seconds (about 4.04 MiB combined), plus bounded in-flight/encoded packets and engine/worker/model memory. The single worker's bounded sentence waveform remains separate from that Swift-buffer limit.

Real selection/OCR during speech, broad display/Space/TCC checks, subjective quality, extended energy/memory benchmarks and packaged release verification remain separate gates. No fabricated Computer Use or permission-dependent test is substituted for a blocked path.
