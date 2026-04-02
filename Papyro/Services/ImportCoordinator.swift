// Papyro/Services/ImportCoordinator.swift
import Foundation

@Observable
@MainActor
class ImportCoordinator {
    private(set) var papers: [Paper] = []

    private let libraryRoot: URL
    private let fileService: FileService
    private let textExtractor: TextExtractor
    private let identifierParser: IdentifierParser
    private let metadataProvider: MetadataProvider
    private let indexService: IndexService

    init(
        libraryRoot: URL,
        metadataProvider: MetadataProvider,
        fileService: FileService = FileService(),
        textExtractor: TextExtractor = TextExtractor(),
        identifierParser: IdentifierParser = IdentifierParser(),
        indexService: IndexService = IndexService()
    ) {
        self.libraryRoot = libraryRoot
        self.metadataProvider = metadataProvider
        self.fileService = fileService
        self.textExtractor = textExtractor
        self.identifierParser = identifierParser
        self.indexService = indexService
    }

    func loadExistingPapers() {
        if let loaded = try? indexService.loadAll(from: libraryRoot) {
            // Reset any stale in-progress states from a prior crash
            papers = loaded.map { paper in
                var p = paper
                if p.importState == .importing || p.importState == .resolving {
                    p.importState = .unresolved
                }
                return p
            }
        }
    }

    func importPDFs(_ urls: [URL]) async {
        for url in urls {
            await importSinglePDF(url)
        }
    }

    private func importSinglePDF(_ sourceURL: URL) async {
        // Step 1: Copy to library
        let copyResult: (URL, UUID)
        do {
            copyResult = try fileService.copyToLibrary(source: sourceURL, libraryRoot: libraryRoot)
        } catch {
            return
        }
        let (pdfURL, paperId) = copyResult

        // Create initial paper
        let paper = Paper(
            id: paperId,
            canonicalId: nil,
            title: sourceURL.deletingPathExtension().lastPathComponent,
            authors: [],
            year: nil,
            journal: nil,
            doi: nil,
            arxivId: nil,
            pmid: nil,
            isbn: nil,
            abstract: nil,
            url: nil,
            pdfPath: "papers/\(pdfURL.lastPathComponent)",
            pdfFilename: pdfURL.lastPathComponent,
            notePath: nil,
            topics: [],
            projects: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .none,
            metadataResolved: false,
            importState: .importing
        )
        papers.append(paper)

        // Step 2: Extract text
        let extractedText = textExtractor.extractText(from: pdfURL)
        if let text = extractedText {
            try? textExtractor.cacheText(text, for: paperId, in: libraryRoot)
        }

        // Step 3: Parse identifiers
        let identifiers = extractedText.map { identifierParser.parse($0) } ?? ParsedIdentifiers()

        updatePaper(paperId) { $0.importState = .resolving }

        // Step 4: Fetch metadata
        let metadata = await fetchMetadataWithFallback(identifiers: identifiers, extractedText: extractedText)

        if let metadata = metadata {
            updatePaper(paperId) { p in
                p.canonicalId = metadata.doi ?? metadata.arxivId
                p.title = metadata.title
                p.authors = metadata.authors
                p.year = metadata.year
                p.journal = metadata.journal
                p.doi = metadata.doi
                p.arxivId = metadata.arxivId
                p.abstract = metadata.abstract
                p.url = metadata.url
                p.metadataSource = metadata.source
                p.metadataResolved = true
                p.importState = .resolved
                p.dateModified = Date()
            }

            // Step 5: Rename PDF
            let firstAuthor = metadata.authors.first.flatMap { $0.components(separatedBy: ",").first }
            let newFilename = fileService.generateFilename(year: metadata.year, author: firstAuthor, title: metadata.title)

            if let newURL = try? fileService.renamePDF(from: pdfURL, to: newFilename) {
                updatePaper(paperId) { p in
                    p.pdfPath = "papers/\(newURL.lastPathComponent)"
                    p.pdfFilename = newURL.lastPathComponent
                }
            }
        } else {
            updatePaper(paperId) { p in
                p.importState = .unresolved
                p.dateModified = Date()
            }
        }

        // Step 6: Write index
        if let finalPaper = papers.first(where: { $0.id == paperId }) {
            try? indexService.save(finalPaper, in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }

    private func fetchMetadataWithFallback(identifiers: ParsedIdentifiers, extractedText: String?) async -> PaperMetadata? {
        // Try identifier-based lookup first (always attempt — provider decides what to do)
        if let metadata = try? await metadataProvider.fetchMetadata(for: identifiers) {
            return metadata
        }

        // Fall back to title search from extracted text
        if let text = extractedText {
            let roughTitle = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.count > 10 && $0.count < 200 } ?? ""
            if !roughTitle.isEmpty {
                if let metadata = try? await metadataProvider.searchByTitle(roughTitle) {
                    return metadata
                }
            }
        }

        return nil
    }

    private func updatePaper(_ id: UUID, transform: (inout Paper) -> Void) {
        guard let index = papers.firstIndex(where: { $0.id == id }) else { return }
        transform(&papers[index])
    }
}
