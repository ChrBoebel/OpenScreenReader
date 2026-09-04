import CoreGraphics
import Carbon.HIToolbox
import Foundation
import Testing
@testable import OpenScreenReader

@Suite("Primary interaction")
@MainActor
struct InteractionTests {
    @Test
    func captureAutomaticallyRecognizesTextAndRetainsOnlyCounts() async {
        let selection = RegionSelectionControllerFake()
        let ocr = OCRFake()
        let escape = EscapeFake()
        let model = AppModel(hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: escape,
            ocrService: ocr)
        await model.handleReadRequest()
        selection.complete(Self.ocrRegion)
        await model.waitForInteractionToSettle()
        await model.waitForCaptureToSettle()
        #expect(ocr.calls == 1)
        #expect(model.status == .ready)
        #expect(model.lastOCRSummary == OCRSummary(characterCount: 11, lineCount: 1))
        #expect(model.captureFeedback.contains("11 characters"))
        #expect(!escape.isActive)
        #expect(await model.pipelineCoordinator.snapshot().lastTerminal?.reason == .completed)
        await model.handleReadRequest()
        #expect(model.lastOCRSummary == nil)
    }

    @Test
    func blankOCRHasActionableFeedbackWithoutSpeech() async {
        let selection = RegionSelectionControllerFake()
        let ocr = OCRFake()
        ocr.result = OCRResult(lines: [])
        let model = AppModel(hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: EscapeFake(),
            ocrService: ocr)
        await model.handleReadRequest()
        selection.complete(Self.ocrRegion)
        await model.waitForInteractionToSettle()
        await model.waitForCaptureToSettle()
        #expect(model.status == .ready)
        #expect(model.lastOCRSummary?.characterCount == 0)
        #expect(model.captureFeedback == "No readable text found. Select a clearer region.")
    }

    @Test(arguments: [false, true])
    func cancelledOCRCannotPublishIntoNewSelection(repeatedShortcut: Bool) async {
        let selection = RegionSelectionControllerFake()
        let ocr = OCRFake()
        ocr.suspend = true
        let escape = EscapeFake()
        let model = AppModel(hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: escape,
            ocrService: ocr)
        await model.handleReadRequest()
        selection.complete(Self.ocrRegion)
        await model.waitForInteractionToSettle()
        await ocr.waitUntilStarted()
        #expect(model.status == .recognizing)
        #expect(escape.isActive)
        if repeatedShortcut { await model.handleReadRequest() }
        else { escape.onEscape?(); await model.waitForInteractionToSettle() }
        #expect(model.status == .stopped)
        #expect(!escape.isActive)
        await model.handleReadRequest()
        ocr.resume()
        await model.waitForCaptureToSettle()
        #expect(model.status == .selecting)
        #expect(model.lastOCRSummary == nil)
        #expect(model.lastCaptureSize == nil)
    }

    @Test
    func recognitionFailureDoesNotExposeUnderlyingPayload() async {
        let selection = RegionSelectionControllerFake()
        let ocr = OCRFake()
        ocr.shouldFail = true
        let escape = EscapeFake()
        let model = AppModel(hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: escape,
            ocrService: ocr)
        await model.handleReadRequest()
        selection.complete(Self.ocrRegion)
        await model.waitForInteractionToSettle()
        await model.waitForCaptureToSettle()
        #expect(model.status == .error)
        #expect(model.errorMessage == OCRFailure.recognitionFailed.localizedDescription)
        #expect(model.lastOCRSummary == nil)
        #expect(!escape.isActive)
    }

    private static var ocrRegion: ScreenRegionSelection {
        ScreenRegionSelection(displayID: 1,
            rectInScreenPoints: CGRect(x: 0, y: 0, width: 20, height: 20),
            rectInBackingPixels: CGRect(x: 0, y: 0, width: 20, height: 20), backingScaleFactor: 1)
    }

