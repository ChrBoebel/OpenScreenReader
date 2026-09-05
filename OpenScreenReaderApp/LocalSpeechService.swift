import AVFoundation
import Darwin
import Foundation
import NaturalLanguage

/// Explicit local development installation, never a downloader or fallback.
struct SpeechRuntimeConfiguration: Sendable {
    let root: URL
    let sampleRate = 44_100
    let modelName = "Supertonic 3 · M1"
    var runtime: URL { root.appendingPathComponent("SupertonicRuntime") }
    var executable: URL { runtime.appendingPathComponent("venv/bin/python3") }
    var script: URL { runtime.appendingPathComponent("worker.py") }
    var model: URL { root.appendingPathComponent("DevelopmentModels/supertonic-3-3cadd1ee") }
    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: executable.path)
            && [script, runtime.appendingPathComponent("installation-receipt.json"),
                runtime.appendingPathComponent("model-manifest.json"),
                runtime.appendingPathComponent("upstream/helper.py"),
                model.appendingPathComponent("onnx/vocoder.onnx")]
                .allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func language(for text: String) -> String {
        // German/English MVP: ambiguous short text uses the product's German default.
        NLLanguageRecognizer.dominantLanguage(for: text) == .english ? "en" : "de"
    }
}

@MainActor
protocol SpeechReading: AnyObject {
    /// Ephemeral normalized level at the playback clock, never queued-ahead PCM.
    var playbackLevel: Double { get }
    /// Returns only after the last audio buffer has played.
    func read(_ text: String, onPlayback: @escaping @MainActor () -> Void) async throws
    /// Must silence playback immediately, without awaiting synthesis.
    func stop()
}

extension SpeechReading { var playbackLevel: Double { 0 } }

enum SpeechFailure: Error, LocalizedError {
    case notInstalled, tooLong, failed
    var errorDescription: String? {
        switch self {
        case .notInstalled: "The local Supertonic development runtime is not installed. No text was sent to a server."
        case .tooLong: "This development version reads up to 8,000 characters. Select a smaller region."
        case .failed: "Local speech could not finish. Please try a smaller region. No cloud or system voice was substituted."
        }
    }
}

@MainActor
final class LocalSpeechService: SpeechReading {
    private let configuration: SpeechRuntimeConfiguration
    private let playback: SpeechAudioPlayer
    var playbackDiagnostics: SpeechAudioPlayer.Diagnostics { playback.diagnostics }
    var playbackLevel: Double { playback.playbackLevel }
    private struct Packet: Decodable {
        let kind: String
        let sampleRate: Int?
        let pcm: Data?
    }
    private struct Request: Encodable { let text: String; let language: String }
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var generation: UInt64 = 0

