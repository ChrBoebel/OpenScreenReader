import Combine
import OpenScreenReaderCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status: AppStatus = .ready

    let pipelineCoordinator: PipelineCoordinator

    init(pipelineCoordinator: PipelineCoordinator = PipelineCoordinator()) {
        self.pipelineCoordinator = pipelineCoordinator
    }
}
