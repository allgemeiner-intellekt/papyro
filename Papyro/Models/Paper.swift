import Foundation

struct Paper: Codable, Identifiable {
    let id: UUID
    var canonicalId: String?

    var title: String
    var authors: [String]
    var year: Int?
    var journal: String?
    var doi: String?
    var arxivId: String?
    var pmid: String?
    var isbn: String?
    var abstract: String?
    var url: String?

    var pdfPath: String
    var pdfFilename: String
    var notePath: String?

    var topics: [String]
    var projects: [String]
    var status: ReadingStatus

    var dateAdded: Date
    var dateModified: Date
    var metadataSource: MetadataSource
    var metadataResolved: Bool
    var importState: ImportState
}

enum ReadingStatus: String, Codable {
    case toRead
    case reading
    case archived
}

enum MetadataSource: String, Codable {
    case translationServer
    case crossRef
    case semanticScholar
    case manual
    case none
}

enum ImportState: String, Codable {
    case importing
    case resolving
    case resolved
    case unresolved
}
