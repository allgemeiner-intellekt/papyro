import SwiftUI

@Observable
class AppState {
    var libraryConfig: LibraryConfig?
    var selectedCategory: SidebarCategory = .all
    var isOnboarding: Bool = true
}
