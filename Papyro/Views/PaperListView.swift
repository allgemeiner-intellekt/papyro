import SwiftUI

struct PaperListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    private var filteredPapers: [Paper] {
        var result = coordinator.papers

        // Filter by sidebar selection
        switch appState.selectedSidebarItem {
        case .allPapers:
            break
        case .project(let projectID):
            result = result.filter { $0.projectIDs.contains(projectID) }
        }

        // Filter by status
        if let status = appState.selectedStatusFilter {
            result = result.filter { $0.status == status }
        }

        // Sort
        result.sort { a, b in
            let ascending = appState.sortAscending
            let cmp: Bool
            switch appState.sortColumn {
            case .authors:
                let aAuthor = a.authors.first ?? ""
                let bAuthor = b.authors.first ?? ""
                cmp = aAuthor.localizedCaseInsensitiveCompare(bAuthor) == .orderedAscending
            case .year:
                cmp = (a.year ?? 0) < (b.year ?? 0)
            case .journal:
                cmp = (a.journal ?? "").localizedCaseInsensitiveCompare(b.journal ?? "") == .orderedAscending
            case .status:
                cmp = a.status.sortOrder < b.status.sortOrder
            case .dateAdded:
                cmp = a.dateAdded < b.dateAdded
            case .dateModified:
                cmp = a.dateModified < b.dateModified
            case .doi:
                cmp = (a.doi ?? "") < (b.doi ?? "")
            case .arxivId:
                cmp = (a.arxivId ?? "") < (b.arxivId ?? "")
            case .pmid:
                cmp = (a.pmid ?? "") < (b.pmid ?? "")
            case .isbn:
                cmp = (a.isbn ?? "") < (b.isbn ?? "")
            case .projects, .metadataSource:
                cmp = a.dateAdded < b.dateAdded
            }
            return ascending ? cmp : !cmp
        }

        return result
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Column header bar
            ColumnHeaderBar(
                visibleColumns: appState.visibleColumns,
                sortColumn: appState.sortColumn,
                sortAscending: appState.sortAscending,
                onTapColumn: { column in
                    if appState.sortColumn == column {
                        appState.sortAscending.toggle()
                    } else {
                        appState.sortColumn = column
                        appState.sortAscending = true
                    }
                },
                onToggleColumn: { column, isOn in
                    if isOn {
                        appState.visibleColumns.insert(column)
                    } else {
                        appState.visibleColumns.remove(column)
                    }
                }
            )

            if filteredPapers.isEmpty {
                ContentUnavailableView(
                    "No Papers",
                    systemImage: "doc.text",
                    description: Text("Drag and drop PDF files here to import them.")
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
                        paperContextMenu(paper: paper)
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
    }

    private var navigationTitle: String {
        switch appState.selectedSidebarItem {
        case .allPapers:
            "All Papers"
        case .project(let id):
            coordinator.projectService.projects.first { $0.id == id }?.name ?? "Papers"
        }
    }

    @ViewBuilder
    private func paperContextMenu(paper: Paper) -> some View {
        Menu("Add to Project") {
            ForEach(coordinator.projectService.userProjects) { project in
                Button {
                    if paper.projectIDs.contains(project.id) {
                        coordinator.unassignPaperFromProject(paperId: paper.id, project: project)
                    } else {
                        coordinator.assignPaperToProject(paperId: paper.id, project: project)
                    }
                } label: {
                    HStack {
                        Text(project.name)
                        if paper.projectIDs.contains(project.id) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Menu("Set Status") {
            ForEach([ReadingStatus.toRead, .reading, .archived], id: \.self) { status in
                Button {
                    coordinator.updatePaperStatus(paperId: paper.id, status: status)
                } label: {
                    HStack {
                        Text(status.displayName)
                        if paper.status == status {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()

        Button("Open PDF") {
            if let config = appState.libraryConfig {
                let pdfURL = URL(fileURLWithPath: config.libraryPath)
                    .appendingPathComponent(paper.pdfPath)
                NSWorkspace.shared.open(pdfURL)
            }
        }

        Button("Reveal in Finder") {
            if let config = appState.libraryConfig {
                let pdfURL = URL(fileURLWithPath: config.libraryPath)
                    .appendingPathComponent(paper.pdfPath)
                NSWorkspace.shared.activateFileViewerSelecting([pdfURL])
            }
        }
    }
}

// MARK: - Column Header Bar

private struct ColumnHeaderBar: View {
    let visibleColumns: Set<PaperColumn>
    let sortColumn: PaperColumn
    let sortAscending: Bool
    let onTapColumn: (PaperColumn) -> Void
    let onToggleColumn: (PaperColumn, Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Title column (no sort — always present)
            Spacer()
                .frame(maxWidth: .infinity)

            ForEach(sortedVisibleColumns, id: \.self) { column in
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
                }
                .buttonStyle(.plain)
                .frame(width: columnWidth(for: column), alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .contextMenu {
            ForEach(PaperColumn.allCases) { column in
                Toggle(column.displayName, isOn: Binding(
                    get: { visibleColumns.contains(column) },
                    set: { isOn in
                        onToggleColumn(column, isOn)
                    }
                ))
            }
        }
    }

    private var sortedVisibleColumns: [PaperColumn] {
        PaperColumn.allCases.filter { visibleColumns.contains($0) }
    }

    private func columnWidth(for column: PaperColumn) -> CGFloat {
        switch column {
        case .authors: 120
        case .year: 50
        case .journal: 100
        case .status: 70
        case .dateAdded, .dateModified: 80
        case .doi, .arxivId: 140
        case .projects: 120
        case .metadataSource: 80
        case .pmid, .isbn: 100
        }
    }
}
