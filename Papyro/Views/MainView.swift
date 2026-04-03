import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var showNewProjectPrompt = false
    @State private var newProjectName = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
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
                createProject()
            }
            Button("Cancel", role: .cancel) {
                newProjectName = ""
            }
        }
        .alert("Delete Project?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                guard let projectID = appState.selectedSidebarItem.projectID else { return }
                coordinator.deleteProject(id: projectID)
                appState.selectedSidebarItem = .allPapers
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Papers will stay in your library and return to Inbox if needed.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Project") {
                        showNewProjectPrompt = true
                    }
                    .keyboardShortcut("N", modifiers: [.command, .shift])

                    Button("Rebuild Symlinks") {
                        try? coordinator.projectService.rebuildSymlinks(papers: coordinator.papers)
                    }

                    Button("Delete Project", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .disabled(!canDeleteSelectedProject)
                    .keyboardShortcut(.delete, modifiers: [.command])
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onKeyPress("1") { setSelectedPaperStatus(.toRead) }
        .onKeyPress("2") { setSelectedPaperStatus(.reading) }
        .onKeyPress("3") { setSelectedPaperStatus(.archived) }
    }

    private var canDeleteSelectedProject: Bool {
        guard let projectID = appState.selectedSidebarItem.projectID else { return false }
        return coordinator.projectService.projects.contains(where: { $0.id == projectID && !$0.isInbox })
    }

    private func createProject() {
        let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            newProjectName = ""
            return
        }
        let project = try? coordinator.projectService.createProject(name: trimmed)
        if let project {
            appState.selectedSidebarItem = .project(project.id)
        }
        newProjectName = ""
    }

    private func setSelectedPaperStatus(_ status: ReadingStatus) -> KeyPress.Result {
        guard let selectedPaperId = appState.selectedPaperId else { return .ignored }
        coordinator.updatePaperStatus(paperId: selectedPaperId, status: status)
        return .handled
    }
}
