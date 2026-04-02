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
            .onChange(of: appState.libraryConfig) { _, newConfig in
                if let config = newConfig {
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

        let metadataProvider: MetadataProvider
        if let serverURLString = config.translationServerURL,
           let serverURL = URL(string: serverURLString) {
            metadataProvider = TranslationServerProvider(serverURL: serverURL)
        } else {
            metadataProvider = CrossRefProvider()
        }

        let coordinator = ImportCoordinator(
            libraryRoot: libraryRoot,
            metadataProvider: metadataProvider
        )
        coordinator.loadExistingPapers()
        importCoordinator = coordinator
    }
}
