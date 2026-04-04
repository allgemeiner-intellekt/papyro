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

        Group {
            if filteredPapers.isEmpty {
                ContentUnavailableView(
                    "No Papers",
                    systemImage: "doc.text",
                    description: Text("Drag and drop PDF files here to import them.")
                )
            } else {
                List(selection: $appState.selectedPaperId) {
                    Section {
                        ForEach(filteredPapers) { paper in
                            PaperRowView(
                                paper: paper,
                                visibleColumns: appState.visibleColumns,
                                columnWidths: appState.columnWidths,
                                projects: coordinator.projectService.projects
                            )
                            .tag(paper.id)
                            .draggable(paper.id.uuidString)
                            .contextMenu {
                                paperContextMenu(paper: paper)
                            }
                        }
                    } header: {
                        ColumnHeaderBar(
                            visibleColumns: appState.visibleColumns,
                            columnWidths: $appState.columnWidths,
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
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
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
    @Binding var columnWidths: [PaperColumn: CGFloat]
    let sortColumn: PaperColumn
    let sortAscending: Bool
    let onTapColumn: (PaperColumn) -> Void
    let onToggleColumn: (PaperColumn, Bool) -> Void

    @State private var dragStartWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            let columns = sortedVisibleColumns
            ForEach(columns, id: \.self) { column in
                let isLast = column == columns.last

                headerCell(for: column, isLast: isLast)

                if !isLast {
                    resizeHandle(for: column)
                }
            }
        }
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

    @ViewBuilder
    private func headerCell(for column: PaperColumn, isLast: Bool) -> some View {
        Button {
            onTapColumn(column)
        } label: {
            HStack(spacing: 3) {
                Text(column.displayName)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                Spacer()
            }
            .font(.system(size: 11))
            .foregroundStyle(sortColumn == column ? .primary : .secondary)
            .padding(.leading, 4)
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: isLast ? nil : widthFor(column), alignment: .leading)
        .frame(maxWidth: isLast ? .infinity : nil, alignment: .leading)
    }

    private func resizeHandle(for column: PaperColumn) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 1, height: 12)
            .padding(.horizontal, 2)
            .contentShape(Rectangle().size(width: 8, height: 20))
            .cursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidth == 0 {
                            dragStartWidth = widthFor(column)
                        }
                        let newWidth = max(column.minWidth, dragStartWidth + value.translation.width)
                        columnWidths[column] = newWidth
                    }
                    .onEnded { _ in
                        dragStartWidth = 0
                    }
            )
    }

    private var sortedVisibleColumns: [PaperColumn] {
        PaperColumn.allCases.filter { visibleColumns.contains($0) }
    }

    private func widthFor(_ column: PaperColumn) -> CGFloat {
        columnWidths[column] ?? column.defaultWidth
    }
}

// MARK: - Resize Cursor

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
