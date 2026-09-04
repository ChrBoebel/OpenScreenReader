import AppKit
import Combine
import OpenScreenReaderCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status: AppStatus = .ready
    @Published private(set) var hotkeyRegistration: HotkeyRegistration = .inactive
    @Published private(set) var lastSelection: ScreenRegionSelection?
    @Published private(set) var lastCaptureSize: CGSize?
    @Published private(set) var lastOCRSummary: OCRSummary?
    @Published private(set) var errorMessage: String?

    let pipelineCoordinator: PipelineCoordinator
    private let hotkeyManager: any HotkeyManaging
    private let selectionController: any RegionSelectionControlling
    private let captureService: any ScreenCapturing
    private let escapeMonitor: any EscapeMonitoring
    private let ocrService: any TextRecognizing
    private let operationTimeout: Duration
    private var activeContext: PipelineOperationContext?
    private var interactionTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var recognitionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    isolated deinit {
        stopResources()
        hotkeyManager.unregister()
    }

    init(
        pipelineCoordinator: PipelineCoordinator = PipelineCoordinator(),
        hotkeyManager: any HotkeyManaging = GlobalHotkeyManager(),
        selectionController: any RegionSelectionControlling = RegionSelectionOverlayController(),
        captureService: any ScreenCapturing = ScreenCaptureService(),
        escapeMonitor: any EscapeMonitoring = EscapeMonitor(),
        ocrService: any TextRecognizing = VisionOCRService(),
        operationTimeout: Duration = .seconds(15)
    ) {
        self.pipelineCoordinator = pipelineCoordinator
        self.hotkeyManager = hotkeyManager
        self.selectionController = selectionController
        self.captureService = captureService
        self.escapeMonitor = escapeMonitor
        self.ocrService = ocrService
        self.operationTimeout = operationTimeout
        hotkeyManager.onPress = { [weak self] in self?.enqueueReadRequest() }
        hotkeyRegistration = hotkeyManager.register(.readScreenRegion)
        if hotkeyRegistration != .registered {
            status = .error
            errorMessage = Self.registrationErrorMessage(for: hotkeyRegistration)
        }
    }

    var readActionTitle: String { activeContext == nil ? "Read Screen Region…" : "Stop Reading" }

    var captureFeedback: String {
        if status == .capturing { return "Capturing selected region locally…" }
        if status == .recognizing { return "Recognizing German and English text locally…" }
        guard let summary = lastOCRSummary else {
            return "Select a region to recognize text locally. Speech is not available yet."
        }
        if summary.characterCount == 0 { return "No readable text found. Select a clearer region." }
        return "Recognized \(summary.characterCount) characters in \(summary.lineCount) lines locally. Speech is not available yet."
    }

    // Serialize only short control transitions. Never queue cancellation behind capture.
    private func enqueue(_ action: @escaping @MainActor (AppModel) async -> Void) {
        let previous = interactionTask
        interactionTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            await action(self)
        }
    }

    func enqueueReadRequest() { enqueue { await $0.processReadRequest() } }

    func handleReadRequest() async {
        enqueueReadRequest()
        await waitForInteractionToSettle()
    }

    func waitForInteractionToSettle() async { await interactionTask?.value }

    func waitForTimeoutToSettle() async {
        await timeoutTask?.value
        await interactionTask?.value
    }

    func waitForCaptureToSettle() async {
        await captureTask?.value
        await interactionTask?.value
        await recognitionTask?.value
        await interactionTask?.value
    }

    private func processReadRequest() async {
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
            lastSelection = nil
            lastCaptureSize = nil
            lastOCRSummary = nil
            errorMessage = nil
            selectionController.start(
                onSelection: { [weak self] selection in
                    self?.enqueue { await $0.beginCapture(selection, context: context) }
                },
                onCancel: { [weak self] in
                    self?.enqueue { await $0.cancel(context: context) }
                }
            )
        case let .cleanupRequired(directive):
            stopResources()
            _ = await pipelineCoordinator.finishCleanup(for: directive.context)
            activeContext = nil
            status = .stopped
        }
    }

    private func beginCapture(_ selection: ScreenRegionSelection, context: PipelineOperationContext) async {
        guard context == activeContext,
              await pipelineCoordinator.accept(.capturing, for: context) else { return }
        lastSelection = selection
        selectionController.cancel()
        do {
            try escapeMonitor.start(
                onEscape: { [weak self] in
                    self?.enqueue { await $0.cancel(context: context) }
                },
                onUnavailable: { [weak self] in
                    self?.enqueue {
                        await $0.fail(context: context, message: EscapeMonitorFailure.unavailable.localizedDescription)
                    }
                }
            )
        } catch {
            await fail(context: context, message: error.localizedDescription)
            return
        }
        status = .capturing
        let service = captureService
        captureTask = Task { @MainActor [weak self] in
            do {
                let image = try await service.capture(selection)
                try Task.checkCancellation()
                let size = CGSize(width: image.width, height: image.height)
                self?.enqueue { await $0.beginRecognition(image, size: size, context: context) }
            } catch is CancellationError {
                self?.enqueue { await $0.cancel(context: context) }
            } catch {
                let message = (error as? ScreenCaptureFailure)?.localizedDescription
                    ?? ScreenCaptureFailure.failed.localizedDescription
                self?.enqueue { await $0.fail(context: context, message: message) }
            }
        }
        let timeout = operationTimeout
        timeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.enqueue { await $0.fail(context: context, message: "Capture or text recognition timed out. Please try a smaller region.") }
        }
    }

    private func beginRecognition(
        _ image: CGImage, size: CGSize, context: PipelineOperationContext
    ) async {
        guard context == activeContext,
              await pipelineCoordinator.accept(.recognizing, for: context) else { return }
        status = .recognizing
        let service = ocrService
        recognitionTask = Task { @MainActor [weak self] in
            do {
                let result = try await service.recognize(image)
                try Task.checkCancellation()
                // Only counts cross into observable UI state. Until speech is wired in,
                // discard the recognized content at the end of this operation.
                let summary = OCRSummary(characterCount: result.characterCount, lineCount: result.lineCount)
                self?.enqueue { await $0.finishRecognition(summary: summary, size: size, context: context) }
            } catch is CancellationError {
                self?.enqueue { await $0.cancel(context: context) }
            } catch {
                let message = (error as? OCRFailure)?.localizedDescription
                    ?? OCRFailure.recognitionFailed.localizedDescription
                self?.enqueue { await $0.fail(context: context, message: message) }
            }
        }
    }

    private func finishRecognition(
        summary: OCRSummary, size: CGSize, context: PipelineOperationContext
    ) async {
        guard context == activeContext, await pipelineCoordinator.complete(context) else { return }
        stopResources()
        activeContext = nil
        lastCaptureSize = size
        lastOCRSummary = summary
        status = .ready
    }

    private func fail(context: PipelineOperationContext, message: String) async {
        guard context == activeContext else { return }
        _ = await pipelineCoordinator.fail(context)
        activeContext = nil
        stopResources()
        status = .error
        errorMessage = message
    }

    private func cancel(context: PipelineOperationContext) async {
        guard context == activeContext else { return }
        let directive = await pipelineCoordinator.cancel()
        activeContext = nil
        stopResources()
        if let directive { _ = await pipelineCoordinator.finishCleanup(for: directive.context) }
        status = .stopped
    }

    private func stopResources() {
        captureTask?.cancel()
        recognitionTask?.cancel()
        timeoutTask?.cancel()
        timeoutTask = nil
        selectionController.cancel()
        escapeMonitor.stop()
    }

    private static func registrationErrorMessage(for registration: HotkeyRegistration) -> String? {
        switch registration {
        case .inactive, .registered: nil
        case .conflict: "The shortcut ⌃⌥R is already in use."
        case let .failed(status): "The global shortcut could not be registered (error \(status))."
        }
    }
}