    @Test(arguments: [false, true])
    func interruptedOCRFailsClosedAndRejectsLateText(timeout: Bool) async {
        let selection = RegionSelectionControllerFake()
        let ocr = OCRFake()
        ocr.suspend = true
        let escape = EscapeFake()
        let model = AppModel(hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: escape,
            ocrService: ocr, operationTimeout: timeout ? .milliseconds(100) : .seconds(15))
        await model.handleReadRequest()
        selection.complete(Self.ocrRegion)
        await model.waitForInteractionToSettle()
        await ocr.waitUntilStarted()
        if timeout { await model.waitForTimeoutToSettle() }
        else { escape.onUnavailable?(); await model.waitForInteractionToSettle() }
        #expect(model.status == .error)
        #expect(!escape.isActive)
        #expect(model.lastOCRSummary == nil)
        #expect(await model.pipelineCoordinator.snapshot().activeContext == nil)
        ocr.resume()
        await model.waitForCaptureToSettle()
        #expect(model.status == .error)
        #expect(model.lastOCRSummary == nil)
    }

    @Test
    func defaultShortcutIsExplicitAndReadable() {
        #expect(HotkeyShortcut.readScreenRegion.carbonModifiers == UInt32(cmdKey | shiftKey))
        #expect(HotkeyShortcut.readScreenRegion.displayName == "⌘⇧Y")
    }

    @Test(arguments: [("com.apple.keylayout.German", UInt32(kVK_ANSI_Z)),
                      ("com.apple.keylayout.US", UInt32(kVK_ANSI_Y))])
    func shortcutResolvesYForGermanAndUSLayouts(layout: (String, UInt32)) throws {
        let sources = TISCreateInputSourceList(
            [kTISPropertyInputSourceID: layout.0] as CFDictionary, true
        ).takeRetainedValue()
        #expect(CFArrayGetCount(sources) > 0)
        guard CFArrayGetCount(sources) > 0 else { return }
        let source = Unmanaged<TISInputSource>.fromOpaque(CFArrayGetValueAtIndex(sources, 0)).takeUnretainedValue()
        #expect(HotkeyShortcut.keyCode(for: "Y", modifiers: UInt32(cmdKey | shiftKey), source: source) == layout.1)
        #expect(HotkeyShortcut.keyCode(for: "🦉", modifiers: UInt32(cmdKey | shiftKey), source: source) == nil)
    }

