import Testing
import Foundation
@testable import Papyro

struct CitationExporterTests {

    // MARK: - Helper

    private func makePaper(
        title: String = "Attention Is All You Need",
        authors: [String] = ["Vaswani, Ashish", "Shazeer, Noam"],
        year: Int? = 2017,
        journal: String? = "NeurIPS",
        doi: String? = "10.5555/3295222.3295349",
        arxivId: String? = "1706.03762",
        abstract: String? = "We propose a new architecture based entirely on attention mechanisms.",
        url: String? = nil,
        pmid: String? = nil,
        isbn: String? = nil,
        pdfFilename: String = "2017_vaswani_attention-is-all-you-need.pdf"
    ) -> Paper {
        Paper(
            id: UUID(),
            canonicalId: doi ?? arxivId,
            title: title,
            authors: authors,
            year: year,
            journal: journal,
            doi: doi,
            arxivId: arxivId,
            pmid: pmid,
            isbn: isbn,
            abstract: abstract,
            url: url,
            pdfPath: "papers/\(pdfFilename)",
            pdfFilename: pdfFilename,
            notePath: nil,
            projectIDs: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .semanticScholar,
            metadataResolved: true,
            importState: .resolved
        )
    }

    private func makeMinimalPaper(
        pdfFilename: String = "unknown.pdf"
    ) -> Paper {
        Paper(
            id: UUID(),
            canonicalId: nil,
            title: pdfFilename,
            authors: [],
            year: nil,
            journal: nil,
            doi: nil,
            arxivId: nil,
            pmid: nil,
            isbn: nil,
            abstract: nil,
            url: nil,
            pdfPath: "papers/\(pdfFilename)",
            pdfFilename: pdfFilename,
            notePath: nil,
            projectIDs: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .none,
            metadataResolved: false,
            importState: .unresolved
        )
    }

    // MARK: - BibTeX Key Generation

    @Test func bibtexKeyNormalCase() {
        let paper = makePaper(
            title: "Attention Is All You Need",
            authors: ["Vaswani, Ashish"],
            year: 2017
        )
        let key = CitationExporter.bibtexKey(for: paper)
        #expect(key == "vaswani2017attention")
    }

    @Test func bibtexKeyNoAuthor() {
        let paper = makePaper(
            title: "Some Paper",
            authors: [],
            year: 2020
        )
        let key = CitationExporter.bibtexKey(for: paper)
        #expect(key.hasPrefix("unknown"))
    }

    @Test func bibtexKeyNoYear() {
        let paper = makePaper(
            title: "Attention Is All You Need",
            authors: ["Vaswani, Ashish"],
            year: nil
        )
        let key = CitationExporter.bibtexKey(for: paper)
        #expect(key.contains("nd"))
    }

    @Test func bibtexKeySkipsCommonLeadingWords() {
        let paperThe = makePaper(
            title: "The Transformer Architecture",
            authors: ["Vaswani, Ashish"],
            year: 2017
        )
        let keyThe = CitationExporter.bibtexKey(for: paperThe)
        #expect(keyThe.contains("transformer"))
        #expect(!keyThe.contains("the"))

        let paperA = makePaper(
            title: "A Novel Approach",
            authors: ["Smith, J."],
            year: 2021
        )
        let keyA = CitationExporter.bibtexKey(for: paperA)
        #expect(keyA.contains("novel"))

        let paperAn = makePaper(
            title: "An Empirical Study",
            authors: ["Chen, L."],
            year: 2022
        )
        let keyAn = CitationExporter.bibtexKey(for: paperAn)
        #expect(keyAn.contains("empirical"))
    }

    @Test func bibtexKeyHandlesDiacritics() {
        let paper = makePaper(
            title: "Optimization Methods",
            authors: ["Müller, Thomas"],
            year: 2019
        )
        let key = CitationExporter.bibtexKey(for: paper)
        // Key should be generated without crashing; exact transliteration may vary
        #expect(!key.isEmpty)
        #expect(key.contains("2019"))
        #expect(key.contains("optimization"))
    }

