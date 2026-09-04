import CoreGraphics
import Foundation
import Vision

struct OCRResult: Equatable, Sendable {
    let lines: [String]

    init(lines: [String]) {
        self.lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var text: String { lines.joined(separator: "\n") }
    var lineCount: Int { lines.count }
    var characterCount: Int { text.count }
}

enum OCRFailure: Error, Equatable, LocalizedError {
    case unsupportedLanguages
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguages:
            "Local German and English text recognition is unavailable on this Mac."
        case .recognitionFailed:
            "Text could not be recognized. Select a clearer or larger text region and try again."
        }
    }
}

@MainActor
protocol TextRecognizing: AnyObject {
    func recognize(_ image: CGImage) async throws -> OCRResult
}

@MainActor
final class VisionOCRService: TextRecognizing {
    // Vision's synchronous perform must not block hotkey, Escape, or UI processing.
    // Serial execution also limits concurrent OCR memory use during rapid restarts.
    private nonisolated static let queue = DispatchQueue(
        label: "OpenScreenReader.local-ocr", qos: .userInitiated
    )

    func recognize(_ image: CGImage) async throws -> OCRResult {
        let cancellation = OCRRequestCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let result: OCRResult = try await withCheckedThrowingContinuation { continuation in
                Self.queue.async {
                    let result = Result { try Self.perform(image, cancellation: cancellation) }
                    continuation.resume(with: result)
                }
            }
            try Task.checkCancellation()
            return result
        } onCancel: {
            cancellation.cancel()
        }
    }

    nonisolated static func makeRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["de-DE", "en-US"]
        // Do not silently autocorrect identifiers, amounts, or mixed-language text.
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = false
        return request
    }

    private nonisolated static func perform(
        _ image: CGImage, cancellation: OCRRequestCancellation
    ) throws -> OCRResult {
        try autoreleasepool {
            try cancellation.checkCancellation()
            let request = makeRequest()
            try cancellation.install(request)
            defer { cancellation.clearRequest() }
            do {
                let supported = try request.supportedRecognitionLanguages()
                guard request.recognitionLanguages.allSatisfy(supported.contains) else {
                    throw OCRFailure.unsupportedLanguages
                }
                try cancellation.checkCancellation()
                try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
                try cancellation.checkCancellation()
                // Preserve Vision's observation order; no speculative column reordering
                // or dehyphenation. Complex layouts still need a dedicated reading-order spike.
                return OCRResult(lines: (request.results ?? []).compactMap {
                    $0.topCandidates(1).first?.string
                })
            } catch {
                try cancellation.checkCancellation()
                if let failure = error as? OCRFailure { throw failure }
                // Never surface Vision's diagnostic payload or recognized text in errors.
                throw OCRFailure.recognitionFailed
            }
        }
    }
}

// The lock protects cancellation state and the request reference. Only the worker
// configures/performs/reads the request; the cancellation handler may call cancel().
final class OCRRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var request: VNRequest?

    func install(_ request: VNRequest) throws {
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            self.request = request
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            request?.cancel()
        }
    }

    func checkCancellation() throws {
        try lock.withLock {
            if cancelled { throw CancellationError() }
        }
    }

    func clearRequest() { lock.withLock { request = nil } }
}
