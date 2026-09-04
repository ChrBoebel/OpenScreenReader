import Darwin
import Foundation
import LocalQwen
import MLX
import MLXAudioCore
import MLXLMCommon
import NaturalLanguage

@main
struct SpeechWorker {
    struct Packet: Encodable {
        let kind: String
        var sampleRate: Int? = nil
        var pcm: Data? = nil
    }

    static func main() async {
        // Only structured packets go to the parent. Upstream diagnostics and
        // errors may contain input, so neither stdout nor stderr is a log sink.
        let output = FileHandle(fileDescriptor: dup(STDOUT_FILENO), closeOnDealloc: true)
        let null = open("/dev/null", O_WRONLY)
        guard null >= 0 else { exit(1) }
        dup2(null, STDOUT_FILENO)
        dup2(null, STDERR_FILENO)
        close(null)
        signal(SIGPIPE, SIG_IGN)
        do {
            let arguments = CommandLine.arguments
            guard arguments.count == 3 else { throw WorkerFailure.invalid }
            let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
            if arguments[1] == "--prepare-tokenizer" {
                try Qwen3TTSModel.generateTokenizerJson(
                    vocabPath: directory.appendingPathComponent("vocab.json"),
                    mergesPath: directory.appendingPathComponent("merges.txt"),
                    tokenizerConfigPath: directory.appendingPathComponent("tokenizer_config.json"),
                    outputPath: directory.appendingPathComponent("tokenizer.json"))
                try send(Packet(kind: "prepared"), to: output)
                return
            }
            guard arguments[1] == "--model", let line = readLine(), line.utf8.count <= 64_000 else {
                throw WorkerFailure.invalid
            }
            let request = try JSONDecoder().decode(SpeechWorkerRequest.self, from: Data(line.utf8))
            guard !request.text.isEmpty, request.text.count <= 8_000 else { throw WorkerFailure.invalid }
            let model = try await Qwen3TTSModel.fromModelDirectory(directory)
            if let seed = request.seed { MLXRandom.seed(seed) }
            try send(Packet(kind: "ready", sampleRate: model.sampleRate), to: output)
            for segment in segments(request.text) {
                let languageName = request.resolvedLanguage(for: segment)
                var tokenCount = 0
                for try await event in model.generateStream(
                    text: segment, voice: request.selectedVoice, refAudio: nil, refText: nil, language: languageName,
                    generationParameters: GenerateParameters(maxTokens: 1024, temperature: request.selectedTemperature,
                        topP: 1.0, repetitionPenalty: 1.05), streamingInterval: 0.32
                ) {
                    switch event {
                    case .token:
                        tokenCount += 1
                    case let .audio(chunk):
                        let samples = chunk.asArray(Float.self)
                        guard samples.allSatisfy({ $0.isFinite }) else { throw WorkerFailure.invalid }
                        // At most one PCM packet in flight: parent acknowledges
                        // after accepting it into its bounded playback queue.
                        // Pipes carry content, never argv/files.
                        for offset in stride(from: 0, to: samples.count, by: 24_000) {
                            let part = Array(samples[offset..<min(samples.count, offset + 24_000)])
                            let pcm = part.withUnsafeBytes { Data($0) }
                            try send(Packet(kind: "audio", sampleRate: model.sampleRate, pcm: pcm), to: output)
                            guard readLine() == "next" else { throw WorkerFailure.invalid }
                        }
                    case .info, .progress: break
                    }
                }
                // A safety cap must never masquerade as a complete reading.
                guard tokenCount < 1024 else { throw WorkerFailure.invalid }
            }
            try send(Packet(kind: "end"), to: output)
        } catch {
            try? send(Packet(kind: "error"), to: output)
            exit(1)
        }
    }

    private static func send(_ packet: Packet, to output: FileHandle) throws {
        var data = try JSONEncoder().encode(packet)
        data.append(10)
        try output.write(contentsOf: data)
    }

    private static func segments(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            var remaining = text[range]
            while remaining.count > 350 {
                let prefix = remaining.prefix(350)
                let split = prefix.lastIndex(where: { $0.isWhitespace }) ?? prefix.endIndex
                let end = split == remaining.startIndex ? prefix.endIndex : split
                result.append(String(remaining[..<end]))
                remaining = remaining[end...]
            }
            let tail = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { result.append(tail) }
            return true
        }
        return result
    }

    private enum WorkerFailure: Error { case invalid }
}