    @Test
    func missingLayoutKeyCannotRegisterAnUnrelatedFallback() {
        let manager = GlobalHotkeyManager()
        #expect(manager.register(HotkeyShortcut(keyCode: nil,
            carbonModifiers: UInt32(cmdKey | shiftKey), displayName: "⌘⇧Y")) == .failed(OSStatus(paramErr)))
    }

    @Test
    func appRegistersTheHotkeyAndStartsSelection() async {
        let hotkey = HotkeyManagerFake(registrationResult: .registered)
        let selection = RegionSelectionControllerFake()
        let model = AppModel(hotkeyManager: hotkey, selectionController: selection,
                             captureService: CaptureFake(), escapeMonitor: EscapeFake())

        #expect(hotkey.registeredShortcut == .readScreenRegion)
        #expect(model.hotkeyRegistration == .registered)

        await model.handleReadRequest()

        #expect(model.status == .selecting)
        #expect(selection.startCount == 1)
        #expect(selection.cancelCount == 0)
    }

    @Test
    func repeatedReadRequestCancelsTheActiveSelection() async {
        let hotkey = HotkeyManagerFake(registrationResult: .registered)
        let selection = RegionSelectionControllerFake()
        let model = AppModel(hotkeyManager: hotkey, selectionController: selection,
                             captureService: CaptureFake(), escapeMonitor: EscapeFake())

        await model.handleReadRequest()
        await model.handleReadRequest()

        let snapshot = await model.pipelineCoordinator.snapshot()
        #expect(model.status == .stopped)
        #expect(selection.cancelCount == 1)
        #expect(snapshot.activeContext == nil)
        #expect(snapshot.pendingCancellation == nil)
    }

    @Test
    func completedSelectionIsPublishedWithoutPersistingPixels() async {
        let selection = RegionSelectionControllerFake()
        let model = AppModel(
            hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: EscapeFake()
        )
        let region = ScreenRegionSelection(
            displayID: 7,
            rectInScreenPoints: CGRect(x: 100, y: 80, width: 400, height: 220),
            rectInBackingPixels: CGRect(x: 200, y: 160, width: 800, height: 440),
            backingScaleFactor: 2
        )

        await model.handleReadRequest()
        selection.complete(region)
        await model.waitForInteractionToSettle()
        await model.waitForCaptureToSettle()

        let snapshot = await model.pipelineCoordinator.snapshot()
        #expect(model.lastSelection == region)
        #expect(model.status == .ready)
        #expect(snapshot.activeContext == nil)
        #expect(snapshot.lastTerminal?.reason == .completed)
    }

    @Test
    func registrationConflictIsVisibleAndPreventsSelection() async {
        let hotkey = HotkeyManagerFake(registrationResult: .conflict)
        let selection = RegionSelectionControllerFake()
        let model = AppModel(hotkeyManager: hotkey, selectionController: selection)

        await model.handleReadRequest()

        #expect(model.hotkeyRegistration == .conflict)
        #expect(model.status == .error)
        #expect(model.errorMessage == "The shortcut ⌘⇧Y is already in use.")
        #expect(selection.startCount == 0)
    }

    @Test
    func cancelledCaptureCannotPublishIntoANewerSelection() async throws {
        let selection = RegionSelectionControllerFake()
        let capture = CaptureFake()
        capture.suspend = true
        let escape = EscapeFake()
        let model = AppModel(hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
                             selectionController: selection, captureService: capture, escapeMonitor: escape)
        await model.handleReadRequest()
        let region = ScreenRegionSelection(displayID: 1,
            rectInScreenPoints: CGRect(x: 0, y: 0, width: 20, height: 20),
            rectInBackingPixels: CGRect(x: 0, y: 0, width: 20, height: 20), backingScaleFactor: 1)
        selection.complete(region)
        await model.waitForInteractionToSettle()
        await capture.waitUntilStarted()
        #expect(model.status == .capturing)
        escape.onEscape?()
        await model.waitForInteractionToSettle()
        #expect(model.status == .stopped)
        #expect(!escape.isActive)
        await model.handleReadRequest()
        capture.resume()
        await model.waitForCaptureToSettle()
        #expect(model.status == .selecting)
        #expect(model.lastCaptureSize == nil)
    }

    @Test
    func missingEscapeAccessPreventsCaptureAndExplainsRemediation() async {
        let selection = RegionSelectionControllerFake()
        let capture = CaptureFake()
        let escape = EscapeFake()
        escape.shouldFail = true
        let model = AppModel(hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
                             selectionController: selection, captureService: capture, escapeMonitor: escape)
        await model.handleReadRequest()
        selection.complete(ScreenRegionSelection(displayID: 1,
            rectInScreenPoints: CGRect(x: 0, y: 0, width: 20, height: 20),
            rectInBackingPixels: CGRect(x: 0, y: 0, width: 20, height: 20), backingScaleFactor: 1))
        await model.waitForInteractionToSettle()
        #expect(model.status == .error)
        #expect(model.errorMessage?.contains("Input Monitoring") == true)
        #expect(capture.calls == 0)
        #expect(!escape.isActive)
    }

    @Test
    func rapidReadRequestsAreProcessedInOrder() async {
        let model = AppModel(hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
                             selectionController: RegionSelectionControllerFake(),
                             captureService: CaptureFake(), escapeMonitor: EscapeFake())
        for _ in 0..<100 { model.enqueueReadRequest() }
        await model.waitForInteractionToSettle()
        let snapshot = await model.pipelineCoordinator.snapshot()
        #expect(model.status == .stopped)
        #expect(snapshot.activeContext == nil)
        #expect(snapshot.pendingCancellation == nil)
    }

    @Test
    func selectionGeometryHandlesNegativeDisplayOriginsAndRetinaScale() throws {
        let geometry = DisplaySelectionGeometry(
            displayID: 9,
            frameInScreenPoints: CGRect(x: -1440, y: 100, width: 1440, height: 900),
            backingScaleFactor: 2
        )

        let selection = try #require(
            geometry.selection(
                from: CGPoint(x: 500, y: 350),
                to: CGPoint(x: 100, y: 200)
            )
        )

        #expect(selection.displayID == 9)
        #expect(selection.rectInScreenPoints == CGRect(x: -1340, y: 300, width: 400, height: 150))
        #expect(selection.rectInBackingPixels == CGRect(x: 200, y: 400, width: 800, height: 300))
        #expect(selection.backingScaleFactor == 2)
    }

    @Test
    func selectionGeometryClipsToItsStartDisplayAndRejectsZeroArea() {
        let geometry = DisplaySelectionGeometry(
            displayID: 3,
            frameInScreenPoints: CGRect(x: 0, y: 0, width: 1000, height: 700),
            backingScaleFactor: 1
        )

        let clipped = geometry.selection(
            from: CGPoint(x: 900, y: 600),
            to: CGPoint(x: 1200, y: 900)
        )

        #expect(clipped?.rectInScreenPoints == CGRect(x: 900, y: 600, width: 100, height: 100))
        #expect(geometry.selection(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 11, y: 11)) == nil)
    }
}