    static var developmentRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenScreenReader")
    }

    static var installationSummary: String {
        SpeechRuntimeConfiguration(root: developmentRoot).isInstalled
            ? "Installed for local development" : "Not installed"
    }

    init(configuration: SpeechRuntimeConfiguration = .init(root: LocalSpeechService.developmentRoot)) {
        self.configuration = configuration
        playback = SpeechAudioPlayer(sampleRate: configuration.sampleRate)
    }

    isolated deinit { stop() }

    func read(_ text: String, onPlayback: @escaping @MainActor () -> Void) async throws {
        guard text.count <= 8_000, text.utf8.count <= 48_000 else { throw SpeechFailure.tooLong }
        stop()
        playback.reset()
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
        let executable = configuration.executable
        guard configuration.isInstalled else { throw SpeechFailure.notInstalled }
        let worker = Process()
        // Extra defence for this experimental external worker, not a substitute
        // for the release App Sandbox/signing and clean-machine privacy gate.
        worker.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        worker.arguments = ["-p", "(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (literal \"/dev/null\"))",
                            executable.path, "-I", "-B", configuration.script.path, "--model", configuration.model.path]
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
            var request = try JSONEncoder().encode(Request(text: text, language: SpeechRuntimeConfiguration.language(for: text)))
            request.append(10)
            // The request is bounded, but can exceed pipe capacity. Write away
            // from the main actor so Escape is never queued behind a pipe write.
            let writer = requestPipe.fileHandleForWriting
            guard fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { throw SpeechFailure.failed }
            try await Task.detached { try writer.write(contentsOf: request) }.value
            let reader = SpeechPacketReader(handle: audioPipe.fileHandleForReading)
            var receivedAudio = false
            var ready = false
            while let line = try await reader.nextLine() {
                try Task.checkCancellation()
                guard generation == current else { throw CancellationError() }
                let packet = try JSONDecoder().decode(Packet.self, from: line)
                switch packet.kind {
                case "ready":
                    guard !ready, packet.sampleRate == configuration.sampleRate else { throw SpeechFailure.failed }
                    ready = true
                case "audio":
                    guard ready, packet.sampleRate == configuration.sampleRate, let data = packet.pcm,
                          !data.isEmpty, data.count <= 96_000, data.count % 4 == 0 else {
                        throw SpeechFailure.failed
                    }
                    try await playback.enqueue(data, onPlayback: onPlayback)
                    try Task.checkCancellation()
                    guard generation == current else { throw CancellationError() }
                    receivedAudio = true
                    try writer.write(contentsOf: Data("next\n".utf8))
                case "end":
                    guard ready, receivedAudio else { throw SpeechFailure.failed }
                    try await playback.finish(onPlayback: onPlayback)
                    try Task.checkCancellation()
                    guard generation == current else { throw CancellationError() }
                    stop()
                    return
                default: throw SpeechFailure.failed
                }
            }
            throw SpeechFailure.failed
        } catch {
            let cancelled = generation != current || error is CancellationError || Task.isCancelled
            if generation == current { stop() }
            if cancelled { throw CancellationError() }
            throw SpeechFailure.failed
        }
    }

    func stop() {
        generation &+= 1
        playback.stop()
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

/// Framing runs away from the main actor, in bounded blocks rather than an
/// actor hop for every byte of base64 audio. Killing the owned worker unblocks
/// a pending pipe read. Only one consumer calls nextLine at a time.
actor SpeechPacketReader {
    private let handle: FileHandle
    private var pending = Data()
    init(handle: FileHandle) { self.handle = handle }

    func nextLine() throws -> Data? {
        while true {
            if let newline = pending.firstIndex(of: 10) {
                guard pending.distance(from: pending.startIndex, to: newline) <= 140_000 else {
                    throw SpeechFailure.failed
                }
                let line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                return line
            }
            guard pending.count <= 140_000 else { throw SpeechFailure.failed }
            // FileHandle.read(upToCount:) may try to fill the requested length.
            // A short ready packet must return immediately: the peer can be
            // waiting for our acknowledgement before producing more bytes.
            var block = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(handle.fileDescriptor, &block, block.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw SpeechFailure.failed }
            guard count > 0 else {
                guard pending.isEmpty else { throw SpeechFailure.failed }
                return nil
            }
            pending.append(contentsOf: block.prefix(count))
        }
    }
}

/// Twenty-millisecond scalar windows. No PCM is retained by this envelope.
struct PlaybackEnvelope {
    private struct Window { let start: Int64; let end: Int64; let level: Double }
    private var windows: [Window] = []
    var count: Int { windows.count }

    mutating func append(_ samples: UnsafeBufferPointer<Float>, startingAt start: Int64, sampleRate: Int) {
        let hop = max(1, sampleRate / 50)
        for offset in stride(from: 0, to: samples.count, by: hop) {
            let end = min(samples.count, offset + hop)
            var energy = 0.0
            for index in offset..<end { energy += Double(samples[index]) * Double(samples[index]) }
            let rms = sqrt(energy / Double(end - offset))
            let level = rms < 0.002 ? 0 : min(1, sqrt(rms) * 1.8)
            windows.append(Window(start: start + Int64(offset), end: start + Int64(end), level: level))
        }
    }
    mutating func level(at frame: Int64) -> Double {
        windows.removeAll { $0.end <= frame }
        guard let first = windows.first, frame >= first.start else { return 0 }
        return first.level
    }
    mutating func reset() { windows.removeAll(keepingCapacity: false) }
}

/// A bounded look-ahead queue: request the next packet after scheduling, not
/// after playing. A short pre-roll absorbs transport/generation jitter.
@MainActor
final class SpeechAudioPlayer {
    struct Diagnostics {
        var frames = 0
        var underruns = 0
        var missingFrames = 0
        var maximumQueuedFrames = 0
    }
    private(set) var diagnostics = Diagnostics()
    private(set) var queuedFrames = 0
    let sampleRate: Int
    var prebufferFrames: Int { sampleRate }
    var capacityFrames: Int { sampleRate * 4 }
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var scheduledEnd: AVAudioFramePosition = 0
    private var generation: UInt64 = 0
    private var waiter: CheckedContinuation<Void, Error>?
    private var draining = false
    private var envelope = PlaybackEnvelope()
    var playbackLevel: Double {
        guard player.isPlaying,
              let time = player.lastRenderTime.flatMap({ player.playerTime(forNodeTime: $0) }) else { return 0 }
        return envelope.level(at: time.sampleTime)
    }

    init(sampleRate: Int = 24_000) {
        self.sampleRate = sampleRate
        engine.attach(player)
    }
    isolated deinit { stop() }

    func reset() {
        stop()
        diagnostics = Diagnostics()
        scheduledEnd = 0
    }

    func enqueue(_ data: Data, onPlayback: @escaping @MainActor () -> Void) async throws {
        guard !data.isEmpty, data.count <= 96_000, data.count % 4 == 0 else { throw SpeechFailure.failed }
        let current = generation
        let frameCount = data.count / 4
        while queuedFrames + frameCount > capacityFrames {
            try await waitForProgress()
            guard generation == current else { throw CancellationError() }
        }
        try Task.checkCancellation()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
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
        }
        let rendered = player.lastRenderTime.flatMap { player.playerTime(forNodeTime: $0) }?.sampleTime ?? 0
        if scheduledEnd > 0, rendered > scheduledEnd + AVAudioFramePosition(sampleRate / 50) {
            diagnostics.underruns += 1
            diagnostics.missingFrames += Int(rendered - scheduledEnd)
        }
        let startFrame = max(scheduledEnd, rendered)
        _ = envelope.level(at: rendered)
        envelope.append(UnsafeBufferPointer(start: samples, count: frameCount), startingAt: startFrame, sampleRate: sampleRate)
        scheduledEnd = startFrame + AVAudioFramePosition(buffer.frameLength)
        diagnostics.frames += frameCount
        queuedFrames += frameCount
        diagnostics.maximumQueuedFrames = max(diagnostics.maximumQueuedFrames, queuedFrames)
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.queuedFrames -= frameCount
                if !self.draining || self.queuedFrames == 0 {
                    let completion = self.waiter
                    self.waiter = nil
                    completion?.resume()
                }
            }
        }
        if !player.isPlaying, queuedFrames >= prebufferFrames { player.play() }
        if player.isPlaying { onPlayback() }
    }

    func finish(onPlayback: @escaping @MainActor () -> Void) async throws {
        try Task.checkCancellation()
        let current = generation
        if queuedFrames > 0, !player.isPlaying {
            player.play()
            onPlayback()
        }
        guard generation == current else { throw CancellationError() }
        draining = true
        defer { if generation == current { draining = false } }
        if queuedFrames > 0 { try await waitForProgress() }
        guard generation == current else { throw CancellationError() }
    }

    private func waitForProgress() async throws {
        try await withCheckedThrowingContinuation { waiter = $0 }
    }

    func stop() {
        generation &+= 1
        player.stop()
        engine.stop()
        envelope.reset()
        queuedFrames = 0
        draining = false
        let completion = waiter
        waiter = nil
        completion?.resume(throwing: CancellationError())
    }
}
