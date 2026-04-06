// Papyro/Services/ImportCoordinator.swift
import Foundation

@Observable
@MainActor
class ImportCoordinator {
    private(set) var papers: [Paper] = []
    private(set) var isResolvingPending: Bool = false

    var pendingPapers: [Paper] {
        papers.filter { $0.importState == .unresolved }
    }

    private let libraryRoot: URL
    private let fileService: FileService
    private let textExtractor: TextExtractor
    private let identifierParser: IdentifierParser
    private let metadataProvider: MetadataProvider
    private let indexService: IndexService
    let projectService: ProjectService
    private let noteGenerator: NoteGenerator
    private weak var appState: AppState?
    weak var externalChangeCoordinator: ExternalChangeCoordinator?

    init(
        libraryRoot: URL,
        metadataProvider: MetadataProvider,
        projectService: ProjectService,
        appState: AppState? = nil,
        fileService: FileService = FileService(),
        textExtractor: TextExtractor = TextExtractor(),
        identifierParser: IdentifierParser = IdentifierParser(),
        indexService: IndexService = IndexService(),
        noteGenerator: NoteGenerator = NoteGenerator()
    ) {
        self.libraryRoot = libraryRoot
        self.metadataProvider = metadataProvider
        self.projectService = projectService
        self.appState = appState
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
                guardedSave(papers[i])
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
            appState?.userError = UserFacingError(
                title: "Couldn't import PDF",
                message: "\(sourceURL.lastPathComponent): \(error.localizedDescription)"
            )
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

            // Both the source and destination of the rename will fire FSEvents.
            externalChangeCoordinator?.willWrite(at: pdfURL)
            externalChangeCoordinator?.willWrite(
                at: pdfURL.deletingLastPathComponent().appendingPathComponent(newFilename))

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
            guardedSave(finalPaper)
            guardedRebuildCombined()
        }

