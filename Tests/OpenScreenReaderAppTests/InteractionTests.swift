import CoreGraphics
import Carbon.HIToolbox
import Foundation
import Testing
@testable import OpenScreenReader

@Suite("Speech transport and buffering", .serialized)
@MainActor
struct SpeechBufferingTests {
    @Test
    func supertonicIsTheOnlyDefaultAndUsesItsNativeSampleRate() {
        let runtime = SpeechRuntimeConfiguration(root: URL(fileURLWithPath: "/missing-runtime"))
        #expect(runtime.sampleRate == 44_100)
        #expect(runtime.modelName == "Supertonic 3 · M1")
        #expect(runtime.executable.path.contains("SupertonicRuntime/venv/bin/python3"))
        #expect(runtime.model.path.hasSuffix("supertonic-3-3cadd1ee"))
        #expect(!runtime.isInstalled)
        #expect(SpeechRuntimeConfiguration.language(for: "Dies ist ein deutscher Beispielsatz.") == "de")
        #expect(SpeechRuntimeConfiguration.language(for: "This is an English sentence about reading books.") == "en")
    }

    @Test
    func nativeSupertonicRateKeepsFourSecondsOfBufferCapacity() async throws {
        let player = SpeechAudioPlayer(sampleRate: 44_100)
        defer { player.stop() }
        #expect(player.capacityFrames == 176_400)
        #expect(player.prebufferFrames == 44_100)
        try await player.enqueue(Data(repeating: 0, count: 9_600)) {}
        try await player.finish {}
        #expect(player.diagnostics.frames == 2_400)
        #expect(player.queuedFrames == 0)
    }

    @Test
    func shortPacketReturnsBeforeWriterCloses() async throws {
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        let reader = SpeechPacketReader(handle: pipe.fileHandleForReading)
        try pipe.fileHandleForWriting.write(contentsOf: Data("ready\n".utf8))
        var hadToCloseWriter = false
        let deadline = Task { @MainActor in
            try await Task.sleep(for: .seconds(1))
            hadToCloseWriter = true
            try? pipe.fileHandleForWriting.close()
        }
        defer { deadline.cancel() }
        let line = try await reader.nextLine()
        #expect(line == Data("ready".utf8))
        #expect(!hadToCloseWriter)
    }

    @Test
    func framingPreservesMultiplePacketsAndRejectsTruncatedTail() async throws {
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close() }
        let reader = SpeechPacketReader(handle: pipe.fileHandleForReading)
        try pipe.fileHandleForWriting.write(contentsOf: Data("first\nsecond\ntail".utf8))
        try pipe.fileHandleForWriting.close()
        #expect(try await reader.nextLine() == Data("first".utf8))
        #expect(try await reader.nextLine() == Data("second".utf8))
        do { _ = try await reader.nextLine(); Issue.record("Truncated packet accepted") }
        catch { #expect(error is SpeechFailure) }
    }

    @Test
    func oversizedPacketIsRejected() async throws {
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close() }
        let reader = SpeechPacketReader(handle: pipe.fileHandleForReading)
        let writer = Task.detached {
            try pipe.fileHandleForWriting.write(contentsOf: Data(repeating: 65, count: 140_001))
            try pipe.fileHandleForWriting.close()
        }
        do { _ = try await reader.nextLine(); Issue.record("Oversized packet accepted") }
        catch { #expect(error is SpeechFailure) }
        try await writer.value
    }

    @Test
    func prebufferQueuesAheadAndShortTailStillDrains() async throws {
        let player = SpeechAudioPlayer()
        defer { player.stop() }
        var started = false
        for _ in 0..<3 {
            try await player.enqueue(Data(repeating: 0, count: 28_800)) { started = true }
        }
        #expect(!started)
        #expect(player.queuedFrames == 21_600)
        try await player.enqueue(Data(repeating: 0, count: 28_800)) { started = true }
        #expect(started)
        #expect(player.queuedFrames == 28_800)
        try await player.finish { started = true }
        #expect(player.queuedFrames == 0)
        #expect(player.diagnostics.underruns == 0)
        player.reset()
        started = false
        try await player.enqueue(Data(repeating: 0, count: 9_600)) { started = true }
        #expect(!started)
        try await player.finish { started = true }
        #expect(started)
        #expect(player.queuedFrames == 0)
        #expect(player.diagnostics.frames == 2_400)
    }

