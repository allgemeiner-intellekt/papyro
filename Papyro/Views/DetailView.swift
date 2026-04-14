import SwiftUI

struct DetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var editAuthors = ""
    @State private var editYear = ""
    @State private var editJournal = ""
    @State private var editDOI = ""
    @State private var editAbstract = ""
    @State private var citationCopied = false

    private var paper: Paper? {
        guard let id = appState.selectedPaperId else { return nil }
        return coordinator.papers.first { $0.id == id }
    }

    private func noteExistsOnDisk(_ paper: Paper) -> Bool {
        guard let notePath = paper.notePath,
              let config = appState.libraryConfig else { return false }
        let noteURL = URL(fileURLWithPath: config.libraryPath)
            .appendingPathComponent(notePath)
        return FileManager.default.fileExists(atPath: noteURL.path)
    }

    private func openNote(_ paper: Paper) {
        guard let notePath = paper.notePath,
              let config = appState.libraryConfig else { return }
        let noteURL = URL(fileURLWithPath: config.libraryPath)
            .appendingPathComponent(notePath)
        NSWorkspace.shared.open(noteURL)
    }

    var body: some View {
        if let paper = paper {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isEditing {
                        editForm(paper)
                    } else {
                        headerSection(paper)
                        Divider()
                        // Projects section
                        ProjectChipsView(
                            paper: paper,
                            projects: coordinator.projectService.projects,
                            onRemove: { project in
                                do {
                                    try coordinator.unassignPaperFromProject(paperId: paper.id, project: project)
                                } catch {
                                    appState.userError = UserFacingError(
                                        title: "Couldn't unassign project",
                                        message: error.localizedDescription
                                    )
                                }
                            },
                            onAdd: { project in
                                do {
                                    try coordinator.assignPaperToProject(paperId: paper.id, project: project)
                                } catch {
                                    appState.userError = UserFacingError(
                                        title: "Couldn't assign project",
                                        message: error.localizedDescription
                                    )
                                }
                            },
                            onCreateProject: { name in
                                do {
                                    let project = try coordinator.projectService.createProject(name: name)
                                    try coordinator.assignPaperToProject(paperId: paper.id, project: project)
                                } catch {
                                    appState.userError = UserFacingError(
                                        title: "Couldn't create project",
                                        message: error.localizedDescription
                                    )
                                }
                            }
                        )
                        Divider()
                        metadataSection(paper)
                        if let abstract = paper.abstract, !abstract.isEmpty {
                            Divider()
                            abstractSection(abstract)
                        }
                        Divider()
                        actionsSection(paper)
                    }
                }
                .padding()
            }
            .onChange(of: appState.selectedPaperId) {
                isEditing = false
                editTitle = ""
                editAuthors = ""
                editYear = ""
                editJournal = ""
                editDOI = ""
                editAbstract = ""
            }
            .onChange(of: isEditing) {
                appState.isEditingText = isEditing
            }
        } else {
            ContentUnavailableView(
                "Select a Paper",
                systemImage: "doc.richtext",
                description: Text("Select a paper to view its details.")
            )
        }
    }

    @ViewBuilder
    private func editForm(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Metadata")
                .font(.title2)
                .fontWeight(.bold)

            LabeledContent("Title") {
                TextField("Title", text: $editTitle)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Authors") {
                TextField("Authors separated by ;", text: $editAuthors)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Year") {
                TextField("Year", text: $editYear)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            LabeledContent("Journal") {
                TextField("Journal", text: $editJournal)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("DOI") {
                TextField("DOI", text: $editDOI)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Abstract") {
                TextEditor(text: $editAbstract)
                    .frame(minHeight: 100)
                    .border(Color.secondary.opacity(0.3))
            }

            HStack(spacing: 12) {
                Button("Save") {
                    let trimmedTitle = editTitle.trimmingCharacters(in: .whitespaces)
                    if trimmedTitle.isEmpty {
                        appState.userError = UserFacingError(
                            title: "Title required",
                            message: "Please enter a title before saving."
                        )
                        return
                    }
                    let trimmedYear = editYear.trimmingCharacters(in: .whitespaces)
                    var parsedYear: Int? = nil
                    if !trimmedYear.isEmpty {
                        guard let y = Int(trimmedYear) else {
                            appState.userError = UserFacingError(
                                title: "Invalid year",
                                message: "Year must be a number (e.g. 2024) or empty."
                            )
                            return
                        }
                        parsedYear = y
                    }
                    let authors = editAuthors
                        .components(separatedBy: ";")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    coordinator.updatePaperMetadata(
                        paperId: paper.id,
                        title: trimmedTitle,
                        authors: authors,
                        year: parsedYear,
                        journal: editJournal.isEmpty ? nil : editJournal,
                        doi: editDOI.isEmpty ? nil : editDOI,
                        abstract: editAbstract.isEmpty ? nil : editAbstract
                    )
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)

                Button("Cancel") {
                    isEditing = false
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func headerSection(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(paper.title)
                .font(.title2)
                .fontWeight(.bold)
                .textSelection(.enabled)

            if !paper.authors.isEmpty {
                Text(paper.authors.joined(separator: "; "))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                if let year = paper.year {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let journal = paper.journal, !journal.isEmpty {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(journal)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func metadataSection(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.headline)

            MetadataRow(label: "DOI", value: paper.doi)
            MetadataRow(label: "arXiv ID", value: paper.arxivId)
            MetadataRow(label: "PMID", value: paper.pmid)
            MetadataRow(label: "ISBN", value: paper.isbn)
            HStack(alignment: .top) {
                Text("Status")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)

                Picker("", selection: Binding(
                    get: { paper.status },
                    set: { newStatus in
                        coordinator.updatePaperStatus(paperId: paper.id, status: newStatus)
                    }
                )) {
                    Text("To Read").tag(ReadingStatus.toRead)
                    Text("Reading").tag(ReadingStatus.reading)
                    Text("Archived").tag(ReadingStatus.archived)
                }
                .labelsHidden()
                .fixedSize()
            }
            MetadataRow(label: "Source", value: paper.metadataSource.rawValue)
            MetadataRow(label: "Added", value: paper.dateAdded.formatted(date: .abbreviated, time: .omitted))
            MetadataRow(label: "File", value: paper.pdfFilename)
        }
    }

    @ViewBuilder
    private func abstractSection(_ abstract: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Abstract")
                .font(.headline)

            Text(abstract)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func actionsSection(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.headline)

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Button {
                        openPDF(paper)
                    } label: {
                        Label("Open PDF", systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("o", modifiers: .command)

                    Button {
                        revealInFinder(paper)
                    } label: {
                        Label("Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                GridRow {
                    if noteExistsOnDisk(paper) {
                        Button {
                            openNote(paper)
                        } label: {
                            Label("Open Note", systemImage: "doc.text")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("e", modifiers: .command)
                    } else {
                        Button {
                            switch coordinator.createNote(for: paper.id) {
                            case .success(let noteURL):
                                NSWorkspace.shared.open(noteURL)
                            case .failure(let error):
                                appState.userError = UserFacingError(
                                    title: "Couldn't create note",
                                    message: error.localizedDescription
                                )
                            }
                        } label: {
                            Label("Create Note", systemImage: "doc.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }

                    Button {
                        editTitle = paper.title
                        editAuthors = paper.authors.joined(separator: "; ")
                        editYear = paper.year.map(String.init) ?? ""
                        editJournal = paper.journal ?? ""
                        editDOI = paper.doi ?? ""
                        editAbstract = paper.abstract ?? ""
                        isEditing = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                GridRow {
                    Menu {
                        Button("Copy as BibTeX") {
                            copyCitation(paper, format: .bibtex)
                        }
                        Button("Copy as RIS") {
                            copyCitation(paper, format: .ris)
                        }
                    } label: {
                        Label(citationCopied ? "Copied" : "Copy Citation",
                              systemImage: citationCopied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: .infinity)
                }
            }

            if paper.importState == .unresolved {
                Button {
                    Task {
                        await coordinator.retryMetadataLookup(for: paper.id)
                    }
                } label: {
                    Label("Retry Lookup", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func copyCitation(_ paper: Paper, format: CitationFormat) {
        let text = CitationExporter.export(paper, format: format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation { citationCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { withAnimation { citationCopied = false } }
        }
    }

    private func openPDF(_ paper: Paper) {
        guard let config = appState.libraryConfig else { return }
        let pdfURL = URL(fileURLWithPath: config.libraryPath)
            .appendingPathComponent(paper.pdfPath)
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            appState.userError = UserFacingError(
                title: "PDF Not Found",
                message: "The file at \(paper.pdfPath) is missing from your library."
            )
            return
        }
        NSWorkspace.shared.open(pdfURL)
    }

    private func revealInFinder(_ paper: Paper) {
        guard let config = appState.libraryConfig else { return }
        let pdfURL = URL(fileURLWithPath: config.libraryPath)
            .appendingPathComponent(paper.pdfPath)
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            appState.userError = UserFacingError(
                title: "PDF Not Found",
                message: "The file at \(paper.pdfPath) is missing from your library."
            )
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([pdfURL])
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String?

    var body: some View {
        if let value = value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)

                Text(value)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
    }
}
