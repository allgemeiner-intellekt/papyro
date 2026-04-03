import Foundation

@Observable
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
        let config = LibraryConfig(
            version: 1,
            libraryPath: path.path,
            translationServerURL: nil,
            visibleColumns: Array(PaperColumn.defaultVisible),
            sortColumn: .dateAdded,
            sortAscending: false
        )
        let data = try encoder.encode(config)
        try data.write(to: path.appendingPathComponent("config.json"))

        let projectService = ProjectService(libraryRoot: path)
        try projectService.initialize()

        // Save to UserDefaults
        defaults.set(path.path, forKey: "libraryPath")

        // Update app state
        appState.libraryConfig = config
        appState.visibleColumns = Set(config.visibleColumns ?? Array(PaperColumn.defaultVisible))
        appState.sortColumn = config.sortColumn ?? .dateAdded
        appState.sortAscending = config.sortAscending ?? false
        appState.isOnboarding = false
    }

    func loadLibrary(from path: URL) throws {
        let configURL = path.appendingPathComponent("config.json")
        let data = try Data(contentsOf: configURL)
        let config = try decoder.decode(LibraryConfig.self, from: data)

        appState.libraryConfig = config
        appState.visibleColumns = Set(config.visibleColumns ?? Array(PaperColumn.defaultVisible))
        appState.sortColumn = config.sortColumn ?? .dateAdded
        appState.sortAscending = config.sortAscending ?? false
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

    func saveCurrentConfig() {
        guard let existingConfig = appState.libraryConfig else { return }

        let updatedConfig = LibraryConfig(
            version: existingConfig.version,
            libraryPath: existingConfig.libraryPath,
            translationServerURL: existingConfig.translationServerURL,
            visibleColumns: PaperColumn.allCases.filter { appState.visibleColumns.contains($0) },
            sortColumn: appState.sortColumn,
            sortAscending: appState.sortAscending
        )

        do {
            let data = try encoder.encode(updatedConfig)
            try data.write(to: URL(fileURLWithPath: updatedConfig.libraryPath).appendingPathComponent("config.json"), options: .atomic)
            appState.libraryConfig = updatedConfig
        } catch {
            return
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        JSONDecoder()
    }
}