    @Test
    func fullQueueBlocksProducerAndCancellationReleasesIt() async throws {
        let player = SpeechAudioPlayer()
        defer { player.stop() }
        let producer = Task { @MainActor in
            for _ in 0..<20 { try await player.enqueue(Data(repeating: 0, count: 96_000)) {} }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while player.queuedFrames < player.capacityFrames, .now < deadline { await Task.yield() }
        #expect(player.queuedFrames == player.capacityFrames)
        #expect(player.diagnostics.maximumQueuedFrames <= player.capacityFrames)
        player.stop()
        do { try await producer.value; Issue.record("Cancelled producer completed successfully") }
        catch { #expect(error is CancellationError) }
        #expect(player.queuedFrames == 0)
        player.reset()
        try await player.enqueue(Data(repeating: 0, count: 9_600)) {}
        try await player.finish {}
        #expect(player.queuedFrames == 0)
        #expect(player.diagnostics.frames == 2_400)
    }
}

@Suite("Primary interaction")
@MainActor
struct InteractionTests {
    @Test
    func customShortcutPersistsAndConflictKeepsPreviousBinding() async {
        let store = MemoryShortcutStore()
        let hotkey = HotkeyManagerFake(registrationResult: .registered)
        let model = AppModel(shortcutStore: store, hotkeyManager: hotkey)
        let custom = ShortcutConfiguration(key: "J", modifiers: UInt32(cmdKey | shiftKey))
        model.enqueueShortcutChange(custom)
        await model.waitForInteractionToSettle()
        #expect(model.shortcutConfiguration == custom)
        #expect(store.saved == custom)
        #expect(hotkey.registeredShortcut == custom.resolvedShortcut())
        hotkey.registrationResult = .conflict
        model.enqueueShortcutChange(.default)
        await model.waitForInteractionToSettle()
        #expect(model.shortcutConfiguration == custom)
        #expect(hotkey.registeredShortcut == custom.resolvedShortcut())
        #expect(model.hotkeyRegistration == .registered)
        #expect(store.saved == custom)
        #expect(model.shortcutNotice?.contains("already in use") == true)
        let restored = AppModel(shortcutStore: store,
            hotkeyManager: HotkeyManagerFake(registrationResult: .registered))
        #expect(restored.shortcutConfiguration == custom)
        hotkey.registrationResult = .registered
        model.enqueueShortcutChange(.default)
        await model.waitForInteractionToSettle()
        #expect(store.saved == .default)
    }

    @Test
    func shortcutCannotChangeDuringSelectionAndInvalidSettingsAreRejected() async {
        let store = MemoryShortcutStore()
        let model = AppModel(shortcutStore: store,
            hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: RegionSelectionControllerFake())
        model.enqueueShortcutChange(ShortcutConfiguration(key: "Y", modifiers: 0))
        await model.waitForInteractionToSettle()
        #expect(store.saved == nil)
        await model.handleReadRequest()
        model.enqueueShortcutChange(ShortcutConfiguration(key: "J", modifiers: UInt32(cmdKey | shiftKey)))
        await model.waitForInteractionToSettle()
        #expect(model.shortcutConfiguration == .default)
        #expect(store.saved == nil)
        #expect(model.status == .selecting)
        await model.handleReadRequest()
        #expect(model.status == .stopped)
    }

    @Test
    func shortcutSettingsValidateAndPersistOnlyConfiguration() throws {
        let suite = "com.christopherbobel.OpenScreenReader.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsShortcutStore(defaults: defaults)
        let custom = ShortcutConfiguration(key: "R", modifiers: UInt32(controlKey | optionKey))
        #expect(custom.displayName == "⌃⌥R")
        #expect(custom.isValid)
        #expect(!ShortcutConfiguration(key: "Escape", modifiers: UInt32(cmdKey)).isValid)
        #expect(!ShortcutConfiguration(key: "Y", modifiers: UInt32(shiftKey)).isValid)
        #expect(!ShortcutConfiguration(key: "Y", modifiers: UInt32(cmdKey) | 1).isValid)
        store.save(custom)
        #expect(store.load() == custom)
        #expect(defaults.persistentDomain(forName: suite)?.count == 1)
        defaults.set(Data("invalid".utf8), forKey: UserDefaultsShortcutStore.preferenceKey)
        #expect(store.load() == nil)
        defaults.set(try JSONEncoder().encode(ShortcutConfiguration(key: "Escape", modifiers: 0)),
                     forKey: UserDefaultsShortcutStore.preferenceKey)
        #expect(store.load() == nil)
    }

    @Test
    func realRegistrationPreservesOldBindingOnConflictAndReleasesItOnSuccess() {
        let manager = GlobalHotkeyManager()
        let competitor = GlobalHotkeyManager()
        let probe = GlobalHotkeyManager()
        defer { manager.unregister(); competitor.unregister(); probe.unregister() }
        let old = ShortcutConfiguration(key: "8", modifiers: UInt32(controlKey | optionKey | shiftKey)).resolvedShortcut()
        let new = ShortcutConfiguration(key: "9", modifiers: UInt32(controlKey | optionKey | shiftKey)).resolvedShortcut()
        #expect(manager.register(old) == .registered)
        #expect(manager.register(old) == .registered)
        #expect(competitor.register(new) == .registered)
        #expect(manager.register(new) == .conflict)
        #expect(probe.register(old) == .conflict)
        competitor.unregister()
        #expect(manager.register(new) == .registered)
        #expect(probe.register(old) == .registered)
    }

    @Test
    func changingShortcutRecoversFromStartupConflict() async {
        let hotkey = HotkeyManagerFake(registrationResult: .conflict)
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: hotkey)
        #expect(model.status == .error)
        hotkey.registrationResult = .registered
        model.enqueueShortcutChange(ShortcutConfiguration(key: "J", modifiers: UInt32(cmdKey | shiftKey)))
        await model.waitForInteractionToSettle()
        #expect(model.status == .ready)
        #expect(model.errorMessage == nil)
    }

    @Test
    func captureAutomaticallyReadsTextAndRetainsOnlyCountsAfterPlayback() async {
        let selection = RegionSelectionControllerFake()
        let ocr = OCRFake()
        let escape = EscapeFake()
        let speech = SpeechFake()
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: escape,
            ocrService: ocr, speechService: speech)
        await model.handleReadRequest()
        selection.complete(Self.ocrRegion)
        await model.waitForInteractionToSettle()
        await model.waitForCaptureToSettle()
        await model.waitForSpeechToSettle()
        #expect(ocr.calls == 1)
        #expect(speech.receivedText == "Hello world")
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
        let speech = SpeechFake()
        ocr.result = OCRResult(lines: [])
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: EscapeFake(),
            ocrService: ocr, speechService: speech)
        await model.handleReadRequest()
        selection.complete(Self.ocrRegion)
        await model.waitForInteractionToSettle()
        await model.waitForCaptureToSettle()
        #expect(model.status == .ready)
        #expect(speech.receivedText == nil)
        #expect(model.lastOCRSummary?.characterCount == 0)
        #expect(model.captureFeedback == "No readable text found. Select a clearer region.")
    }

    @Test(arguments: [false, true])
    func speechRemainsCancellableAndLateCompletionCannotAffectNewSelection(repeatedShortcut: Bool) async {
        let selection = RegionSelectionControllerFake()
        let escape = EscapeFake()
        let speech = SpeechFake()
        speech.suspend = true
        let model = AppModel(shortcutStore: MemoryShortcutStore(),
            hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: escape,
            ocrService: OCRFake(), speechService: speech)
        await model.handleReadRequest()
        selection.complete(Self.ocrRegion)
        await model.waitForInteractionToSettle()
        await model.waitForCaptureToSettle()
        await speech.waitUntilStarted()
        await model.waitForInteractionToSettle()
        #expect(model.status == .speaking)
        #expect(escape.isActive)
        #expect(!model.canChangeShortcut)
        #expect(await model.pipelineCoordinator.snapshot().phase == .speaking)
        if repeatedShortcut { await model.handleReadRequest() }
        else { escape.onEscape?(); await model.waitForInteractionToSettle() }
        #expect(speech.stopped)
        #expect(model.status == .stopped)
        #expect(!escape.isActive)
        await model.handleReadRequest()
        speech.resume()
        await model.waitForSpeechToSettle()
        #expect(model.status == .selecting)
        #expect(model.lastOCRSummary == nil)
    }

    @Test
    func speechFailureIsGenericAndDoesNotFallBack() async {
        let selection = RegionSelectionControllerFake()
        let speech = SpeechFake()
        speech.shouldFail = true
        let model = AppModel(shortcutStore: MemoryShortcutStore(),
            hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: EscapeFake(),
            ocrService: OCRFake(), speechService: speech)
        await model.handleReadRequest()
        selection.complete(Self.ocrRegion)
        await model.waitForInteractionToSettle()
        await model.waitForCaptureToSettle()
        await model.waitForSpeechToSettle()
        #expect(model.status == .error)
        #expect(model.errorMessage == SpeechFailure.failed.localizedDescription)
        #expect(speech.stopped)
    }

    @Test(arguments: [false, true])
    func modelLoadingCanBeCancelledOrTimedOutWithoutWaitingForWorker(timeout: Bool) async {
        let selection = RegionSelectionControllerFake()
        let speech = SpeechFake()
        speech.suspend = true
        speech.emitPlayback = false
        let model = AppModel(shortcutStore: MemoryShortcutStore(),
            hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: EscapeFake(),
            ocrService: OCRFake(), speechService: speech,
            speechStartupTimeout: timeout ? .milliseconds(80) : .seconds(90))
        await model.handleReadRequest()
        selection.complete(Self.ocrRegion)
        await model.waitForInteractionToSettle()
        await model.waitForCaptureToSettle()
        await speech.waitUntilStarted()
        #expect(model.status == .synthesizing)
        if timeout { await model.waitForTimeoutToSettle() }
        else { await model.handleReadRequest() }
        #expect(model.status == (timeout ? .error : .stopped))
        #expect(speech.stopped)
        speech.resume()
        await model.waitForSpeechToSettle()
        #expect(model.status == (timeout ? .error : .stopped))
    }

    @Test(arguments: [false, true])
    func cancelledOCRCannotPublishIntoNewSelection(repeatedShortcut: Bool) async {
        let selection = RegionSelectionControllerFake()
        let ocr = OCRFake()
        ocr.suspend = true
        let escape = EscapeFake()
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: escape,
            ocrService: ocr)
        await model.handleReadRequest()
        selection.complete(Self.ocrRegion)
        await model.waitForInteractionToSettle()
        await ocr.waitUntilStarted()
        #expect(model.status == .recognizing)
        #expect(escape.isActive)
        model.enqueueShortcutChange(ShortcutConfiguration(key: "J", modifiers: UInt32(cmdKey | shiftKey)))
        await model.waitForInteractionToSettle()
        #expect(model.shortcutConfiguration == .default)
        #expect(!model.canChangeShortcut)
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
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
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
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
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
        #expect(ShortcutConfiguration(key: "Y", modifiers: UInt32(controlKey | optionKey))
            .resolvedShortcut(source: source).keyCode == layout.1)
        #expect(ShortcutConfiguration(key: "1", modifiers: UInt32(cmdKey | shiftKey))
            .resolvedShortcut(source: source).keyCode == UInt32(kVK_ANSI_1))
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
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: hotkey, selectionController: selection,
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
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: hotkey, selectionController: selection,
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
            shortcutStore: MemoryShortcutStore(),
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
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: hotkey, selectionController: selection)

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
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
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
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
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
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
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
private final class SpeechFake: SpeechReading {
    var receivedText: String?
    var suspend = false
    var stopped = false
    var shouldFail = false
    var emitPlayback = true
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func read(_ text: String, onPlayback: @escaping @MainActor () -> Void) async throws {
        receivedText = text
        if shouldFail { throw NSError(domain: "private synthetic speech diagnostic", code: 1) }
        if emitPlayback { onPlayback() }
        if suspend {
            await withCheckedContinuation { continuation = $0; started?.resume(); started = nil }
        }
        // Deliberately non-cooperative: AppModel must reject a stale completion.
    }
    func stop() { stopped = true }
    func waitUntilStarted() async {
        if continuation == nil { await withCheckedContinuation { started = $0 } }
    }
    func resume() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class HotkeyManagerFake: HotkeyManaging {
    var onPress: (() -> Void)?
    private(set) var registeredShortcut: HotkeyShortcut?
    var registrationResult: HotkeyRegistration

    init(registrationResult: HotkeyRegistration) {
        self.registrationResult = registrationResult
    }

    func register(_ shortcut: HotkeyShortcut) -> HotkeyRegistration {
        if registrationResult == .registered { registeredShortcut = shortcut }
        return registrationResult
    }

    func unregister() {}
}

@MainActor
final class MemoryShortcutStore: ShortcutStoring {
    var saved: ShortcutConfiguration?
    func load() -> ShortcutConfiguration? { saved }
    func save(_ configuration: ShortcutConfiguration) { saved = configuration }
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
