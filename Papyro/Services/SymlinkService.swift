import Foundation

struct SymlinkService {
    private let fileManager = FileManager.default

    func createProjectFolder(project: Project, in libraryRoot: URL) throws {
        let folderURL = libraryRoot.appendingPathComponent(".symlinks/\(project.slug)")
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    func deleteProjectFolder(project: Project, in libraryRoot: URL) throws {
        let folderURL = libraryRoot.appendingPathComponent(".symlinks/\(project.slug)")
        if itemExists(at: folderURL) {
            try fileManager.removeItem(at: folderURL)
        }
    }

    func renameProjectFolder(oldSlug: String, newSlug: String, in libraryRoot: URL) throws {
        guard oldSlug != newSlug else { return }

        let oldURL = libraryRoot.appendingPathComponent(".symlinks/\(oldSlug)")
        let newURL = libraryRoot.appendingPathComponent(".symlinks/\(newSlug)")

        if itemExists(at: oldURL) {
            if itemExists(at: newURL) {
                try fileManager.removeItem(at: newURL)
            }
            try fileManager.moveItem(at: oldURL, to: newURL)
        } else {
            try fileManager.createDirectory(at: newURL, withIntermediateDirectories: true)
        }
    }

    func addLink(paper: Paper, project: Project, in libraryRoot: URL) throws {
        try createProjectFolder(project: project, in: libraryRoot)

        let symlinkURL = libraryRoot.appendingPathComponent(".symlinks/\(project.slug)/\(paper.pdfFilename)")
        if itemExists(at: symlinkURL) {
            try fileManager.removeItem(at: symlinkURL)
        }

        let relativePath = "../../\(paper.pdfPath)"
        try fileManager.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: relativePath)
    }

    func removeLink(paper: Paper, project: Project, in libraryRoot: URL) throws {
        let symlinkURL = libraryRoot.appendingPathComponent(".symlinks/\(project.slug)/\(paper.pdfFilename)")
        if itemExists(at: symlinkURL) {
            try fileManager.removeItem(at: symlinkURL)
        }
    }

    func rebuildAll(projects: [Project], papers: [Paper], in libraryRoot: URL) throws {
        let symlinksRoot = libraryRoot.appendingPathComponent(".symlinks")

        if itemExists(at: symlinksRoot) {
            try fileManager.removeItem(at: symlinksRoot)
        }
        try fileManager.createDirectory(at: symlinksRoot, withIntermediateDirectories: true)

        let projectMap = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })

        for project in projects {
            try createProjectFolder(project: project, in: libraryRoot)
        }

        for paper in papers {
            for projectID in paper.projectIDs {
                guard let project = projectMap[projectID] else { continue }
                try addLink(paper: paper, project: project, in: libraryRoot)
            }
        }
    }

    private func itemExists(at url: URL) -> Bool {
        if fileManager.fileExists(atPath: url.path) {
            return true
        }
        return (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}
