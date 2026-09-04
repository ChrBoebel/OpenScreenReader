import Testing
@testable import OpenScreenReaderCore

@Suite("Pipeline coordinator")
struct PipelineCoordinatorSmokeTests {
    @Test
    func firstStartCreatesSelectingGeneration() async {
        let coordinator = PipelineCoordinator()

        let result = await coordinator.start()
        let snapshot = await coordinator.snapshot()

        guard case let .started(context) = result else {
            Issue.record("A fresh coordinator must start without cleanup")
            return
        }

        #expect(context.generation.rawValue == 1)
        #expect(context.workerEpoch.rawValue == 1)
        #expect(snapshot.activeContext == context)
        #expect(snapshot.phase == .selecting)
        #expect(snapshot.lastTerminal == nil)
        #expect(snapshot.pendingCancellation == nil)
    }
}
