import Testing
import Foundation
@testable import Papyro

struct ProjectServiceTests {
    let fileManager = FileManager.default

    private func makeTempLibrary() throws -> URL {
        let directory = fileManager.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory.appendingPathComponent("papers"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: directory.appendingPathComponent("index"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: directory.appendingPathComponent(".symlinks"), withIntermediateDirectories: true)
        return directory
    }

    private func makePaper(id: UUID = UUID(), filename: String = "test.pdf") -> Paper {
        Paper(
            id: id,
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

    @Test func initializeCreatesInbox() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        let service = ProjectService(libraryRoot: libraryRoot)
        try service.initialize()

        #expect(service.projects.count == 1)
        #expect(service.projects[0].isInbox == true)
        #expect(service.projects[0].slug == "inbox")

        let data = try Data(contentsOf: libraryRoot.appendingPathComponent("projects.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let projects = try decoder.decode([Project].self, from: data)
        #expect(projects.count == 1)
        #expect(projects[0].isInbox == true)
        #expect(fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(".symlinks/inbox").path))
    }

    @Test func loadExistingProjects() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        let service1 = ProjectService(libraryRoot: libraryRoot)
        try service1.initialize()

        let service2 = ProjectService(libraryRoot: libraryRoot)
        try service2.loadProjects()

        #expect(service2.projects.count == 1)
        #expect(service2.projects[0].isInbox == true)
    }

    @Test func createProjectAddsToListAndDisk() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        let service = ProjectService(libraryRoot: libraryRoot)
        try service.initialize()

        let project = try service.createProject(name: "PhD Thesis")

        #expect(project.name == "PhD Thesis")
        #expect(project.slug == "phd-thesis")
        #expect(service.projects.count == 2)
        #expect(fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(".symlinks/phd-thesis").path))
    }

    @Test func createProjectWithDuplicateSlugAppendsSuffix() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        let service = ProjectService(libraryRoot: libraryRoot)
        try service.initialize()

        let project1 = try service.createProject(name: "My Project")
        let project2 = try service.createProject(name: "My Project")

        #expect(project1.slug == "my-project")
        #expect(project2.slug == "my-project-2")
    }

    @Test func deleteProjectRemovesAndOrphansPapersToInbox() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        fileManager.createFile(atPath: libraryRoot.appendingPathComponent("papers/test.pdf").path, contents: Data("dummy".utf8))

        let service = ProjectService(libraryRoot: libraryRoot)
        try service.initialize()
        let inbox = service.inbox

        let project = try service.createProject(name: "To Delete")
        var paper = makePaper(filename: "test.pdf")

        paper = try service.assignPaper(paper, to: project)
        #expect(!paper.projectIDs.contains(inbox.id))
        #expect(paper.projectIDs.contains(project.id))

        let updatedPapers = try service.deleteProject(id: project.id, papers: [paper])
        #expect(service.projects.count == 1)
        #expect(updatedPapers[0].projectIDs == [inbox.id])
    }

    @Test func assignPaperRemovesFromInbox() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        fileManager.createFile(atPath: libraryRoot.appendingPathComponent("papers/test.pdf").path, contents: Data("dummy".utf8))

        let service = ProjectService(libraryRoot: libraryRoot)
        try service.initialize()
        let inbox = service.inbox

        let project = try service.createProject(name: "My Project")
        var paper = makePaper(filename: "test.pdf")
        paper.projectIDs = [inbox.id]

        paper = try service.assignPaper(paper, to: project)
        #expect(paper.projectIDs.contains(project.id))
        #expect(!paper.projectIDs.contains(inbox.id))
    }

    @Test func unassignPaperReturnsToInboxWhenOrphaned() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        fileManager.createFile(atPath: libraryRoot.appendingPathComponent("papers/test.pdf").path, contents: Data("dummy".utf8))

        let service = ProjectService(libraryRoot: libraryRoot)
        try service.initialize()
        let inbox = service.inbox

        let project = try service.createProject(name: "My Project")
        var paper = makePaper(filename: "test.pdf")
        paper.projectIDs = [inbox.id]

        paper = try service.assignPaper(paper, to: project)
        paper = try service.unassignPaper(paper, from: project)

        #expect(paper.projectIDs == [inbox.id])
    }

    @Test func renameProjectUpdatesList() throws {
        let libraryRoot = try makeTempLibrary()
        defer { try? fileManager.removeItem(at: libraryRoot) }

        let service = ProjectService(libraryRoot: libraryRoot)
        try service.initialize()

        let project = try service.createProject(name: "Old Name")
        try service.renameProject(id: project.id, newName: "New Name")

        let renamed = service.projects.first(where: { $0.id == project.id })
        #expect(renamed?.name == "New Name")
        #expect(renamed?.slug == "new-name")
        #expect(fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(".symlinks/new-name").path))
        #expect(!fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(".symlinks/old-name").path))
    }
}
