import Testing
import Foundation
@testable import Papyro

struct ExternalChangeCoordinatorTests {

    private func makeTempLibrary() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PapyroExt-\(UUID().uuidString)")
        for sub in ["papers", "index", "notes", ".symlinks", ".cache/text", "templates"] {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        return dir
    }

    @MainActor
    private func makeCoordinator(libraryRoot: URL) -> ImportCoordinator {
        let projectService = ProjectService(libraryRoot: libraryRoot)
        try? projectService.initialize()
        return ImportCoordinator(
            libraryRoot: libraryRoot,
            metadataProvider: FallbackMetadataProvider(providers: []),
            projectService: projectService
        )
    }

    @Test @MainActor func handlePDFAddedCreatesPendingPaper() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }
        let importer = makeCoordinator(libraryRoot: libRoot)
        let ext = ExternalChangeCoordinator(libraryRoot: libRoot, importCoordinator: importer)

        let pdfURL = libRoot.appendingPathComponent("papers/2401.12345.pdf")
        FileManager.default.createFile(atPath: pdfURL.path, contents: Data())

        await ext.handlePDFAdded(url: pdfURL)

        #expect(importer.papers.count == 1)
        let p = importer.papers[0]
        #expect(p.importState == .unresolved)
        #expect(p.metadataResolved == false)
        #expect(p.pdfPath == "papers/2401.12345.pdf")
    }

    @Test @MainActor func handlePDFAddedIsIdempotent() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }
        let importer = makeCoordinator(libraryRoot: libRoot)
        let ext = ExternalChangeCoordinator(libraryRoot: libRoot, importCoordinator: importer)

        let pdfURL = libRoot.appendingPathComponent("papers/dup.pdf")
        FileManager.default.createFile(atPath: pdfURL.path, contents: Data())

        await ext.handlePDFAdded(url: pdfURL)
        await ext.handlePDFAdded(url: pdfURL)

        #expect(importer.papers.count == 1)
    }

    @Test @MainActor func handlePDFRemovedDropsPaper() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }
        let importer = makeCoordinator(libraryRoot: libRoot)
        let ext = ExternalChangeCoordinator(libraryRoot: libRoot, importCoordinator: importer)

        let pdfURL = libRoot.appendingPathComponent("papers/gone.pdf")
        FileManager.default.createFile(atPath: pdfURL.path, contents: Data())
        await ext.handlePDFAdded(url: pdfURL)
        #expect(importer.papers.count == 1)

        try FileManager.default.removeItem(at: pdfURL)
        await ext.handlePDFRemoved(url: pdfURL)

        #expect(importer.papers.isEmpty)
    }

    @Test @MainActor func selfWriteGuardSuppresses() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }
        let importer = makeCoordinator(libraryRoot: libRoot)
        let ext = ExternalChangeCoordinator(libraryRoot: libRoot, importCoordinator: importer)

        let pdfURL = libRoot.appendingPathComponent("papers/ours.pdf")
        FileManager.default.createFile(atPath: pdfURL.path, contents: Data())

        ext.willWrite(at: pdfURL)
        await ext.handlePDFAdded(url: pdfURL)  // should be suppressed

        #expect(importer.papers.isEmpty)
    }

    @Test @MainActor func selfWriteGuardExpiresAfterTTL() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }
        let importer = makeCoordinator(libraryRoot: libRoot)
        let ext = ExternalChangeCoordinator(
            libraryRoot: libRoot,
            importCoordinator: importer,
            guardTTLMilliseconds: 100
        )

        let pdfURL = libRoot.appendingPathComponent("papers/expired.pdf")
        FileManager.default.createFile(atPath: pdfURL.path, contents: Data())

        ext.willWrite(at: pdfURL)
        try await Task.sleep(nanoseconds: 200_000_000)
        await ext.handlePDFAdded(url: pdfURL)

        #expect(importer.papers.count == 1)
    }
}
