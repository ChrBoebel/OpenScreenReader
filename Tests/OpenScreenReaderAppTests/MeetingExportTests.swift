import AppKit
import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import OpenScreenReader

private func said(_ speaker: MeetingSpeaker, _ start: TimeInterval, _ end: TimeInterval, _ text: String) -> MeetingRecognition {
    MeetingRecognition(speaker: speaker, start: start, end: end, text: text, isFinal: true)
}

private func sampleExport(turns: Int = 2) -> MeetingExport {
    var transcript = MeetingTranscript()
    for index in 0..<turns {
        let speaker: MeetingSpeaker = index.isMultiple(of: 2) ? .me : .others
        let text = index == 0 ? "Kurzer Stand." : index == 1 ? "Danke, sieht gut aus." : "Beitrag \(index) mit etwas mehr Text, damit die Seite sich füllt und umbricht."
        transcript.apply(said(speaker, 3 + Double(index) * 62, 5 + Double(index) * 62, text))
    }
    return MeetingExport(transcript: transcript, title: "Meeting transcript, 18 Oct 2026", duration: 125)
}

@Suite("Meeting transcript export")
struct MeetingExportTests {
    @Test
    func turnsCarrySpeakerTimeAndVisibleText() {
        let export = sampleExport()
        #expect(export.turns == [
            MeetingExport.Turn(speaker: "Me", start: 3, text: "Kurzer Stand."),
            MeetingExport.Turn(speaker: "Others", start: 65, text: "Danke, sieht gut aus."),
        ])
        #expect(export.speakers == ["Me", "Others"])
    }

    @Test
    func markdownIsWhatCopyPutsOnThePasteboard() throws {
        let export = sampleExport()
        let markdown = try #require(String(data: try export.data(as: .markdown), encoding: .utf8))
        #expect(markdown == """
            # Meeting transcript, 18 Oct 2026

            **Me** · 00:00:03
            Kurzer Stand.

            **Others** · 00:01:05
            Danke, sieht gut aus.

            """)
    }

    @Test
    func plainTextHasNoMarkup() throws {
        let text = try #require(String(data: try sampleExport().data(as: .plainText), encoding: .utf8))
        #expect(text == """
            Meeting transcript, 18 Oct 2026

            Me · 00:00:03
            Kurzer Stand.

            Others · 00:01:05
            Danke, sieht gut aus.

            """)
    }

    @Test
    func pdfHoldsTitleSpeakersAndTextAsRealText() throws {
        let data = try sampleExport().data(as: .pdf)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        let text = try #require(document.string)
        for expected in ["Meeting transcript, 18 Oct 2026", "Me", "00:00:03", "Kurzer Stand.", "Others", "00:01:05", "Danke, sieht gut aus."] {
            #expect(text.contains(expected), "missing \(expected)")
        }
        #expect(text.range(of: "Kurzer Stand.")!.lowerBound < text.range(of: "Danke, sieht gut aus.")!.lowerBound)
    }

    @Test
    func pdfNamesItselfButNotThePerson() throws {
        let document = try #require(PDFDocument(data: try sampleExport().data(as: .pdf)))
        let attributes = document.documentAttributes ?? [:]
        #expect(attributes[PDFDocumentAttribute.titleAttribute] as? String == "Meeting transcript, 18 Oct 2026")
        #expect(attributes[PDFDocumentAttribute.creatorAttribute] as? String == "Saywing")
        #expect(attributes[PDFDocumentAttribute.authorAttribute] == nil)
    }

    @Test
    func longTranscriptsFlowOntoNumberedPagesWithoutLosingText() throws {
        let export = sampleExport(turns: 120)
        let document = try #require(PDFDocument(data: try export.data(as: .pdf)))
        #expect(document.pageCount > 2)
        let text = try #require(document.string)
        #expect(text.contains("Beitrag 119"))
        #expect(text.contains("1 / \(document.pageCount)"))
        #expect(text.contains("\(document.pageCount) / \(document.pageCount)"))
    }

    /// Saywing reads screens aloud; its own documents should be readable by
    /// screen readers too, so the PDF carries a structure tree.
    @Test
    func pdfIsTaggedForScreenReaders() throws {
        let data = try sampleExport().data(as: .pdf)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let pdf = try #require(CGPDFDocument(provider))
        let catalog = try #require(pdf.catalog)
        var tree: CGPDFDictionaryRef?
        #expect(CGPDFDictionaryGetDictionary(catalog, "StructTreeRoot", &tree))
    }

    @Test
    func formatsNameTheirFiles() {
        #expect(MeetingExportFormat.allCases.first == .pdf)
        #expect(MeetingExportFormat.pdf.fileName(base: "Meeting transcript 2026-10-18") == "Meeting transcript 2026-10-18.pdf")
        #expect(MeetingExportFormat.markdown.fileName(base: "x") == "x.md")
        #expect(MeetingExportFormat.plainText.fileName(base: "x") == "x.txt")
    }

    @Test
    @MainActor
    func theFormatMenuStartsWithPDFAndSwitchesTheExtension() {
        let panel = NSSavePanel()
        let chooser = MeetingFormatChooser(panel: panel, baseName: "Meeting transcript 2026-10-18")
        #expect(chooser.format == .pdf)
        #expect(panel.nameFieldStringValue == "Meeting transcript 2026-10-18.pdf")
        #expect(panel.allowedContentTypes == [.pdf])
        panel.nameFieldStringValue = "Weekly sync.pdf"
        chooser.select(.markdown)
        #expect(panel.nameFieldStringValue == "Weekly sync.md")
        chooser.select(.plainText)
        #expect(panel.nameFieldStringValue == "Weekly sync.txt")
        #expect(panel.allowedContentTypes == [.plainText])
    }
}
