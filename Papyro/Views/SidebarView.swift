import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedSidebarItem) {
            Label("All Papers", systemImage: "books.vertical")
                .tag(SidebarItem.allPapers)
        }
        .navigationTitle("Papyro")
    }
}
