import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView(selectedCategory: $appState.selectedCategory)
        } content: {
            PaperListView(category: appState.selectedCategory)
        } detail: {
            DetailView()
        }
    }
}
