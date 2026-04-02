import SwiftUI

struct DetailView: View {
    var body: some View {
        ContentUnavailableView(
            "Select a Paper",
            systemImage: "doc.richtext",
            description: Text("Select a paper to view its details.")
        )
    }
}
