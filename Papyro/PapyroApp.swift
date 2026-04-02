import SwiftUI

@main
struct PapyroApp: App {
    @State private var appState: AppState
    @State private var libraryManager: LibraryManager

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
                } else {
                    MainView()
                }
            }
            .environment(appState)
            .environment(libraryManager)
            .onAppear {
                libraryManager.detectExistingLibrary()
            }
        }
    }
}
