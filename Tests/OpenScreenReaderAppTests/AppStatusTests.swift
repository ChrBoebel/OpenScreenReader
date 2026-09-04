import Foundation
import Testing
@testable import OpenScreenReader

@Suite("App status")
struct AppStatusTests {
    @Test
    func userFacingTitlesCoverEveryPipelineState() {
        #expect(AppStatus.allCases.map(\.title) == [
            "Ready",
            "Selecting",
            "Recognizing",
            "Speaking",
            "Stopped",
            "Error",
        ])
    }

    @Test
    @MainActor
    func appModelStartsReadyWithAnIdleCoordinator() async {
        let model = AppModel()
        let snapshot = await model.pipelineCoordinator.snapshot()

        #expect(model.status == .ready)
        #expect(snapshot.activeContext == nil)
        #expect(snapshot.phase == .idle)
    }

    @Test
    func appBundleIsConfiguredAsMenuBarOnly() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
    }
}
