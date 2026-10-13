import CoreGraphics
import Foundation
import Vision

/// Repair only explicit soft-hyphen artifacts. Ordinary hyphens, identifiers,
/// punctuation and paragraph breaks are deliberately preserved.
enum SpeechTextNormalizer {
    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00ad}\n", with: "")
            .replacingOccurrences(of: "\u{00ad}", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
    }
}

struct OCRSummary: Equatable, Sendable {
    let characterCount: Int
    let lineCount: Int
}

struct OCRResult: Equatable, Sendable {
    let lines: [String]
    /// Normalized Vision bounding boxes (origin bottom-left), one per line when known.
    let boxes: [CGRect]

    init(lines: [String], boxes: [CGRect] = []) {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let kept = trimmed.indices.filter { !trimmed[$0].isEmpty }
        self.lines = kept.map { trimmed[$0] }
        self.boxes = boxes.count == lines.count ? kept.map { boxes[$0] } : []
    }

    /// The paragraph containing (or right next to) a clicked point, in reading order.
    /// Lines join when they are close vertically, overlap horizontally and have similar
    /// height, or continue the same row. Everything else is discarded. `point` is
    /// normalized like the boxes; `size` gives the area's aspect in points.
    func block(around point: CGPoint, in size: CGSize) -> OCRResult? {
        guard !lines.isEmpty, boxes.count == lines.count, size.width > 0, size.height > 0 else { return nil }
        let rects = boxes.map { CGRect(x: $0.minX * size.width, y: $0.minY * size.height,
                                       width: $0.width * size.width, height: $0.height * size.height) }
        let target = CGPoint(x: point.x * size.width, y: point.y * size.height)
        func distance(_ rect: CGRect) -> CGFloat {
            hypot(max(rect.minX - target.x, 0, target.x - rect.maxX), max(rect.minY - target.y, 0, target.y - rect.maxY))
        }
        guard let hit = rects.indices.min(by: { distance(rects[$0]) < distance(rects[$1]) }),
              distance(rects[hit]) <= rects[hit].height * 1.5 else { return nil }
        func joined(_ a: CGRect, _ b: CGRect) -> Bool {
            let height = min(a.height, b.height)
            let ratio = a.height / b.height
            guard ratio > 0.6, ratio < 1.6 else { return false }
            let verticalGap = max(b.minY - a.maxY, a.minY - b.maxY)
            let horizontalGap = max(b.minX - a.maxX, a.minX - b.maxX)
            if verticalGap < -height * 0.5 { return horizontalGap <= height * 1.5 } // Same row.
            return verticalGap <= height && horizontalGap < 0
        }
        var block: Set<Int> = [hit]
        var frontier = [hit]
        while let current = frontier.popLast() {
            for candidate in rects.indices where !block.contains(candidate) && joined(rects[current], rects[candidate]) {
                block.insert(candidate)
                frontier.append(candidate)
            }
        }
        let ordered = block.sorted { a, b in
            let rowTolerance = min(rects[a].height, rects[b].height) / 2
            if abs(rects[a].midY - rects[b].midY) < rowTolerance { return rects[a].minX < rects[b].minX }
            return rects[a].midY > rects[b].midY
        }
        return OCRResult(lines: ordered.map { lines[$0] }, boxes: ordered.map { boxes[$0] })
    }

    var text: String { lines.joined(separator: "\n") }
    var speechText: String { SpeechTextNormalizer.normalize(text) }
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
                let observations = (request.results ?? []).compactMap { observation in
                    observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
                }
                return OCRResult(lines: observations.map(\.0), boxes: observations.map(\.1))
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
