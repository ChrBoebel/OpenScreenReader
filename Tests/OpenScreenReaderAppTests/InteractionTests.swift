import AppKit
import AVFoundation
import CoreGraphics
import Carbon.HIToolbox
import Foundation
import Testing
@testable import OpenScreenReader

@Suite("Speech transport and buffering", .serialized)
@MainActor
struct SpeechBufferingTests {
    @Test
    func stoppingBeforePreparationTaskStartsCannotLaunchAWorkerLater() async throws {
        let service = LocalSpeechService()
        defer { service.stop() }
        service.prepareNext("Ein kurzer öffentlicher Testsatz.")
        service.stop()
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.workerLaunchCount == 0)
        #expect(service.workerPID == nil)
        #expect(service.preparedAudioBytes == 0)
    }

    @Test
    func preparationBufferIsBoundedAndCancellationReleasesBothSides() async throws {
        let buffer = SpeechPreparationBuffer(capacityBytes: 8)
        try await buffer.send(Data(repeating: 1, count: 8))
        var sent = false
        let producer = Task { try await buffer.send(Data(repeating: 2, count: 4)); sent = true }
        await Task.yield()
        #expect(buffer.bufferedBytes == 8)
        #expect(!sent)
        #expect(try await buffer.next()?.count == 8)
        try await producer.value
        #expect(buffer.bufferedBytes == 4)
        buffer.cancel()
        #expect(buffer.bufferedBytes == 0)
        do { _ = try await buffer.next(); Issue.record("Cancelled buffer accepted consumer") }
        catch { #expect(error is CancellationError) }
        let full = SpeechPreparationBuffer(capacityBytes: 8)
        try await full.send(Data(repeating: 1, count: 8))
        let blockedProducer = Task { try await full.send(Data(repeating: 1, count: 4)) }
        await Task.yield()
        full.cancel()
        do { try await blockedProducer.value; Issue.record("Cancelled producer survived") }
        catch { #expect(error is CancellationError) }
        #expect(full.bufferedBytes == 0)
        let empty = SpeechPreparationBuffer(capacityBytes: 8)
        let consumer = Task { try await empty.next() }
        await Task.yield()
        empty.cancel()
        do { _ = try await consumer.value; Issue.record("Cancelled consumer survived") }
        catch { #expect(error is CancellationError) }
    }

    @Test
    func playbackSpeedIsBoundedAndSurvivesResetWithoutPitchShift() {
        let player = SpeechAudioPlayer(sampleRate: 44_100)
        player.playbackRate = 1.5
        #expect(player.playbackRate == 1.5)
        #expect(player.prebufferFrames == 66_150)
        #expect(player.pitchCents == 0)
        player.reset()
        #expect(player.playbackRate == 1.5)
        player.playbackRate = 99
        #expect(player.playbackRate == 2)
        player.playbackRate = 0
        #expect(player.playbackRate == 0.75)
        player.playbackRate = .nan
        #expect(player.playbackRate == 1)
        player.stop()
    }

    @Test
    func envelopeFollowsRenderedFramesAndDropsOldLevels() {
        var envelope = PlaybackEnvelope()
        let samples: [Float] = Array(repeating: 0.25, count: 480) + Array(repeating: 0, count: 480)
        samples.withUnsafeBufferPointer { envelope.append($0, startingAt: 2_400, sampleRate: 24_000) }
        #expect(envelope.level(at: 0) == 0)
        #expect(envelope.level(at: 2_400) > 0.5)
        #expect(envelope.level(at: 2_880) == 0)
        #expect(envelope.level(at: 3_360) == 0)
        #expect(envelope.count == 0)
    }

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
    func nativeSupertonicRateKeepsEightSourceSecondsOfBufferCapacity() async throws {
        let player = SpeechAudioPlayer(sampleRate: 44_100)
        defer { player.stop() }
        #expect(player.capacityFrames == 352_800)
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
    func explicitStopWhileIdleNeverStartsSelection() async {
        let f = QueueFixture()
        f.model.enqueueStopRequest()
        await f.model.waitForInteractionToSettle()
        #expect(f.selection.startCount == 0)
        #expect(f.model.status == .ready)
    }
    @Test
    func pausedPlayerDoesNotAutoStartAndStopReleasesDrain() async throws {
        let player = SpeechAudioPlayer(sampleRate: 44_100)
        player.setPaused(true)
        var callbacks = 0
        for _ in 0..<3 { try await player.enqueue(Data(repeating: 0, count: 96_000)) { callbacks += 1 } }
        #expect(player.isPaused)
        #expect(callbacks == 0)
        let drain = Task { try await player.finish { callbacks += 1 } }
        try await Task.sleep(for: .milliseconds(80))
        #expect(player.queuedFrames == 72_000)
        player.stop()
        do { try await drain.value; Issue.record("Stopped drain returned successfully") }
        catch is CancellationError {}
        #expect(!player.isPaused)
        #expect(player.queuedFrames == 0)
    }

    @Test
    func queueEditingUsesStableIDsAndRefreshesPreparation() async throws {
        let f = QueueFixture()
        await f.model.handleReadRequest()
        f.selection.complete(Self.ocrRegion)
        await f.model.waitForCaptureToSettle()
        try await f.speech.waitForReads(1)
        await f.model.waitForInteractionToSettle()
        f.model.togglePause()
        #expect(f.model.isPaused && f.speech.isPaused)
        for text in ["Second", "Third", "Fourth"] {
            f.ocr.result = OCRResult(lines: [text])
            f.model.enqueueAddRequest()
            await f.model.waitForInteractionToSettle()
            f.selection.complete(Self.ocrRegion)
            await f.model.waitForQueueInputToSettle()
        }
        let entries = f.model.queueEntries
        f.model.moveQueueEntry(entries[2].id, offset: -1)
        f.model.removeQueueEntry(entries[0].id)
        #expect(f.model.queueEntries.map(\.preview) == ["Fourth", "Third"])
        #expect(f.speech.preparedText == "Fourth")
        f.model.removeQueueEntry(entries[0].id)
        #expect(f.model.queuedTextCount == 2)
        f.model.playQueueEntry(entries[1].id)
        await f.model.waitForInteractionToSettle()
        try await f.speech.waitForReads(2)
        #expect(f.speech.texts.last == "Third")
        #expect(!f.model.isPaused)
        #expect(f.model.queueEntries.map(\.preview) == ["Fourth"])
        await f.model.handleReadRequest()
        #expect(f.model.queueEntries.isEmpty)
    }
    @Test
    func repeatedPrimaryShortcutQueuesWithoutStoppingAndIgnoresDuplicateSelection() async throws {
        let f = QueueFixture()
        f.hotkey.onPress?()
        await f.model.waitForInteractionToSettle()
        f.hotkey.onPress?()
        await f.model.waitForInteractionToSettle()
        #expect(f.model.status == .selecting)
        #expect(f.selection.startCount == 1)
        guard f.model.status == .selecting else { return }
        f.selection.complete(Self.ocrRegion)
        await f.model.waitForCaptureToSettle()
        try await f.speech.waitForReads(1)
        f.hotkey.onPress?()
        await f.model.waitForInteractionToSettle()
        #expect(f.model.status == .speaking)
        #expect(f.model.isAddingToQueue)
        #expect(f.selection.startCount == 2)
        guard f.model.isAddingToQueue else { return }
        f.hotkey.onPress?()
        await f.model.waitForInteractionToSettle()
        #expect(f.selection.startCount == 2)
        f.ocr.result = OCRResult(lines: ["Danach vorlesen"])
        f.selection.complete(Self.ocrRegion)
        await f.model.waitForQueueInputToSettle()
        #expect(f.model.queuedTextCount == 1)
        #expect(f.speech.texts.count == 1)
        f.speech.finishFirst()
        try await f.speech.waitForReads(2)
        #expect(f.speech.texts.last == "Danach vorlesen")
        f.escape.onEscape?()
        await f.model.waitForInteractionToSettle()
        #expect(f.model.status == .stopped)
        #expect(f.model.queuedTextCount == 0)
    }

    @Test
    func speedPreferencePersistsAndReachesTheProviderImmediately() throws {
        let suite = "com.christopherbobel.OpenScreenReader.speed-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let speech = QueueSpeechFake()
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            speechService: speech, preferences: defaults)
        #expect(model.playbackRate == 1)
        model.setPlaybackRate(1.75)
        #expect(speech.playbackRate == 1.75)
        let next = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            speechService: QueueSpeechFake(), preferences: defaults)
        #expect(next.playbackRate == 1.75)
    }

    @Test
    func queueShortcutCannotReplaceStopAndFailedRegistrationKeepsPrevious() async {
        let queueHotkey = HotkeyManagerFake(registrationResult: .registered)
        let store = MemoryShortcutStore()
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            queueHotkeyManager: queueHotkey, queueShortcutStore: store)
        model.enqueueQueueShortcutChange(.default)
        await model.waitForInteractionToSettle()
        #expect(model.queueShortcutConfiguration == .queueDefault)
        #expect(store.saved == nil)
        let custom = ShortcutConfiguration(key: "J", modifiers: UInt32(cmdKey | shiftKey | optionKey))
        model.enqueueQueueShortcutChange(custom)
        await model.waitForInteractionToSettle()
        #expect(store.saved == custom)
        queueHotkey.registrationResult = .conflict
        model.enqueueQueueShortcutChange(.queueDefault)
        await model.waitForInteractionToSettle()
        #expect(model.queueShortcutConfiguration == custom)
        #expect(store.saved == custom)
        model.enqueueShortcutChange(custom)
        await model.waitForInteractionToSettle()
        #expect(model.shortcutConfiguration == .default)
    }

    @Test
    func queueRejectsEmptyAndOversizedTextsAndStopsAtFive() async throws {
        let f = QueueFixture()
        await f.model.handleReadRequest()
        f.selection.complete(Self.ocrRegion)
        await f.model.waitForCaptureToSettle()
        try await f.speech.waitForReads(1)
        for text in ["", String(repeating: "a", count: 8_001)] {
            f.ocr.result = OCRResult(lines: [text])
            f.model.enqueueAddRequest()
            await f.model.waitForInteractionToSettle()
            f.selection.complete(Self.ocrRegion)
            await f.model.waitForQueueInputToSettle()
            #expect(f.model.queuedTextCount == 0)
            #expect(f.model.status == .speaking)
            #expect(!f.model.isAddingToQueue)
        }
        for index in 0..<5 {
            f.ocr.result = OCRResult(lines: ["Text \(index)"])
            f.model.enqueueAddRequest()
            await f.model.waitForInteractionToSettle()
            f.selection.complete(Self.ocrRegion)
            await f.model.waitForQueueInputToSettle()
        }
        #expect(f.model.queuedTextCount == 5)
        let starts = f.selection.startCount
        f.hotkey.onPress?()
        await f.model.waitForInteractionToSettle()
        #expect(f.selection.startCount == starts)
        #expect(f.model.queuedTextCount == 5)
        #expect(f.model.status == .speaking)
        #expect(!f.model.canAddToQueue)
        await f.model.handleReadRequest()
        #expect(f.model.queuedTextCount == 0)
    }

    @Test
    func queuedTextsReadInOrderAndStopClearsAllWaitingText() async throws {
        let f = QueueFixture()
        await f.model.handleReadRequest()
        f.selection.complete(Self.ocrRegion)
        await f.model.waitForCaptureToSettle()
        try await f.speech.waitForReads(1)
        for text in ["Zweiter Text", "Dritter Text"] {
            f.ocr.result = OCRResult(lines: [text])
            f.model.enqueueAddRequest()
            await f.model.waitForInteractionToSettle()
            f.selection.complete(Self.ocrRegion)
            await f.model.waitForQueueInputToSettle()
        }
        #expect(f.model.queuedTextCount == 2)
        #expect(f.speech.preparedText == "Zweiter Text", "Only the next FIFO entry is prepared.")
        #expect(f.speech.texts.count == 1, "Adding text must not stop or restart speech.")
        f.speech.finishFirst()
        try await f.speech.waitForReads(2)
        #expect(f.speech.texts == ["Hello world", "Zweiter Text"])
        #expect(f.model.queuedTextCount == 1)
        await f.model.waitForInteractionToSettle()
        #expect(f.speech.preparedText == "Dritter Text")
        await f.model.handleReadRequest()
        #expect(f.model.queuedTextCount == 0)
        #expect(!f.model.isAddingToQueue)
        #expect(f.model.status == .stopped)
        #expect(!f.escape.isActive)
        #expect(f.speech.preparedText == nil)
    }

    @Test
    func completionWaitsForPendingOCRAndSkipCannotCancelTheNextText() async throws {
        let f = QueueFixture()
        await f.model.handleReadRequest()
        f.selection.complete(Self.ocrRegion)
        await f.model.waitForCaptureToSettle()
        try await f.speech.waitForReads(1)
        f.ocr.suspend = true
        f.ocr.result = OCRResult(lines: ["Danach"])
        f.model.enqueueAddRequest()
        await f.model.waitForInteractionToSettle()
        f.selection.complete(Self.ocrRegion)
        await f.ocr.waitUntilStarted()
        f.speech.finishFirst()
        await f.model.waitForSpeechToSettle()
        #expect(f.model.status == .waiting)
        #expect(f.escape.isActive)
        f.ocr.resume()
        await f.model.waitForQueueInputToSettle()
        try await f.speech.waitForReads(2)
        f.ocr.suspend = false
        f.ocr.result = OCRResult(lines: ["Übersprungen zum nächsten"])
        f.model.enqueueAddRequest()
        await f.model.waitForInteractionToSettle()
        f.selection.complete(Self.ocrRegion)
        await f.model.waitForQueueInputToSettle()
        f.model.enqueueSkipRequest()
        await f.model.waitForInteractionToSettle()
        try await f.speech.waitForReads(3)
        await f.model.waitForInteractionToSettle()
        #expect(f.model.status == .speaking)
        #expect(f.speech.texts.last == "Übersprungen zum nächsten")
        await f.model.handleReadRequest()
    }

    @Test
    func escapeDiscardsLateQueueOCRAndDoesNotRestartReading() async throws {
        let f = QueueFixture()
        await f.model.handleReadRequest()
        f.selection.complete(Self.ocrRegion)
        await f.model.waitForCaptureToSettle()
        try await f.speech.waitForReads(1)
        f.ocr.suspend = true
        f.model.enqueueAddRequest()
        await f.model.waitForInteractionToSettle()
        f.selection.complete(Self.ocrRegion)
        await f.ocr.waitUntilStarted()
        f.escape.onEscape?()
        await f.model.waitForInteractionToSettle()
        f.ocr.resume()
        await f.model.waitForQueueInputToSettle()
        #expect(f.model.status == .stopped)
        #expect(f.model.queuedTextCount == 0)
        #expect(f.speech.texts.count == 1)
    }

    @Test
    func queueCaptureTimeoutDoesNotInterruptSpeechOrAcceptItsLateResult() async throws {
        let f = QueueFixture(operationTimeout: .milliseconds(120))
        await f.model.handleReadRequest()
        f.selection.complete(Self.ocrRegion)
        await f.model.waitForCaptureToSettle()
        try await f.speech.waitForReads(1)
        f.capture.suspend = true
        f.model.enqueueAddRequest()
        await f.model.waitForInteractionToSettle()
        f.selection.complete(Self.ocrRegion)
        await f.capture.waitUntilStarted()
        try await Task.sleep(for: .milliseconds(180))
        await f.model.waitForInteractionToSettle()
        #expect(!f.model.isAddingToQueue)
        #expect(f.model.status == .speaking)
        f.capture.resume()
        await f.model.waitForQueueInputToSettle()
        #expect(f.model.queuedTextCount == 0)
        #expect(f.ocr.calls == 1)
        await f.model.handleReadRequest()
    }

    @Test
    func escapeStillStopsAfterAdvancingToAQueuedText() async throws {
        let f = QueueFixture()
        await f.model.handleReadRequest()
        f.selection.complete(Self.ocrRegion)
        await f.model.waitForCaptureToSettle()
        try await f.speech.waitForReads(1)
        let escapeFromSessionStart = f.escape.onEscape
        f.model.enqueueAddRequest()
        await f.model.waitForInteractionToSettle()
        f.selection.complete(Self.ocrRegion)
        await f.model.waitForQueueInputToSettle()
        f.speech.finishFirst()
        try await f.speech.waitForReads(2)
        escapeFromSessionStart?()
        await f.model.waitForInteractionToSettle()
        #expect(f.model.status == .stopped)
        #expect(f.model.queuedTextCount == 0)
        await f.model.handleReadRequest()
        escapeFromSessionStart?()
        await f.model.waitForInteractionToSettle()
        #expect(f.model.status == .selecting, "An old session's Escape callback must not stop a new session.")
        await f.model.handleReadRequest()
    }

    @Test
    func positionPreviewDoesNotCaptureRecognizeSpeakOrReplaceAnActiveOperation() async {
        let selection = RegionSelectionControllerFake()
        let capture = CaptureFake()
        let ocr = OCRFake()
        let speech = SpeechFake()
        let escape = EscapeFake()
        let panel = ReadingPanelFake()
        let model = AppModel(shortcutStore: MemoryShortcutStore(),
            hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: capture, escapeMonitor: escape,
            ocrService: ocr, speechService: speech, readingPanel: panel)
        model.previewReadingPanelPosition()
        #expect(panel.state == .positioning)
        #expect(panel.onStop == nil)
        #expect(model.status == .ready)
        #expect(selection.startCount == 0 && capture.calls == 0 && ocr.calls == 0)
        #expect(speech.receivedText == nil && !escape.isActive)
        await model.handleReadRequest()
        #expect(panel.state == nil)
        model.previewReadingPanelPosition()
        #expect(panel.state == nil, "Preview cannot replace selection or an active pipeline.")
        #expect(selection.startCount == 1)
        await model.handleReadRequest()
    }

    @Test
    func readingPanelStaysHiddenUntilCaptureFinishesAndStopsOnlyItsOwnOperation() async {
        let selection = RegionSelectionControllerFake()
        let capture = CaptureFake()
        capture.suspend = true
        let ocr = OCRFake()
        ocr.suspend = true
        let panel = ReadingPanelFake()
        let sounds = InterfaceSoundsFake()
        let model = AppModel(shortcutStore: MemoryShortcutStore(),
            hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: capture, escapeMonitor: EscapeFake(),
            ocrService: ocr, readingPanel: panel, interfaceSounds: sounds)
        await model.handleReadRequest()
        #expect(panel.state == nil)
        selection.complete(Self.ocrRegion)
        await capture.waitUntilStarted()
        #expect(model.status == .capturing)
        #expect(panel.state == nil)
        #expect(sounds.cues.isEmpty)
        capture.resume()
        await ocr.waitUntilStarted()
        #expect(panel.state == .recognizing)
        #expect(panel.origin == Self.ocrRegion.rectInScreenPoints, "The first visible state carries the captured frame.")
        #expect(sounds.cues.isEmpty, "The opening cue belongs to the control's landing, not the pipeline.")
        #expect(panel.displayID == Self.ocrRegion.displayID)
        let oldStop = panel.onStop
        oldStop?()
        await model.waitForInteractionToSettle()
        #expect(model.status == .stopped)
        #expect(panel.state == .stopped)
        #expect(sounds.isStopped)
        await model.handleReadRequest()
        #expect(panel.state == nil)
        oldStop?()
        ocr.resume()
        await model.waitForCaptureToSettle()
        await model.waitForInteractionToSettle()
        #expect(model.status == .selecting)
        #expect(panel.state == nil)
        await model.handleReadRequest()
    }

    @Test(arguments: [false, true])
    func readingPanelStopsLoadingAndPlayback(playing: Bool) async {
        let selection = RegionSelectionControllerFake()
        let speech = SpeechFake()
        speech.suspend = true
        speech.emitPlayback = playing
        let panel = ReadingPanelFake()
        let sounds = InterfaceSoundsFake()
        let model = AppModel(shortcutStore: MemoryShortcutStore(),
            hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: EscapeFake(),
            ocrService: OCRFake(), speechService: speech, readingPanel: panel, interfaceSounds: sounds)
        await model.handleReadRequest()
        selection.complete(Self.ocrRegion)
        await model.waitForInteractionToSettle()
        await model.waitForCaptureToSettle()
        await speech.waitUntilStarted()
        await model.waitForInteractionToSettle()
        #expect(panel.state == (playing ? .speaking : .preparing))
        try? await Task.sleep(for: .milliseconds(80))
        #expect(panel.level == (playing ? 0.65 : 0))
        #expect(sounds.cues.isEmpty)
        #expect(panel.origin == nil, "Later states never re-open from the frame.")
        if playing { #expect(sounds.isStopped) }
        panel.onStop?()
        await model.waitForInteractionToSettle()
        #expect(speech.stopped)
        #expect(sounds.isStopped)
        #expect(model.status == .stopped)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(panel.level == 0)
        #expect(panel.state == .stopped)
        speech.resume()
        await model.waitForSpeechToSettle()
        #expect(panel.state == .stopped)
    }

    @Test(arguments: ["complete", "empty", "failure"])
    func readingPanelReportsTerminalResultsWithoutRetainingContent(outcome: String) async {
        let selection = RegionSelectionControllerFake()
        let ocr = OCRFake()
        let speech = SpeechFake()
        if outcome == "empty" { ocr.result = OCRResult(lines: []) }
        speech.shouldFail = outcome == "failure"
        let panel = ReadingPanelFake()
        let sounds = InterfaceSoundsFake()
        let model = AppModel(shortcutStore: MemoryShortcutStore(),
            hotkeyManager: HotkeyManagerFake(registrationResult: .registered),
            selectionController: selection, captureService: CaptureFake(), escapeMonitor: EscapeFake(),
            ocrService: ocr, speechService: speech, readingPanel: panel, interfaceSounds: sounds)
        await model.handleReadRequest()
        selection.complete(Self.ocrRegion)
        await model.waitForInteractionToSettle()
        await model.waitForCaptureToSettle()
        await model.waitForSpeechToSettle()
        let expected: ReadingPanelState = outcome == "empty" ? .noText : outcome == "failure" ? .failed : .finished
        #expect(panel.state == expected)
        #expect(panel.onStop == nil)
        #expect(sounds.cues == (outcome == "complete" ? [.completion] : [.attention]))
    }

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

@Suite("Reading status presentation", .serialized)
@MainActor
struct ReadingPanelTests {
    @Test
    func returningFromQueueCaptureIsSilentAndShowsQueueCount() throws {
        let screen = try #require(NSScreen.screens.first)
        let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        let sounds = InterfaceSoundsFake()
        let controller = ReadingPanelController(interfaceSounds: sounds)
        defer { controller.hide() }
        controller.show(.speaking, displayID: number.uint32Value, onStop: {})
        controller.hide()
        sounds.cues.removeAll()
        controller.restore(.speaking, displayID: number.uint32Value, onStop: {})
        controller.updateQueueCount(2)
        #expect(sounds.cues.isEmpty)
        let badge = controller.panel?.contentView?.subviews.compactMap { $0 as? NSButton }.first
        #expect(badge?.title == "+2")
        #expect(badge?.isHidden == false)
        controller.updateQueueCount(0)
        #expect(badge?.title == "···")
        #expect(badge?.isHidden == false)
    }

    @Test
    func draggingSurvivesSpeechTransitionsButNeverSurvivesHide() async throws {
        let suite = "com.christopherbobel.OpenScreenReader.placement-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let screen = try #require(NSScreen.screens.first)
        let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        let controller = ReadingPanelController(defaults: defaults)
        defer { controller.hide() }
        var stops = 0
        controller.show(.preparing, displayID: number.uint32Value, onStop: { stops += 1 })
        let panel = try #require(controller.panel)
        let original = panel.frame
        let pointer = CGPoint(x: original.midX, y: original.midY)
        controller.beginDrag(at: pointer)
        controller.moveDrag(to: CGPoint(x: pointer.x + 2, y: pointer.y + 2))
        controller.endDrag()
        #expect(panel.frame == original, "A click or tiny hand movement is not a drag.")
        controller.beginDrag(at: pointer)
        controller.moveDrag(to: CGPoint(x: screen.visibleFrame.minX + 20, y: screen.visibleFrame.midY))
        let draggedFrame = panel.frame
        controller.show(.speaking, displayID: number.uint32Value, onStop: { stops += 1 })
        #expect(panel.frame == draggedFrame, "Starting speech must not jerk a held capsule back to its dock.")
        controller.endDrag()
        try await Task.sleep(for: .milliseconds(300))
        let saved = ReadingPanelPlacement.load(from: defaults)
        #expect(saved.edge == .left)
        // Other suites synthesize cue buffers on MainActor. Give the animation's next tick a turn.
        for _ in 0..<40 {
            if panel.frame == saved.frame(in: screen.visibleFrame) { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(panel.frame == saved.frame(in: screen.visibleFrame))
        #expect(stops == 0)
        (panel.contentView as? ReadingControlView)?.currentAction()
        #expect(stops == 1)
        controller.beginDrag(at: CGPoint(x: panel.frame.midX, y: panel.frame.midY))
        controller.moveDrag(to: CGPoint(x: screen.visibleFrame.maxX, y: screen.visibleFrame.midY))
        controller.endDrag()
        controller.hide()
        controller.moveDrag(to: .zero)
        controller.endDrag()
        try await Task.sleep(for: .milliseconds(300))
        #expect(panel.isVisible == false)
        #expect(panel.contentView == nil)
        let newController = ReadingPanelController(defaults: defaults)
        defer { newController.hide() }
        newController.show(.positioning, displayID: number.uint32Value, onStop: nil)
        #expect(newController.panel?.frame == ReadingPanelPlacement.load(from: defaults).frame(in: screen.visibleFrame))
    }

    @Test
    func completionWaitsUntilUserReleasesTheDragSurface() async throws {
        let screen = try #require(NSScreen.screens.first)
        let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        let controller = ReadingPanelController(terminalDuration: .milliseconds(40))
        defer { controller.hide() }
        controller.show(.finished, displayID: number.uint32Value, onStop: nil)
        let frame = try #require(controller.panel?.frame)
        controller.beginDrag(at: CGPoint(x: frame.midX, y: frame.midY))
        try await Task.sleep(for: .milliseconds(350))
        #expect(controller.panel?.isVisible == true)
        controller.endDrag()
        try await Task.sleep(for: .milliseconds(350))
        #expect(controller.panel?.isVisible == false)
    }

    @Test
    func placementFitsEveryEdgeAndRemembersOnlyNormalizedGeometry() throws {
        let suite = "com.christopherbobel.OpenScreenReader.placement-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ReadingPanelPlacement.load(from: defaults) == ReadingPanelPlacement())
        for visible in [CGRect(x: -1440, y: 124, width: 1440, height: 850),
                        CGRect(x: 120, y: -900, width: 1920, height: 860),
                        CGRect(x: 0, y: 0, width: 200, height: 50)] {
            for edge in ReadingPanelEdge.allCases {
                for fraction in [0.0, 0.5, 1.0] {
                    let placement = ReadingPanelPlacement(edge: edge, fraction: fraction)
                    let frame = placement.frame(in: visible)
                    #expect(visible.contains(frame))
                    placement.save(to: defaults)
                    #expect(ReadingPanelPlacement.load(from: defaults) == placement)
                }
            }
        }
        defaults.set("unknown", forKey: ReadingPanelPlacement.edgeKey)
        defaults.set(Double.nan, forKey: ReadingPanelPlacement.fractionKey)
        #expect(ReadingPanelPlacement.load(from: defaults) == ReadingPanelPlacement())
    }

    @Test
    func droppingSelectsNearestEdgeAndPreservesAlongEdgePosition() {
        let screen = CGRect(x: -1200, y: 100, width: 1200, height: 900)
        for (point, edge) in [(CGPoint(x: -1190, y: 700), ReadingPanelEdge.left),
                              (CGPoint(x: -10, y: 700), .right),
                              (CGPoint(x: -400, y: 110), .bottom)] {
            let placement = ReadingPanelPlacement.dropped(at: point, in: screen)
            #expect(placement.edge == edge)
            let frame = placement.frame(in: screen)
            #expect(screen.contains(frame))
            #expect(abs((edge == .bottom ? frame.midX : frame.midY) - (edge == .bottom ? point.x : point.y)) < 1)
        }
    }

    @Test
    func verticalControlHasUprightStopTargetAndBackgroundDragDoesNotStop() {
        let view = ReadingControlView(frame: CGRect(x: 0, y: 0, width: 92, height: 300))
        view.isVertical = true
        var stops = 0
        view.present(.speaking, opening: false, action: { stops += 1 })
        for index in 0..<120 { view.tick(now: CACurrentMediaTime() + Double(index) / 60) }
        let button = view.subviews.flatMap(\.subviews).compactMap { $0 as? ReadingStopButton }.first
        #expect(button?.frame.size == CGSize(width: 44, height: 44))
        #expect(stops == 0)
        // Re-presenting a captured callback (as the selection flight does) must not recurse.
        let capturedAction = view.currentAction
        view.present(.speaking, opening: false, action: capturedAction)
        view.currentAction()
        #expect(stops == 1)
        view.stopAnimating()
    }

    @Test
    func dragSurfaceReceivesMouseEventsWhileStopKeepsItsOwnHitTarget() throws {
        let window = ReadingStatusPanel()
        window.setFrame(CGRect(x: 100, y: 100, width: 300, height: 92), display: false)
        let view = ReadingControlView(frame: CGRect(x: 0, y: 0, width: 300, height: 92))
        window.contentView = view
        defer { view.stopAnimating(); window.close() }
        view.present(.positioning, opening: false, action: {})
        for index in 0..<120 { view.tick(now: CACurrentMediaTime() + Double(index) / 60) }
        let target = try #require(view.hitTest(CGPoint(x: 130, y: 46)))
        #expect(!(target is ReadingStopButton))
        let button = try #require(view.subviews.flatMap(\.subviews).compactMap { $0 as? ReadingStopButton }.first)
        let buttonPoint = view.convert(CGPoint(x: 22, y: 22), from: button)
        #expect(view.hitTest(buttonPoint) === button)
        var positions: [CGPoint] = []
        var releases = 0
        view.onDragStart = { positions.append($0) }
        view.onDragMove = { positions.append($0) }
        view.onDragEnd = { releases += 1 }
        func event(_ type: NSEvent.EventType, _ location: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0.5))
        }
        target.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 130, y: 46)))
        target.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 150, y: 66)))
        target.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 150, y: 66)))
        #expect(positions == [CGPoint(x: 230, y: 146), CGPoint(x: 250, y: 166)])
        #expect(releases == 1)
    }

    /// Opt-in render of only the view's drawing, never a screenshot of the user's screen.
    @Test
    func renderPlacementLayouts() throws {
        guard let path = ProcessInfo.processInfo.environment["OSR_PLACEMENT_RENDER_DIR"] else { return }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for edge in ReadingPanelEdge.allCases {
            let size = edge == .bottom ? CGSize(width: 300, height: 92) : CGSize(width: 92, height: 300)
            let view = ReadingControlView(frame: CGRect(origin: .zero, size: size))
            view.isVertical = edge != .bottom
            view.present(.positioning, opening: false, action: {})
            for index in 0..<120 { view.tick(now: CACurrentMediaTime() + Double(index) / 60) }
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("\(edge.rawValue).png"))
            view.stopAnimating()
        }
    }

    @Test
    func drawingClockDoesNotRetainAnUnownedView() async throws {
        weak var released: ReadingControlView?
        do {
            let view = ReadingControlView(frame: CGRect(origin: .zero, size: ReadingControlView.Metrics.surface))
            released = view
            view.present(.speaking, opening: true, action: {})
            try await Task.sleep(for: .milliseconds(35))
        }
        try await Task.sleep(for: .milliseconds(35))
        #expect(released == nil)
    }

    @Test
    func sameHostSurvivesTransitionsAndImmediateHideCancelsExit() async throws {
        let screen = try #require(NSScreen.screens.first)
        let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        let suite = "com.christopherbobel.OpenScreenReader.placement-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = ReadingPanelController(terminalDuration: .seconds(10), defaults: defaults)
        defer { controller.hide() }
        controller.show(.recognizing, displayID: number.uint32Value, onStop: {})
        let host = try #require(controller.panel?.contentView)
        #expect(host is ReadingControlView, "First show installs the native reading control.")
        controller.show(.preparing, displayID: number.uint32Value, onStop: {})
        #expect(controller.panel?.contentView === host)
        controller.show(.speaking, displayID: number.uint32Value, onStop: {})
        #expect(controller.panel?.contentView === host)
        controller.dismiss()
        controller.hide()
        #expect(controller.panel?.isVisible == false)
        controller.show(.recognizing, displayID: number.uint32Value, onStop: {})
        try await Task.sleep(for: .milliseconds(350))
        #expect(controller.state == .recognizing)
        #expect(controller.panel?.isVisible == true)
        #expect(controller.panel?.frame == ReadingPanelController.frame(in: screen.visibleFrame))
    }

    @Test
    func soundCuesAreShortBoundedDeterministicStereoAndDecodeWithoutFiles() throws {
        for cue in InterfaceCue.allCases {
            let samples = cue.samples
            let rendering = cue.render(variant: 0)
            #expect(samples == cue.samples)
            #expect(rendering == cue.render(variant: 0))
            #expect(rendering.left.count == rendering.right.count)
            #expect(rendering.left != rendering.right, "The room is stereo.")
            let limit = cue == .tap || cue == .release ? 7_056 : 66_150
            #expect(samples.count <= limit, "Cues stay under 1.5 s; clicks under 160 ms.")
            let peak = Double(cue.peak) + 0.001
            #expect(rendering.left.allSatisfy { $0.isFinite && abs(Double($0)) <= peak })
            #expect(rendering.right.allSatisfy { $0.isFinite && abs(Double($0)) <= peak })
            #expect((rendering.left + rendering.right).map { abs($0) }.max() ?? 0 > cue.peak * 0.98, "Normalised to the intended peak.")
            #expect(rendering.left.first == 0 && rendering.right.first == 0)
            #expect(abs(rendering.left.last ?? 1) < 0.001 && abs(rendering.right.last ?? 1) < 0.001)
            if cue.variantCount > 1 { #expect(cue.render(variant: 1) != rendering, "Alternate voicings differ.") }
            #expect(cue.wavData.count == 44 + samples.count * 2 * InterfaceCue.channels)
            let decoded = try AVAudioPlayer(data: cue.wavData)
            #expect(decoded.numberOfChannels == 2)
            #expect(abs(decoded.duration - Double(samples.count) / Double(InterfaceCue.sampleRate)) < 0.001)
        }
    }

    @Test
    func stopButtonPressPlaysATapWithoutStoppingCuesAndCancellationCannotCutIt() {
        let sounds = InterfaceSoundsFake()
        let controller = ReadingPanelController(terminalDuration: .seconds(10), interfaceSounds: sounds)
        defer { controller.hide() }
        guard let number = NSScreen.screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        controller.show(.speaking, displayID: number.uint32Value, onStop: {})
        #expect(sounds.cues == [.selection], "Without a frame to fly, the opening cue plays immediately.")
        let view = controller.panel?.contentView as? ReadingControlView
        #expect(view != nil)
        sounds.cues.removeAll()
        sounds.isStopped = true
        view?.onPress?()
        view?.onRelease?()
        #expect(sounds.cues == [.tap, .release])
        #expect(sounds.isStopped, "Clicks are never registered as interruptible cues.")
    }

    @Test
    func capturedFrameFliesIntoTheControlBeforeItOpensAndHideCancelsTheFlight() async throws {
        let sounds = InterfaceSoundsFake()
        let controller = ReadingPanelController(terminalDuration: .seconds(10), interfaceSounds: sounds)
        defer { controller.hide() }
        let screen = try #require(NSScreen.screens.first)
        let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        let origin = CGRect(x: screen.frame.midX - 120, y: screen.frame.midY - 40, width: 240, height: 80)
        controller.show(.recognizing, displayID: number.uint32Value, origin: origin, onStop: {})
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduced {
            #expect(controller.flight == nil)
            #expect(controller.panel?.isVisible == true)
            return
        }
        #expect(controller.flight?.isVisible == true)
        #expect(controller.panel?.isVisible == false, "The control opens only when the frame has landed.")
        #expect(sounds.cues.isEmpty)
        controller.show(.preparing, displayID: number.uint32Value, onStop: {})
        #expect(controller.state == .preparing)
        try await Task.sleep(for: .milliseconds(SelectionFlightWindow.durationMilliseconds + 120))
        #expect(controller.flight == nil)
        #expect(controller.panel?.isVisible == true)
        #expect(sounds.cues == [.selection], "The opening cue is synchronised with the landing.")
        controller.hide()
        controller.show(.recognizing, displayID: number.uint32Value, origin: origin, onStop: {})
        let flight = controller.flight
        #expect(flight?.isVisible == true)
        controller.hide()
        #expect(controller.flight == nil)
        #expect(flight?.isVisible != true)
        try await Task.sleep(for: .milliseconds(SelectionFlightWindow.durationMilliseconds + 60))
        #expect(controller.panel?.isVisible != true)
        #expect(sounds.cues == [.selection], "A cancelled flight never lands or plays.")
    }
    /// Opt-in design review: `OSR_PANEL_PREVIEW_DIR=/path` (pass it to xcodebuild as
    /// `TEST_RUNNER_OSR_PANEL_PREVIEW_DIR`) writes the cue WAVs and on-screen captures
    /// of the opening sequence and every reading-control state into that directory.
    @Test
    func exportReadingControlPreview() async throws {
        guard let path = ProcessInfo.processInfo.environment["OSR_PANEL_PREVIEW_DIR"] else { return }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for cue in InterfaceCue.allCases {
            for variant in 0..<cue.variantCount {
                try cue.wavData(variant: variant).write(to: directory.appendingPathComponent("cue-\(cue)\(variant == 0 ? "" : "-b").wav"))
            }
        }
        let screen = try #require(NSScreen.screens.first)
        let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        let controller = ReadingPanelController(terminalDuration: .seconds(30))
        defer { controller.hide() }
        func capture(_ name: String) throws {
            let panel = try #require(controller.panel)
            let frame = panel.frame
            let primary = NSScreen.screens[0].frame
            let rect = CGRect(x: frame.minX - 40, y: primary.maxY - frame.maxY - 40, width: frame.width + 80, height: frame.height + 80)
            var image = CGWindowListCreateImage(rect, [.optionOnScreenOnly], kCGNullWindowID, [.bestResolution])
            if image == nil, let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                image = rep.cgImage
            }
            let captured = try #require(image)
            let png = try #require(NSBitmapImageRep(cgImage: captured).representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        let display = number.uint32Value
        let origin = CGRect(x: screen.frame.midX - 160, y: screen.frame.midY + 40, width: 320, height: 90)
        controller.show(.recognizing, displayID: display, origin: origin, onStop: {})
        for (index, delay) in [120, 140, 140, 160, 120, 100, 120, 400].enumerated() {
            try await Task.sleep(for: .milliseconds(delay))
            try capture("0-opening-\(index)")
        }
        try capture("1-recognizing")
        controller.show(.preparing, displayID: display, onStop: {})
        try await Task.sleep(for: .milliseconds(600))
        try capture("2-preparing")
        controller.show(.speaking, displayID: display, onStop: {})
        for (index, level) in [0.12, 0.45, 0.9].enumerated() {
            for _ in 0..<12 { controller.updateLevel(level); try await Task.sleep(for: .milliseconds(33)) }
            try capture("3-speaking-\(index)")
        }
        controller.show(.finished, displayID: display, onStop: nil)
        try await Task.sleep(for: .milliseconds(180))
        try capture("4-finished-drawing")
        try await Task.sleep(for: .milliseconds(500))
        try capture("4-finished")
        controller.dismiss()
        try await Task.sleep(for: .milliseconds(110))
        try capture("4-finished-closing")
        try await Task.sleep(for: .milliseconds(300))
        for (name, state) in [("5-stopped", ReadingPanelState.stopped), ("6-notext", .noText), ("7-failed", .failed)] {
            controller.hide()
            controller.show(.speaking, displayID: display, onStop: {})
            try await Task.sleep(for: .milliseconds(500))
            controller.show(state, displayID: display, onStop: nil)
            try await Task.sleep(for: .milliseconds(700))
            try capture(name)
        }
    }

    @Test
    func panelFitsSelectedDisplaysIncludingNegativeOriginsAndSmallFrames() {
        for visible in [CGRect(x: -1440, y: 124, width: 1440, height: 850),
                        CGRect(x: 120, y: -900, width: 1920, height: 860),
                        CGRect(x: 0, y: 0, width: 200, height: 50)] {
            let frame = ReadingPanelController.frame(in: visible)
            #expect(visible.contains(frame))
            #expect(frame.midX == visible.midX)
            #expect(frame.minY >= visible.minY)
        }
    }

    @Test
    func terminalDismissalCannotHideNewWorkAndPanelNeverBecomesKey() async throws {
        let screen = try #require(NSScreen.screens.first)
        let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        let controller = ReadingPanelController(terminalDuration: .milliseconds(50))
        defer { controller.hide() }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        controller.show(.stopped, displayID: number.uint32Value, onStop: nil)
        let panel = try #require(controller.panel)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.hidesOnDeactivate)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost)
        controller.show(.preparing, displayID: number.uint32Value, onStop: {})
        try await Task.sleep(for: .milliseconds(120))
        #expect(controller.state == .preparing)
        #expect(panel.isVisible)
        controller.show(.finished, displayID: number.uint32Value, onStop: nil)
        try await Task.sleep(for: .milliseconds(350))
        #expect(controller.state == nil)
        #expect(!panel.isVisible)
        controller.show(.noText, displayID: number.uint32Value, onStop: nil)
        try await Task.sleep(for: .milliseconds(120))
        #expect(controller.state == .noText)
        controller.hide()
        #expect(panel.contentView == nil)
        controller.show(.speaking, displayID: UInt32.max, onStop: {})
        #expect(controller.state == nil)
        #expect(!panel.isVisible)
    }
}

