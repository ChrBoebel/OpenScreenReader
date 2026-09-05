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
    @Published private(set) var shortcutConfiguration: ShortcutConfiguration
    @Published private(set) var shortcutNotice: String?

    let pipelineCoordinator: PipelineCoordinator
    private let hotkeyManager: any HotkeyManaging
    private let shortcutStore: any ShortcutStoring
    private let selectionController: any RegionSelectionControlling
    private let captureService: any ScreenCapturing
    private let escapeMonitor: any EscapeMonitoring
    private let ocrService: any TextRecognizing
    private let speechService: any SpeechReading
    private let readingPanel: (any ReadingStatusPresenting)?
    private let interfaceSounds: (any InterfaceSoundPlaying)?
    private let operationTimeout: Duration
    private let speechStartupTimeout: Duration
    private var activeContext: PipelineOperationContext?
    private var interactionTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var recognitionTask: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var speechTimeoutGeneration: UInt64 = 0

    isolated deinit {
        readingPanel?.hide()
        stopResources()
        hotkeyManager.unregister()
    }

    init(
        shortcutStore: any ShortcutStoring = UserDefaultsShortcutStore(),
        pipelineCoordinator: PipelineCoordinator = PipelineCoordinator(),
        hotkeyManager: any HotkeyManaging = GlobalHotkeyManager(),
        selectionController: any RegionSelectionControlling = RegionSelectionOverlayController(),
        captureService: any ScreenCapturing = ScreenCaptureService(),
        escapeMonitor: any EscapeMonitoring = EscapeMonitor(),
        ocrService: any TextRecognizing = VisionOCRService(),
        speechService: any SpeechReading = LocalSpeechService(),
        readingPanel: (any ReadingStatusPresenting)? = nil,
        interfaceSounds: (any InterfaceSoundPlaying)? = nil,
        operationTimeout: Duration = .seconds(15),
        speechStartupTimeout: Duration = .seconds(90)
    ) {
        self.pipelineCoordinator = pipelineCoordinator
        self.shortcutStore = shortcutStore
        self.shortcutConfiguration = shortcutStore.load() ?? .default
        self.hotkeyManager = hotkeyManager
        self.selectionController = selectionController
        self.captureService = captureService
        self.escapeMonitor = escapeMonitor
        self.ocrService = ocrService
        self.speechService = speechService
        self.readingPanel = readingPanel
        self.interfaceSounds = interfaceSounds
        self.operationTimeout = operationTimeout
        self.speechStartupTimeout = speechStartupTimeout
        hotkeyManager.onPress = { [weak self] in self?.enqueueReadRequest() }
        hotkeyRegistration = hotkeyManager.register(shortcutConfiguration.resolvedShortcut())
        if hotkeyRegistration != .registered {
            status = .error
            errorMessage = Self.registrationErrorMessage(for: hotkeyRegistration, shortcut: shortcutConfiguration)
        }
    }

    var readActionTitle: String { activeContext == nil ? "Read Screen Region…" : "Stop Reading" }
    var canChangeShortcut: Bool { activeContext == nil }

    func enqueueShortcutChange(_ configuration: ShortcutConfiguration) {
        enqueue { $0.changeShortcut(configuration) }
    }

    private func changeShortcut(_ configuration: ShortcutConfiguration) {
        guard canChangeShortcut else {
            shortcutNotice = "Stop the current operation before changing its shortcut."
            return
        }
        guard configuration.isValid else {
            shortcutNotice = "Choose a key and at least Command, Option, or Control. Escape is reserved for cancellation."
            return
        }
        let result = hotkeyManager.register(configuration.resolvedShortcut())
        guard result == .registered else {
            shortcutNotice = Self.registrationErrorMessage(for: result, shortcut: configuration)
            return
        }
        if hotkeyRegistration != .registered {
            status = .ready
            errorMessage = nil
        }
        hotkeyRegistration = .registered
        shortcutConfiguration = configuration
        shortcutStore.save(configuration)
        shortcutNotice = "Shortcut \(configuration.displayName) is active and saved."
    }

    var captureFeedback: String {
        if status == .capturing { return "Capturing selected region locally…" }
        if status == .recognizing { return "Recognizing German and English text locally…" }
        if status == .synthesizing { return "Preparing the local Supertonic voice…" }
        if status == .speaking { return "Reading locally. Press Escape or the shortcut to stop." }
        guard let summary = lastOCRSummary else {
            return "Select a region to recognize and read text locally."
        }
        if summary.characterCount == 0 { return "No readable text found. Select a clearer region." }
        return "Recognized \(summary.characterCount) characters in \(summary.lineCount) lines locally."
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

    func waitForSpeechToSettle() async {
        await speechTask?.value
        await interactionTask?.value
    }

    private func processReadRequest() async {
        interfaceSounds?.stop()
        guard hotkeyRegistration == .registered else {
            status = .error
            errorMessage = Self.registrationErrorMessage(for: hotkeyRegistration, shortcut: shortcutConfiguration)
            return
        }
        if let activeContext {
            await cancel(context: activeContext)
            return
        }
        switch await pipelineCoordinator.start() {
        case let .started(context):
            readingPanel?.hide()
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
            readingPanel?.hide()
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
        readingPanel?.hide()
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
            self?.enqueue {
                guard $0.status == .capturing || $0.status == .recognizing else { return }
                await $0.fail(context: context, message: "Capture or text recognition timed out. Please try a smaller region.")
            }
        }
    }

    private func beginRecognition(
        _ image: CGImage, size: CGSize, context: PipelineOperationContext
    ) async {
        guard context == activeContext,
              await pipelineCoordinator.accept(.recognizing, for: context) else { return }
        status = .recognizing
        showReadingPanel(.recognizing, context: context)
        interfaceSounds?.play(.selection)
        let service = ocrService
        recognitionTask = Task { @MainActor [weak self] in
            do {
                let result = try await service.recognize(image)
                try Task.checkCancellation()
                self?.enqueue { await $0.finishRecognition(result: result, size: size, context: context) }
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
        result: OCRResult, size: CGSize, context: PipelineOperationContext
    ) async {
        guard context == activeContext else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        lastCaptureSize = size
        lastOCRSummary = OCRSummary(characterCount: result.characterCount, lineCount: result.lineCount)
        guard !result.text.isEmpty else { await finishSpeech(context: context); return }
        guard await pipelineCoordinator.accept(.synthesizing, for: context) else { return }
        status = .synthesizing
        showReadingPanel(.preparing, context: context)
        armSpeechTimeout(speechStartupTimeout, context: context)
        let service = speechService
        let text = result.text
        speechTask = Task { @MainActor [weak self] in
            do {
                try Task.checkCancellation()
                try await service.read(text) { [weak self] in
                    self?.enqueue { await $0.speechPlaybackStarted(context: context) }
                }
                try Task.checkCancellation()
                self?.enqueue { await $0.finishSpeech(context: context) }
            } catch is CancellationError {
                self?.enqueue { await $0.cancel(context: context) }
            } catch {
                let message = (error as? SpeechFailure)?.localizedDescription ?? SpeechFailure.failed.localizedDescription
                self?.enqueue { await $0.fail(context: context, message: message) }
            }
        }
    }

    private func speechPlaybackStarted(context: PipelineOperationContext) async {
        guard context == activeContext else { return }
        if status == .synthesizing {
            interfaceSounds?.stop()
            guard await pipelineCoordinator.accept(.speaking, for: context) else { return }
            status = .speaking
            showReadingPanel(.speaking, context: context)
            levelTask?.cancel()
            levelTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do {
                        guard let self, self.activeContext == context, self.status == .speaking else { return }
                        self.readingPanel?.updateLevel(self.speechService.playbackLevel)
                    }
                    do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                }
            }
        }
        armSpeechTimeout(.seconds(30), context: context)
    }

    private func armSpeechTimeout(_ duration: Duration, context: PipelineOperationContext) {
        timeoutTask?.cancel()
        speechTimeoutGeneration &+= 1
        let timerGeneration = speechTimeoutGeneration
        timeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            self?.enqueue {
                guard $0.speechTimeoutGeneration == timerGeneration else { return }
                await $0.fail(context: context, message: "Local speech timed out. Please try a smaller region.")
            }
        }
    }

    private func finishSpeech(context: PipelineOperationContext) async {
        guard context == activeContext, await pipelineCoordinator.complete(context) else { return }
        stopResources()
        activeContext = nil
        status = .ready
        showReadingPanel(lastOCRSummary?.characterCount == 0 ? .noText : .finished, context: context)
        interfaceSounds?.play(lastOCRSummary?.characterCount == 0 ? .attention : .completion)
    }

    private func fail(context: PipelineOperationContext, message: String) async {
        guard context == activeContext else { return }
        speechService.stop()
        _ = await pipelineCoordinator.fail(context)
        activeContext = nil
        stopResources()
        status = .error
        errorMessage = message
        showReadingPanel(.failed, context: context)
        interfaceSounds?.play(.attention)
    }

    private func cancel(context: PipelineOperationContext) async {
        guard context == activeContext else { return }
        interfaceSounds?.stop()
        speechService.stop()
        let directive = await pipelineCoordinator.cancel()
        activeContext = nil
        stopResources()
        if let directive { _ = await pipelineCoordinator.finishCleanup(for: directive.context) }
        status = .stopped
        showReadingPanel(.stopped, context: context)
    }

    private func showReadingPanel(_ state: ReadingPanelState, context: PipelineOperationContext) {
        guard let selection = lastSelection else { readingPanel?.hide(); return }
        let stop: (() -> Void)? = state.isActive ? { [weak self] in
            self?.enqueue { await $0.cancel(context: context) }
        } : nil
        readingPanel?.show(state, displayID: selection.displayID, onStop: stop)
    }

    private func stopResources() {
        levelTask?.cancel()
        levelTask = nil
        readingPanel?.updateLevel(0)
        interfaceSounds?.stop()
        speechService.stop()
        speechTask?.cancel()
        captureTask?.cancel()
        recognitionTask?.cancel()
        timeoutTask?.cancel()
        timeoutTask = nil
        selectionController.cancel()
        escapeMonitor.stop()
    }

    private static func registrationErrorMessage(
        for registration: HotkeyRegistration, shortcut: ShortcutConfiguration
    ) -> String? {
        switch registration {
        case .inactive, .registered: nil
        case .conflict: "The shortcut \(shortcut.displayName) is already in use."
        case let .failed(status): "The global shortcut could not be registered (error \(status))."
        }
    }
}
