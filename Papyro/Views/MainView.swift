import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var showNewProjectPrompt = false
    @State private var newProjectName = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView()
        } content: {
            PaperListView()
        } detail: {
            DetailView()
        }
        .alert("New Project", isPresented: $showNewProjectPrompt) {
            TextField("Project name", text: $newProjectName)
            Button("Create") {
                if !newProjectName.isEmpty {
                    try? coordinator.projectService.createProject(name: newProjectName)
                }
                newProjectName = ""
            }
            Button("Cancel", role: .cancel) {
                newProjectName = ""
            }
        }
        .alert("Delete Project?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let projectID = appState.selectedSidebarItem.projectID {
                    coordinator.deleteProject(id: projectID)
                    appState.selectedSidebarItem = .allPapers
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Papers will remain in your library but will be moved to Inbox.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Project") {
                        showNewProjectPrompt = true
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])

                    Button("Rebuild Symlinks") {
                        try? coordinator.projectService.rebuildSymlinks(papers: coordinator.papers)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onKeyPress("1") {
            setSelectedPaperStatus(.toRead)
        }
        .onKeyPress("2") {
            setSelectedPaperStatus(.reading)
        }
        .onKeyPress("3") {
            setSelectedPaperStatus(.archived)
        }
    }

    private func setSelectedPaperStatus(_ status: ReadingStatus) -> KeyPress.Result {
        guard let paperId = appState.selectedPaperId else { return .ignored }
        coordinator.updatePaperStatus(paperId: paperId, status: status)
        return .handled
    }
}
