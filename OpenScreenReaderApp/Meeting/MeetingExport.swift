import AppKit
import CoreText
import Foundation
import UniformTypeIdentifiers

/// The file formats an explicit Save offers. PDF comes first: it is what people
/// share and print; Markdown and plain text stay for editing and other tools.
enum MeetingExportFormat: String, CaseIterable, Sendable {
  case pdf, markdown, plainText

  var title: String {
    switch self {
    case .pdf: String(localized: "PDF")
    case .markdown: String(localized: "Markdown")
    case .plainText: String(localized: "Plain Text")
    }
  }

  var fileExtension: String {
    switch self {
    case .pdf: "pdf"
    case .markdown: "md"
    case .plainText: "txt"
    }
  }

  var contentType: UTType {
    switch self {
    case .pdf: .pdf
    case .markdown: UTType(filenameExtension: "md") ?? .plainText
    case .plainText: .plainText
    }
  }

  func fileName(base: String) -> String { "\(base).\(fileExtension)" }
}

/// A finished transcript as it leaves the window: visible turns only, already
/// labelled. It exists only while a Copy or Save runs.
struct MeetingExport {
  struct Turn: Equatable {
    let speaker: String
    let start: TimeInterval
    let text: String
  }

  let title: String
  let duration: TimeInterval
  let turns: [Turn]

  init(transcript: MeetingTranscript, title: String, duration: TimeInterval) {
    self.title = title
    self.duration = duration
    turns = transcript.entries.compactMap { entry in
      let text = [entry.text, entry.pending].filter { !$0.isEmpty }.joined(separator: " ")
      return text.isEmpty ? nil : Turn(speaker: entry.label, start: entry.start, text: text)
    }
  }

  /// Everyone who spoke, in the order they first did.
  var speakers: [String] {
    var seen = Set<String>()
    return turns.map(\.speaker).filter { seen.insert($0).inserted }
  }

  func data(as format: MeetingExportFormat) throws -> Data {
    switch format {
    case .markdown: Data(markdown.utf8)
    case .plainText: Data(plainText.utf8)
    case .pdf: try MeetingPDF(export: self).render()
    }
  }

  var markdown: String {
    var lines = ["# \(title)", ""]
    for turn in turns {
      lines += ["**\(turn.speaker)** · \(MeetingClock.timestamp(turn.start))", turn.text, ""]
    }
    return lines.joined(separator: "\n")
  }

  var plainText: String {
    var lines = [title, ""]
    for turn in turns {
      lines += ["\(turn.speaker) · \(MeetingClock.timestamp(turn.start))", turn.text, ""]
    }
    return lines.joined(separator: "\n")
  }
}

/// Lays the transcript out on A4 pages with Core Text and draws it into a tagged
/// PDF: a heading, then per turn the speaker line and the text as paragraphs, so
/// screen readers follow the structure. Only the title and "Saywing" go into the
/// document info; no author, no machine or user names.
private struct MeetingPDF {
  let export: MeetingExport

  private static let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
  private static let margin: CGFloat = 56
  private static let footerHeight: CGFloat = 24
  // Fixed colours: a PDF is printed and read on white, whatever the Mac's appearance.
  private static let ink = NSColor.black
  private static let quiet = NSColor(white: 0.38, alpha: 1)

  private enum Role { case title, meta, speaker, body }

