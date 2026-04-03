import Foundation

struct LibraryConfig: Codable, Equatable {
    let version: Int
    var libraryPath: String
    var translationServerURL: String?
    var visibleColumns: [PaperColumn]?
    var sortColumn: PaperColumn?
    var sortAscending: Bool?

    init(
        version: Int,
        libraryPath: String,
        translationServerURL: String?,
        visibleColumns: [PaperColumn]? = nil,
        sortColumn: PaperColumn? = nil,
        sortAscending: Bool? = nil
    ) {
        self.version = version
        self.libraryPath = libraryPath
        self.translationServerURL = translationServerURL
        self.visibleColumns = visibleColumns
        self.sortColumn = sortColumn
        self.sortAscending = sortAscending
    }
}
