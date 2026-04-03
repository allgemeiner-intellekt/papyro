import Foundation

struct LibraryConfig: Codable, Equatable {
    let version: Int
    var libraryPath: String
    var translationServerURL: String?
    var visibleColumns: [PaperColumn]?
    var sortColumn: PaperColumn?
    var sortAscending: Bool?
}
