import Testing
import Foundation
@testable import Papyro

@MainActor
struct ProjectServiceTests {
    let fm = FileManager.default

    private func makeTempLibrary() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("papers"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("index"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent(".symlinks"), withIntermediateDirectories: true)
        return dir
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
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()

        #expect(service.projects.count == 1)
        #expect(service.projects[0].isInbox == true)
        #expect(service.projects[0].slug == "inbox")

        // Verify projects.json was written
        let data = try Data(contentsOf: libRoot.appendingPathComponent("projects.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let projects = try decoder.decode([Project].self, from: data)
        #expect(projects.count == 1)
        #expect(projects[0].isInbox == true)

        // Verify .symlinks/inbox/ was created
        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/inbox").path))
    }

    @Test func loadExistingProjects() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        // Initialize to create projects.json
        let service1 = ProjectService(libraryRoot: libRoot)
        try service1.initialize()

        // Create a new service and load
        let service2 = ProjectService(libraryRoot: libRoot)
        try service2.loadProjects()
        #expect(service2.projects.count == 1)
        #expect(service2.projects[0].isInbox == true)
    }

    @Test func createProjectAddsToListAndDisk() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()

        let project = try service.createProject(name: "PhD Thesis")

        #expect(project.name == "PhD Thesis")
        #expect(project.slug == "phd-thesis")
        #expect(service.projects.count == 2) // inbox + new
        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/phd-thesis").path))
    }

    @Test func createProjectWithDuplicateSlugAppendsSuffix() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()

        let project1 = try service.createProject(name: "My Project")
        let project2 = try service.createProject(name: "My Project")

        #expect(project1.slug == "my-project")
        #expect(project2.slug == "my-project-2")
    }

    @Test func deleteProjectRemovesAndOrphansPapersToInbox() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        fm.createFile(atPath: libRoot.appendingPathComponent("papers/test.pdf").path, contents: "dummy".data(using: .utf8))

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()
        let inbox = service.inbox

        let project = try service.createProject(name: "To Delete")
        var paper = makePaper(filename: "test.pdf")

        // Assign to project (which removes from inbox)
        paper = try service.assignPaper(paper, to: project)
        #expect(!paper.projectIDs.contains(inbox.id))
        #expect(paper.projectIDs.contains(project.id))

        // Delete project — paper should go back to inbox
        let updatedPapers = try service.deleteProject(id: project.id, papers: [paper])
        #expect(service.projects.count == 1) // only inbox remains
        #expect(updatedPapers[0].projectIDs == [inbox.id])
    }

    @Test func assignPaperRemovesFromInbox() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        fm.createFile(atPath: libRoot.appendingPathComponent("papers/test.pdf").path, contents: "dummy".data(using: .utf8))

        let service = ProjectService(libraryRoot: libRoot)
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
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        fm.createFile(atPath: libRoot.appendingPathComponent("papers/test.pdf").path, contents: "dummy".data(using: .utf8))

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()
        let inbox = service.inbox

        let project = try service.createProject(name: "My Project")
        var paper = makePaper(filename: "test.pdf")
        paper.projectIDs = [inbox.id]

        paper = try service.assignPaper(paper, to: project)
        #expect(!paper.projectIDs.contains(inbox.id))

        paper = try service.unassignPaper(paper, from: project)
        #expect(paper.projectIDs == [inbox.id])
    }

    @Test func renameProjectUpdatesList() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()

        let project = try service.createProject(name: "Old Name")
        try service.renameProject(id: project.id, newName: "New Name")

        let renamed = service.projects.first { $0.id == project.id }
        #expect(renamed?.name == "New Name")
        #expect(renamed?.slug == "new-name")
        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/new-name").path))
        #expect(!fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/old-name").path))
    }

    @Test func unassignFromOneOfTwoProjectsDoesNotAddInbox() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        fm.createFile(atPath: libRoot.appendingPathComponent("papers/test.pdf").path, contents: "dummy".data(using: .utf8))

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()
        let inbox = service.inbox

        let projectA = try service.createProject(name: "Project A")
        let projectB = try service.createProject(name: "Project B")
        var paper = makePaper(filename: "test.pdf")
        paper.projectIDs = [inbox.id]

        // Assign to both projects
        paper = try service.assignPaper(paper, to: projectA)
        paper = try service.assignPaper(paper, to: projectB)
        #expect(paper.projectIDs.contains(projectA.id))
        #expect(paper.projectIDs.contains(projectB.id))
        #expect(!paper.projectIDs.contains(inbox.id))

        // Unassign from A — should still have B, no Inbox
        paper = try service.unassignPaper(paper, from: projectA)
        #expect(!paper.projectIDs.contains(projectA.id))
        #expect(paper.projectIDs.contains(projectB.id))
        #expect(!paper.projectIDs.contains(inbox.id))
    }
}
