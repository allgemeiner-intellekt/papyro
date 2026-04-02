import SwiftUI

@Observable
class AppState {
    var libraryConfig: LibraryConfig?
    var selectedCategory: SidebarCategory = .all
    var selectedPaperId: UUID?
    var isOnboarding: Bool = true
}
