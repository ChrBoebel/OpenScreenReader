import OpenScreenReaderCore

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard condition() else {
        throw CheckFailure(description: "\(file):\(line): \(message)")
    }
}

@main
struct OpenScreenReaderCoreBehaviorChecks {
    static func main() async throws {
        try await run("start creates selecting generation", startCreatesSelectingGeneration)
        try await run("cancel revokes generation and rejects late result", cancelRevokesGeneration)
        try await run("new start supersedes active generation", newStartSupersedesActiveGeneration)
        try await run("worker replacement rejects old epoch", workerReplacementRejectsOldEpoch)
        try await run(
            "pending cancellation records worker replacement",
            pendingCancellationRecordsWorkerReplacement
        )
        try await run("only legal forward transitions are accepted", onlyLegalTransitionsAreAccepted)
        try await run("completion emits one terminal state", completionEmitsOneTerminalState)
        try await run("failure emits one terminal state", failureEmitsOneTerminalState)
        try await run("inactive cancellation does nothing", inactiveCancellationDoesNothing)
        print("All 9 OpenScreenReaderCore behavior checks passed.")
    }

    private static func run(
        _ name: String,
        _ check: () async throws -> Void
    ) async throws {
        try await check()
        print("PASS: \(name)")
    }

    private static func startContext(
        _ coordinator: PipelineCoordinator
    ) async throws -> PipelineOperationContext {
        switch await coordinator.start() {
        case let .started(context):
            context
        case .cleanupRequired:
            throw CheckFailure(description: "expected a new context, but cleanup is still required")
        }
    }

    private static func startCreatesSelectingGeneration() async throws {
        let coordinator = PipelineCoordinator()

        let context = try await startContext(coordinator)
        let snapshot = await coordinator.snapshot()

        try expect(context.generation.rawValue == 1, "first generation must be 1")
        try expect(context.workerEpoch.rawValue == 1, "first worker epoch must be 1")
        try expect(snapshot.activeContext == context, "started context must be active")
        try expect(snapshot.phase == .selecting, "pipeline must begin in selecting")
        try expect(snapshot.lastTerminal == nil, "fresh coordinator must not have a terminal state")
        try expect(snapshot.pendingCancellation == nil, "fresh coordinator must not require cleanup")
    }

    private static func cancelRevokesGeneration() async throws {
        let coordinator = PipelineCoordinator()
        let context = try await startContext(coordinator)

        let directive = await coordinator.cancel()
        let blockedStart = await coordinator.start()
        let snapshot = await coordinator.snapshot()
        let accepted = await coordinator.accept(.capturing, for: context)

        try expect(
            directive?.steps == [
                .silenceAudio,
                .dismissOverlay,
                .cancelLocalTasks,
                .requestWorkerCancellation,
                .awaitWorkerAcknowledgement,
                .terminateUnresponsiveWorker,
            ],
            "cancellation order must be deterministic"
        )
        try expect(snapshot.activeContext == nil, "cancellation must revoke the active context")
        try expect(snapshot.phase == .idle, "cancellation must return to idle")
        try expect(snapshot.pendingCancellation == directive, "cancellation must publish its cleanup barrier")
        try expect(
            snapshot.lastTerminal == PipelineTerminal(context: context, reason: .stopped),
            "cancellation must record a stopped terminal state"
        )
        try expect(!accepted, "results arriving after cancellation must be rejected")
        try expect(
            blockedStart == .cleanupRequired(directive!),
            "a new start must wait until cancellation cleanup completes"
        )
    }

