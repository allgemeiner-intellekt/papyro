// Papyro/Services/TextExtractor.swift
import Foundation
@preconcurrency import PDFKit

struct TextExtractor: Sendable {
    func extractText(from pdfURL: URL, pages: Int = 5) -> String? {
        guard let document = PDFDocument(url: pdfURL) else { return nil }
        let pageCount = min(document.pageCount, pages)
        guard pageCount > 0 else { return nil }

        var texts: [String] = []
        for i in 0..<pageCount {
            if let page = document.page(at: i), let text = page.string {
                texts.append(text)
            }
        }

        let combined = texts.joined(separator: "\n\n")
        return combined.isEmpty ? nil : combined
    }

    func cacheText(_ text: String, for paperId: UUID, in libraryRoot: URL) throws {
        let cacheDir = libraryRoot.appendingPathComponent(".cache/text")
        let fileURL = cacheDir.appendingPathComponent("\(paperId.uuidString).txt")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