        // Generate note (best-effort during import — surfacing this is alert spam)
        _ = createNote(for: paperId)
    }

    func retryMetadataLookup(for paperId: UUID) async {
        guard let paper = papers.first(where: { $0.id == paperId }),
              paper.importState == .unresolved else { return }

        let cachedText = textExtractor.loadCachedText(for: paperId, in: libraryRoot)
        let identifiers = cachedText.map { identifierParser.parse($0) } ?? ParsedIdentifiers()
        let pdfURL = libraryRoot.appendingPathComponent(paper.pdfPath)

        await resolveMetadata(paperId: paperId, pdfURL: pdfURL, identifiers: identifiers, extractedText: cachedText)
    }

    /// Drains every paper currently marked .unresolved through the same
    /// pipeline as a manual retry. Capped at 3 concurrent fetches.
    /// On per-item failure, the paper stays .unresolved and lastResolutionError
    /// is updated. The drain continues regardless of individual failures.
    func resolveAllPending() async {
        guard !isResolvingPending else { return }
        let toResolve = pendingPapers.map(\.id)
        guard !toResolve.isEmpty else { return }
        isResolvingPending = true
        defer { isResolvingPending = false }

        await withTaskGroup(of: Void.self) { group in
            var iterator = toResolve.makeIterator()

            func addNext() {
                guard let id = iterator.next() else { return }
                group.addTask { [weak self] in
                    await self?.resolveOnePending(paperId: id)
                }
            }

            // Prime up to 3 concurrent
            for _ in 0..<min(3, toResolve.count) { addNext() }

            for await _ in group {
                addNext()
            }
        }
    }

    private func resolveOnePending(paperId: UUID) async {
        let beforeState = papers.first(where: { $0.id == paperId })?.importState
        await retryMetadataLookup(for: paperId)
        guard let after = papers.first(where: { $0.id == paperId }) else { return }

        if after.importState == .unresolved && beforeState == .unresolved {
            // Retry didn't move it forward — record an error string.
            // TODO(post-M6): surface the real error from the metadata provider chain
            // instead of this static placeholder. retryMetadataLookup currently
            // discards the underlying error.
            updatePaper(paperId) { p in
                p.lastResolutionError = "Metadata lookup failed"
            }
            if let p = papers.first(where: { $0.id == paperId }) {
                guardedSave(p)
            }
        } else if after.importState == .resolved {
            // Second save is intentional: retryMetadataLookup already persisted the
            // resolved paper, but clearing lastResolutionError happens after its return.
            updatePaper(paperId) { p in p.lastResolutionError = nil }
            if let p = papers.first(where: { $0.id == paperId }) {
                guardedSave(p)
            }
        }
    }

    func createNote(for paperId: UUID) -> Result<URL, Error> {
        guard let index = papers.firstIndex(where: { $0.id == paperId }) else {
            return .failure(CocoaError(.fileNoSuchFile))
        }
        let paper = papers[index]
        do {
            let notePath = try noteGenerator.generateNote(for: paper, libraryRoot: libraryRoot)
            papers[index].notePath = notePath
            papers[index].dateModified = Date()
            // Downstream index writes are best-effort — see plan §6 / Risks.
            guardedSave(papers[index])
            guardedRebuildCombined()
            let noteURL = libraryRoot.appendingPathComponent(notePath)
            return .success(noteURL)
        } catch {
            return .failure(error)
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
            guardedSave(finalPaper)
            guardedRebuildCombined()
        }
    }

    func updatePaperStatus(paperId: UUID, status: ReadingStatus) {
        updatePaper(paperId) { p in
            p.status = status
            p.dateModified = Date()
        }
        if let paper = papers.first(where: { $0.id == paperId }) {
            guardedSave(paper)
            guardedRebuildCombined()
        }
    }

    func deletePaper(paperId: UUID) {
        guard let index = papers.firstIndex(where: { $0.id == paperId }) else { return }
        let paper = papers[index]
        // Guard the upcoming PDF Trash event (UI layer moves the file).
        let pdfURL = libraryRoot.appendingPathComponent(paper.pdfPath)
        externalChangeCoordinator?.willWrite(at: pdfURL)
        papers.remove(at: index)
        guardedDelete(paper)
        guardedRebuildCombined()
        if appState?.selectedPaperId == paperId {
            appState?.selectedPaperId = nil
        }
    }

    func assignPaperToProject(paperId: UUID, project: Project) throws {
        guard let index = papers.firstIndex(where: { $0.id == paperId }) else { return }
        let updated = try projectService.assignPaper(papers[index], to: project)
        papers[index] = updated
        // Downstream index writes are best-effort — see plan §6 / Risks.
        guardedSave(papers[index])
        guardedRebuildCombined()
    }

    func unassignPaperFromProject(paperId: UUID, project: Project) throws {
        guard let index = papers.firstIndex(where: { $0.id == paperId }) else { return }
        let updated = try projectService.unassignPaper(papers[index], from: project)
        papers[index] = updated
        guardedSave(papers[index])
        guardedRebuildCombined()
    }

    func deleteProject(id: UUID) {
        if let updatedPapers = try? projectService.deleteProject(id: id, papers: papers) {
            papers = updatedPapers
            for paper in papers {
                guardedSave(paper)
            }
            guardedRebuildCombined()
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

    private func guardedSave(_ paper: Paper) {
        let url = libraryRoot
            .appendingPathComponent("index/\(paper.id.uuidString).json")
        externalChangeCoordinator?.willWrite(at: url)
        try? indexService.save(paper, in: libraryRoot)
    }

    private func guardedRebuildCombined() {
        let url = libraryRoot.appendingPathComponent("index/_all.json")
        externalChangeCoordinator?.willWrite(at: url)
        try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
    }

    private func guardedDelete(_ paper: Paper) {
        let url = libraryRoot
            .appendingPathComponent("index/\(paper.id.uuidString).json")
        externalChangeCoordinator?.willWrite(at: url)
        try? indexService.delete(paper, in: libraryRoot)
    }

    /// Append a Paper produced by the external-sync layer (FileSystemWatcher).
    /// Idempotent: if a paper with the same `pdfPath` is already present, this
    /// is a no-op. Callers (ExternalChangeCoordinator, future reconcile) can
    /// safely re-invoke without producing duplicates.
    func addPaperFromExternalSync(_ paper: Paper) {
        if papers.contains(where: { $0.pdfPath == paper.pdfPath }) { return }
        papers.append(paper)
    }

    /// Replace a Paper in place when the external-sync layer reports an
    /// updated index file. No-op if the id is unknown — caller is responsible
    /// for choosing between this and addPaperFromExternalSync.
    func replaceFromExternalSync(_ paper: Paper) {
        guard let index = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        papers[index] = paper
    }
}
