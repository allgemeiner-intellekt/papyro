import SwiftUI

struct PaperListView: View {
    let category: SidebarCategory
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var appState = appState

        Group {
            if coordinator.papers.isEmpty {
                ContentUnavailableView(
                    "No Papers Yet",
                    systemImage: "doc.text",
                    description: Text("Drag and drop PDF files here to import them.")
                )
            } else {
                List(coordinator.papers, selection: $appState.selectedPaperId) { paper in
                    PaperRowView(paper: paper)
                        .tag(paper.id)
                }
            }
        }
        .navigationTitle(category.displayName)
        .dropDestination(for: URL.self) { urls, _ in
            let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            guard !pdfURLs.isEmpty else { return false }
            Task { await coordinator.importPDFs(pdfURLs) }
            return true
        }
    }
}
