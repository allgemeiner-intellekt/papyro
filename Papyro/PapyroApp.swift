import SwiftUI

@main
struct PapyroApp: App {
    @State private var appState = AppState()
    @State private var libraryManager: LibraryManager?

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
            .environment(libraryManager ?? LibraryManager(appState: appState))
            .onAppear {
                if libraryManager == nil {
                    libraryManager = LibraryManager(appState: appState)
                }
                libraryManager?.detectExistingLibrary()
            }
        }
    }
}
