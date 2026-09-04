import AppKit
import Foundation

/// Standalone integration check against the installed Qwen worker and real audio device.
/// Uses only a fixed public sentence and prints counters, never PCM or recognized content.
@main
struct SpeechPlaybackProbe {
    @MainActor
    static func main() async {
        let cancel = CommandLine.arguments.contains("--cancel")
        let long = CommandLine.arguments.contains("--long")
        let service = LocalSpeechService()
        let clipboardRevision = NSPasteboard.general.changeCount
        var timedOut = false
        var stopped = false
        var chunks = 0
        var lateChunks = 0
        var stopMilliseconds: Double?
        let timeout = Task { @MainActor in
            try await Task.sleep(for: .seconds(long ? 90 : 30))
            timedOut = true
            service.stop()
        }
        defer { timeout.cancel(); service.stop() }
        do {
            let text = long
                ? "Dieser längere Test prüft die flüssige Wiedergabe mehrerer Sätze. Während die ersten Wörter gesprochen werden, bereitet das lokale Modell bereits die nächsten Audioblöcke vor. Die Wiedergabe soll nicht nach jedem kleinen Abschnitt anhalten. Auch beim Übergang zum nächsten Satz darf die Warteschlange nicht leer laufen. Trotzdem muss sich das Vorlesen jederzeit sofort abbrechen lassen. Alle Daten bleiben dabei auf diesem Mac."
                : "Hallo Welt. Dies ist ein lokaler Sprachtest."
            try await service.read(text) {
                chunks += 1
                if stopped { lateChunks += 1 }
                if cancel && chunks == 1 {
                    let start = ContinuousClock.now
                    service.stop()
                    let duration = start.duration(to: .now).components
                    stopMilliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
                    stopped = true
                }
            }
            guard !cancel, !timedOut, chunks > 0,
                  NSPasteboard.general.changeCount == clipboardRevision else { exit(1) }
            let diagnostics = service.playbackDiagnostics
            print("Continuity: underruns=\(diagnostics.underruns); missing=\(Double(diagnostics.missingFrames) / 24_000) s; audio=\(Double(diagnostics.frames) / 24_000) s; maximum queued=\(Double(diagnostics.maximumQueuedFrames) / 24_000) s")
            guard diagnostics.underruns == 0,
                  diagnostics.maximumQueuedFrames <= SpeechAudioPlayer.capacityFrames else {
                print("FAIL: playback queue ran dry between audio chunks")
                exit(1)
            }
            print("PASS: real playback completed; chunks=\(chunks); clipboard unchanged")
        } catch is CancellationError {
            guard cancel, stopped, !timedOut, chunks > 0, lateChunks == 0,
                  NSPasteboard.general.changeCount == clipboardRevision else {
                print("FAIL: unexpected cancellation; timeout=\(timedOut); chunks=\(chunks)")
                exit(1)
            }
            print("PASS: real playback cancelled; late chunks=0; synchronous stop=\(stopMilliseconds ?? -1) ms; clipboard unchanged")
        } catch {
            print("FAIL: local playback check; no content diagnostics exported")
            exit(1)
        }
    }
}
