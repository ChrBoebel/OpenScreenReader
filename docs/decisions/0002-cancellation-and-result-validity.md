# ADR 0002: Cancellation and result validity

- Status: Accepted
- Date: 2026-09-04

## Context

`Esc` and the repeated hotkey must stop every observable part of an active selection-to-speech operation. OCR and model work may complete after cancellation when an underlying API is not cooperative. Late callbacks must never revive state or audio.

## Decision

- A single coordinator owns a monotonically increasing generation counter and an optional active generation.
- Starting creates and activates a new generation.
- Cancelling atomically revokes the active generation before cleanup starts.
- A start request received while work is active revokes that generation and returns only its cleanup directive. It does not issue a replacement generation in the same call.
- While cancellation cleanup is pending, all start requests return the same directive. A matching explicit cleanup acknowledgement is required before the coordinator can issue another generation.
- If timeout handling replaces the worker during pending cleanup, that outcome is recorded idempotently. Cleanup completion advances the worker epoch before releasing the start barrier in the same serialized operation.
- Every callback, status, error, and audio chunk passes through one serialized result gate.
- The gate accepts data only for the active generation and current worker process epoch.
- Cancellation order is: revoke generation, silence playback, dismiss overlay, cancel Swift/OS tasks, send worker cancel, wait for a bounded acknowledgement, then terminate and replace a non-cooperative worker.
- Each generation emits at most one terminal state.

## Consequences

- Immediate cancellation means immediate loss of observable effect, even if background compute takes longer to exit.
- Supersession cannot overlap a new generation with stale audio, overlay, task, or worker cleanup.
- Every asynchronous adapter must carry generation context.
- Worker restarts increment a separate epoch so output from a dead process can never match new work accidentally.

## Validation

Race tests cover cancel-without-restart, out-of-order callbacks, stale audio, worker replacement, ignored cancellation, and repeated cancellation storms before real OCR or TTS is integrated.
