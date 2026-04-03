import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var isAddingProject = false
    @State private var newProjectName = ""
    @State private var renamingProjectID: UUID?
    @State private var renameText = ""

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedSidebarItem) {
            Label("All Papers", systemImage: "books.vertical")
                .tag(SidebarItem.allPapers)

            Section {
                projectRow(projectService.inbox)

                ForEach(projectService.userProjects) { project in
                    if renamingProjectID == project.id {
                        renameField(for: project)
                    } else {
                        projectRow(project)
                            .contextMenu {
                                Button("Rename") {
                                    renameText = project.name
                                    renamingProjectID = project.id
                                }

                                Button("Delete", role: .destructive) {
                                    coordinator.deleteProject(id: project.id)
                                    if appState.selectedSidebarItem.projectID == project.id {
                                        appState.selectedSidebarItem = .allPapers
                                    }
                                }
                            }
                    }
                }

                if isAddingProject {
                    TextField("Project name", text: $newProjectName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            createProject()
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

            Section("Status") {
                statusRow(.toRead)
                statusRow(.reading)
                statusRow(.archived)
            }
        }
        .navigationTitle("Papyro")
    }

    private var projectService: ProjectService {
        coordinator.projectService
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
        .dropDestination(for: String.self) { draggedPaperIDs, _ in
            for string in draggedPaperIDs {
                if let paperID = UUID(uuidString: string) {
                    coordinator.assignPaperToProject(paperId: paperID, project: project)
                }
            }
            return !draggedPaperIDs.isEmpty
        }
    }

    @ViewBuilder
    private func statusRow(_ status: ReadingStatus) -> some View {
        let count = coordinator.papers.filter { $0.status == status }.count
        let isSelected = appState.selectedStatusFilter == status

        Button {
            appState.selectedStatusFilter = isSelected ? nil : status
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
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func renameField(for project: Project) -> some View {
        TextField("Project name", text: $renameText)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    try? projectService.renameProject(id: project.id, newName: trimmed)
                }
                renamingProjectID = nil
            }
            .onExitCommand {
                renamingProjectID = nil
            }
    }

    private func createProject() {
        let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            newProjectName = ""
            isAddingProject = false
            return
        }

        if let project = try? projectService.createProject(name: trimmed) {
            appState.selectedSidebarItem = .project(project.id)
        }
        newProjectName = ""
        isAddingProject = false
    }
}
