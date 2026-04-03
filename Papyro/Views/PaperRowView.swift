import SwiftUI

struct PaperRowView: View {
    let paper: Paper
    let visibleColumns: Set<PaperColumn>
    let projects: [Project]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(paper.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
                importStateBadge
            }

            HStack(spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity)

                ForEach(visibleColumnsInOrder, id: \.self) { column in
                    columnValue(for: column)
                        .frame(width: column.width, alignment: .leading)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var visibleColumnsInOrder: [PaperColumn] {
        PaperColumn.allCases.filter { visibleColumns.contains($0) }
    }

    @ViewBuilder
    private var importStateBadge: some View {
        switch paper.importState {
        case .importing:
            BadgeView(text: "Importing", color: .blue)
                .fixedSize()
        case .resolving:
            BadgeView(text: "Resolving", color: .orange)
                .fixedSize()
        case .unresolved:
            BadgeView(text: "Unresolved", color: .red)
                .fixedSize()
        case .resolved:
            EmptyView()
        }
    }

    @ViewBuilder
    private func columnValue(for column: PaperColumn) -> some View {
        switch column {
        case .authors:
            Text(formatAuthors(paper.authors))
                .lineLimit(1)
        case .year:
            Text(paper.year.map(String.init) ?? "—")
        case .journal:
            Text(paper.journal ?? "—")
                .lineLimit(1)
        case .status:
            BadgeView(text: paper.status.displayName, color: paper.status.color)
                .fixedSize()
        case .dateAdded:
            Text(paper.dateAdded.formatted(date: .abbreviated, time: .omitted))
                .lineLimit(1)
        case .doi:
            Text(paper.doi ?? "—")
                .lineLimit(1)
        case .arxivId:
            Text(paper.arxivId ?? "—")
                .lineLimit(1)
        case .projects:
            Text(projectNames)
                .lineLimit(1)
        case .metadataSource:
            Text(metadataSourceLabel)
                .lineLimit(1)
        case .dateModified:
            Text(paper.dateModified.formatted(date: .abbreviated, time: .omitted))
                .lineLimit(1)
        case .pmid:
            Text(paper.pmid ?? "—")
                .lineLimit(1)
        case .isbn:
            Text(paper.isbn ?? "—")
                .lineLimit(1)
        }
    }

    private var projectNames: String {
        let names = paper.projectIDs.compactMap { id in
            projects.first(where: { $0.id == id })?.name
        }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    private var metadataSourceLabel: String {
        switch paper.metadataSource {
        case .translationServer: "Translation Server"
        case .crossRef: "Crossref"
        case .semanticScholar: "Semantic Scholar"
        case .manual: "Manual"
        case .none: "None"
        }
    }

    private func formatAuthors(_ authors: [String]) -> String {
        guard let firstAuthor = authors.first else { return "—" }
        let surname = firstAuthor.components(separatedBy: ",").first ?? firstAuthor
        return authors.count > 1 ? "\(surname) et al." : surname
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
