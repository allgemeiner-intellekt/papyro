import SwiftUI

struct PaperListView: View {
    let category: SidebarCategory

    var body: some View {
        ContentUnavailableView(
            "No Papers Yet",
            systemImage: "doc.text",
            description: Text("Papers in \"\(category.displayName)\" will appear here.")
        )
        .navigationTitle(category.displayName)
    }
}