    @Test func bibtexKeySingleWordTitle() {
        let paper = makePaper(
            title: "Transformers",
            authors: ["Vaswani, Ashish"],
            year: 2017
        )
        let key = CitationExporter.bibtexKey(for: paper)
        #expect(key.contains("transformers"))
    }

    @Test func bibtexKeyEmptyTitle() {
        let paper = makePaper(
            title: "",
            authors: ["Smith, J."],
            year: 2020
        )
        let key = CitationExporter.bibtexKey(for: paper)
        #expect(key.contains("untitled"))
    }

    // MARK: - BibTeX Formatting

    @Test func bibtexEntryFullPaper() {
        let paper = makePaper()
        let entry = CitationExporter.bibtexEntry(for: paper)

        #expect(entry.contains("@article{"))
        #expect(entry.contains("title = {Attention Is All You Need}"))
        #expect(entry.contains("author = {Vaswani, Ashish and Shazeer, Noam}"))
        #expect(entry.contains("year = {2017}"))
        #expect(entry.contains("journal = {NeurIPS}"))
        #expect(entry.contains("doi = {10.5555/3295222.3295349}"))
    }

    @Test func bibtexEntryArticleTypeWithJournal() {
        let paper = makePaper(journal: "Nature")
        let entry = CitationExporter.bibtexEntry(for: paper)
        #expect(entry.hasPrefix("@article{"))
    }

    @Test func bibtexEntryMiscTypeWithoutJournal() {
        let paper = makePaper(journal: nil)
        let entry = CitationExporter.bibtexEntry(for: paper)
        #expect(entry.hasPrefix("@misc{"))
    }

    @Test func bibtexEntryEscapesSpecialCharacters() {
        let paper = makePaper(
            title: "Cats & Dogs: A Study of 100% Natural Behavior",
            authors: ["O'Brien, J."],
            journal: "Nature & Science"
        )
        let entry = CitationExporter.bibtexEntry(for: paper)
        #expect(entry.contains(#"Cats \& Dogs"#))
        #expect(entry.contains(#"100\%"#))
    }

    @Test func bibtexEntryEscapesBracesAndBackslash() {
        let paper = makePaper(
            title: #"The {EM} Algorithm: A \textbf{Review}"#,
            authors: ["Doe, J."]
        )
        let entry = CitationExporter.bibtexEntry(for: paper)
        #expect(entry.contains(#"\{EM\}"#))
        #expect(entry.contains(#"\textbackslash{}"#))
    }

    @Test func bibtexEntryMultipleAuthorsJoinedWithAnd() {
        let paper = makePaper(
            authors: ["Smith, J.", "Chen, L.", "Kim, S."]
        )
        let entry = CitationExporter.bibtexEntry(for: paper)
        #expect(entry.contains("author = {Smith, J. and Chen, L. and Kim, S.}"))
    }

    @Test func bibtexEntryOmitsMissingOptionalFields() {
        let paper = makePaper(
            journal: nil,
            doi: nil,
            arxivId: nil,
            abstract: nil
        )
        let entry = CitationExporter.bibtexEntry(for: paper)
        #expect(!entry.contains("journal ="))
        #expect(!entry.contains("doi ="))
        #expect(!entry.contains("abstract ="))
    }

    @Test func bibtexEntryIncludesAbstract() {
        let paper = makePaper(abstract: "This paper studies attention mechanisms.")
        let entry = CitationExporter.bibtexEntry(for: paper)
        #expect(entry.contains("abstract = {This paper studies attention mechanisms.}"))
    }

    // MARK: - RIS Formatting

    @Test func risEntryFullPaper() {
        let paper = makePaper()
        let entry = CitationExporter.risEntry(for: paper)

        #expect(entry.contains("TY  - JOUR"))
        #expect(entry.contains("TI  - Attention Is All You Need"))
        #expect(entry.contains("AU  - Vaswani, Ashish"))
        #expect(entry.contains("AU  - Shazeer, Noam"))
        #expect(entry.contains("PY  - 2017"))
        #expect(entry.contains("JO  - NeurIPS"))
        #expect(entry.contains("DO  - 10.5555/3295222.3295349"))
        #expect(entry.contains("ER  - "))
    }

