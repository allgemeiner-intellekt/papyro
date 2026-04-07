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

    /// Timestamp of the most recent `reconcile()` call. Used by
    /// `reconcileIfNeeded()` to rate-limit focus-driven sweeps.
    private var lastReconcile: Date = .distantPast
    private let reconcileDebounce: TimeInterval = 2.0

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

    // MARK: - Reconciliation

    /// Calls `reconcile()` unless it ran within the debounce window. Cheap
    /// safety net for FSEvents misses (sandbox edge cases, sleep/wake, the
    /// app being suspended while files moved). Wired to scenePhase=.active.
    func reconcileIfNeeded() async {
        if Date().timeIntervalSince(lastReconcile) < reconcileDebounce { return }
        await reconcile()
    }

    /// Walks papers/ and the in-memory index, syncing them. Called once at
    /// launch (and after the watcher reports rootChanged recovery).
    func reconcile() async {
        lastReconcile = Date()
        guard let importer = importCoordinator else { return }

        // Discover every PDF under papers/, recursively.
        // FileManager enumeration is synchronous, so we collect them first.
        let foundPDFs = findAllPDFs()

        let foundRelPaths = Set(foundPDFs.map { relativePath(of: $0) })
        let knownRelPaths = Set(importer.papers.map(\.pdfPath))

        // Add orphan PDFs (on disk, not in index)
        for url in foundPDFs where !knownRelPaths.contains(relativePath(of: url)) {
            await handlePDFAdded(url: url)
        }

        // Remove ghost entries (in index, not on disk)
        let papersToCheck = importer.papers
        for paper in papersToCheck where !foundRelPaths.contains(paper.pdfPath) {
            let url = libraryRoot.appendingPathComponent(paper.pdfPath)
            await handlePDFRemoved(url: url)
        }
    }

    /// Helper to recursively find all PDF files under papers/.
    /// Synchronous because FileManager enumeration is synchronous.
    private func findAllPDFs() -> [URL] {
        let papersRoot = libraryRoot.appendingPathComponent("papers")
        let fm = FileManager.default
        var foundPDFs: [URL] = []

        if let enumerator = fm.enumerator(
            at: papersRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if url.pathExtension.lowercased() == "pdf" {
                    foundPDFs.append(url)
                }
            }
        }

        return foundPDFs
    }

    private func relativePath(of url: URL) -> String {
        let rootPath = libraryRoot.path.hasSuffix("/") ? libraryRoot.path : libraryRoot.path + "/"
        if url.path.hasPrefix(rootPath) {
            return String(url.path.dropFirst(rootPath.count))
        }
        return url.lastPathComponent
    }
}
