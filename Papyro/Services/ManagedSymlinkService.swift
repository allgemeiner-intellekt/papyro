import Foundation

enum SymlinkHealth: Equatable, Sendable {
    case healthy
    case destinationMissing
    case broken
}

struct ManagedSymlinkService: Sendable {
    private nonisolated(unsafe) let fm = FileManager.default

    func createLink(sourceRelativePath: String, destinationPath: String, libraryRoot: URL) throws -> ManagedSymlink {
        let sourceAbsolutePath = libraryRoot.appendingPathComponent(sourceRelativePath).path
        try fm.createSymbolicLink(atPath: destinationPath, withDestinationPath: sourceAbsolutePath)

        let sourceName = URL(fileURLWithPath: sourceRelativePath).lastPathComponent
        let destName = URL(fileURLWithPath: destinationPath).lastPathComponent
        let label = "\(sourceName) → \(destName)"

        return ManagedSymlink(
            id: UUID(),
            sourceRelativePath: sourceRelativePath,
            destinationPath: destinationPath,
            label: label,
            createdAt: Date()
        )
    }

    func removeLink(_ symlink: ManagedSymlink) throws {
        if fm.fileExists(atPath: symlink.destinationPath) {
            try fm.removeItem(atPath: symlink.destinationPath)
        }
    }

    func repairLink(_ symlink: ManagedSymlink, newDestinationPath: String, libraryRoot: URL) throws -> ManagedSymlink {
        if fm.fileExists(atPath: symlink.destinationPath) {
            try fm.removeItem(atPath: symlink.destinationPath)
        }

        let sourceAbsolutePath = libraryRoot.appendingPathComponent(symlink.sourceRelativePath).path
        try fm.createSymbolicLink(atPath: newDestinationPath, withDestinationPath: sourceAbsolutePath)

        let destName = URL(fileURLWithPath: newDestinationPath).lastPathComponent
        let sourceName = URL(fileURLWithPath: symlink.sourceRelativePath).lastPathComponent

        var repaired = symlink
        repaired.destinationPath = newDestinationPath
        repaired.label = "\(sourceName) → \(destName)"
        return repaired
    }

    func checkHealth(_ symlink: ManagedSymlink) -> SymlinkHealth {
        let attrs = try? fm.attributesOfItem(atPath: symlink.destinationPath)
        guard let fileType = attrs?[.type] as? FileAttributeType,
              fileType == .typeSymbolicLink else {
            return .broken
        }

        let resolvedPath = try? fm.destinationOfSymbolicLink(atPath: symlink.destinationPath)
        guard let resolved = resolvedPath else {
            return .broken
        }

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: resolved, isDirectory: &isDir) {
            return .healthy
        } else {
            return .destinationMissing
        }
    }

    func checkAllHealth(_ symlinks: [ManagedSymlink]) -> [(ManagedSymlink, SymlinkHealth)] {
        symlinks.map { ($0, checkHealth($0)) }
    }
}
