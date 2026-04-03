import Foundation

enum ProjectServiceError: Error {
    case missingInbox
    case emptyName
}

@Observable
final class ProjectService {
    private(set) var projects: [Project] = []

    private let libraryRoot: URL
    private let symlinkService: SymlinkService
    private let indexService: IndexService

    init(
        libraryRoot: URL,
        symlinkService: SymlinkService = SymlinkService(),
        indexService: IndexService = IndexService()
    ) {
        self.libraryRoot = libraryRoot
        self.symlinkService = symlinkService
        self.indexService = indexService
    }

    var inbox: Project {
        guard let inbox = projects.first(where: \.isInbox) else {
            preconditionFailure("ProjectService requires an Inbox project")
        }
        return inbox
    }

    var userProjects: [Project] {
        projects
            .filter { !$0.isInbox }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func initialize() throws {
        let inbox = Project.makeInbox()
        projects = [inbox]
        try persist()
        try symlinkService.createProjectFolder(project: inbox, in: libraryRoot)
    }

    func loadProjects() throws {
        let url = projectsURL
        let data = try Data(contentsOf: url)
        projects = try decoder.decode([Project].self, from: data)

        if !projects.contains(where: \.isInbox) {
            let inbox = Project.makeInbox()
            projects.insert(inbox, at: 0)
            try persist()
        }
    }

    @discardableResult
    func createProject(name: String) throws -> Project {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProjectServiceError.emptyName
        }

        let project = Project(
            id: UUID(),
            name: trimmedName,
            slug: uniqueSlug(from: trimmedName),
            isInbox: false,
            dateCreated: Date()
        )
        projects.append(project)
        try persist()
        try symlinkService.createProjectFolder(project: project, in: libraryRoot)
        return project
    }

    func renameProject(id: UUID, newName: String) throws {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProjectServiceError.emptyName
        }

        guard let index = projects.firstIndex(where: { $0.id == id }),
              !projects[index].isInbox else {
            return
        }

        let oldSlug = projects[index].slug
        let newSlug = uniqueSlug(from: trimmedName, excluding: id)

        projects[index].name = trimmedName
        projects[index].slug = newSlug
        try persist()
        try symlinkService.renameProjectFolder(oldSlug: oldSlug, newSlug: newSlug, in: libraryRoot)
    }

    func deleteProject(id: UUID, papers: [Paper]) throws -> [Paper] {
        guard let project = projects.first(where: { $0.id == id }),
              !project.isInbox else {
            return papers
        }

        var updatedPapers = papers
        var orphanedPapers: [Paper] = []

        for index in updatedPapers.indices where updatedPapers[index].projectIDs.contains(id) {
            updatedPapers[index].projectIDs.removeAll { $0 == id }
            if updatedPapers[index].projectIDs.isEmpty {
                updatedPapers[index].projectIDs = [inbox.id]
                orphanedPapers.append(updatedPapers[index])
            }
        }

        projects.removeAll { $0.id == id }
        try persist()
        try symlinkService.deleteProjectFolder(project: project, in: libraryRoot)

        for paper in orphanedPapers {
            try? symlinkService.addLink(paper: paper, project: inbox, in: libraryRoot)
        }

        return updatedPapers
    }

    func assignPaper(_ paper: Paper, to project: Project) throws -> Paper {
        guard projects.contains(where: { $0.id == project.id }) else {
            return paper
        }

        var updated = paper
        let hadInbox = updated.projectIDs.contains(inbox.id)

        if !updated.projectIDs.contains(project.id) {
            updated.projectIDs.append(project.id)
        }

        if !project.isInbox {
            updated.projectIDs.removeAll { $0 == inbox.id }
            if hadInbox {
                try? symlinkService.removeLink(paper: paper, project: inbox, in: libraryRoot)
            }
        }

        try symlinkService.addLink(paper: updated, project: project, in: libraryRoot)
        return updated
    }

    func unassignPaper(_ paper: Paper, from project: Project) throws -> Paper {
        guard !project.isInbox else {
            return paper
        }

        var updated = paper
        guard updated.projectIDs.contains(project.id) else {
            return paper
        }

        updated.projectIDs.removeAll { $0 == project.id }
        try symlinkService.removeLink(paper: paper, project: project, in: libraryRoot)

        if updated.projectIDs.isEmpty {
            updated.projectIDs = [inbox.id]
            try symlinkService.addLink(paper: updated, project: inbox, in: libraryRoot)
        }

        return updated
    }

    func rebuildSymlinks(papers: [Paper]) throws {
        try symlinkService.rebuildAll(projects: projects, papers: papers, in: libraryRoot)
    }

    private var projectsURL: URL {
        libraryRoot.appendingPathComponent("projects.json")
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func persist() throws {
        let data = try encoder.encode(projects.sorted(by: projectOrder))
        try data.write(to: projectsURL, options: .atomic)
        projects.sort(by: projectOrder)
    }

    private func uniqueSlug(from name: String, excluding excludedID: UUID? = nil) -> String {
        let base = Project.generateSlug(from: name)
        let existingSlugs = Set(
            projects
                .filter { $0.id != excludedID }
                .map(\.slug)
        )

        guard existingSlugs.contains(base) else {
            return base
        }

        var suffix = 2
        while existingSlugs.contains("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }

    private func projectOrder(_ lhs: Project, _ rhs: Project) -> Bool {
        if lhs.isInbox != rhs.isInbox {
            return lhs.isInbox
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
