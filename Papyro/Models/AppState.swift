import SwiftUI

struct UserFacingError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@Observable
class AppState {
    var libraryConfig: LibraryConfig?
    var selectedSidebarItem: SidebarItem = .allPapers
    var selectedStatusFilter: ReadingStatus?
    var selectedPaperId: UUID?
    var isOnboarding: Bool = true
    var isEditingText: Bool = false
    var searchText: String = ""
    var symlinkHealthIssueCount: Int = 0
    var showSettingsIntegrations: Bool = false
    var userError: UserFacingError? = nil

    var visibleColumns: Set<PaperColumn> = PaperColumn.defaultVisible
    var sortColumn: PaperColumn = .dateAdded
    var sortAscending: Bool = false
    var columnWidths: [PaperColumn: CGFloat] = PaperColumn.defaultWidths
}
