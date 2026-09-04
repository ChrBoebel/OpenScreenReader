import AppKit
import Foundation

/// Standalone integration check against the installed Qwen worker and real audio device.
/// Uses only a fixed public sentence and prints counters, never PCM or recognized content.
@main
struct SpeechPlaybackProbe {
    @MainActor
    static func main() async {
        let cancel = CommandLine.arguments.contains("--cancel")
        let service = LocalSpeechService()
        let clipboardRevision = NSPasteboard.general.changeCount
        var timedOut = false
        var stopped = false
        var chunks = 0
        var lateChunks = 0
        var stopMilliseconds: Double?
        let timeout = Task { @MainActor in
            try await Task.sleep(for: .seconds(30))
            timedOut = true
            service.stop()
        }
        defer { timeout.cancel(); service.stop() }
        do {
            try await service.read("Hallo Welt. Dies ist ein lokaler Sprachtest.") {
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
            print("PASS: real playback completed; chunks=\(chunks); clipboard unchanged")
        } catch is CancellationError {
            guard cancel, stopped, !timedOut, chunks > 0, lateChunks == 0,
                  NSPasteboard.general.changeCount == clipboardRevision else { exit(1) }
            print("PASS: real playback cancelled; late chunks=0; synchronous stop=\(stopMilliseconds ?? -1) ms; clipboard unchanged")
        } catch {
            print("FAIL: local playback check; no content diagnostics exported")
            exit(1)
        }
    }
}
