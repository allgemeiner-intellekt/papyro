import Testing
import Foundation
@testable import Papyro

struct SymlinkServiceTests {
    let symlinkService = SymlinkService()
    let fileManager = FileManager.default

    private func makeTempLibrary() throws -> URL {
        let directory = fileManager.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory.appendingPathComponent("papers"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: directory.appendingPathComponent(".symlinks"), withIntermediateDirectories: true)
        return directory
    }

    private func createDummyPDF(named filename: String, in libraryRoot: URL) -> URL {
        let url = libraryRoot.appendingPathComponent("papers/\(filename)")
        fileManager.createFile(atPath: url.path, contents: Data("dummy".utf8))
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
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        let project = makeProject(slug: "phd-thesis")
        try symlinkService.createProjectFolder(project: project, in: libraryRoot)

        #expect(fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(".symlinks/phd-thesis").path))
    }

    @Test func addLinkCreatesSymlink() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        let project = makeProject(slug: "my-project")
        try symlinkService.createProjectFolder(project: project, in: libraryRoot)
        createDummyPDF(named: "2024_smith_test.pdf", in: libraryRoot)

        let paper = makePaper(filename: "2024_smith_test.pdf")
        try symlinkService.addLink(paper: paper, project: project, in: libraryRoot)

        let symlinkPath = libraryRoot.appendingPathComponent(".symlinks/my-project/2024_smith_test.pdf").path
        let attributes = try fileManager.attributesOfItem(atPath: symlinkPath)

        #expect(fileManager.fileExists(atPath: symlinkPath))
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
    }

    @Test func removeLinkDeletesSymlink() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        let project = makeProject(slug: "my-project")
        try symlinkService.createProjectFolder(project: project, in: libraryRoot)
        createDummyPDF(named: "2024_smith_test.pdf", in: libraryRoot)

        let paper = makePaper(filename: "2024_smith_test.pdf")
        try symlinkService.addLink(paper: paper, project: project, in: libraryRoot)
        try symlinkService.removeLink(paper: paper, project: project, in: libraryRoot)

        #expect(!fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(".symlinks/my-project/2024_smith_test.pdf").path))
    }

    @Test func deleteProjectFolderRemovesDirectory() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        let project = makeProject(slug: "to-delete")
        try symlinkService.createProjectFolder(project: project, in: libraryRoot)
        try symlinkService.deleteProjectFolder(project: project, in: libraryRoot)

        #expect(!fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(".symlinks/to-delete").path))
    }

    @Test func renameProjectFolderRenamesDirectory() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        let project = makeProject(slug: "old-name")
        try symlinkService.createProjectFolder(project: project, in: libraryRoot)
        try symlinkService.renameProjectFolder(oldSlug: "old-name", newSlug: "new-name", in: libraryRoot)

        #expect(!fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(".symlinks/old-name").path))
        #expect(fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(".symlinks/new-name").path))
    }

    @Test func rebuildAllRecreatesEverything() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        createDummyPDF(named: "paper1.pdf", in: libraryRoot)
        createDummyPDF(named: "paper2.pdf", in: libraryRoot)

        let inbox = makeProject(name: "Inbox", slug: "inbox", isInbox: true)
        let projectA = makeProject(name: "Project A", slug: "project-a")

        var paper1 = makePaper(filename: "paper1.pdf")
        paper1.projectIDs = [inbox.id]
        var paper2 = makePaper(filename: "paper2.pdf")
        paper2.projectIDs = [projectA.id]

        try symlinkService.rebuildAll(projects: [inbox, projectA], papers: [paper1, paper2], in: libraryRoot)

        #expect(fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(".symlinks/inbox/paper1.pdf").path))
        #expect(fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(".symlinks/project-a/paper2.pdf").path))
        #expect(!fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(".symlinks/inbox/paper2.pdf").path))
    }

    @Test func addLinkUsesRelativePath() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        let project = makeProject(slug: "my-project")
        try symlinkService.createProjectFolder(project: project, in: libraryRoot)
        createDummyPDF(named: "test.pdf", in: libraryRoot)

        let paper = makePaper(filename: "test.pdf")
        try symlinkService.addLink(paper: paper, project: project, in: libraryRoot)

        let symlinkPath = libraryRoot.appendingPathComponent(".symlinks/my-project/test.pdf").path
        let destination = try fileManager.destinationOfSymbolicLink(atPath: symlinkPath)
        #expect(destination == "../../papers/test.pdf")
    }
}
