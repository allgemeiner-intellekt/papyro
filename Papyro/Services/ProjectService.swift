import Foundation

@Observable
@MainActor
class ProjectService {
    private(set) var projects: [Project] = []

    private let libraryRoot: URL
    private let symlinkService: SymlinkService
    private let indexService: IndexService

    private var encoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    private var decoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    var inbox: Project {
        if let existing = projects.first(where: { $0.isInbox }) {
            return existing
        }
        let newInbox = Project.makeInbox()
        projects.insert(newInbox, at: 0)
        try? persist()
        return newInbox
    }

    var userProjects: [Project] {
        projects.filter { !$0.isInbox }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    init(
        libraryRoot: URL,
        symlinkService: SymlinkService = SymlinkService(),
        indexService: IndexService = IndexService()
    ) {
        self.libraryRoot = libraryRoot
        self.symlinkService = symlinkService
        self.indexService = indexService
    }

    func initialize() throws {
        let inbox = Project.makeInbox()
        projects = [inbox]
        try persist()
        try symlinkService.createProjectFolder(project: inbox, in: libraryRoot)
    }

    func loadProjects() throws {
        let url = libraryRoot.appendingPathComponent("projects.json")
        let data = try Data(contentsOf: url)
        projects = try decoder.decode([Project].self, from: data)
    }

    @discardableResult
    func createProject(name: String) throws -> Project {
        var slug = Project.generateSlug(from: name)
        let existingSlugs = Set(projects.map(\.slug))
        if existingSlugs.contains(slug) {
            var counter = 2
            while existingSlugs.contains("\(slug)-\(counter)") {
                counter += 1
            }
            slug = "\(slug)-\(counter)"
        }

        let project = Project(
            id: UUID(),
            name: name,
            slug: slug,
            isInbox: false,
            dateCreated: Date()
        )
        projects.append(project)
        try persist()
        try symlinkService.createProjectFolder(project: project, in: libraryRoot)
        return project
    }

    func renameProject(id: UUID, newName: String) throws {
        guard let index = projects.firstIndex(where: { $0.id == id }),
              !projects[index].isInbox else { return }

        let oldSlug = projects[index].slug
        let newSlug = Project.generateSlug(from: newName)

        projects[index].name = newName
        projects[index].slug = newSlug
        try persist()
        try symlinkService.renameProjectFolder(oldSlug: oldSlug, newSlug: newSlug, in: libraryRoot)
    }

    func deleteProject(id: UUID, papers: [Paper]) throws -> [Paper] {
        guard let project = projects.first(where: { $0.id == id }),
              !project.isInbox else { return papers }

        var updatedPapers = papers
        for i in updatedPapers.indices {
            if updatedPapers[i].projectIDs.contains(id) {
                updatedPapers[i].projectIDs.removeAll { $0 == id }
                if updatedPapers[i].projectIDs.isEmpty {
                    updatedPapers[i].projectIDs.append(inbox.id)
                }
            }
        }

        projects.removeAll { $0.id == id }
        try persist()
        try symlinkService.deleteProjectFolder(project: project, in: libraryRoot)
        return updatedPapers
    }

    func assignPaper(_ paper: Paper, to project: Project) throws -> Paper {
        var updated = paper
        if !updated.projectIDs.contains(project.id) {
            updated.projectIDs.append(project.id)
        }
        // Auto-remove from Inbox when assigning to a non-Inbox project
        if !project.isInbox {
            updated.projectIDs.removeAll { $0 == inbox.id }
        }
        try symlinkService.addLink(paper: updated, project: project, in: libraryRoot)
        return updated
    }

    func unassignPaper(_ paper: Paper, from project: Project) throws -> Paper {
        guard !project.isInbox else { return paper }

        var updated = paper
        updated.projectIDs.removeAll { $0 == project.id }
        // Auto-add to Inbox if no projects left
        if updated.projectIDs.isEmpty {
            updated.projectIDs.append(inbox.id)
            try symlinkService.addLink(paper: updated, project: inbox, in: libraryRoot)
        }
        try symlinkService.removeLink(paper: paper, project: project, in: libraryRoot)
        return updated
    }

    func rebuildSymlinks(papers: [Paper]) throws {
        try symlinkService.rebuildAll(projects: projects, papers: papers, in: libraryRoot)
    }

    private func persist() throws {
        let url = libraryRoot.appendingPathComponent("projects.json")
        let data = try encoder.encode(projects)
        try data.write(to: url, options: .atomic)
    }
}
