import AppKit
import CoreText
import Testing
import Vision
@testable import OpenScreenReader

@Suite("Local text recognition")
@MainActor
struct OCRTests {
    @Test
    func speechNormalizationOnlyRepairsUnambiguousArtifacts() {
        #expect(SpeechTextNormalizer.normalize("Stra\u{00ad}\nße\u{00a0}lesen.") == "Straße lesen.")
        #expect(SpeechTextNormalizer.normalize("AB-123\n42,50 €\n04.09.2026\nz. B.\nhttps://example.com") ==
                "AB-123\n42,50 €\n04.09.2026\nz. B.\nhttps://example.com")
        #expect(SpeechTextNormalizer.normalize("Straßen-\nbahn") == "Straßen-\nbahn")
        #expect(SpeechTextNormalizer.normalize("Heading\n\nParagraph") == "Heading\n\nParagraph")
    }
    @Test
    func cancellationBeforeRequestInstallationRejectsWork() {
        let cancellation = OCRRequestCancellation()
        cancellation.cancel()
        #expect(throws: CancellationError.self) { try cancellation.install(VNRequest()) }
        #expect(throws: CancellationError.self) { try cancellation.checkCancellation() }
    }

    @Test
    func cancellationReachesTheInstalledVisionRequest() throws {
        let cancellation = OCRRequestCancellation()
        let request = CancellationProbeRequest()
        try cancellation.install(request)
        cancellation.cancel()
        #expect(request.cancelCount == 1)
        #expect(throws: CancellationError.self) { try cancellation.checkCancellation() }
        cancellation.clearRequest()
        cancellation.cancel()
        #expect(request.cancelCount == 1)
    }

    @Test
    func configurationUsesAccurateGermanAndEnglishWithoutRewriting() {
        let request = VisionOCRService.makeRequest()
        #expect(request.recognitionLevel == .accurate)
        #expect(request.recognitionLanguages == ["de-DE", "en-US"])
        #expect(request.revision == VNRecognizeTextRequestRevision3)
        #expect(!request.usesLanguageCorrection)
    }

    @Test
    func resultPreservesLineBreaksCodesAndHyphens() {
        let result = OCRResult(lines: ["  AB-123  ", "", "Straßen-", "bahn 42,50 €", " \n "])
        #expect(result.text == "AB-123\nStraßen-\nbahn 42,50 €")
        #expect(result.lineCount == 3)
        #expect(result.characterCount == result.text.count)
    }

    @Test
    func blankImageProducesAnEmptyResult() async throws {
        let result = try await VisionOCRService().recognize(makeOCRFixture(lines: []))
        #expect(result.text.isEmpty)
        #expect(result.lineCount == 0)
        #expect(result.characterCount == 0)
    }

    @Test
    func clickedBlockKeepsOnlyItsParagraphInReadingOrder() throws {
        // Normalized boxes in a 1000 × 600 pt area, origin bottom-left as Vision reports them.
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat = 20) -> CGRect {
            CGRect(x: x / 1000, y: y / 600, width: width / 1000, height: height / 600)
        }
        let result = OCRResult(
            lines: ["Heading", "Left one", "Left two", "Left three", "Right one", "Right two",
                    "Second left", "Second left end", "continued"],
            boxes: [box(40, 540, 300, 30), box(40, 470, 400), box(40, 444, 380), box(40, 418, 200),
                    box(560, 470, 400), box(560, 444, 300), box(40, 340, 400), box(40, 314, 180), box(232, 314, 120)])
        let size = CGSize(width: 1000, height: 600)
        let left = try #require(result.block(around: CGPoint(x: 0.1, y: 0.75), in: size))
        #expect(left.lines == ["Left one", "Left two", "Left three"])
        let right = try #require(result.block(around: CGPoint(x: 0.7, y: 0.75), in: size))
        #expect(right.lines == ["Right one", "Right two"])
        let second = try #require(result.block(around: CGPoint(x: 0.25, y: 0.53), in: size))
        #expect(second.lines == ["Second left", "Second left end", "continued"], "Split observations on one row stay in order.")
        #expect(result.block(around: CGPoint(x: 0.5, y: 0.05), in: size) == nil, "Far from any text, nothing is read.")
        #expect(OCRResult(lines: ["No boxes"]).block(around: CGPoint(x: 0.5, y: 0.5), in: size) == nil)
    }

    @Test
    func realVisionBoxesFindTheClickedParagraph() async throws {
        let first = ["Erster Absatz mit Text.", "Er hat zwei Zeilen."]
        let second = ["Second paragraph here.", "It should be read alone."]
        let image = try makeOCRFixture(lines: first + ["", ""] + second, height: 420)
        let result = try await VisionOCRService().recognize(image)
        #expect(result.boxes.count == result.lines.count)
        // Lines are drawn from y = 360 downward in steps of 60 px.
        let block = try #require(result.block(around: CGPoint(x: 0.2, y: (120.0 + 12) / 420),
                                              in: CGSize(width: 1100, height: 420)))
        #expect(block.text == second.joined(separator: "\n"))
    }

    @Test
    func alreadyCancelledTaskCannotDeliverRecognizedText() async throws {
        let image = try makeOCRFixture(lines: ["Do not deliver this result"])
        let task = Task { @MainActor in
            try await VisionOCRService().recognize(image)
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("A cancelled OCR task must not return text.")
        } catch is CancellationError {
            // Expected.
        }
    }
}

private final class CancellationProbeRequest: VNRequest {
    var cancelCount = 0
    override func cancel() {
        cancelCount += 1
        super.cancel()
    }
}

@MainActor
private func makeOCRFixture(lines: [String], height: Int = 240) throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: 1100, height: height,
        bitsPerComponent: 8, bytesPerRow: 4400, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1100, height: height))
    for (index, line) in lines.enumerated() {
        let text = NSAttributedString(string: line, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 32, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ])
        context.textPosition = CGPoint(x: 30, y: height - 60 - index * 60)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
    }
    return try #require(context.makeImage())
}

// This real-clipboard assertion shares the serialized suite with the dictation
// paste test. OCR itself is asynchronous; unrelated paste tests must not mutate
// the process-global clipboard while its privacy assertion is in flight.
extension FeedbackAtSourceTests {
    @Test
    func realVisionRecognizesGermanEnglishAndNumbersWithoutClipboardWrites() async throws {
        let lines = ["Guten Morgen. Straße und Grüße.",
                     "Hello world. Local text recognition.", "AB-123 42,50 EUR 04.09.2026"]
        let image = try makeOCRFixture(lines: lines)
        let clipboardRevision = NSPasteboard.general.changeCount
        let result = try await VisionOCRService().recognize(image)
        // Only synthetic text is asserted; never attach a screenshot to test reports.
        #expect(result.text == lines.joined(separator: "\n"))
        #expect(NSPasteboard.general.changeCount == clipboardRevision)
    }
}
