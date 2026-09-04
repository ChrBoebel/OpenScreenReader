import AVFoundation
import Darwin
import Foundation

@MainActor
protocol SpeechReading: AnyObject {
    /// Returns only after the last audio buffer has played.
    func read(_ text: String, onPlayback: @escaping @MainActor () -> Void) async throws
    /// Must silence playback immediately, without awaiting synthesis.
    func stop()
}

enum SpeechFailure: Error, LocalizedError {
    case notInstalled, tooLong, failed
    var errorDescription: String? {
        switch self {
        case .notInstalled: "The local Qwen development runtime is not installed. No text was sent to a server."
        case .tooLong: "This development version reads up to 8,000 characters. Select a smaller region."
        case .failed: "Local speech could not finish. Please try a smaller region. No cloud or system voice was substituted."
        }
    }
}

@MainActor
final class LocalSpeechService: SpeechReading {
    private struct Packet: Decodable {
        let kind: String
        let sampleRate: Int?
        let pcm: Data?
    }
    private struct Request: Encodable { let text: String }
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var playbackContinuation: CheckedContinuation<Void, Error>?
    private var generation: UInt64 = 0

    static var developmentRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenScreenReader")
    }

    static var installationSummary: String {
        let executable = developmentRoot.appendingPathComponent("DevelopmentRuntime/OpenScreenReaderSpeechWorker")
        let tokenizer = developmentRoot.appendingPathComponent("DevelopmentModels/qwen3-tts-0.6b-customvoice-4bit-08c72cad/tokenizer.json")
        return FileManager.default.isExecutableFile(atPath: executable.path)
            && FileManager.default.fileExists(atPath: tokenizer.path)
            ? "Installed for local development" : "Not installed"
    }

    init() { engine.attach(player) }
    isolated deinit { stop() }

    func read(_ text: String, onPlayback: @escaping @MainActor () -> Void) async throws {
        guard text.count <= 8_000, text.utf8.count <= 48_000 else { throw SpeechFailure.tooLong }
        stop()
        let current = generation
        try await withTaskCancellationHandler {
            try await run(text, generation: current, onPlayback: onPlayback)
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                self.stop()
            }
        }
    }

    private func run(_ text: String, generation current: UInt64,
                     onPlayback: @escaping @MainActor () -> Void) async throws {
        // Development staging is explicit. Release packaging remains a gate;
        // no Hub/model downloader or shell is invoked by the application.
        let executable = Self.developmentRoot.appendingPathComponent("DevelopmentRuntime/OpenScreenReaderSpeechWorker")
        let model = Self.developmentRoot.appendingPathComponent("DevelopmentModels/qwen3-tts-0.6b-customvoice-4bit-08c72cad")
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.fileExists(atPath: model.appendingPathComponent("tokenizer.json").path) else {
            throw SpeechFailure.notInstalled
        }
        let worker = Process()
        // Extra defence for this experimental external worker, not a substitute
        // for the release App Sandbox/signing and clean-machine privacy gate.
        worker.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        worker.arguments = ["-p", "(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (literal \"/dev/null\"))",
                            executable.path, "--model", model.path]
        worker.environment = ["PATH": "/usr/bin:/bin", "HF_HUB_OFFLINE": "1", "HF_HUB_DISABLE_TELEMETRY": "1"]
        worker.currentDirectoryURL = executable.deletingLastPathComponent()
        let requestPipe = Pipe()
        let audioPipe = Pipe()
        worker.standardInput = requestPipe
        worker.standardOutput = audioPipe
        worker.standardError = FileHandle.nullDevice
        process = worker
        input = requestPipe.fileHandleForWriting
        output = audioPipe.fileHandleForReading
        do {
            try Task.checkCancellation()
            try worker.run()
            try requestPipe.fileHandleForReading.close()
            try audioPipe.fileHandleForWriting.close()
            var request = try JSONEncoder().encode(Request(text: text))
            request.append(10)
            // The request is bounded, but can exceed pipe capacity. Write away
            // from the main actor so Escape is never queued behind a pipe write.
            let writer = requestPipe.fileHandleForWriting
            guard fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { throw SpeechFailure.failed }
            try await Task.detached { try writer.write(contentsOf: request) }.value
            var line = Data()
            var receivedAudio = false
            var ready = false
            for try await byte in audioPipe.fileHandleForReading.bytes {
                try Task.checkCancellation()
                guard generation == current else { throw CancellationError() }
                if byte != 10 {
                    guard line.count < 140_000 else { throw SpeechFailure.failed }
                    line.append(byte)
                    continue
                }
                let packet = try JSONDecoder().decode(Packet.self, from: line)
                line.removeAll(keepingCapacity: true)
                switch packet.kind {
                case "ready":
                    guard !ready, packet.sampleRate == 24_000 else { throw SpeechFailure.failed }
                    ready = true
                case "audio":
                    guard ready, packet.sampleRate == 24_000, let data = packet.pcm,
                          !data.isEmpty, data.count <= 96_000, data.count % 4 == 0 else {
                        throw SpeechFailure.failed
                    }
                    try await play(data, onPlayback: onPlayback)
                    try Task.checkCancellation()
                    guard generation == current else { throw CancellationError() }
                    receivedAudio = true
                    try writer.write(contentsOf: Data("next\n".utf8))
                case "end":
                    guard ready, receivedAudio else { throw SpeechFailure.failed }
                    stop()
                    return
                default: throw SpeechFailure.failed
                }
            }
            throw SpeechFailure.failed
        } catch {
            if generation == current { stop() }
            if error is CancellationError { throw CancellationError() }
            throw SpeechFailure.failed
        }
    }

    private func play(_ data: Data, onPlayback: @escaping @MainActor () -> Void) async throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count / 4)),
              let samples = buffer.floatChannelData?[0] else { throw SpeechFailure.failed }
        buffer.frameLength = buffer.frameCapacity
        try data.withUnsafeBytes { bytes in
            for index in 0..<Int(buffer.frameLength) {
                let value = Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)))
                guard value.isFinite else { throw SpeechFailure.failed }
                samples[index] = min(1, max(-1, value))
            }
        }
        if !engine.isRunning {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            player.play()
        }
        let current = generation
        try await withCheckedThrowingContinuation { continuation in
            playbackContinuation = continuation
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    let completion = self.playbackContinuation
                    self.playbackContinuation = nil
                    completion?.resume()
                }
            }
            onPlayback()
        }
    }

    func stop() {
        generation &+= 1
        player.stop()
        engine.stop()
        let completion = playbackContinuation
        playbackContinuation = nil
        completion?.resume(throwing: CancellationError())
        // One disposable worker per operation: hard termination is deliberate
        // until a warm-worker acknowledgement protocol has been validated.
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process = nil
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
    }
}
