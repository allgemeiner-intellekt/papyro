import Testing
import Foundation
@testable import Papyro

struct SymlinkServiceTests {
    let symlinkService = SymlinkService()
    let fm = FileManager.default

    private func makeTempLibrary() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("papers"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent(".symlinks"), withIntermediateDirectories: true)
        return dir
    }

    private func createDummyPDF(named filename: String, in libraryRoot: URL) -> URL {
        let url = libraryRoot.appendingPathComponent("papers/\(filename)")
        fm.createFile(atPath: url.path, contents: "dummy".data(using: .utf8))
        return url
    }

    private func makeProject(name: String = "Test", slug: String = "test", isInbox: Bool = false) -> Project {
        Project(id: UUID(), name: name, slug: slug, isInbox: isInbox, dateCreated: Date())
    }

    private func makePaper(filename: String = "2024_smith_test.pdf") -> Paper {
        Paper(
            id: UUID(),
            canonicalId: nil,
            title: "Test",
            authors: [],
            year: nil,
            journal: nil,
            doi: nil,
            arxivId: nil,
            pmid: nil,
            isbn: nil,
            abstract: nil,
            url: nil,
            pdfPath: "papers/\(filename)",
            pdfFilename: filename,
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

    @Test func createProjectFolderCreatesDirectory() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let project = makeProject(slug: "phd-thesis")
        try symlinkService.createProjectFolder(project: project, in: libRoot)

        let folderPath = libRoot.appendingPathComponent(".symlinks/phd-thesis").path
        #expect(fm.fileExists(atPath: folderPath))
    }

    @Test func addLinkCreatesSymlink() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let project = makeProject(slug: "my-project")
        try symlinkService.createProjectFolder(project: project, in: libRoot)
        createDummyPDF(named: "2024_smith_test.pdf", in: libRoot)

        let paper = makePaper(filename: "2024_smith_test.pdf")
        try symlinkService.addLink(paper: paper, project: project, in: libRoot)

        let symlinkPath = libRoot.appendingPathComponent(".symlinks/my-project/2024_smith_test.pdf").path
        #expect(fm.fileExists(atPath: symlinkPath))

        // Verify it's actually a symlink
        let attrs = try fm.attributesOfItem(atPath: symlinkPath)
        #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
    }

    @Test func removeLinkDeletesSymlink() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let project = makeProject(slug: "my-project")
        try symlinkService.createProjectFolder(project: project, in: libRoot)
        createDummyPDF(named: "2024_smith_test.pdf", in: libRoot)

        let paper = makePaper(filename: "2024_smith_test.pdf")
        try symlinkService.addLink(paper: paper, project: project, in: libRoot)
        try symlinkService.removeLink(paper: paper, project: project, in: libRoot)

        let symlinkPath = libRoot.appendingPathComponent(".symlinks/my-project/2024_smith_test.pdf").path
        #expect(!fm.fileExists(atPath: symlinkPath))
    }

    @Test func deleteProjectFolderRemovesDirectory() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let project = makeProject(slug: "to-delete")
        try symlinkService.createProjectFolder(project: project, in: libRoot)
        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/to-delete").path))

        try symlinkService.deleteProjectFolder(project: project, in: libRoot)
        #expect(!fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/to-delete").path))
    }

    @Test func renameProjectFolderRenamesDirectory() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let project = makeProject(slug: "old-name")
        try symlinkService.createProjectFolder(project: project, in: libRoot)

        try symlinkService.renameProjectFolder(oldSlug: "old-name", newSlug: "new-name", in: libRoot)

        #expect(!fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/old-name").path))
        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/new-name").path))
    }

    @Test func rebuildAllRecreatesEverything() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        createDummyPDF(named: "paper1.pdf", in: libRoot)
        createDummyPDF(named: "paper2.pdf", in: libRoot)

        let inbox = makeProject(name: "Inbox", slug: "inbox", isInbox: true)
        let projectA = makeProject(name: "Project A", slug: "project-a")

        var paper1 = makePaper(filename: "paper1.pdf")
        paper1.projectIDs = [inbox.id]
        var paper2 = makePaper(filename: "paper2.pdf")
        paper2.projectIDs = [projectA.id]

        try symlinkService.rebuildAll(
            projects: [inbox, projectA],
            papers: [paper1, paper2],
            in: libRoot
        )

        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/inbox/paper1.pdf").path))
        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/project-a/paper2.pdf").path))
        #expect(!fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/inbox/paper2.pdf").path))
    }

    @Test func addLinkUsesRelativePath() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let project = makeProject(slug: "my-project")
        try symlinkService.createProjectFolder(project: project, in: libRoot)
        createDummyPDF(named: "test.pdf", in: libRoot)

        let paper = makePaper(filename: "test.pdf")
        try symlinkService.addLink(paper: paper, project: project, in: libRoot)

        let symlinkPath = libRoot.appendingPathComponent(".symlinks/my-project/test.pdf").path
        let destination = try fm.destinationOfSymbolicLink(atPath: symlinkPath)
        #expect(destination == "../../papers/test.pdf")
    }
}
