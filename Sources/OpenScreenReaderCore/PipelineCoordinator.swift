public struct PipelineGeneration: Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public struct WorkerEpoch: Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public struct PipelineOperationContext: Equatable, Hashable, Sendable {
    public let generation: PipelineGeneration
    public let workerEpoch: WorkerEpoch

    public init(generation: PipelineGeneration, workerEpoch: WorkerEpoch) {
        self.generation = generation
        self.workerEpoch = workerEpoch
    }
}

public enum PipelinePhase: Equatable, Sendable {
    case idle
    case selecting
    case capturing
    case recognizing
    case synthesizing
    case speaking
}

public enum PipelineTerminalReason: Equatable, Sendable {
    case stopped
    case superseded
    case workerReplaced
    case completed
    case failed
}

public struct PipelineTerminal: Equatable, Sendable {
    public let context: PipelineOperationContext
    public let reason: PipelineTerminalReason

    public init(context: PipelineOperationContext, reason: PipelineTerminalReason) {
        self.context = context
        self.reason = reason
    }
}

public enum PipelineCancellationStep: Equatable, Sendable {
    case silenceAudio
    case dismissOverlay
    case cancelLocalTasks
    case requestWorkerCancellation
    case awaitWorkerAcknowledgement
    case terminateUnresponsiveWorker
}

public struct PipelineCancellationDirective: Equatable, Sendable {
    public let context: PipelineOperationContext
    public let steps: [PipelineCancellationStep]

    public init(
        context: PipelineOperationContext,
        steps: [PipelineCancellationStep]
    ) {
        self.context = context
        self.steps = steps
    }
}

public struct PipelineSnapshot: Equatable, Sendable {
    public let activeContext: PipelineOperationContext?
    public let phase: PipelinePhase
    public let lastTerminal: PipelineTerminal?
    public let workerEpoch: WorkerEpoch

    public init(
        activeContext: PipelineOperationContext?,
        phase: PipelinePhase,
        lastTerminal: PipelineTerminal?,
        workerEpoch: WorkerEpoch
    ) {
        self.activeContext = activeContext
        self.phase = phase
        self.lastTerminal = lastTerminal
        self.workerEpoch = workerEpoch
    }
}

public actor PipelineCoordinator {
    private static let cancellationSteps: [PipelineCancellationStep] = [
        .silenceAudio,
        .dismissOverlay,
        .cancelLocalTasks,
        .requestWorkerCancellation,
        .awaitWorkerAcknowledgement,
        .terminateUnresponsiveWorker,
    ]

    private var generation = PipelineGeneration(rawValue: 0)
    private var workerEpoch = WorkerEpoch(rawValue: 1)
    private var activeContext: PipelineOperationContext?
    private var phase = PipelinePhase.idle
    private var lastTerminal: PipelineTerminal?

    public init() {}

    @discardableResult
    public func start() -> PipelineOperationContext {
        if let activeContext {
            revoke(activeContext, reason: .superseded)
        }

        precondition(generation.rawValue < UInt64.max, "Pipeline generation exhausted")
        generation = PipelineGeneration(rawValue: generation.rawValue + 1)

        let context = PipelineOperationContext(
            generation: generation,
            workerEpoch: workerEpoch
        )
        activeContext = context
        phase = .selecting
        return context
    }

    public func snapshot() -> PipelineSnapshot {
        PipelineSnapshot(
            activeContext: activeContext,
            phase: phase,
            lastTerminal: lastTerminal,
            workerEpoch: workerEpoch
        )
    }

    @discardableResult
    public func accept(
        _ nextPhase: PipelinePhase,
        for context: PipelineOperationContext
    ) -> Bool {
        guard context == activeContext, nextPhase == legalSuccessor(of: phase) else {
            return false
        }

        phase = nextPhase
        return true
    }

    @discardableResult
    public func cancel() -> PipelineCancellationDirective? {
        guard let context = activeContext else {
            return nil
        }

        revoke(context, reason: .stopped)
        return cancellationDirective(for: context)
    }

    @discardableResult
    public func replaceWorker() -> PipelineCancellationDirective? {
        let directive: PipelineCancellationDirective?
        if let context = activeContext {
            revoke(context, reason: .workerReplaced)
            directive = cancellationDirective(for: context)
        } else {
            directive = nil
        }

        precondition(workerEpoch.rawValue < UInt64.max, "Worker epoch exhausted")
        workerEpoch = WorkerEpoch(rawValue: workerEpoch.rawValue + 1)
        return directive
    }

    @discardableResult
    public func complete(_ context: PipelineOperationContext) -> Bool {
        finish(context, reason: .completed)
    }

    @discardableResult
    public func fail(_ context: PipelineOperationContext) -> Bool {
        finish(context, reason: .failed)
    }

    private func finish(
        _ context: PipelineOperationContext,
        reason: PipelineTerminalReason
    ) -> Bool {
        guard context == activeContext else {
            return false
        }

        revoke(context, reason: reason)
        return true
    }

    private func revoke(
        _ context: PipelineOperationContext,
        reason: PipelineTerminalReason
    ) {
        activeContext = nil
        phase = .idle
        lastTerminal = PipelineTerminal(context: context, reason: reason)
    }

    private func cancellationDirective(
        for context: PipelineOperationContext
    ) -> PipelineCancellationDirective {
        PipelineCancellationDirective(
            context: context,
            steps: Self.cancellationSteps
        )
    }

    private func legalSuccessor(of phase: PipelinePhase) -> PipelinePhase? {
        switch phase {
        case .idle:
            nil
        case .selecting:
            .capturing
        case .capturing:
            .recognizing
        case .recognizing:
            .synthesizing
        case .synthesizing:
            .speaking
        case .speaking:
            nil
        }
    }
}
