import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var showNewProjectPrompt = false
    @State private var newProjectName = ""
    @State private var showDeleteConfirmation = false
    @State private var showHealthBanner = false

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView()
        } content: {
            PaperListView()
        } detail: {
            DetailView()
        }
        .overlay(alignment: .top) {
            if showHealthBanner {
                healthBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
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
        .onKeyPress("e", phases: .down) { press in
            guard press.modifiers == .command else { return .ignored }
            return openOrCreateNote()
        }
        .onAppear {
            if appState.symlinkHealthIssueCount > 0 {
                withAnimation { showHealthBanner = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    withAnimation { showHealthBanner = false }
                }
            }
        }
    }

    @ViewBuilder
    private var healthBanner: some View {
        let count = appState.symlinkHealthIssueCount
        Button {
            showHealthBanner = false
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("\(count) linked \(count == 1 ? "folder" : "folders") \(count == 1 ? "needs" : "need") attention")
                    .font(.callout)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func openOrCreateNote() -> KeyPress.Result {
        guard !appState.isEditingText else { return .ignored }
        guard let paperId = appState.selectedPaperId else { return .ignored }
        guard let paper = coordinator.papers.first(where: { $0.id == paperId }) else { return .ignored }

        if let notePath = paper.notePath, let config = appState.libraryConfig {
            let noteURL = URL(fileURLWithPath: config.libraryPath).appendingPathComponent(notePath)
            if FileManager.default.fileExists(atPath: noteURL.path) {
                NSWorkspace.shared.open(noteURL)
                return .handled
            }
        }

        coordinator.createNote(for: paperId)
        if let updatedPaper = coordinator.papers.first(where: { $0.id == paperId }),
           let notePath = updatedPaper.notePath,
           let config = appState.libraryConfig {
            let noteURL = URL(fileURLWithPath: config.libraryPath).appendingPathComponent(notePath)
            NSWorkspace.shared.open(noteURL)
        }
        return .handled
    }

    private func setSelectedPaperStatus(_ status: ReadingStatus) -> KeyPress.Result {
        guard !appState.isEditingText else { return .ignored }
        guard let paperId = appState.selectedPaperId else { return .ignored }
        coordinator.updatePaperStatus(paperId: paperId, status: status)
        return .handled
    }
}
