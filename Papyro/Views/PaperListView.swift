import SwiftUI

struct PaperListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator
    @Environment(LibraryManager.self) private var libraryManager

    private var filteredPapers: [Paper] {
        coordinator.papers
            .filter(matchesSidebarSelection)
            .filter(matchesStatusSelection)
            .sorted(by: areInIncreasingOrder)
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            ColumnHeaderBar(
                visibleColumns: appState.visibleColumns,
                sortColumn: appState.sortColumn,
                sortAscending: appState.sortAscending,
                onTapColumn: { column in
                    if appState.sortColumn == column {
                        appState.sortAscending.toggle()
                    } else {
                        appState.sortColumn = column
                        appState.sortAscending = isDefaultAscending(column)
                    }
                },
                onToggleColumn: { column, isEnabled in
                    if isEnabled {
                        appState.visibleColumns.insert(column)
                    } else if appState.visibleColumns.count > 1 {
                        appState.visibleColumns.remove(column)
                    }
                }
            )

            if filteredPapers.isEmpty {
                ContentUnavailableView(
                    "No Papers",
                    systemImage: "doc.text",
                    description: Text(emptyStateMessage)
                )
            } else {
                List(filteredPapers, selection: $appState.selectedPaperId) { paper in
                    PaperRowView(
                        paper: paper,
                        visibleColumns: appState.visibleColumns,
                        projects: coordinator.projectService.projects
                    )
                        .tag(paper.id)
                        .draggable(paper.id.uuidString)
                        .contextMenu {
                            paperContextMenu(for: paper)
                        }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .dropDestination(for: URL.self) { urls, _ in
            let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            guard !pdfURLs.isEmpty else { return false }
            Task { await coordinator.importPDFs(pdfURLs) }
            return true
        }
        .onChange(of: appState.visibleColumns) {
            libraryManager.saveCurrentConfig()
        }
        .onChange(of: appState.sortColumn) {
            libraryManager.saveCurrentConfig()
        }
        .onChange(of: appState.sortAscending) {
            libraryManager.saveCurrentConfig()
        }
    }

    private var navigationTitle: String {
        switch appState.selectedSidebarItem {
        case .allPapers:
            return "All Papers"
        case .project(let id):
            return coordinator.projectService.projects.first(where: { $0.id == id })?.name ?? "Papers"
        }
    }

    private var emptyStateMessage: String {
        coordinator.papers.isEmpty
            ? "Drag and drop PDF files here to import them."
            : "No papers match the current filters."
    }

    private func matchesSidebarSelection(_ paper: Paper) -> Bool {
        switch appState.selectedSidebarItem {
        case .allPapers:
            return true
        case .project(let projectID):
            return paper.projectIDs.contains(projectID)
        }
    }

    private func matchesStatusSelection(_ paper: Paper) -> Bool {
        guard let status = appState.selectedStatusFilter else {
            return true
        }
        return paper.status == status
    }

    private func areInIncreasingOrder(_ lhs: Paper, _ rhs: Paper) -> Bool {
        let result = compare(lhs, rhs, by: appState.sortColumn)
        switch result {
        case .orderedAscending:
            return appState.sortAscending
        case .orderedDescending:
            return !appState.sortAscending
        case .orderedSame:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func compare(_ lhs: Paper, _ rhs: Paper, by column: PaperColumn) -> ComparisonResult {
        switch column {
        case .authors:
            return firstAuthorDisplayName(for: lhs).localizedCaseInsensitiveCompare(firstAuthorDisplayName(for: rhs))
        case .year:
            return compare(lhs.year ?? 0, rhs.year ?? 0)
        case .journal:
            return (lhs.journal ?? "").localizedCaseInsensitiveCompare(rhs.journal ?? "")
        case .status:
            return compare(lhs.status.sortOrder, rhs.status.sortOrder)
        case .dateAdded:
            return compare(lhs.dateAdded, rhs.dateAdded)
        case .dateModified:
            return compare(lhs.dateModified, rhs.dateModified)
        case .doi:
            return (lhs.doi ?? "").localizedCaseInsensitiveCompare(rhs.doi ?? "")
        case .arxivId:
            return (lhs.arxivId ?? "").localizedCaseInsensitiveCompare(rhs.arxivId ?? "")
        case .projects:
            return projectNames(for: lhs).localizedCaseInsensitiveCompare(projectNames(for: rhs))
        case .metadataSource:
            return lhs.metadataSource.rawValue.localizedCaseInsensitiveCompare(rhs.metadataSource.rawValue)
        case .pmid:
            return (lhs.pmid ?? "").localizedCaseInsensitiveCompare(rhs.pmid ?? "")
        case .isbn:
            return (lhs.isbn ?? "").localizedCaseInsensitiveCompare(rhs.isbn ?? "")
        }
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private func firstAuthorDisplayName(for paper: Paper) -> String {
        let firstAuthor = paper.authors.first ?? ""
        return firstAuthor.components(separatedBy: ",").first ?? firstAuthor
    }

    private func projectNames(for paper: Paper) -> String {
        paper.projectIDs
            .compactMap { id in coordinator.projectService.projects.first(where: { $0.id == id })?.name }
            .joined(separator: ", ")
    }

    private func isDefaultAscending(_ column: PaperColumn) -> Bool {
        switch column {
        case .dateAdded, .dateModified:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private func paperContextMenu(for paper: Paper) -> some View {
        Menu("Add to Project") {
            ForEach(coordinator.projectService.userProjects) { project in
                Button {
                    if paper.projectIDs.contains(project.id) {
                        coordinator.unassignPaperFromProject(paperId: paper.id, project: project)
                    } else {
                        coordinator.assignPaperToProject(paperId: paper.id, project: project)
                    }
                } label: {
                    if paper.projectIDs.contains(project.id) {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
        }

        Menu("Set Status") {
            ForEach(ReadingStatus.allCases, id: \.self) { status in
                Button {
                    coordinator.updatePaperStatus(paperId: paper.id, status: status)
                } label: {
                    if paper.status == status {
                        Label(status.displayName, systemImage: "checkmark")
                    } else {
                        Text(status.displayName)
                    }
                }
            }
        }

        Divider()

        Button("Open PDF") {
            openPDF(for: paper)
        }

        Button("Reveal in Finder") {
            revealInFinder(for: paper)
        }
    }

    private func openPDF(for paper: Paper) {
        guard let libraryPath = appState.libraryConfig?.libraryPath else { return }
        let url = URL(fileURLWithPath: libraryPath).appendingPathComponent(paper.pdfPath)
        NSWorkspace.shared.open(url)
    }

    private func revealInFinder(for paper: Paper) {
        guard let libraryPath = appState.libraryConfig?.libraryPath else { return }
        let url = URL(fileURLWithPath: libraryPath).appendingPathComponent(paper.pdfPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct ColumnHeaderBar: View {
    let visibleColumns: Set<PaperColumn>
    let sortColumn: PaperColumn
    let sortAscending: Bool
    let onTapColumn: (PaperColumn) -> Void
    let onToggleColumn: (PaperColumn, Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("Title")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(visibleColumnsInOrder, id: \.self) { column in
                Button {
                    onTapColumn(column)
                } label: {
                    HStack(spacing: 4) {
                        Text(column.displayName)
                        if sortColumn == column {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(sortColumn == column ? .primary : .secondary)
                    .frame(width: column.width, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.bar)
        .contextMenu {
            ForEach(PaperColumn.allCases) { column in
                Button {
                    onToggleColumn(column, !visibleColumns.contains(column))
                } label: {
                    if visibleColumns.contains(column) {
                        Label(column.displayName, systemImage: "checkmark")
                    } else {
                        Text(column.displayName)
                    }
                }
            }
        }
    }

    private var visibleColumnsInOrder: [PaperColumn] {
        PaperColumn.allCases.filter { visibleColumns.contains($0) }
    }
}