    @Test func risEntryJournalTypeWithJournal() {
        let paper = makePaper(journal: "Science")
        let entry = CitationExporter.risEntry(for: paper)
        #expect(entry.contains("TY  - JOUR"))
    }

    @Test func risEntryGenericTypeWithoutJournal() {
        let paper = makePaper(journal: nil)
        let entry = CitationExporter.risEntry(for: paper)
        #expect(entry.contains("TY  - GEN"))
    }

    @Test func risEntryMultipleAuthorsSeparateLines() {
        let paper = makePaper(
            authors: ["Smith, J.", "Chen, L.", "Kim, S."]
        )
        let entry = CitationExporter.risEntry(for: paper)

        let auLines = entry.components(separatedBy: "\n").filter { $0.hasPrefix("AU  - ") }
        #expect(auLines.count == 3)
        #expect(auLines[0] == "AU  - Smith, J.")
        #expect(auLines[1] == "AU  - Chen, L.")
        #expect(auLines[2] == "AU  - Kim, S.")
    }

    @Test func risEntryEndsWithER() {
        let paper = makePaper()
        let entry = CitationExporter.risEntry(for: paper)
        let trimmed = entry.trimmingCharacters(in: .newlines)
        #expect(trimmed.hasSuffix("ER  - "))
    }

    @Test func risEntryOmitsMissingFields() {
        let paper = makePaper(
            journal: nil,
            doi: nil,
            arxivId: nil,
            abstract: nil
        )
        let entry = CitationExporter.risEntry(for: paper)
        #expect(!entry.contains("JO  - "))
        #expect(!entry.contains("DO  - "))
        #expect(!entry.contains("AB  - "))
    }

    // MARK: - Single Export (format dispatch)

    @Test func exportDispatchesBibtex() {
        let paper = makePaper()
        let result = CitationExporter.export(paper, format: .bibtex)
        #expect(result.contains("@article{") || result.contains("@misc{"))
    }

    @Test func exportDispatchesRIS() {
        let paper = makePaper()
        let result = CitationExporter.export(paper, format: .ris)
        #expect(result.contains("TY  - "))
        #expect(result.contains("ER  - "))
    }

    // MARK: - Batch Export

    @Test func batchExportMultiplePapersSeparatedByBlankLines() {
        let papers = [
            makePaper(title: "Paper One", authors: ["Alpha, A."], year: 2020),
            makePaper(title: "Paper Two", authors: ["Beta, B."], year: 2021),
        ]
        let result = CitationExporter.exportBatch(papers, format: .bibtex)

        // Each entry is an @article/@misc block; entries separated by blank line
        let entries = result.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        #expect(entries.count == 2)
    }

    @Test func batchExportDeduplicatesBibtexKeys() {
        // Two papers that would generate the same key: same first author surname, same year, same first title word
        let paper1 = makePaper(
            title: "Attention Is All You Need",
            authors: ["Vaswani, Ashish"],
            year: 2017
        )
        let paper2 = makePaper(
            title: "Attention Mechanisms Revisited",
            authors: ["Vaswani, Ashish"],
            year: 2017
        )
        let result = CitationExporter.exportBatch([paper1, paper2], format: .bibtex)

        // The two entries should have distinct keys (e.g. vaswani2017attention vs vaswani2017attentionb,
        // or vaswani2017attentiona vs vaswani2017attentionb)
        let keyPattern = result.components(separatedBy: "\n")
            .filter { $0.contains("@article{") || $0.contains("@misc{") }
        #expect(keyPattern.count == 2)

        // Extract keys from "@article{key," or "@misc{key,"
        let keys = keyPattern.compactMap { line -> String? in
            guard let openBrace = line.firstIndex(of: "{"),
                  let comma = line.firstIndex(of: ",") else { return nil }
            return String(line[line.index(after: openBrace)..<comma])
        }
        #expect(keys.count == 2)
        #expect(keys[0] != keys[1])
    }

    @Test func batchExportEmptyArrayReturnsEmptyString() {
        let result = CitationExporter.exportBatch([], format: .bibtex)
        #expect(result == "")

        let risResult = CitationExporter.exportBatch([], format: .ris)
        #expect(risResult == "")
    }

