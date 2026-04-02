import Testing
import Foundation
@testable import Papyro

struct PaperTests {
    @Test func encodesAndDecodesCorrectly() throws {
        let paper = Paper(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!,
            canonicalId: "10.1038/s41586-024-07998-6",
            title: "Test Paper",
            authors: ["Smith, J.", "Chen, L."],
            year: 2024,
            journal: "Nature",
            doi: "10.1038/s41586-024-07998-6",
            arxivId: nil,
            pmid: nil,
            isbn: nil,
            abstract: "A test abstract.",
            url: "https://doi.org/10.1038/s41586-024-07998-6",
            pdfPath: "papers/2024_smith_test-paper.pdf",
            pdfFilename: "2024_smith_test-paper.pdf",
            notePath: nil,
            topics: [],
            projects: [],
            status: .toRead,
            dateAdded: Date(timeIntervalSince1970: 1712000000),
            dateModified: Date(timeIntervalSince1970: 1712000000),
            metadataSource: .translationServer,
            metadataResolved: true,
            importState: .resolved
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(paper)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Paper.self, from: data)

        #expect(decoded.id == paper.id)
        #expect(decoded.title == "Test Paper")
        #expect(decoded.authors == ["Smith, J.", "Chen, L."])
        #expect(decoded.year == 2024)
        #expect(decoded.journal == "Nature")
        #expect(decoded.doi == "10.1038/s41586-024-07998-6")
        #expect(decoded.status == .toRead)
        #expect(decoded.metadataSource == .translationServer)
        #expect(decoded.metadataResolved == true)
        #expect(decoded.importState == .resolved)
    }

    @Test func defaultsForUnresolvedPaper() throws {
        let paper = Paper(
            id: UUID(),
            canonicalId: nil,
            title: "unknown-file.pdf",
            authors: [],
            year: nil,
            journal: nil,
            doi: nil,
            arxivId: nil,
            pmid: nil,
            isbn: nil,
            abstract: nil,
            url: nil,
            pdfPath: "papers/some-uuid.pdf",
            pdfFilename: "some-uuid.pdf",
            notePath: nil,
            topics: [],
            projects: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .none,
            metadataResolved: false,
            importState: .unresolved
        )

        #expect(paper.metadataResolved == false)
        #expect(paper.importState == .unresolved)
        #expect(paper.authors.isEmpty)
    }
}
