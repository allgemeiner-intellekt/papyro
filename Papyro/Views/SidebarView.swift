import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var isAddingProject = false
    @State private var newProjectName = ""
    @State private var renamingProjectID: UUID?
    @State private var renameText = ""

    private var projectService: ProjectService {
        coordinator.projectService
    }

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedSidebarItem) {
            // All Papers
            Label("All Papers", systemImage: "books.vertical")
                .tag(SidebarItem.allPapers)

            // Projects section
            Section {
                // Inbox (pinned)
                projectRow(projectService.inbox)

                // User projects (alphabetical)
                ForEach(projectService.userProjects) { project in
                    if renamingProjectID == project.id {
                        renameField(project: project)
                    } else {
                        projectRow(project)
                            .contextMenu {
                                Button("Rename") {
                                    renameText = project.name
                                    renamingProjectID = project.id
                                }
                                Button("Delete", role: .destructive) {
                                    coordinator.deleteProject(id: project.id)
                                }
                            }
                    }
                }

                if isAddingProject {
                    TextField("Project name", text: $newProjectName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !newProjectName.isEmpty {
                                try? projectService.createProject(name: newProjectName)
                            }
                            newProjectName = ""
                            isAddingProject = false
                        }
                        .onExitCommand {
                            newProjectName = ""
                            isAddingProject = false
                        }
                }
            } header: {
                HStack {
                    Text("Projects")
                    Spacer()
                    Button {
                        isAddingProject = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Status section
            Section("Status") {
                statusRow(.toRead)
                statusRow(.reading)
                statusRow(.archived)
            }
        }
        .navigationTitle("Papyro")
    }

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        let count = coordinator.papers.filter { $0.projectIDs.contains(project.id) }.count

        HStack {
            Label(project.name, systemImage: project.isInbox ? "tray" : "folder")
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tag(SidebarItem.project(project.id))
        .dropDestination(for: String.self) { paperIDStrings, _ in
            for idString in paperIDStrings {
                if let paperId = UUID(uuidString: idString) {
                    coordinator.assignPaperToProject(paperId: paperId, project: project)
                }
            }
            return !paperIDStrings.isEmpty
        }
    }

    @ViewBuilder
    private func statusRow(_ status: ReadingStatus) -> some View {
        let count = coordinator.papers.filter { $0.status == status }.count
        let isSelected = appState.selectedStatusFilter == status

        Button {
            if isSelected {
                appState.selectedStatusFilter = nil
            } else {
                appState.selectedStatusFilter = status
            }
        } label: {
            HStack {
                Image(systemName: status.iconName)
                    .foregroundStyle(status.color)
                Text(status.displayName)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func renameField(project: Project) -> some View {
        TextField("Project name", text: $renameText)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                if !renameText.isEmpty {
                    try? projectService.renameProject(id: project.id, newName: renameText)
                }
                renamingProjectID = nil
            }
            .onExitCommand {
                renamingProjectID = nil
            }
    }
}
