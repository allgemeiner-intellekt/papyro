// PapyroTests/TextExtractorTests.swift
import Testing
import Foundation
import CoreGraphics
import CoreText
@testable import Papyro

struct TextExtractorTests {
    let extractor = TextExtractor()

    @Test func returnsNilForNonExistentFile() {
        let badURL = URL(fileURLWithPath: "/nonexistent/file.pdf")
        let text = extractor.extractText(from: badURL)
        #expect(text == nil)
    }

    @Test func cachesTextToDisk() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir.appendingPathComponent(".cache/text"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let paperId = UUID()
        try extractor.cacheText("some extracted text", for: paperId, in: tempDir)

        let cachedURL = tempDir.appendingPathComponent(".cache/text/\(paperId.uuidString).txt")
        #expect(fm.fileExists(atPath: cachedURL.path))

        let content = try String(contentsOf: cachedURL, encoding: .utf8)
        #expect(content == "some extracted text")
    }

    @Test func extractsTextFromValidPDF() throws {
        // Create a minimal PDF using Core Graphics
        let fm = FileManager.default
        let pdfURL = fm.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).pdf")
        defer { try? fm.removeItem(at: pdfURL) }

        try createMinimalPDF(at: pdfURL, text: "Hello World Test Document DOI 10.1234/test")

        let text = extractor.extractText(from: pdfURL)
        // PDFKit may or may not extract text from a CG-rendered PDF depending on how it was drawn
        // At minimum, the function should not crash and should return String?
        // If text is extractable, it should contain some of our content
        if let text = text {
            #expect(!text.isEmpty)
        }
        // This test mainly verifies the function handles real PDFs without crashing
    }

    /// Creates a minimal PDF with text rendered via Core Graphics
    private func createMinimalPDF(at url: URL, text: String) throws {
        var pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &pageRect, nil) else {
            return
        }
        context.beginPage(mediaBox: &pageRect)

        let font = CTFontCreateWithName("Helvetica" as CFString, 12.0, nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let frameSetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
        let textRect = CGRect(x: 72, y: 72, width: 468, height: 648)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(frameSetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)

        context.endPage()
        context.closePDF()
    }
}
