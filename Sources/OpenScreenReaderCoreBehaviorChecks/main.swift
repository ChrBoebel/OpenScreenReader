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
        try await run("only legal forward transitions are accepted", onlyLegalTransitionsAreAccepted)
        try await run("completion emits one terminal state", completionEmitsOneTerminalState)
        try await run("failure emits one terminal state", failureEmitsOneTerminalState)
        try await run("inactive cancellation does nothing", inactiveCancellationDoesNothing)
        print("All 8 OpenScreenReaderCore behavior checks passed.")
    }

    private static func run(
        _ name: String,
        _ check: () async throws -> Void
    ) async throws {
        try await check()
        print("PASS: \(name)")
    }

    private static func startCreatesSelectingGeneration() async throws {
        let coordinator = PipelineCoordinator()

        let context = await coordinator.start()
        let snapshot = await coordinator.snapshot()

        try expect(context.generation.rawValue == 1, "first generation must be 1")
        try expect(context.workerEpoch.rawValue == 1, "first worker epoch must be 1")
        try expect(snapshot.activeContext == context, "started context must be active")
        try expect(snapshot.phase == .selecting, "pipeline must begin in selecting")
        try expect(snapshot.lastTerminal == nil, "fresh coordinator must not have a terminal state")
    }

    private static func cancelRevokesGeneration() async throws {
        let coordinator = PipelineCoordinator()
        let context = await coordinator.start()

        let directive = await coordinator.cancel()
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
        try expect(
            snapshot.lastTerminal == PipelineTerminal(context: context, reason: .stopped),
            "cancellation must record a stopped terminal state"
        )
        try expect(!accepted, "results arriving after cancellation must be rejected")
    }

    private static func newStartSupersedesActiveGeneration() async throws {
        let coordinator = PipelineCoordinator()
        let first = await coordinator.start()

        let second = await coordinator.start()
        let oldAccepted = await coordinator.accept(.capturing, for: first)
        let newAccepted = await coordinator.accept(.capturing, for: second)
        let snapshot = await coordinator.snapshot()

        try expect(second.generation.rawValue == 2, "a repeated start must create a new generation")
        try expect(second.workerEpoch == first.workerEpoch, "start must not replace the worker")
        try expect(!oldAccepted, "superseded results must be rejected")
        try expect(newAccepted, "current generation results must be accepted")
        try expect(snapshot.activeContext == second, "second context must remain active")
        try expect(snapshot.phase == .capturing, "accepted transition must update the phase")
        try expect(
            snapshot.lastTerminal == PipelineTerminal(context: first, reason: .superseded),
            "repeated start must record supersession"
        )
    }

    private static func workerReplacementRejectsOldEpoch() async throws {
        let coordinator = PipelineCoordinator()
        let oldContext = await coordinator.start()

        let directive = await coordinator.replaceWorker()
        let oldAccepted = await coordinator.accept(.capturing, for: oldContext)
        let newContext = await coordinator.start()
        let snapshot = await coordinator.snapshot()

        try expect(directive != nil, "replacing an active worker must produce cancellation work")
        try expect(!oldAccepted, "old worker epoch results must be rejected")
        try expect(newContext.generation.rawValue == 2, "new start must advance generation")
        try expect(newContext.workerEpoch.rawValue == 2, "worker replacement must advance epoch")
        try expect(snapshot.workerEpoch.rawValue == 2, "snapshot must expose current worker epoch")
        try expect(
            snapshot.lastTerminal == PipelineTerminal(context: oldContext, reason: .workerReplaced),
            "worker replacement must record its terminal reason"
        )
    }

    private static func onlyLegalTransitionsAreAccepted() async throws {
        let coordinator = PipelineCoordinator()
        let context = await coordinator.start()

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
        let context = await coordinator.start()

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
        let context = await coordinator.start()
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
