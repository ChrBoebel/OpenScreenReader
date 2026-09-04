import AppKit
import CoreText
import Testing
import Vision
@testable import OpenScreenReader

@Suite("Local text recognition")
@MainActor
struct OCRTests {
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

    @Test
    func blankImageProducesAnEmptyResult() async throws {
        let result = try await VisionOCRService().recognize(makeOCRFixture(lines: []))
        #expect(result.text.isEmpty)
        #expect(result.lineCount == 0)
        #expect(result.characterCount == 0)
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
private func makeOCRFixture(lines: [String]) throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: 1100, height: 240,
        bitsPerComponent: 8, bytesPerRow: 4400, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1100, height: 240))
    for (index, line) in lines.enumerated() {
        let text = NSAttributedString(string: line, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 32, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ])
        context.textPosition = CGPoint(x: 30, y: 180 - index * 60)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
    }
    return try #require(context.makeImage())
}
