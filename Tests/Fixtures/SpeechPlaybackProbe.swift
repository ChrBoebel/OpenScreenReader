import AppKit
import Foundation

/// Standalone integration check against the installed default worker and real audio device.
/// Uses only a fixed public sentence and prints counters, never PCM or recognized content.
@main
struct SpeechPlaybackProbe {
    @MainActor
    static func main() async {
        if CommandLine.arguments.contains("--prefetch") {
            await measurePrefetch()
            return
        }
        if CommandLine.arguments.contains("--measure-speed") {
            await measureSpeeds()
            return
        }
        let cancel = CommandLine.arguments.contains("--cancel")
        let cancelLoading = CommandLine.arguments.contains("--cancel-loading")
        let long = CommandLine.arguments.contains("--long")
        let bundleRoot = CommandLine.arguments.first { $0.hasPrefix("--bundled-root=") }
            .map { URL(fileURLWithPath: String($0.dropFirst("--bundled-root=".count))) }
        let service = LocalSpeechService(configuration: bundleRoot.map { .init(root: $0, bundled: true) } ?? LocalSpeechService.installedConfiguration)
        let speed = CommandLine.arguments.first { $0.hasPrefix("--speed=") }
            .flatMap { Double($0.dropFirst("--speed=".count)) } ?? 1
        service.playbackRate = speed
        let changeSpeed = CommandLine.arguments.contains("--change-speed")
        let pausePlayback = CommandLine.arguments.contains("--pause")
        var pauseTask: Task<Void, Never>?
        var resumed = false
        let rate = Double(SpeechRuntimeConfiguration(root: LocalSpeechService.developmentRoot).sampleRate)
        let clipboardRevision = NSPasteboard.general.changeCount
        var timedOut = false
        var stopped = false
        var chunks = 0
        var lateChunks = 0
        var stopMilliseconds: Double?
        let loadingCancellation = Task { @MainActor in
            guard cancelLoading else { return }
            try await Task.sleep(for: .milliseconds(100))
            let start = ContinuousClock.now
            service.stop()
            let duration = start.duration(to: .now).components
            stopMilliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
            stopped = true
        }
        let timeout = Task { @MainActor in
            try await Task.sleep(for: .seconds(long ? 90 : 30))
            timedOut = true
            service.stop()
        }
        defer { timeout.cancel(); loadingCancellation.cancel(); pauseTask?.cancel(); service.stop() }
        do {
            let text = long
                ? "Dieser längere Test prüft die flüssige Wiedergabe mehrerer Sätze. Während die ersten Wörter gesprochen werden, bereitet das lokale Modell bereits die nächsten Audioblöcke vor. Die Wiedergabe soll nicht nach jedem kleinen Abschnitt anhalten. Auch beim Übergang zum nächsten Satz darf die Warteschlange nicht leer laufen. Trotzdem muss sich das Vorlesen jederzeit sofort abbrechen lassen. Alle Daten bleiben dabei auf diesem Mac."
                : "Hallo Welt. Dies ist ein lokaler Sprachtest."
            try await service.read(text) {
                chunks += 1
                if pausePlayback && chunks == 1 {
                    service.setPaused(true)
                    pauseTask = Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(3)) } catch { return }
                        guard service.playbackLevel == 0 else { print("FAIL: paused playback level"); exit(1) }
                        service.setPaused(false)
                        resumed = true
                    }
                }
                if changeSpeed && chunks == 2 { service.playbackRate = 2 }
                if stopped { lateChunks += 1 }
                if cancel && chunks == 1 {
                    let start = ContinuousClock.now
                    service.stop()
                    let duration = start.duration(to: .now).components
                    stopMilliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
                    stopped = true
                }
            }
            guard !cancel, !cancelLoading, !timedOut, chunks > 0,
                  NSPasteboard.general.changeCount == clipboardRevision else { exit(1) }
            let diagnostics = service.playbackDiagnostics
            if pausePlayback && !resumed { print("FAIL: pause did not hold reading"); exit(1) }
            print("Continuity: underruns=\(diagnostics.underruns); missing=\(Double(diagnostics.missingFrames) / rate) s; audio=\(Double(diagnostics.frames) / rate) s; maximum queued=\(Double(diagnostics.maximumQueuedFrames) / rate) s")
            guard diagnostics.underruns == 0,
                  diagnostics.maximumQueuedFrames <= Int(rate * 8) else {
                print("FAIL: playback queue ran dry between audio chunks")
                exit(1)
            }
            print("PASS: real playback completed; chunks=\(chunks); speed=\(service.playbackRate); changed live=\(changeSpeed); clipboard unchanged")
        } catch is CancellationError {
            guard (cancel || cancelLoading), stopped, !timedOut,
                  (cancelLoading ? chunks == 0 : chunks > 0), lateChunks == 0,
                  NSPasteboard.general.changeCount == clipboardRevision else {
                print("FAIL: unexpected cancellation; timeout=\(timedOut); chunks=\(chunks)")
                exit(1)
            }
            print("PASS: real \(cancelLoading ? "model loading" : "playback") cancelled; late chunks=0; synchronous stop=\(stopMilliseconds ?? -1) ms; clipboard unchanged")
        } catch {
            print("FAIL: local playback check; no content diagnostics exported")
            exit(1)
        }
    }

    @MainActor
    static func measurePrefetch() async {
        let service = LocalSpeechService()
        service.playbackRate = CommandLine.arguments.contains("--speed=2") ? 2 : 1
        let clipboard = NSPasteboard.general.changeCount
        let cancelPrepared = CommandLine.arguments.contains("--cancel-prepared")
        let skipPrepared = CommandLine.arguments.contains("--skip-prepared")
        let latePrefetch = CommandLine.arguments.contains("--late-prefetch")
        var expired = false
        let timeout = Task { @MainActor in
            try await Task.sleep(for: .seconds(90))
            expired = true
            service.stop()
        }
        defer { timeout.cancel(); service.stop() }
        let first = "Dieser längere Test prüft die flüssige Wiedergabe mehrerer Sätze. Während die ersten Wörter gesprochen werden, bereitet das lokale Modell bereits die nächsten Audioblöcke vor. Die Wiedergabe soll nicht nach jedem kleinen Abschnitt anhalten. Auch beim Übergang zum nächsten Satz darf die Warteschlange nicht leer laufen. Trotzdem muss sich das Vorlesen jederzeit sofort abbrechen lassen. Alle Daten bleiben dabei auf diesem Mac."
        let second = CommandLine.arguments.contains("--long-next") ? first
            : "Dies ist der vorbereitete nächste Text. Die Stimme liest ohne erneutes Laden des Modells weiter."
        var requested = false
        var observedPrefetch = false
        let cancellation = Task { @MainActor in
            while !Task.isCancelled {
                if service.preparedAudioBytes > 0 {
                    observedPrefetch = true
                    if cancelPrepared { service.stop() }
                    else if skipPrepared { service.stopCurrent() }
                    return
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        defer { cancellation.cancel() }
        do {
            do {
                try await service.read(first) {
                    if !requested {
                        requested = true
                        if !latePrefetch { service.prepareNext(second) }
                    }
                }
            } catch is CancellationError {
                guard skipPrepared, observedPrefetch, !expired else { throw CancellationError() }
            }
            if latePrefetch { service.prepareNext(second) }
            let pid = service.workerPID
            let bytes = service.preparedAudioBytes
            guard (latePrefetch || (observedPrefetch && bytes > 0)), bytes <= 44_100 * 8 * 4,
                  service.playbackDiagnostics.underruns == 0 else {
                print("FAIL: next text not prepared or current playback underrun"); exit(1)
            }
            // Match the app's between-item cleanup; it must retain the successor.
            service.stopCurrent()
            let handoff = ContinuousClock.now
            var firstPlayback: Duration?
            try await service.read(second) {
                if firstPlayback == nil { firstPlayback = handoff.duration(to: .now) }
            }
            guard let latency = firstPlayback, latency < (latePrefetch ? .seconds(10) : .milliseconds(500)),
                  service.workerLaunchCount == 1, service.workerPID == pid,
                  !expired, NSPasteboard.general.changeCount == clipboard,
                  service.playbackDiagnostics.underruns == 0 else {
                print("FAIL: warm handoff, continuity, or privacy check"); exit(1)
            }
            print("PASS: prepared bytes=\(bytes); handoff to player start=\(latency); launches=1; both texts underruns=0; skipped=\(skipPrepared); late=\(latePrefetch); clipboard unchanged")
            service.stop()
            guard service.preparedAudioBytes == 0, service.workerPID == nil else { exit(1) }
        } catch is CancellationError {
            guard cancelPrepared, observedPrefetch, !expired, service.preparedAudioBytes == 0,
                  service.workerPID == nil, NSPasteboard.general.changeCount == clipboard else { exit(1) }
            print("PASS: stop while successor had prepared audio cleared buffers and worker; clipboard unchanged")
        } catch { print("FAIL: prefetch integration"); exit(1) }
    }

    /// Isolated process: unrelated MainActor UI tests must not distort wall-clock playback measurements.
    @MainActor
    private static func measureSpeeds() async {
        do {
            for speed in [0.75, 1.0, 1.5, 2.0] {
                let player = SpeechAudioPlayer(sampleRate: 44_100)
                defer { player.stop() }
                player.playbackRate = speed
                let halfSecond = Data(repeating: 0, count: 22_050 * 4)
                try await player.enqueue(halfSecond) {}
                var started = ContinuousClock.now
                try await player.enqueue(halfSecond) { started = .now }
                try await player.finish {}
                let elapsed = started.duration(to: .now).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                print("Speed \(speed)×: 1 second of PCM played in \(seconds)s; pitch=\(player.pitchCents) cents")
                guard abs(seconds - 1 / speed) < 0.3, player.pitchCents == 0, player.queuedFrames == 0 else { exit(1) }
            }
            print("PASS: all four real-output speed durations within 300 ms; pitch parameter unchanged")
        } catch {
            print("FAIL: playback duration measurement")
            exit(1)
        }
    }
}
