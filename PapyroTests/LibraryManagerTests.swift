import Testing
import Foundation
@testable import Papyro

struct LibraryManagerTests {
    @Test @MainActor func setupLibraryCreatesFoldersAndConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let suiteName = "PapyroTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState()
        let manager = LibraryManager(appState: appState)

        try manager.setupLibrary(at: tempDir, using: defaults)

        // Verify folders exist
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: tempDir.appendingPathComponent("papers").path))
        #expect(fm.fileExists(atPath: tempDir.appendingPathComponent("index").path))
        #expect(fm.fileExists(atPath: tempDir.appendingPathComponent("notes").path))
        #expect(fm.fileExists(atPath: tempDir.appendingPathComponent(".symlinks").path))
        #expect(fm.fileExists(atPath: tempDir.appendingPathComponent(".cache/text").path))
        #expect(fm.fileExists(atPath: tempDir.appendingPathComponent("templates").path))

        // Verify config.json exists and is valid
        let configURL = tempDir.appendingPathComponent("config.json")
        #expect(fm.fileExists(atPath: configURL.path))

        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(LibraryConfig.self, from: data)
        #expect(config.version == 1)
        #expect(config.libraryPath == tempDir.path)
        #expect(config.translationServerURL == nil)

        // Verify app state was updated
        #expect(appState.isOnboarding == false)
        #expect(appState.libraryConfig != nil)

        // Verify projects.json was created
        let projectsURL = tempDir.appendingPathComponent("projects.json")
        #expect(fm.fileExists(atPath: projectsURL.path))
    }

    @Test @MainActor func detectExistingLibraryReturnsNilWhenNoPath() throws {
        let appState = AppState()
        let manager = LibraryManager(appState: appState)

        // Use a custom UserDefaults suite to avoid polluting real defaults
        let suiteName = "PapyroTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let result = manager.detectExistingLibrary(using: defaults)
        #expect(result == false)
        #expect(appState.isOnboarding == true)
    }

    @Test @MainActor func detectExistingLibraryLoadsValidPath() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appState = AppState()
        let manager = LibraryManager(appState: appState)

        // Set up a library first (use a throwaway defaults for setup)
        let setupSuiteName = "PapyroTest-\(UUID().uuidString)"
        let setupDefaults = UserDefaults(suiteName: setupSuiteName)!
        defer { setupDefaults.removePersistentDomain(forName: setupSuiteName) }
        try manager.setupLibrary(at: tempDir, using: setupDefaults)

        // Reset state to simulate a fresh launch
        appState.isOnboarding = true
        appState.libraryConfig = nil

        // Save path to a test-specific UserDefaults
        let suiteName = "PapyroTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(tempDir.path, forKey: "libraryPath")

        let result = manager.detectExistingLibrary(using: defaults)
        #expect(result == true)
        #expect(appState.isOnboarding == false)
        #expect(appState.libraryConfig?.libraryPath == tempDir.path)
    }
}