  func render() throws -> Data {
    let (text, roles) = content()
    let framesetter = CTFramesetterCreateWithAttributedString(text)
    let body = CGRect(
      x: Self.margin, y: Self.margin + Self.footerHeight, width: Self.page.width - 2 * Self.margin,
      height: Self.page.height - 2 * Self.margin - Self.footerHeight)
    var frames: [CTFrame] = []
    var location = 0
    repeat {
      let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), CGPath(rect: body, transform: nil), nil)
      let visible = CTFrameGetVisibleStringRange(frame)
      frames.append(frame)
      guard visible.length > 0 else { break }
      location += visible.length
    } while location < text.length
    return try draw(frames: frames, roles: roles)
  }

  private func draw(frames: [CTFrame], roles: [(NSRange, Role)]) throws -> Data {
    let data = NSMutableData()
    var box = Self.page
    let info: [CFString: Any] = [kCGPDFContextTitle: export.title, kCGPDFContextCreator: "Saywing"]
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)
    else { throw MeetingError(String(localized: "The PDF could not be created.")) }
    CGPDFContextBeginTag(context, .document, [:] as CFDictionary)
    for (index, frame) in frames.enumerated() {
      context.beginPDFPage(nil)
      context.textMatrix = .identity
      let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
      var origins = [CGPoint](repeating: .zero, count: lines.count)
      CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
      let frameOrigin = CTFrameGetPath(frame).boundingBox.origin
      // Consecutive lines of one paragraph share one tag; a paragraph that runs
      // onto the next page gets a second tag there.
      var openParagraph: Int?
      for (line, origin) in zip(lines, origins) {
        let start = CTLineGetStringRange(line).location
        let paragraph = roles.firstIndex { NSLocationInRange(start, $0.0) }
        if paragraph != openParagraph {
          if openParagraph != nil { CGPDFContextEndTag(context) }
          if let paragraph { CGPDFContextBeginTag(context, Self.tag(for: roles[paragraph].1), [:] as CFDictionary) }
          openParagraph = paragraph
        }
        context.textPosition = CGPoint(x: frameOrigin.x + origin.x, y: frameOrigin.y + origin.y)
        CTLineDraw(line, context)
      }
      if openParagraph != nil { CGPDFContextEndTag(context) }
      drawFooter("\(index + 1) / \(frames.count)", in: context)
      context.endPDFPage()
    }
    CGPDFContextEndTag(context)
    context.closePDF()
    return data as Data
  }

  private static func tag(for role: Role) -> CGPDFTagType {
    switch role {
    case .title: .header1
    case .meta, .speaker, .body: .paragraph
    }
  }

  private func drawFooter(_ string: String, in context: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular), .foregroundColor: Self.quiet,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    CGPDFContextBeginTag(context, .paragraph, [:] as CFDictionary)
    context.textPosition = CGPoint(x: (Self.page.width - width) / 2, y: Self.margin)
    CTLineDraw(line, context)
    CGPDFContextEndTag(context)
  }

  /// The whole document as one attributed string, with the role of each paragraph.
  private func content() -> (NSAttributedString, [(NSRange, Role)]) {
    let ink = Self.ink, quiet = Self.quiet
    func style(after: CGFloat, before: CGFloat = 0) -> NSParagraphStyle {
      let style = NSMutableParagraphStyle()
      style.paragraphSpacing = after
      style.paragraphSpacingBefore = before
      style.lineHeightMultiple = 1.15
      return style
    }
    let text = NSMutableAttributedString()
    var roles: [(NSRange, Role)] = []
    func add(_ parts: [(String, [NSAttributedString.Key: Any])], _ role: Role, _ paragraph: NSParagraphStyle) {
      let start = text.length
      for (string, attributes) in parts {
        text.append(NSAttributedString(string: string, attributes: attributes.merging([.paragraphStyle: paragraph]) { $1 }))
      }
      text.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph, .font: NSFont.systemFont(ofSize: 11)]))
      roles.append((NSRange(location: start, length: text.length - start), role))
    }

    add([(export.title, [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: ink])], .title, style(after: 6))
    var meta = [String(localized: "Duration \(MeetingClock.elapsed(export.duration))")]
    if !export.speakers.isEmpty {
      meta.append(String(localized: "Speakers: \(export.speakers.formatted(.list(type: .and)))"))
    }
    let metaFont = NSFont.systemFont(ofSize: 10)
    add([(meta.joined(separator: " · "), [.font: metaFont, .foregroundColor: quiet])], .meta, style(after: 2))
    add(
      [(String(localized: "Transcribed on this Mac with Saywing. No audio was saved."), [.font: metaFont, .foregroundColor: quiet])],
      .meta, style(after: 22))
    for turn in export.turns {
      add(
        [
          (turn.speaker, [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: ink]),
          ("  " + MeetingClock.timestamp(turn.start), [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: quiet]),
        ], .speaker, style(after: 3, before: 4))
      add([(turn.text, [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: ink])], .body, style(after: 10))
    }
    return (text, roles)
  }
}
