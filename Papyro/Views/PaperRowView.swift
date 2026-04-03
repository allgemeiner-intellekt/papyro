import SwiftUI

struct PaperRowView: View {
    let paper: Paper
    let visibleColumns: Set<PaperColumn>
    let projects: [Project]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Row 1: Title (full width)
            Text(paper.title)
                .font(.system(size: 13, weight: .semibold))

            // Row 2: Metadata columns
            HStack(spacing: 0) {
                Spacer()
                    .frame(maxWidth: .infinity)

                ForEach(sortedVisibleColumns, id: \.self) { column in
                    columnValue(for: column)
                        .frame(width: columnWidth(for: column), alignment: .leading)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var sortedVisibleColumns: [PaperColumn] {
        PaperColumn.allCases.filter { visibleColumns.contains($0) }
    }

    @ViewBuilder
    private func columnValue(for column: PaperColumn) -> some View {
        switch column {
        case .authors:
            Text(formatAuthors(paper.authors))
                .lineLimit(1)
        case .year:
            Text(paper.year.map(String.init) ?? "\u{2014}")
        case .journal:
            Text(paper.journal ?? "\u{2014}")
                .lineLimit(1)
        case .status:
            BadgeView(text: paper.status.displayName, color: paper.status.color)
        case .dateAdded:
            Text(paper.dateAdded.formatted(.dateTime.month(.abbreviated).day()))
        case .dateModified:
            Text(paper.dateModified.formatted(.dateTime.month(.abbreviated).day()))
        case .doi:
            Text(paper.doi ?? "\u{2014}")
                .lineLimit(1)
        case .arxivId:
            Text(paper.arxivId ?? "\u{2014}")
                .lineLimit(1)
        case .pmid:
            Text(paper.pmid ?? "\u{2014}")
        case .isbn:
            Text(paper.isbn ?? "\u{2014}")
        case .projects:
            Text(projectNames)
                .lineLimit(1)
        case .metadataSource:
            Text(paper.metadataSource.rawValue)
                .lineLimit(1)
        }
    }

    private var projectNames: String {
        let names = paper.projectIDs.compactMap { id in
            projects.first { $0.id == id }?.name
        }
        return names.isEmpty ? "\u{2014}" : names.joined(separator: ", ")
    }

    private func formatAuthors(_ authors: [String]) -> String {
        guard let first = authors.first else { return "\u{2014}" }
        let surname = first.components(separatedBy: ",").first ?? first
        return authors.count > 1 ? "\(surname) et al." : surname
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

struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

extension ReadingStatus {
    var displayName: String {
        switch self {
        case .toRead: "To Read"
        case .reading: "Reading"
        case .archived: "Archived"
        }
    }

    var iconName: String {
        switch self {
        case .toRead: "circle.fill"
        case .reading: "circle.dotted.circle"
        case .archived: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .toRead: .blue
        case .reading: .orange
        case .archived: .green
        }
    }

    var sortOrder: Int {
        switch self {
        case .toRead: 0
        case .reading: 1
        case .archived: 2
        }
    }
}