@MainActor
private final class EscapeFake: EscapeMonitoring {
    var onEscape: (() -> Void)?
    var onUnavailable: (() -> Void)?
    var isActive = false
    var shouldFail = false
    func start(onEscape: @escaping () -> Void, onUnavailable: @escaping () -> Void) throws {
        if shouldFail { throw EscapeMonitorFailure.permissionRequired }
        self.onEscape = onEscape
        self.onUnavailable = onUnavailable
        isActive = true
    }
    func stop() { isActive = false; onEscape = nil; onUnavailable = nil }
}

@MainActor
private final class CaptureFake: ScreenCapturing {
    var suspend = false
    var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func capture(_ selection: ScreenRegionSelection) async throws -> CGImage {
        calls += 1
        if suspend {
            await withCheckedContinuation { continuation = $0; started?.resume(); started = nil }
        }
        // Deliberately ignore cancellation to model Apple's one-shot callback.
        return CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 80,
                         space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
    func waitUntilStarted() async {
        if continuation == nil { await withCheckedContinuation { started = $0 } }
    }
    func resume() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class OCRFake: TextRecognizing {
    var calls = 0
    var suspend = false
    var shouldFail = false
    var result = OCRResult(lines: ["Hello world"])
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func recognize(_ image: CGImage) async throws -> OCRResult {
        calls += 1
        if suspend {
            await withCheckedContinuation { continuation = $0; started?.resume(); started = nil }
        }
        if shouldFail { throw NSError(domain: "private synthetic diagnostic", code: 1) }
        // Deliberately ignore cancellation to exercise stale-result rejection.
        return result
    }
    func waitUntilStarted() async {
        if continuation == nil { await withCheckedContinuation { started = $0 } }
    }
    func resume() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class HotkeyManagerFake: HotkeyManaging {
    var onPress: (() -> Void)?
    private(set) var registeredShortcut: HotkeyShortcut?
    private let registrationResult: HotkeyRegistration

    init(registrationResult: HotkeyRegistration) {
        self.registrationResult = registrationResult
    }

    func register(_ shortcut: HotkeyShortcut) -> HotkeyRegistration {
        registeredShortcut = shortcut
        return registrationResult
    }

    func unregister() {}
}

@MainActor
private final class RegionSelectionControllerFake: RegionSelectionControlling {
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private var completion: ((ScreenRegionSelection) -> Void)?

    func start(
        onSelection: @escaping (ScreenRegionSelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        startCount += 1
        completion = onSelection
    }

    func cancel() {
        cancelCount += 1
        completion = nil
    }

    func complete(_ selection: ScreenRegionSelection) {
        let completion = completion
        self.completion = nil
        completion?(selection)
    }
}
