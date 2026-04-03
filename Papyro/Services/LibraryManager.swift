import Foundation

@Observable
@MainActor
class LibraryManager {
    private let appState: AppState
    private let fileManager = FileManager.default

    private let subdirectories = ["papers", "index", "notes", ".symlinks", ".cache/text", "templates"]

    init(appState: AppState) {
        self.appState = appState
    }

    func setupLibrary(at path: URL, using defaults: UserDefaults = .standard) throws {
        // Create subdirectories
        for subdir in subdirectories {
            try fileManager.createDirectory(
                at: path.appendingPathComponent(subdir),
                withIntermediateDirectories: true
            )
        }

        // Write config.json
        let config = LibraryConfig(version: 1, libraryPath: path.path, translationServerURL: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(config)
        try data.write(to: path.appendingPathComponent("config.json"))

        // Initialize projects.json with Inbox
        let projectService = ProjectService(libraryRoot: path)
        try projectService.initialize()

        // Save to UserDefaults
        defaults.set(path.path, forKey: "libraryPath")

        // Update app state
        appState.libraryConfig = config
        appState.isOnboarding = false
    }

    func loadLibrary(from path: URL) throws {
        let configURL = path.appendingPathComponent("config.json")
        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(LibraryConfig.self, from: data)

        appState.libraryConfig = config
        appState.isOnboarding = false
    }

    @discardableResult
    func detectExistingLibrary(using defaults: UserDefaults = .standard) -> Bool {
        guard let path = defaults.string(forKey: "libraryPath") else {
            return false
        }

        let url = URL(fileURLWithPath: path)
        let configURL = url.appendingPathComponent("config.json")

        guard fileManager.fileExists(atPath: configURL.path) else {
            return false
        }

        do {
            try loadLibrary(from: url)
            return true
        } catch {
            return false
        }
    }
}
