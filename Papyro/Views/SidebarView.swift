import SwiftUI

struct SidebarView: View {
    @Binding var selectedCategory: SidebarCategory

    var body: some View {
        List(SidebarCategory.allCases, selection: $selectedCategory) { category in
            SidebarRow(category: category)
        }
        .navigationTitle("Papyro")
    }
}

private struct SidebarRow: View {
    let category: SidebarCategory

    var body: some View {
        Label(category.displayName, systemImage: category.iconName)
            .tag(category)
    }
}