    private static func newStartSupersedesActiveGeneration() async throws {
        let coordinator = PipelineCoordinator()
        let first = try await startContext(coordinator)

        let supersession = await coordinator.start()
        let repeatedStartBeforeCleanup = await coordinator.start()
        let supersededSnapshot = await coordinator.snapshot()
        let oldAccepted = await coordinator.accept(.capturing, for: first)
        guard case let .cleanupRequired(cleanup) = supersession else {
            throw CheckFailure(description: "supersession must require cleanup before starting")
        }
        let unrelatedContext = PipelineOperationContext(
            generation: PipelineGeneration(rawValue: 999),
            workerEpoch: first.workerEpoch
        )
        let unrelatedCleanupAcknowledged = await coordinator.finishCleanup(for: unrelatedContext)
        let stillBlockedAfterUnrelatedCleanup = await coordinator.start()
        let cleanupAcknowledged = await coordinator.finishCleanup(for: cleanup.context)
        let second = try await startContext(coordinator)
        let newAccepted = await coordinator.accept(.capturing, for: second)
        let snapshot = await coordinator.snapshot()

        try expect(cleanup.context == first, "cleanup must target the superseded context")
        try expect(
            cleanup.steps == [
                .silenceAudio,
                .dismissOverlay,
                .cancelLocalTasks,
                .requestWorkerCancellation,
                .awaitWorkerAcknowledgement,
                .terminateUnresponsiveWorker,
            ],
            "supersession cleanup order must be deterministic"
        )
        try expect(
            repeatedStartBeforeCleanup == .cleanupRequired(cleanup),
            "repeated starts must not bypass the cleanup barrier"
        )
        try expect(supersededSnapshot.activeContext == nil, "supersession must revoke before cleanup")
        try expect(supersededSnapshot.phase == .idle, "supersession must become idle before cleanup")
        try expect(
            supersededSnapshot.pendingCancellation == cleanup,
            "snapshot must expose the pending supersession cleanup"
        )
        try expect(!unrelatedCleanupAcknowledged, "unrelated cleanup must not release the barrier")
        try expect(
            stillBlockedAfterUnrelatedCleanup == .cleanupRequired(cleanup),
            "a rejected cleanup acknowledgement must leave the barrier active"
        )
        try expect(cleanupAcknowledged, "matching cleanup completion must release the start barrier")
        try expect(second.generation.rawValue == 2, "a repeated start must create a new generation")
        try expect(second.workerEpoch == first.workerEpoch, "start must not replace the worker")
        try expect(!oldAccepted, "superseded results must be rejected")
        try expect(newAccepted, "current generation results must be accepted")
        try expect(snapshot.activeContext == second, "second context must remain active")
        try expect(snapshot.phase == .capturing, "accepted transition must update the phase")
        try expect(snapshot.pendingCancellation == nil, "completed cleanup must clear the barrier")
        try expect(
            snapshot.lastTerminal == PipelineTerminal(context: first, reason: .superseded),
            "repeated start must record supersession"
        )
    }

    private static func workerReplacementRejectsOldEpoch() async throws {
        let coordinator = PipelineCoordinator()
        let oldContext = try await startContext(coordinator)

        let directive = await coordinator.replaceWorker()
        let oldAccepted = await coordinator.accept(.capturing, for: oldContext)
        let blockedStart = await coordinator.start()
        guard let directive else {
            throw CheckFailure(description: "active worker replacement must return cleanup")
        }
        let cleanupAcknowledged = await coordinator.finishCleanup(for: directive.context)
        let newContext = try await startContext(coordinator)
        let snapshot = await coordinator.snapshot()

        try expect(!oldAccepted, "old worker epoch results must be rejected")
        try expect(
            blockedStart == .cleanupRequired(directive),
            "replacement cleanup must finish before new work starts"
        )
        try expect(cleanupAcknowledged, "worker cleanup must release the start barrier")
        try expect(newContext.generation.rawValue == 2, "new start must advance generation")
        try expect(newContext.workerEpoch.rawValue == 2, "worker replacement must advance epoch")
        try expect(snapshot.workerEpoch.rawValue == 2, "snapshot must expose current worker epoch")
        try expect(
            snapshot.lastTerminal == PipelineTerminal(context: oldContext, reason: .workerReplaced),
            "worker replacement must record its terminal reason"
        )
    }

