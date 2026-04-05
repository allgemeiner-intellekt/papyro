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
    let projectService: ProjectService
    private let noteGenerator: NoteGenerator

    init(
        libraryRoot: URL,
        metadataProvider: MetadataProvider,
        projectService: ProjectService,
        fileService: FileService = FileService(),
        textExtractor: TextExtractor = TextExtractor(),
        identifierParser: IdentifierParser = IdentifierParser(),
        indexService: IndexService = IndexService(),
        noteGenerator: NoteGenerator = NoteGenerator()
    ) {
        self.libraryRoot = libraryRoot
        self.metadataProvider = metadataProvider
        self.projectService = projectService
        self.fileService = fileService
        self.textExtractor = textExtractor
        self.identifierParser = identifierParser
        self.indexService = indexService
        self.noteGenerator = noteGenerator
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

        // Migration: if papers have empty projectIDs, assign to Inbox
        let inboxID = projectService.inbox.id
        for i in papers.indices {
            if papers[i].projectIDs.isEmpty {
                papers[i].projectIDs = [inboxID]
                try? indexService.save(papers[i], in: libraryRoot)
            }
        }
    }

    func importPDFs(_ urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { await self.importSinglePDF(url) }
            }
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
        var paper = Paper(
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
            projectIDs: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .none,
            metadataResolved: false,
            importState: .importing
        )

        // Assign to Inbox
        if let assigned = try? projectService.assignPaper(paper, to: projectService.inbox) {
            paper = assigned
        }

        papers.append(paper)

        // Step 2: Extract text
        let extractedText = textExtractor.extractText(from: pdfURL)
        if let text = extractedText {
            try? textExtractor.cacheText(text, for: paperId, in: libraryRoot)
        }

        // Step 3: Parse identifiers
        let identifiers = extractedText.map { identifierParser.parse($0) } ?? ParsedIdentifiers()

        await resolveMetadata(paperId: paperId, pdfURL: pdfURL, identifiers: identifiers, extractedText: extractedText)
    }

    private func resolveMetadata(paperId: UUID, pdfURL: URL, identifiers: ParsedIdentifiers, extractedText: String?) async {
        updatePaper(paperId) { $0.importState = .resolving }

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

        if let finalPaper = papers.first(where: { $0.id == paperId }) {
            try? indexService.save(finalPaper, in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }

        // Generate note
        if let finalPaper = papers.first(where: { $0.id == paperId }) {
            if let notePath = try? noteGenerator.generateNote(for: finalPaper, libraryRoot: libraryRoot) {
                updatePaper(paperId) { $0.notePath = notePath }
                if let updated = papers.first(where: { $0.id == paperId }) {
                    try? indexService.save(updated, in: libraryRoot)
                    try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
                }
            }
        }
    }

    func retryMetadataLookup(for paperId: UUID) async {
        guard let paper = papers.first(where: { $0.id == paperId }),
              paper.importState == .unresolved else { return }

        let cachedText = textExtractor.loadCachedText(for: paperId, in: libraryRoot)
        let identifiers = cachedText.map { identifierParser.parse($0) } ?? ParsedIdentifiers()
        let pdfURL = libraryRoot.appendingPathComponent(paper.pdfPath)

        await resolveMetadata(paperId: paperId, pdfURL: pdfURL, identifiers: identifiers, extractedText: cachedText)
    }

    func createNote(for paperId: UUID) {
        guard let index = papers.firstIndex(where: { $0.id == paperId }) else { return }
        let paper = papers[index]
        if let notePath = try? noteGenerator.generateNote(for: paper, libraryRoot: libraryRoot) {
            papers[index].notePath = notePath
            papers[index].dateModified = Date()
            try? indexService.save(papers[index], in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }

    func updatePaperMetadata(
        paperId: UUID,
        title: String,
        authors: [String],
        year: Int?,
        journal: String?,
        doi: String?,
        abstract: String?
    ) {
        guard let paper = papers.first(where: { $0.id == paperId }) else { return }

        updatePaper(paperId) { p in
            p.title = title
            p.authors = authors
            p.year = year
            p.journal = journal
            p.doi = doi
            p.abstract = abstract
            p.metadataSource = .manual
            p.metadataResolved = true
            p.importState = .resolved
            p.dateModified = Date()
        }

        // Re-generate filename if metadata changed
        let firstAuthor = authors.first.flatMap { $0.components(separatedBy: ",").first }
        let newFilename = fileService.generateFilename(year: year, author: firstAuthor, title: title)
        let pdfURL = libraryRoot.appendingPathComponent(paper.pdfPath)

        if let newURL = try? fileService.renamePDF(from: pdfURL, to: newFilename) {
            updatePaper(paperId) { p in
                p.pdfPath = "papers/\(newURL.lastPathComponent)"
                p.pdfFilename = newURL.lastPathComponent
            }
        }

        if let finalPaper = papers.first(where: { $0.id == paperId }) {
            try? indexService.save(finalPaper, in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }

    func updatePaperStatus(paperId: UUID, status: ReadingStatus) {
        updatePaper(paperId) { p in
            p.status = status
            p.dateModified = Date()
        }
        if let paper = papers.first(where: { $0.id == paperId }) {
            try? indexService.save(paper, in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }

    func assignPaperToProject(paperId: UUID, project: Project) {
        guard let index = papers.firstIndex(where: { $0.id == paperId }) else { return }
        if let updated = try? projectService.assignPaper(papers[index], to: project) {
            papers[index] = updated
            try? indexService.save(papers[index], in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }

    func unassignPaperFromProject(paperId: UUID, project: Project) {
        guard let index = papers.firstIndex(where: { $0.id == paperId }) else { return }
        if let updated = try? projectService.unassignPaper(papers[index], from: project) {
            papers[index] = updated
            try? indexService.save(papers[index], in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }

    func deleteProject(id: UUID) {
        if let updatedPapers = try? projectService.deleteProject(id: id, papers: papers) {
            papers = updatedPapers
            for paper in papers {
                try? indexService.save(paper, in: libraryRoot)
            }
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
