// Papyro/Views/ProjectChipsView.swift
import SwiftUI

struct ProjectChipsView: View {
    let paper: Paper
    let projects: [Project]
    let onRemove: (Project) -> Void
    let onAdd: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects")
                .font(.headline)

            FlowLayout(spacing: 6) {
                ForEach(assignedProjects) { project in
                    HStack(spacing: 4) {
                        Text(project.name)
                            .font(.caption)
                            .fontWeight(.medium)

                        if !project.isInbox {
                            Button {
                                onRemove(project)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
                }

                Menu {
                    ForEach(availableProjects) { project in
                        Button(project.name) {
                            onAdd(project)
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(availableProjects.isEmpty)
            }
        }
    }

    private var assignedProjects: [Project] {
        paper.projectIDs.compactMap { id in
            projects.first { $0.id == id }
        }
    }

    private var availableProjects: [Project] {
        projects.filter { !$0.isInbox && !paper.projectIDs.contains($0.id) }
    }
}

// Simple flow layout for chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
