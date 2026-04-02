import SwiftUI

struct DetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    private var paper: Paper? {
        guard let id = appState.selectedPaperId else { return nil }
        return coordinator.papers.first { $0.id == id }
    }

    var body: some View {
        if let paper = paper {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                .padding()
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