@MainActor
private final class ReadingPanelFake: ReadingStatusPresenting {
    var level: Double = 0
    func updateLevel(_ level: Double) { self.level = level }
    var state: ReadingPanelState?
    var displayID: UInt32?
    var origin: CGRect?
    var onStop: (() -> Void)?
    func show(_ state: ReadingPanelState, displayID: UInt32, origin: CGRect?, onStop: (() -> Void)?) {
        self.origin = origin
        self.state = state
        self.displayID = displayID
        self.onStop = onStop
    }
    func hide() { state = nil; onStop = nil }
}

@MainActor
private final class InterfaceSoundsFake: InterfaceSoundPlaying {
    var cues: [InterfaceCue] = []
    var isStopped = true
    func play(_ cue: InterfaceCue) { cues.append(cue); if cue != .tap && cue != .release { isStopped = false } }
    func stop() { isStopped = true }
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
    var playbackRate: Double = 1
    var playbackLevel: Double { 0.65 }
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
private final class QueueSpeechFake: SpeechReading {
    var isPaused = false
    func setPaused(_ paused: Bool) { isPaused = paused }
    var playbackRate = 1.0
    var preparedText: String?
    func prepareNext(_ text: String?) { preparedText = text }
    var texts: [String] = []
    private var completions: [CheckedContinuation<Void, Error>] = []
    func read(_ text: String, onPlayback: @escaping @MainActor () -> Void) async throws {
        texts.append(text)
        onPlayback()
        try await withCheckedThrowingContinuation { completions.append($0) }
    }
    func finishFirst() { if !completions.isEmpty { completions.removeFirst().resume() } }
    func stop() {
        preparedText = nil
        stopCurrent()
    }
    func stopCurrent() {
        let pending = completions
        completions.removeAll()
        for completion in pending { completion.resume(throwing: CancellationError()) }
    }
    func waitForReads(_ count: Int) async throws {
        for _ in 0..<500 {
            if texts.count >= count { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(texts.count >= count)
    }
}

@MainActor
private struct QueueFixture {
    let hotkey = HotkeyManagerFake(registrationResult: .registered)
    let selection = RegionSelectionControllerFake()
    let capture = CaptureFake()
    let ocr = OCRFake()
    let speech = QueueSpeechFake()
    let escape = EscapeFake()
    let model: AppModel
    init(operationTimeout: Duration = .seconds(15)) {
        model = AppModel(shortcutStore: MemoryShortcutStore(),
            hotkeyManager: hotkey,
            selectionController: selection, captureService: capture, escapeMonitor: escape,
            ocrService: ocr, speechService: speech, operationTimeout: operationTimeout)
    }
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
