import SwiftUI

@main
struct PapyroApp: App {
    @State private var appState: AppState
    @State private var libraryManager: LibraryManager
    @State private var importCoordinator: ImportCoordinator?

    init() {
        let state = AppState()
        _appState = State(initialValue: state)
        _libraryManager = State(initialValue: LibraryManager(appState: state))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isOnboarding {
                    WelcomeView()
                } else if let coordinator = importCoordinator {
                    MainView()
                        .environment(coordinator)
                } else {
                    ProgressView("Loading library...")
                }
            }
            .environment(appState)
            .environment(libraryManager)
            .onChange(of: appState.libraryConfig?.libraryPath) { _, newLibraryPath in
                if let newLibraryPath {
                    let config = appState.libraryConfig ?? LibraryConfig(version: 1, libraryPath: newLibraryPath, translationServerURL: nil)
                    setupImportCoordinator(config: config)
                }
            }
            .onAppear {
                libraryManager.detectExistingLibrary()
            }
        }
    }

    private func setupImportCoordinator(config: LibraryConfig) {
        let libraryRoot = URL(fileURLWithPath: config.libraryPath)

        if let columns = config.visibleColumns {
            appState.visibleColumns = Set(columns)
        }
        if let sortColumn = config.sortColumn {
            appState.sortColumn = sortColumn
        }
        if let sortAscending = config.sortAscending {
            appState.sortAscending = sortAscending
        }

        var providers: [MetadataProvider] = []
        if let serverURLString = config.translationServerURL,
           let serverURL = URL(string: serverURLString) {
            providers.append(TranslationServerProvider(serverURL: serverURL))
        }
        providers.append(CrossRefProvider())
        providers.append(SemanticScholarProvider())
        let metadataProvider: MetadataProvider = FallbackMetadataProvider(providers: providers)
        let projectService = ProjectService(libraryRoot: libraryRoot)

        if FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent("projects.json").path) {
            try? projectService.loadProjects()
        } else {
            try? projectService.initialize()
        }

        let coordinator = ImportCoordinator(
            libraryRoot: libraryRoot,
            metadataProvider: metadataProvider,
            projectService: projectService
        )
        coordinator.loadExistingPapers()
        importCoordinator = coordinator
    }
}
