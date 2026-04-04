// Papyro/Views/ProjectChipsView.swift
import SwiftUI

struct ProjectChipsView: View {
    let paper: Paper
    let projects: [Project]
    let onRemove: (Project) -> Void
    let onAdd: (Project) -> Void
    let onCreateProject: (String) -> Void

    @State private var isAddingNew = false
    @State private var newProjectName = ""
    @FocusState private var isNewProjectFieldFocused: Bool

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

                addProjectMenu
            }

            if isAddingNew {
                TextField("Project name", text: $newProjectName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNewProjectFieldFocused)
                    .onSubmit {
                        if !newProjectName.isEmpty {
                            onCreateProject(newProjectName)
                        }
                        newProjectName = ""
                        isAddingNew = false
                    }
                    .onExitCommand {
                        newProjectName = ""
                        isAddingNew = false
                    }
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

    private var addProjectMenu: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
            Text("Add")
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .overlay {
            Menu {
                ForEach(availableProjects) { project in
                    Button(project.name) {
                        onAdd(project)
                    }
                }
                if !availableProjects.isEmpty {
                    Divider()
                }
                Button("New Project...") {
                    isAddingNew = true
                    isNewProjectFieldFocused = true
                }
            } label: {
                Color.clear
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .fixedSize()
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
