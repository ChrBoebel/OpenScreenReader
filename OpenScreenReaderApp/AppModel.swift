import Combine
import OpenScreenReaderCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status: AppStatus = .ready

    @Published private(set) var hotkeyRegistration: HotkeyRegistration = .inactive
    @Published private(set) var lastSelection: ScreenRegionSelection?
    @Published private(set) var errorMessage: String?

    let pipelineCoordinator: PipelineCoordinator

    private let hotkeyManager: any HotkeyManaging
    private let selectionController: any RegionSelectionControlling
    private var activeContext: PipelineOperationContext?
    private var interactionTask: Task<Void, Never>?

    init(
        pipelineCoordinator: PipelineCoordinator = PipelineCoordinator(),
        hotkeyManager: any HotkeyManaging = GlobalHotkeyManager(),
        selectionController: any RegionSelectionControlling = RegionSelectionOverlayController()
    ) {
        self.pipelineCoordinator = pipelineCoordinator
        self.hotkeyManager = hotkeyManager
        self.selectionController = selectionController

        hotkeyManager.onPress = { [weak self] in
            self?.enqueueReadRequest()
        }
        hotkeyRegistration = hotkeyManager.register(.readScreenRegion)
        if hotkeyRegistration != .registered {
            status = .error
            errorMessage = Self.registrationErrorMessage(for: hotkeyRegistration)
        }
    }

    var readActionTitle: String {
        activeContext == nil ? "Read Screen Region…" : "Stop Reading"
    }

    func enqueueReadRequest() {
        interactionTask = Task { @MainActor [weak self] in
            await self?.handleReadRequest()
        }
    }

    func handleReadRequest() async {
        guard hotkeyRegistration == .registered else {
            status = .error
            errorMessage = Self.registrationErrorMessage(for: hotkeyRegistration)
            return
        }

        if let activeContext {
            await cancel(context: activeContext)
            return
        }

        switch await pipelineCoordinator.start() {
        case let .started(context):
            activeContext = context
            status = .selecting
            errorMessage = nil
            selectionController.start(
                onSelection: { [weak self] selection in
                    self?.enqueueSelectionCompletion(selection, context: context)
                },
                onCancel: { [weak self] in
                    self?.enqueueCancellation(for: context)
                }
            )
        case let .cleanupRequired(directive):
            selectionController.cancel()
            _ = await pipelineCoordinator.finishCleanup(for: directive.context)
            activeContext = nil
            status = .stopped
        }
    }

    func waitForInteractionToSettle() async {
        await interactionTask?.value
    }

    private func enqueueSelectionCompletion(
        _ selection: ScreenRegionSelection,
        context: PipelineOperationContext
    ) {
        interactionTask = Task { @MainActor [weak self] in
            await self?.completeSelection(selection, context: context)
        }
    }

    private func enqueueCancellation(for context: PipelineOperationContext) {
        interactionTask = Task { @MainActor [weak self] in
            await self?.cancel(context: context)
        }
    }

    private func completeSelection(
        _ selection: ScreenRegionSelection,
        context: PipelineOperationContext
    ) async {
        guard context == activeContext,
              await pipelineCoordinator.accept(.capturing, for: context) else {
            return
        }

        lastSelection = selection
        _ = await pipelineCoordinator.complete(context)
        activeContext = nil
        status = .ready
    }

    private func cancel(context: PipelineOperationContext) async {
        guard context == activeContext else {
            return
        }

        let directive = await pipelineCoordinator.cancel()
        selectionController.cancel()
        if let directive {
            _ = await pipelineCoordinator.finishCleanup(for: directive.context)
        }
        activeContext = nil
        status = .stopped
    }

    private static func registrationErrorMessage(
        for registration: HotkeyRegistration
    ) -> String? {
        switch registration {
        case .inactive, .registered:
            nil
        case .conflict:
            "The shortcut ⌃⌥R is already in use."
        case let .failed(status):
            "The global shortcut could not be registered (error \(status))."
        }
    }
}
