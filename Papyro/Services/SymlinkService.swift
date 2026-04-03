import Foundation

struct SymlinkService: Sendable {
    private nonisolated(unsafe) let fm = FileManager.default

    func createProjectFolder(project: Project, in libraryRoot: URL) throws {
        let folderURL = libraryRoot.appendingPathComponent(".symlinks/\(project.slug)")
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    func deleteProjectFolder(project: Project, in libraryRoot: URL) throws {
        let folderURL = libraryRoot.appendingPathComponent(".symlinks/\(project.slug)")
        if fm.fileExists(atPath: folderURL.path) {
            try fm.removeItem(at: folderURL)
        }
    }

    func renameProjectFolder(oldSlug: String, newSlug: String, in libraryRoot: URL) throws {
        let oldURL = libraryRoot.appendingPathComponent(".symlinks/\(oldSlug)")
        let newURL = libraryRoot.appendingPathComponent(".symlinks/\(newSlug)")
        try fm.moveItem(at: oldURL, to: newURL)
    }

    func addLink(paper: Paper, project: Project, in libraryRoot: URL) throws {
        let pdfURL = libraryRoot.appendingPathComponent(paper.pdfPath)
        guard fm.fileExists(atPath: pdfURL.path) else { return }

        let symlinkURL = libraryRoot
            .appendingPathComponent(".symlinks/\(project.slug)/\(paper.pdfFilename)")
        let relativePath = "../../\(paper.pdfPath)"
        try fm.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: relativePath)
    }

    func removeLink(paper: Paper, project: Project, in libraryRoot: URL) throws {
        let symlinkURL = libraryRoot
            .appendingPathComponent(".symlinks/\(project.slug)/\(paper.pdfFilename)")
        if fm.fileExists(atPath: symlinkURL.path) {
            try fm.removeItem(at: symlinkURL)
        }
    }

    func rebuildAll(projects: [Project], papers: [Paper], in libraryRoot: URL) throws {
        let symlinksRoot = libraryRoot.appendingPathComponent(".symlinks")
        let tempRoot = libraryRoot.appendingPathComponent(".symlinks-rebuilding")

        // Clean up any leftover temp directory
        if fm.fileExists(atPath: tempRoot.path) {
            try fm.removeItem(at: tempRoot)
        }
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        // Build in temp directory
        let projectMap = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        for project in projects {
            let folderURL = tempRoot.appendingPathComponent(project.slug)
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        for paper in papers {
            let pdfURL = libraryRoot.appendingPathComponent(paper.pdfPath)
            guard fm.fileExists(atPath: pdfURL.path) else { continue }

            for projectID in paper.projectIDs {
                if let project = projectMap[projectID] {
                    let symlinkURL = tempRoot
                        .appendingPathComponent("\(project.slug)/\(paper.pdfFilename)")
                    let relativePath = "../../\(paper.pdfPath)"
                    try fm.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: relativePath)
                }
            }
        }

        // Atomically swap: remove old, move temp into place
        if fm.fileExists(atPath: symlinksRoot.path) {
            try fm.removeItem(at: symlinksRoot)
        }
        try fm.moveItem(at: tempRoot, to: symlinksRoot)
    }
}
