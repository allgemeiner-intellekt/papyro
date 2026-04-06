// PapyroTests/PendingResolutionTests.swift
import Testing
import Foundation
@testable import Papyro

struct PendingResolutionTests {

    private func makeTempLibrary() throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        let subdirs = ["papers", "index", "notes", ".symlinks", ".cache/text", "templates"]
        for subdir in subdirs {
            try fm.createDirectory(at: dir.appendingPathComponent(subdir), withIntermediateDirectories: true)
        }
        return dir
    }

    @MainActor
    private func makeProjectService(libraryRoot: URL) throws -> ProjectService {
        let service = ProjectService(libraryRoot: libraryRoot)
        try service.initialize()
        return service
    }

    private func makeUnresolvedPaper(id: UUID = UUID(), title: String = "Unresolved Paper", pdfFilename: String = "paper.pdf") -> Paper {
        Paper(
            id: id,
            canonicalId: nil,
            title: title,
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

    @Test @MainActor func pendingPapersFiltersUnresolved() throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let projectService = try makeProjectService(libraryRoot: libRoot)
        let coordinator = ImportCoordinator(
            libraryRoot: libRoot,
            metadataProvider: FallbackMetadataProvider(providers: []),
            projectService: projectService
        )

        let paper1 = makeUnresolvedPaper(title: "Pending One", pdfFilename: "pending1.pdf")
        let paper2 = makeUnresolvedPaper(title: "Pending Two", pdfFilename: "pending2.pdf")

        try IndexService().save(paper1, in: libRoot)
        try IndexService().save(paper2, in: libRoot)

        coordinator.loadExistingPapers()

        #expect(coordinator.pendingPapers.count == 2)
        #expect(coordinator.pendingPapers.allSatisfy { $0.importState == .unresolved })
    }

    @Test @MainActor func resolveAllPendingMarksFailureWithErrorString() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let mock = MockMetadataProvider()
        mock.shouldThrow = true

        let projectService = try makeProjectService(libraryRoot: libRoot)
        let coordinator = ImportCoordinator(
            libraryRoot: libRoot,
            metadataProvider: mock,
            projectService: projectService
        )

        let paper = makeUnresolvedPaper(pdfFilename: "failing.pdf")
        try IndexService().save(paper, in: libRoot)
        coordinator.loadExistingPapers()

        #expect(coordinator.pendingPapers.count == 1)

        await coordinator.resolveAllPending()

        #expect(coordinator.pendingPapers.count == 1)
        #expect(coordinator.papers.first?.lastResolutionError != nil)
        #expect(coordinator.papers.first?.lastResolutionError == "Metadata lookup failed")
    }

    @Test @MainActor func resolveAllPendingClearsFlagOnSuccess() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let mock = MockMetadataProvider()
        let goodMetadata = PaperMetadata(
            title: "Successfully Resolved",
            authors: ["Author, Test"],
            year: 2024,
            journal: "Journal of Testing",
            doi: "10.1234/resolved",
            arxivId: nil,
            abstract: "An abstract",
            url: nil,
            source: .crossRef
        )
        mock.metadataToReturn = goodMetadata
        mock.searchResult = goodMetadata

        let projectService = try makeProjectService(libraryRoot: libRoot)
        let coordinator = ImportCoordinator(
            libraryRoot: libRoot,
            metadataProvider: mock,
            projectService: projectService
        )

        let paperId = UUID()
        let pdfFilename = "\(paperId.uuidString).pdf"
        let pdfURL = libRoot.appendingPathComponent("papers/\(pdfFilename)")
        // Create a stub PDF so retryMetadataLookup doesn't fail on missing file
        FileManager.default.createFile(atPath: pdfURL.path, contents: "stub pdf".data(using: .utf8))

        let paper = makeUnresolvedPaper(id: paperId, pdfFilename: pdfFilename)
        try IndexService().save(paper, in: libRoot)
        coordinator.loadExistingPapers()

        #expect(coordinator.pendingPapers.count == 1)

        await coordinator.resolveAllPending()

        #expect(coordinator.pendingPapers.isEmpty)
        #expect(coordinator.papers.first?.lastResolutionError == nil)
        #expect(coordinator.papers.first?.importState == .resolved)
    }

    @Test @MainActor func isResolvingPendingFlagToggles() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let mock = MockMetadataProvider()
        mock.shouldThrow = true

        let projectService = try makeProjectService(libraryRoot: libRoot)
        let coordinator = ImportCoordinator(
            libraryRoot: libRoot,
            metadataProvider: mock,
            projectService: projectService
        )

        let paper = makeUnresolvedPaper(pdfFilename: "toggle-test.pdf")
        try IndexService().save(paper, in: libRoot)
        coordinator.loadExistingPapers()

        #expect(coordinator.isResolvingPending == false)

        await coordinator.resolveAllPending()

        #expect(coordinator.isResolvingPending == false)
    }
}
