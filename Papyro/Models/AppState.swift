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

    var visibleColumns: Set<PaperColumn> = PaperColumn.defaultVisible {
        didSet { persistColumnPreferences() }
    }
    var sortColumn: PaperColumn = .dateAdded {
        didSet { persistColumnPreferences() }
    }
    var sortAscending: Bool = false {
        didSet { persistColumnPreferences() }
    }
    var columnWidths: [PaperColumn: CGFloat] = PaperColumn.defaultWidths

    private let defaults: UserDefaults
    private var suppressPersist: Bool = false

    private enum Keys {
        static let visibleColumns = "papyro.visibleColumns"
        static let sortColumn = "papyro.sortColumn"
        static let sortAscending = "papyro.sortAscending"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadColumnPreferences()
    }

    private func loadColumnPreferences() {
        suppressPersist = true
        defer { suppressPersist = false }

        if let raw = defaults.array(forKey: Keys.visibleColumns) as? [String] {
            let cols = raw.compactMap { PaperColumn(rawValue: $0) }
            if !cols.isEmpty { visibleColumns = Set(cols) }
        }
        if let raw = defaults.string(forKey: Keys.sortColumn),
           let col = PaperColumn(rawValue: raw) {
            sortColumn = col
        }
        if defaults.object(forKey: Keys.sortAscending) != nil {
            sortAscending = defaults.bool(forKey: Keys.sortAscending)
        }
    }

    private func persistColumnPreferences() {
        guard !suppressPersist else { return }
        defaults.set(visibleColumns.map { $0.rawValue }, forKey: Keys.visibleColumns)
        defaults.set(sortColumn.rawValue, forKey: Keys.sortColumn)
        defaults.set(sortAscending, forKey: Keys.sortAscending)
    }
}
