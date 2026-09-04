# ADR 0002: Cancellation and result validity

- Status: Accepted
- Date: 2026-09-04

## Context

`Esc` and the repeated hotkey must stop every observable part of an active selection-to-speech operation. OCR and model work may complete after cancellation when an underlying API is not cooperative. Late callbacks must never revive state or audio.

## Decision

- A single coordinator owns a monotonically increasing generation counter and an optional active generation.
- Starting creates and activates a new generation.
- Cancelling atomically revokes the active generation before cleanup starts.
- Every callback, status, error, and audio chunk passes through one serialized result gate.
- The gate accepts data only for the active generation and current worker process epoch.
- Cancellation order is: revoke generation, silence playback, dismiss overlay, cancel Swift/OS tasks, send worker cancel, wait for a bounded acknowledgement, then terminate and replace a non-cooperative worker.
- Each generation emits at most one terminal state.

## Consequences

- Immediate cancellation means immediate loss of observable effect, even if background compute takes longer to exit.
- Every asynchronous adapter must carry generation context.
- Worker restarts increment a separate epoch so output from a dead process can never match new work accidentally.

## Validation

Race tests cover cancel-without-restart, out-of-order callbacks, stale audio, worker replacement, ignored cancellation, and repeated cancellation storms before real OCR or TTS is integrated.
