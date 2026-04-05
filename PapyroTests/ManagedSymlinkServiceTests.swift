import Testing
import Foundation
@testable import Papyro

struct ManagedSymlinkServiceTests {
    let fm = FileManager.default

    private func makeTempDir(_ name: String = "PapyroTest") -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func createLinkCreatesSymlinkAtDestination() throws {
        let libRoot = makeTempDir("lib")
        let destParent = makeTempDir("dest")
        defer { try? fm.removeItem(at: libRoot) }
        defer { try? fm.removeItem(at: destParent) }

        let notesDir = libRoot.appendingPathComponent("notes")
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let destPath = destParent.appendingPathComponent("Papyro Notes").path
        let service = ManagedSymlinkService()
        let symlink = try service.createLink(
            sourceRelativePath: "notes",
            destinationPath: destPath,
            libraryRoot: libRoot
        )

        #expect(symlink.sourceRelativePath == "notes")
        #expect(symlink.destinationPath == destPath)
        #expect(symlink.label.contains("notes"))

        var isDir: ObjCBool = false
        #expect(fm.fileExists(atPath: destPath, isDirectory: &isDir))

        let resolved = try fm.destinationOfSymbolicLink(atPath: destPath)
        #expect(resolved == notesDir.path)
    }

    @Test func removeLinkDeletesSymlinkFromDisk() throws {
        let libRoot = makeTempDir("lib")
        let destParent = makeTempDir("dest")
        defer { try? fm.removeItem(at: libRoot) }
        defer { try? fm.removeItem(at: destParent) }

        let notesDir = libRoot.appendingPathComponent("notes")
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let destPath = destParent.appendingPathComponent("Papyro Notes").path
        let service = ManagedSymlinkService()
        let symlink = try service.createLink(
            sourceRelativePath: "notes",
            destinationPath: destPath,
            libraryRoot: libRoot
        )

        try service.removeLink(symlink)
        #expect(!fm.fileExists(atPath: destPath))
    }

    @Test func checkHealthReturnsHealthyForValidSymlink() throws {
        let libRoot = makeTempDir("lib")
        let destParent = makeTempDir("dest")
        defer { try? fm.removeItem(at: libRoot) }
        defer { try? fm.removeItem(at: destParent) }

        let notesDir = libRoot.appendingPathComponent("notes")
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let destPath = destParent.appendingPathComponent("Papyro Notes").path
        let service = ManagedSymlinkService()
        let symlink = try service.createLink(
            sourceRelativePath: "notes",
            destinationPath: destPath,
            libraryRoot: libRoot
        )

        let health = service.checkHealth(symlink)
        #expect(health == .healthy)
    }

    @Test func checkHealthReturnsBrokenWhenSymlinkRemoved() throws {
        let libRoot = makeTempDir("lib")
        let destParent = makeTempDir("dest")
        defer { try? fm.removeItem(at: libRoot) }
        defer { try? fm.removeItem(at: destParent) }

        let notesDir = libRoot.appendingPathComponent("notes")
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let destPath = destParent.appendingPathComponent("Papyro Notes").path
        let service = ManagedSymlinkService()
        let symlink = try service.createLink(
            sourceRelativePath: "notes",
            destinationPath: destPath,
            libraryRoot: libRoot
        )

        try fm.removeItem(atPath: destPath)

        let health = service.checkHealth(symlink)
        #expect(health == .broken)
    }

    @Test func checkHealthReturnsDestinationMissingWhenSourceRemoved() throws {
        let libRoot = makeTempDir("lib")
        let destParent = makeTempDir("dest")
        defer { try? fm.removeItem(at: libRoot) }
        defer { try? fm.removeItem(at: destParent) }

        let notesDir = libRoot.appendingPathComponent("notes")
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let destPath = destParent.appendingPathComponent("Papyro Notes").path
        let service = ManagedSymlinkService()
        let symlink = try service.createLink(
            sourceRelativePath: "notes",
            destinationPath: destPath,
            libraryRoot: libRoot
        )

        try fm.removeItem(at: notesDir)

        let health = service.checkHealth(symlink)
        #expect(health == .destinationMissing)
    }

    @Test func repairLinkUpdatesDestination() throws {
        let libRoot = makeTempDir("lib")
        let destParent = makeTempDir("dest")
        let newDestParent = makeTempDir("newdest")
        defer { try? fm.removeItem(at: libRoot) }
        defer { try? fm.removeItem(at: destParent) }
        defer { try? fm.removeItem(at: newDestParent) }

        let notesDir = libRoot.appendingPathComponent("notes")
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let destPath = destParent.appendingPathComponent("Papyro Notes").path
        let service = ManagedSymlinkService()
        let symlink = try service.createLink(
            sourceRelativePath: "notes",
            destinationPath: destPath,
            libraryRoot: libRoot
        )

        let newDestPath = newDestParent.appendingPathComponent("New Notes").path
        let repaired = try service.repairLink(symlink, newDestinationPath: newDestPath, libraryRoot: libRoot)

        #expect(repaired.destinationPath == newDestPath)
        #expect(!fm.fileExists(atPath: destPath))
        #expect(fm.fileExists(atPath: newDestPath))
    }
}
