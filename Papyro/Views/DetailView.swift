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

    private var paper: Paper? {
        guard let id = appState.selectedPaperId else { return nil }
        return coordinator.papers.first { $0.id == id }
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
                TextField("Comma-separated authors", text: $editAuthors)
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
                    let authors = editAuthors
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    coordinator.updatePaperMetadata(
                        paperId: paper.id,
                        title: editTitle,
                        authors: authors,
                        year: Int(editYear),
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
                Text(paper.authors.joined(separator: ", "))
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
            MetadataRow(label: "Status", value: paper.status.displayName)
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

            HStack(spacing: 12) {
                Button("Open PDF") {
                    openPDF(paper)
                }

                Button("Reveal in Finder") {
                    revealInFinder(paper)
                }

                if paper.importState == .unresolved {
                    Button("Retry Lookup") {
                        Task {
                            await coordinator.retryMetadataLookup(for: paper.id)
                        }
                    }
                }

                Button("Edit") {
                    editTitle = paper.title
                    editAuthors = paper.authors.joined(separator: ", ")
                    editYear = paper.year.map(String.init) ?? ""
                    editJournal = paper.journal ?? ""
                    editDOI = paper.doi ?? ""
                    editAbstract = paper.abstract ?? ""
                    isEditing = true
                }
            }
        }
    }

    private func openPDF(_ paper: Paper) {
        guard let config = appState.libraryConfig else { return }
        let pdfURL = URL(fileURLWithPath: config.libraryPath)
            .appendingPathComponent(paper.pdfPath)
        NSWorkspace.shared.open(pdfURL)
    }

    private func revealInFinder(_ paper: Paper) {
        guard let config = appState.libraryConfig else { return }
        let pdfURL = URL(fileURLWithPath: config.libraryPath)
            .appendingPathComponent(paper.pdfPath)
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
                    .frame(width: 80, alignment: .trailing)

                Text(value)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
    }
}
