// Papyro/Services/ExternalChangeCoordinator.swift
import Foundation
import Observation

/// Translates filesystem events from FileSystemWatcher into ImportCoordinator
/// mutations. Owns the self-write guard so events caused by Papyro's own
/// writes are ignored.
@Observable
@MainActor
final class ExternalChangeCoordinator {
    private let libraryRoot: URL
    private weak var importCoordinator: ImportCoordinator?
    private let guardTTL: TimeInterval
    private let indexService = IndexService()

    /// Map of absolute path → expiration date. Entries older than now are stale.
    private var writeGuard: [String: Date] = [:]

    init(
        libraryRoot: URL,
        importCoordinator: ImportCoordinator,
        guardTTLMilliseconds: Int = 1500
    ) {
        self.libraryRoot = libraryRoot
        self.importCoordinator = importCoordinator
        self.guardTTL = TimeInterval(guardTTLMilliseconds) / 1000.0
    }

    // MARK: - Self-write guard

    func willWrite(at url: URL) {
        let path = url.path
        writeGuard[path] = Date().addingTimeInterval(guardTTL)
    }

    private func consumeGuard(for url: URL) -> Bool {
        let now = Date()
        // Drop expired entries
        writeGuard = writeGuard.filter { $0.value > now }
        if let expires = writeGuard[url.path], expires > now {
            writeGuard.removeValue(forKey: url.path)
            return true
        }
        return false
    }

    // MARK: - Event handlers

    func handlePDFAdded(url: URL) async {
        if consumeGuard(for: url) { return }
        guard let importer = importCoordinator else { return }

        let relPath = relativePath(of: url)
        if importer.papers.contains(where: { $0.pdfPath == relPath }) {
            return  // idempotent
        }

        var paper = Paper(
            id: UUID(),
            canonicalId: nil,
            title: url.deletingPathExtension().lastPathComponent,
            authors: [],
            year: nil, journal: nil, doi: nil, arxivId: nil,
            pmid: nil, isbn: nil, abstract: nil, url: nil,
            pdfPath: relPath,
            pdfFilename: url.lastPathComponent,
            notePath: nil,
            projectIDs: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .none,
            metadataResolved: false,
            importState: .unresolved,
            lastResolutionError: nil
        )

        // Route Inbox assignment through ProjectService so the symlink in
        // .symlinks/inbox/ is created. Direct projectIDs injection would set the
        // paper-side state but skip the symlink layer (see ProjectService.assignPaper).
        if let assigned = try? importer.projectService.assignPaper(paper, to: importer.projectService.inbox) {
            paper = assigned
        }

        importer.addPaperFromExternalSync(paper)
        try? indexService.save(paper, in: libraryRoot)
        try? indexService.rebuildCombinedIndex(from: importer.papers, in: libraryRoot)
    }

    func handlePDFRemoved(url: URL) async {
        if consumeGuard(for: url) { return }
        guard let importer = importCoordinator else { return }

        let relPath = relativePath(of: url)
        guard let paper = importer.papers.first(where: { $0.pdfPath == relPath }) else { return }
        importer.deletePaper(paperId: paper.id)
    }

    func handleIndexModified(url: URL) async {
        if consumeGuard(for: url) { return }
        guard let importer = importCoordinator else { return }

        do {
            guard let updated = try indexService.loadOne(at: url) else {
                // Corrupt JSON or unreadable — leave in-memory authoritative.
                return
            }
            if importer.papers.contains(where: { $0.id == updated.id }) {
                importer.replaceFromExternalSync(updated)
            } else {
                importer.addPaperFromExternalSync(updated)
            }
        } catch {
            // Corrupt JSON or unreadable — leave in-memory authoritative.
            return
        }
    }

    private func relativePath(of url: URL) -> String {
        let rootPath = libraryRoot.path.hasSuffix("/") ? libraryRoot.path : libraryRoot.path + "/"
        if url.path.hasPrefix(rootPath) {
            return String(url.path.dropFirst(rootPath.count))
        }
        return url.lastPathComponent
    }
}
