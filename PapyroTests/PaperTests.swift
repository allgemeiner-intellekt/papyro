import Testing
import Foundation
@testable import Papyro

struct PaperTests {
    @Test func decodesPaperWithoutLastResolutionError() throws {
        // Pre-M6 JSON has no lastResolutionError field — must still decode.
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "Test",
          "authors": ["Smith, J."],
          "pdfPath": "papers/test.pdf",
          "pdfFilename": "test.pdf",
          "projectIDs": [],
          "status": "toRead",
          "dateAdded": "2026-04-01T00:00:00Z",
          "dateModified": "2026-04-01T00:00:00Z",
          "metadataSource": "none",
          "metadataResolved": false,
          "importState": "unresolved"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let paper = try decoder.decode(Paper.self, from: json)
        #expect(paper.lastResolutionError == nil)
    }

    @Test func decodesPaperWithLastResolutionError() throws {
        let json = """
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "title": "Test",
          "authors": [],
          "pdfPath": "papers/test.pdf",
          "pdfFilename": "test.pdf",
          "projectIDs": [],
          "status": "toRead",
          "dateAdded": "2026-04-01T00:00:00Z",
          "dateModified": "2026-04-01T00:00:00Z",
          "metadataSource": "none",
          "metadataResolved": false,
          "importState": "unresolved",
          "lastResolutionError": "network unreachable"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let paper = try decoder.decode(Paper.self, from: json)
        #expect(paper.lastResolutionError == "network unreachable")
    }

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
            projectIDs: [],
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
        #expect(decoded.projectIDs.isEmpty)
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
            projectIDs: [],
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
        #expect(paper.projectIDs.isEmpty)
    }

    @Test func matchesTitleSearch() {
        let paper = makePaper(title: "Attention Is All You Need", authors: ["Vaswani, A."])
        #expect(paper.matches(searchTokens: ["attention"]))
        #expect(!paper.matches(searchTokens: ["transformer"]))
    }

    @Test func matchesAuthorSearch() {
        let paper = makePaper(title: "Some Paper", authors: ["Smith, J.", "Chen, L."])
        #expect(paper.matches(searchTokens: ["smith"]))
        #expect(paper.matches(searchTokens: ["chen"]))
    }

    @Test func matchesMultipleTokensWithANDLogic() {
        let paper = makePaper(title: "Neural Plasticity", authors: ["Smith, J."], year: 2024)
        #expect(paper.matches(searchTokens: ["smith", "2024"]))
        #expect(paper.matches(searchTokens: ["neural", "smith"]))
        #expect(!paper.matches(searchTokens: ["smith", "2025"]))
    }

    @Test func matchesIdentifierFields() {
        let paper = makePaper(title: "Test", doi: "10.1038/s41586-024-07998-6", arxivId: "2401.12345")
        #expect(paper.matches(searchTokens: ["10.1038"]))
        #expect(paper.matches(searchTokens: ["2401.12345"]))
    }

    @Test func matchesJournalAndAbstract() {
        let paper = makePaper(title: "Test", journal: "Nature", abstract: "We study deep learning")
        #expect(paper.matches(searchTokens: ["nature"]))
        #expect(paper.matches(searchTokens: ["deep", "learning"]))
    }

    @Test func emptyTokensMatchesEverything() {
        let paper = makePaper(title: "Anything")
        #expect(paper.matches(searchTokens: []))
    }

    @Test func matchesIsCaseInsensitive() {
        let paper = makePaper(title: "Attention Is All You Need")
        #expect(paper.matches(searchTokens: ["ATTENTION"]))
        #expect(paper.matches(searchTokens: ["Attention"]))
    }

    private func makePaper(
        title: String = "Untitled",
        authors: [String] = [],
        year: Int? = nil,
        journal: String? = nil,
        abstract: String? = nil,
        doi: String? = nil,
        arxivId: String? = nil,
        pmid: String? = nil,
        isbn: String? = nil
    ) -> Paper {
        Paper(
            id: UUID(),
            canonicalId: nil,
            title: title,
            authors: authors,
            year: year,
            journal: journal,
            doi: doi,
            arxivId: arxivId,
            pmid: pmid,
            isbn: isbn,
            abstract: abstract,
            url: nil,
            pdfPath: "papers/test.pdf",
            pdfFilename: "test.pdf",
            notePath: nil,
            projectIDs: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .none,
            metadataResolved: false,
            importState: .resolved
        )
    }
}