    private static func pendingCancellationRecordsWorkerReplacement() async throws {
        let coordinator = PipelineCoordinator()
        let cancelledContext = try await startContext(coordinator)

        guard let cancellation = await coordinator.cancel() else {
            throw CheckFailure(description: "active cancellation must return cleanup")
        }
        let firstReplacementRequest = await coordinator.replaceWorker()
        let repeatedReplacementRequest = await coordinator.replaceWorker()
        let beforeCleanup = await coordinator.snapshot()
        let cleanupAcknowledged = await coordinator.finishCleanup(for: cancellation.context)
        let afterCleanup = await coordinator.snapshot()
        let replacementContext = try await startContext(coordinator)
        let staleAccepted = await coordinator.accept(.capturing, for: cancelledContext)

        try expect(
            firstReplacementRequest == cancellation,
            "worker replacement during cleanup must preserve the cancellation directive"
        )
        try expect(
            repeatedReplacementRequest == cancellation,
            "repeated worker replacement requests must be idempotent"
        )
        try expect(
            beforeCleanup.workerEpoch == cancelledContext.workerEpoch,
            "pending replacement must not publish its epoch before cleanup completes"
        )
        try expect(cleanupAcknowledged, "matching cleanup must release the barrier")
        try expect(
            afterCleanup.workerEpoch.rawValue == cancelledContext.workerEpoch.rawValue + 1,
            "replacement epoch must be visible when the cleanup barrier is released"
        )
        try expect(
            afterCleanup.pendingCancellation == nil,
            "epoch publication and barrier release must occur together"
        )
        try expect(
            replacementContext.workerEpoch.rawValue == cancelledContext.workerEpoch.rawValue + 1,
            "cleanup completion must atomically publish the replacement epoch"
        )
        try expect(!staleAccepted, "output from the replaced worker epoch must remain stale")
    }

    private static func onlyLegalTransitionsAreAccepted() async throws {
        let coordinator = PipelineCoordinator()
        let context = try await startContext(coordinator)

        let skippedCapture = await coordinator.accept(.recognizing, for: context)
        let captured = await coordinator.accept(.capturing, for: context)
        let skippedRecognition = await coordinator.accept(.speaking, for: context)
        let recognized = await coordinator.accept(.recognizing, for: context)
        let synthesized = await coordinator.accept(.synthesizing, for: context)
        let spoke = await coordinator.accept(.speaking, for: context)
        let movedBackward = await coordinator.accept(.capturing, for: context)

        try expect(!skippedCapture, "pipeline must not skip capture")
        try expect(captured, "selecting must advance to capturing")
        try expect(!skippedRecognition, "pipeline must not skip recognition and synthesis")
        try expect(recognized, "capturing must advance to recognizing")
        try expect(synthesized, "recognizing must advance to synthesizing")
        try expect(spoke, "synthesizing must advance to speaking")
        try expect(!movedBackward, "pipeline must not move backward")
    }

    private static func completionEmitsOneTerminalState() async throws {
        let coordinator = PipelineCoordinator()
        let context = try await startContext(coordinator)

        let firstCompletion = await coordinator.complete(context)
        let secondCompletion = await coordinator.complete(context)
        let lateFailure = await coordinator.fail(context)
        let snapshot = await coordinator.snapshot()

        try expect(firstCompletion, "active context must be completable")
        try expect(!secondCompletion, "completion must only be accepted once")
        try expect(!lateFailure, "a terminal context must reject later failures")
        try expect(snapshot.activeContext == nil, "completion must revoke the active context")
        try expect(
            snapshot.lastTerminal == PipelineTerminal(context: context, reason: .completed),
            "completion must record its terminal reason"
        )
    }

    private static func failureEmitsOneTerminalState() async throws {
        let coordinator = PipelineCoordinator()
        let context = try await startContext(coordinator)
        _ = await coordinator.accept(.capturing, for: context)

        let firstFailure = await coordinator.fail(context)
        let lateCancel = await coordinator.cancel()
        let snapshot = await coordinator.snapshot()

        try expect(firstFailure, "active context must be failable")
        try expect(lateCancel == nil, "a failed context must not be cancelled again")
        try expect(
            snapshot.lastTerminal == PipelineTerminal(context: context, reason: .failed),
            "failure must record its terminal reason"
        )
    }

    private static func inactiveCancellationDoesNothing() async throws {
        let coordinator = PipelineCoordinator()

        let directive = await coordinator.cancel()
        let snapshot = await coordinator.snapshot()

        try expect(directive == nil, "inactive cancellation must not produce work")
        try expect(snapshot.phase == .idle, "inactive coordinator must remain idle")
        try expect(snapshot.activeContext == nil, "inactive coordinator must have no context")
        try expect(snapshot.lastTerminal == nil, "inactive cancellation must not add history")
    }
}
