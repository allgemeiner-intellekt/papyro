import SwiftUI

@Observable
class AppState {
    var libraryConfig: LibraryConfig?
    var selectedSidebarItem: SidebarItem = .allPapers
    var selectedStatusFilter: ReadingStatus?
    var selectedPaperId: UUID?
    var isOnboarding: Bool = true
    var visibleColumns: Set<PaperColumn> = PaperColumn.defaultVisible
    var sortColumn: PaperColumn = .dateAdded
    var sortAscending: Bool = false
}