    @Test func batchExportRISMultiplePapers() {
        let papers = [
            makePaper(title: "First", authors: ["A, B."], year: 2020, journal: "Nature"),
            makePaper(title: "Second", authors: ["C, D."], year: 2021, journal: "Science"),
        ]
        let result = CitationExporter.exportBatch(papers, format: .ris)

        let erLines = result.components(separatedBy: "\n").filter { $0.hasPrefix("ER  - ") }
        #expect(erLines.count == 2)
        #expect(result.contains("ER  - \n\nTY  - "))
    }

    // MARK: - File Extension

    @Test func fileExtensionBibtex() {
        #expect(CitationExporter.fileExtension(for: .bibtex) == ".bib")
    }

    @Test func fileExtensionRIS() {
        #expect(CitationExporter.fileExtension(for: .ris) == ".ris")
    }

    // MARK: - Edge Cases

    @Test func paperWithNoMetadata() {
        let paper = makeMinimalPaper()
        let bibtex = CitationExporter.export(paper, format: .bibtex)
        let ris = CitationExporter.export(paper, format: .ris)

        // Should produce valid output without crashing
        #expect(!bibtex.isEmpty)
        #expect(!ris.isEmpty)
        #expect(ris.contains("ER  - "))
    }

    @Test func paperWithVeryLongTitle() {
        let longTitle = (1...50).map { "Word\($0)" }.joined(separator: " ")
        let paper = makePaper(title: longTitle, authors: ["Smith, J."], year: 2023)
        let key = CitationExporter.bibtexKey(for: paper)

        // Key should remain a reasonable length, not contain the entire title
        #expect(key.count <= 50)
        #expect(key.contains("smith"))
        #expect(key.contains("2023"))
    }

    @Test func paperWithArxivIdInBibtexNote() {
        let paper = makePaper(
            title: "Deep Learning",
            authors: ["LeCun, Y."],
            year: 2015,
            journal: "Nature",
            arxivId: "1501.12345"
        )
        let entry = CitationExporter.bibtexEntry(for: paper)
        #expect(entry.contains("1501.12345"))
    }

    @Test func bibtexKeyIsLowercased() {
        let paper = makePaper(
            title: "UPPERCASE TITLE",
            authors: ["SMITH, J."],
            year: 2020
        )
        let key = CitationExporter.bibtexKey(for: paper)
        #expect(key == key.lowercased())
    }

    @Test func risEntryIncludesAbstractWhenPresent() {
        let paper = makePaper(abstract: "A fascinating study of transformers.")
        let entry = CitationExporter.risEntry(for: paper)
        #expect(entry.contains("AB  - A fascinating study of transformers."))
    }

    @Test func risEntryIncludesURLWhenPresent() {
        let paper = makePaper(url: "https://example.com/paper.pdf")
        let entry = CitationExporter.risEntry(for: paper)
        #expect(entry.contains("UR  - https://example.com/paper.pdf"))
    }

    @Test func risEntryIncludesArxivIdAsNote() {
        let paper = makePaper(arxivId: "2301.00001")
        let entry = CitationExporter.risEntry(for: paper)
        #expect(entry.contains("N1  - arXiv: 2301.00001"))
    }

    @Test func authorGivenSurnameFormatConvertedToSurnameGiven() {
        let paper = makePaper(authors: ["Ashish Vaswani", "Noam Shazeer"])
        let entry = CitationExporter.bibtexEntry(for: paper)
        #expect(entry.contains("Vaswani, Ashish and Shazeer, Noam"))
    }

    @Test func bibtexEntrySingleAuthor() {
        let paper = makePaper(authors: ["Solo, Han"])
        let entry = CitationExporter.bibtexEntry(for: paper)
        #expect(entry.contains("author = {Solo, Han}"))
        // No " and " when there is only one author
        #expect(!entry.contains(" and "))
    }

    @Test func bibtexEntryNoAuthorsField() {
        let paper = makePaper(authors: [])
        let entry = CitationExporter.bibtexEntry(for: paper)
        // Should either omit the author field or handle gracefully
        #expect(!entry.contains("author = {}"))
    }
}
