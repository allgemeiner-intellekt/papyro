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

    @Test @MainActor func handlePDFAddedCreatesSymlinkInInbox() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }
        let importer = makeCoordinator(libraryRoot: libRoot)
        let ext = ExternalChangeCoordinator(libraryRoot: libRoot, importCoordinator: importer)

        let pdfURL = libRoot.appendingPathComponent("papers/with-symlink.pdf")
        FileManager.default.createFile(atPath: pdfURL.path, contents: Data())

        await ext.handlePDFAdded(url: pdfURL)

        let inboxSlug = importer.projectService.inbox.slug
        let symlinkURL = libRoot
            .appendingPathComponent(".symlinks/\(inboxSlug)/with-symlink.pdf")
        #expect(FileManager.default.fileExists(atPath: symlinkURL.path))
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

    @Test @MainActor func handleIndexModifiedReplacesPaper() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }
        let importer = makeCoordinator(libraryRoot: libRoot)
        let ext = ExternalChangeCoordinator(libraryRoot: libRoot, importCoordinator: importer)

        // Seed via the existing add path
        let pdfURL = libRoot.appendingPathComponent("papers/seeded.pdf")
        FileManager.default.createFile(atPath: pdfURL.path, contents: Data())
        await ext.handlePDFAdded(url: pdfURL)
        let originalId = importer.papers[0].id

        // Externally rewrite the index file with a new title
        var updated = importer.papers[0]
        updated.title = "Edited Externally"
        try IndexService().save(updated, in: libRoot)
        let indexURL = libRoot.appendingPathComponent("index/\(originalId.uuidString).json")

        await ext.handleIndexModified(url: indexURL)

        #expect(importer.papers.first?.title == "Edited Externally")
    }

    @Test @MainActor func handleIndexModifiedIgnoresCorruptJSON() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }
        let importer = makeCoordinator(libraryRoot: libRoot)
        let ext = ExternalChangeCoordinator(libraryRoot: libRoot, importCoordinator: importer)

        let pdfURL = libRoot.appendingPathComponent("papers/keep.pdf")
        FileManager.default.createFile(atPath: pdfURL.path, contents: Data())
        await ext.handlePDFAdded(url: pdfURL)
        let originalTitle = importer.papers[0].title
        let originalId = importer.papers[0].id

        let indexURL = libRoot.appendingPathComponent("index/\(originalId.uuidString).json")
        try "{ broken".write(to: indexURL, atomically: true, encoding: .utf8)

        await ext.handleIndexModified(url: indexURL)

        // In-memory copy must remain authoritative
        #expect(importer.papers.first?.title == originalTitle)
    }
}
