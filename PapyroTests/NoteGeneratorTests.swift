import Testing
import Foundation
@testable import Papyro

struct NoteGeneratorTests {
    let fm = FileManager.default

    private func makeTempLibrary() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("templates"), withIntermediateDirectories: true)
        return dir
    }

    private func makePaper(
        title: String = "Attention Is All You Need",
        authors: [String] = ["Vaswani, Ashish", "Shazeer, Noam"],
        year: Int? = 2017,
        journal: String? = "NeurIPS",
        doi: String? = "10.5555/3295222.3295349",
        arxivId: String? = "1706.03762",
        abstract: String? = "We propose a new architecture...",
        pdfFilename: String = "2017_vaswani_attention-is-all-you-need.pdf",
        canonicalId: String? = "10.5555/3295222.3295349"
    ) -> Paper {
        Paper(
            id: UUID(),
            canonicalId: canonicalId,
            title: title,
            authors: authors,
            year: year,
            journal: journal,
            doi: doi,
            arxivId: arxivId,
            pmid: nil,
            isbn: nil,
            abstract: abstract,
            url: nil,
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

    @Test func expandsAllPlaceholders() throws {
        let template = """
        ---
        title: "{{title}}"
        authors: [{{authors_linked}}]
        year: {{year}}
        doi: "{{doi}}"
        status: "{{status}}"
        ---

        # {{title}}

        **Authors:** {{authors_formatted}}
        **Published:** {{journal}}, {{year}}
        **DOI:** [{{doi}}](https://doi.org/{{doi}})
        **PDF:** [[{{pdf_filename}}]]
        **arXiv:** {{arxiv_id}}

        ## Abstract

        {{abstract}}

        ## Notes

        """

        let paper = makePaper()
        let result = NoteGenerator.expandTemplate(template, with: paper)

        #expect(result.contains("title: \"Attention Is All You Need\""))
        #expect(result.contains("authors: [[[Vaswani, Ashish]], [[Shazeer, Noam]]]"))
        #expect(result.contains("year: 2017"))
        #expect(result.contains("doi: \"10.5555/3295222.3295349\""))
        #expect(result.contains("status: \"to-read\""))
        #expect(result.contains("**Authors:** Vaswani, Ashish, Shazeer, Noam"))
        #expect(result.contains("**Published:** NeurIPS, 2017"))
        #expect(result.contains("**PDF:** [[2017_vaswani_attention-is-all-you-need.pdf]]"))
        #expect(result.contains("**arXiv:** 1706.03762"))
        #expect(result.contains("We propose a new architecture..."))
    }

    @Test func missingValuesRenderAsEmptyStrings() {
        let template = "DOI: {{doi}}, Journal: {{journal}}, arXiv: {{arxiv_id}}"
        let paper = makePaper(journal: nil, doi: nil, arxivId: nil)
        let result = NoteGenerator.expandTemplate(template, with: paper)
        #expect(result == "DOI: , Journal: , arXiv: ")
    }

    @Test func noteFilenameFromDOI() {
        let paper = makePaper(doi: "10.1038/s41586-024-07998-6", arxivId: nil, canonicalId: "10.1038/s41586-024-07998-6")
        let filename = NoteGenerator.noteFilename(for: paper)
        #expect(filename == "10.1038_s41586-024-07998-6.md")
    }

    @Test func noteFilenameFromArxivId() {
        let paper = makePaper(doi: nil, arxivId: "2401.12345", canonicalId: "2401.12345")
        let filename = NoteGenerator.noteFilename(for: paper)
        #expect(filename == "2401.12345.md")
    }

    @Test func noteFilenameFromTitleFallback() {
        let paper = makePaper(title: "Some Interesting Paper!", doi: nil, arxivId: nil, canonicalId: nil)
        let filename = NoteGenerator.noteFilename(for: paper)
        #expect(filename == "some-interesting-paper.md")
    }

    @Test func generatesNoteFileOnDisk() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let paper = makePaper()
        let generator = NoteGenerator()
        let notePath = try generator.generateNote(for: paper, libraryRoot: libRoot)

        #expect(notePath == "notes/10.5555_3295222.3295349.md")
        let noteURL = libRoot.appendingPathComponent(notePath)
        #expect(fm.fileExists(atPath: noteURL.path))

        let content = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(content.contains("Attention Is All You Need"))
    }

    @Test func usesCustomTemplateWhenPresent() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let customTemplate = "# {{title}}\nBy {{authors_formatted}}"
        try customTemplate.write(
            to: libRoot.appendingPathComponent("templates/note.md"),
            atomically: true,
            encoding: .utf8
        )

        let paper = makePaper()
        let generator = NoteGenerator()
        let notePath = try generator.generateNote(for: paper, libraryRoot: libRoot)

        let content = try String(contentsOf: libRoot.appendingPathComponent(notePath), encoding: .utf8)
        #expect(content == "# Attention Is All You Need\nBy Vaswani, Ashish, Shazeer, Noam")
    }

    @Test func writesDefaultTemplateIfMissing() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let paper = makePaper()
        let generator = NoteGenerator()
        _ = try generator.generateNote(for: paper, libraryRoot: libRoot)

        let templateURL = libRoot.appendingPathComponent("templates/note.md")
        #expect(fm.fileExists(atPath: templateURL.path))
    }
}
