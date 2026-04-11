import SwiftUI

@main
struct PapyroApp: App {
    @State private var appState: AppState
    @State private var libraryManager: LibraryManager
    @State private var importCoordinator: ImportCoordinator?
    @State private var externalCoordinator: ExternalChangeCoordinator?
    @State private var fileWatcher: FileSystemWatcher?
    @Environment(\.scenePhase) private var scenePhase

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
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, let extCoord = externalCoordinator else { return }
                Task { @MainActor in
                    await extCoord.reconcileIfNeeded()
                }
            }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                SettingsLink {
                    Text("Manage Linked Folders…")
                }
            }
        }

        Settings {
            Group {
                if let coordinator = importCoordinator {
                    SettingsView()
                        .environment(coordinator)
                } else {
                    SettingsView()
                }
            }
            .environment(appState)
        }
    }

    private func setupImportCoordinator(config: LibraryConfig) {
        // Resolve symlinks once so FSEvents paths and our prefix-stripping agree.
        let libraryRoot = URL(fileURLWithPath: config.libraryPath).resolvingSymlinksInPath()

        // Column/sort preferences are loaded from UserDefaults inside AppState.init.

        var providers: [MetadataProvider] = []
        if let serverURLString = config.translationServerURL,
           let serverURL = URL(string: serverURLString) {
            providers.append(TranslationServerProvider(serverURL: serverURL))
        }
        providers.append(CrossRefProvider())
        providers.append(SemanticScholarProvider())
        let metadataProvider: MetadataProvider = FallbackMetadataProvider(providers: providers)

        let projectService = ProjectService(libraryRoot: libraryRoot)
        // Load or initialize projects
        if FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent("projects.json").path) {
            try? projectService.loadProjects()
        } else {
            try? projectService.initialize()
        }

        let coordinator = ImportCoordinator(
            libraryRoot: libraryRoot,
            metadataProvider: metadataProvider,
            projectService: projectService,
            appState: appState
        )
        coordinator.loadExistingPapers()
        importCoordinator = coordinator

        // --- M6 external sync wiring ---
        let extCoord = ExternalChangeCoordinator(
            libraryRoot: libraryRoot,
            importCoordinator: coordinator
        )
        coordinator.externalChangeCoordinator = extCoord
        externalCoordinator = extCoord

        let watcher = FileSystemWatcher(
            directories: [
                libraryRoot.appendingPathComponent("papers"),
                libraryRoot.appendingPathComponent("index")
            ]
        ) { [weak appState] event in
            Task { @MainActor in
                switch event {
                case .pdfAdded(let url):
                    await extCoord.handlePDFAdded(url: url)
                case .pdfRemoved(let url):
                    await extCoord.handlePDFRemoved(url: url)
                case .indexModified(let url):
                    await extCoord.handleIndexModified(url: url)
                case .rootChanged:
                    appState?.userError = UserFacingError(
                        title: "Library folder moved",
                        message: "Papyro lost track of your library. Restart and choose it again from Settings."
                    )
                }
            }
        }
        if !watcher.start() {
            appState.userError = UserFacingError(
                title: "Live sync unavailable",
                message: "Papyro couldn't start filesystem monitoring. External changes will only be picked up when you relaunch."
            )
        }
        fileWatcher = watcher

        // Reconcile + initial drain (fire-and-forget; runs after this function returns on MainActor)
        Task { @MainActor in
            await extCoord.reconcile()
            if !coordinator.pendingPapers.isEmpty {
                await coordinator.resolveAllPending()
            }
        }
    }
}
