import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var isAddingProject = false
    @State private var newProjectName = ""
    @State private var renamingProjectID: UUID?
    @State private var renameText = ""
    @State private var isProjectsExpanded = true
    @State private var isStatusExpanded = true
    @State private var isProjectsHeaderHovered = false
    @State private var isStatusHeaderHovered = false
    @State private var hoveredStatus: ReadingStatus?
    @State private var projectToDelete: Project?
    @FocusState private var isNewProjectFieldFocused: Bool

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
                if isProjectsExpanded {
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
                                        projectToDelete = project
                                    }
                                }
                        }
                    }

                    if isAddingProject {
                        TextField("Project name", text: $newProjectName)
                            .textFieldStyle(.roundedBorder)
                            .focused($isNewProjectFieldFocused)
                            .onSubmit {
                                if !newProjectName.isEmpty {
                                    do {
                                        try projectService.createProject(name: newProjectName)
                                    } catch {
                                        appState.userError = UserFacingError(
                                            title: "Couldn't create project",
                                            message: error.localizedDescription
                                        )
                                    }
                                }
                                newProjectName = ""
                                isAddingProject = false
                            }
                            .onExitCommand {
                                newProjectName = ""
                                isAddingProject = false
                            }
                            .onChange(of: isNewProjectFieldFocused) { _, focused in
                                appState.isEditingText = focused
                                if !focused {
                                    newProjectName = ""
                                    isAddingProject = false
                                }
                            }
                    }
                }
            } header: {
                sectionHeader("Projects", isExpanded: $isProjectsExpanded, isHovered: $isProjectsHeaderHovered) {
                    Button {
                        isAddingProject = true
                        isNewProjectFieldFocused = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 7)
                }
            }
            .collapsible(false)

            // Status section
            Section {
                if isStatusExpanded {
                    statusRow(.toRead)
                    statusRow(.reading)
                    statusRow(.archived)
                }
            } header: {
                sectionHeader("Status", isExpanded: $isStatusExpanded, isHovered: $isStatusHeaderHovered)
            }
            .collapsible(false)
        }
        .navigationTitle("Papyro")
        .alert(item: $projectToDelete) { project in
            Alert(
                title: Text("Delete Project?"),
                message: Text("Papers will remain in your library but will be moved to Inbox."),
                primaryButton: .destructive(Text("Delete")) {
                    if appState.selectedSidebarItem.projectID == project.id {
                        appState.selectedSidebarItem = .allPapers
                    }
                    coordinator.deleteProject(id: project.id)
                },
                secondaryButton: .cancel {
                    projectToDelete = nil
                }
            )
        }
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
                    do {
                        try coordinator.assignPaperToProject(paperId: paperId, project: project)
                    } catch {
                        appState.userError = UserFacingError(
                            title: "Couldn't assign project",
                            message: error.localizedDescription
                        )
                    }
                }
            }
            return !paperIDStrings.isEmpty
        }
    }

    @ViewBuilder
    private func statusRow(_ status: ReadingStatus) -> some View {
        let count = coordinator.papers.filter { $0.status == status }.count
        let isSelected = appState.selectedStatusFilter == status
        let isHovered = hoveredStatus == status

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
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? status.color.opacity(0.12) : (isHovered ? status.color.opacity(0.15) : .clear))
                .padding(.leading, -6)
                .padding(.trailing, -6)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredStatus = hovering ? status : nil
            }
        }
        .onTapGesture {
            if isSelected {
                appState.selectedStatusFilter = nil
            } else {
                appState.selectedStatusFilter = status
            }
        }
    }

    @ViewBuilder
    private func sectionHeader<Actions: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        isHovered: Binding<Bool>,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isHovered.wrappedValue ? .secondary : .tertiary)
                .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                .frame(width: 10)

            Text(title)

            Spacer()

            actions()
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered.wrappedValue ? Color.primary.opacity(0.06) : .clear)
                .shadow(color: .black.opacity(isHovered.wrappedValue ? 0.08 : 0), radius: 2, y: 1)
                .padding(.leading, -4)
                .padding(.trailing, 8)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered.wrappedValue = hovering
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        }
    }

    @ViewBuilder
    private func renameField(project: Project) -> some View {
        TextField("Project name", text: $renameText)
            .textFieldStyle(.roundedBorder)
            .onAppear { appState.isEditingText = true }
            .onDisappear { appState.isEditingText = false }
            .onSubmit {
                if !renameText.isEmpty {
                    do {
                        try projectService.renameProject(id: project.id, newName: renameText)
                    } catch {
                        appState.userError = UserFacingError(
                            title: "Couldn't rename project",
                            message: error.localizedDescription
                        )
                    }
                }
                renamingProjectID = nil
            }
            .onExitCommand {
                renamingProjectID = nil
            }
    }
}
