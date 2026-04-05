import Foundation

struct LibraryConfig: Codable, Equatable {
    let version: Int
    var libraryPath: String
    var translationServerURL: String?
    var visibleColumns: [PaperColumn]?
    var sortColumn: PaperColumn?
    var sortAscending: Bool?
    var managedSymlinks: [ManagedSymlink]

    init(version: Int, libraryPath: String, translationServerURL: String?, visibleColumns: [PaperColumn]? = nil, sortColumn: PaperColumn? = nil, sortAscending: Bool? = nil, managedSymlinks: [ManagedSymlink] = []) {
        self.version = version
        self.libraryPath = libraryPath
        self.translationServerURL = translationServerURL
        self.visibleColumns = visibleColumns
        self.sortColumn = sortColumn
        self.sortAscending = sortAscending
        self.managedSymlinks = managedSymlinks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        libraryPath = try container.decode(String.self, forKey: .libraryPath)
        translationServerURL = try container.decodeIfPresent(String.self, forKey: .translationServerURL)
        visibleColumns = try container.decodeIfPresent([PaperColumn].self, forKey: .visibleColumns)
        sortColumn = try container.decodeIfPresent(PaperColumn.self, forKey: .sortColumn)
        sortAscending = try container.decodeIfPresent(Bool.self, forKey: .sortAscending)
        managedSymlinks = (try? container.decode([ManagedSymlink].self, forKey: .managedSymlinks)) ?? []
    }
}
