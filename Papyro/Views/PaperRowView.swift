import SwiftUI

struct PaperRowView: View {
    let paper: Paper

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(paper.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            badge
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch paper.importState {
        case .importing, .resolving:
            ProgressView()
                .controlSize(.small)
        case .resolved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unresolved:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch paper.importState {
        case .importing:
            BadgeView(text: "Importing", color: .blue)
        case .resolving:
            BadgeView(text: "Resolving", color: .orange)
        case .resolved:
            BadgeView(text: paper.status.displayName, color: .blue)
        case .unresolved:
            BadgeView(text: "Unresolved", color: .red)
        }
    }

    private var subtitle: String {
        switch paper.importState {
        case .importing:
            "Importing..."
        case .resolving:
            paper.doi.map { "DOI: \($0) — Looking up metadata..." } ?? "Resolving..."
        case .resolved:
            formatAuthors(paper.authors, year: paper.year, journal: paper.journal)
        case .unresolved:
            "Could not resolve metadata"
        }
    }

    private func formatAuthors(_ authors: [String], year: Int?, journal: String?) -> String {
        var parts: [String] = []
        if let firstAuthor = authors.first {
            let surname = firstAuthor.components(separatedBy: ",").first ?? firstAuthor
            parts.append(authors.count > 1 ? "\(surname) et al." : surname)
        }
        if let year = year { parts.append(String(year)) }
        if let journal = journal, !journal.isEmpty { parts.append(journal) }
        return parts.joined(separator: " · ")
    }
}

private struct BadgeView: View {
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
}
