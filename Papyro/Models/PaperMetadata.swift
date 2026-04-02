import Foundation

struct PaperMetadata: Sendable {
    var title: String
    var authors: [String]
    var year: Int?
    var journal: String?
    var doi: String?
    var arxivId: String?
    var abstract: String?
    var url: String?
    var source: MetadataSource
}

struct ParsedIdentifiers: Sendable {
    var doi: String?
    var arxivId: String?
    var pmid: String?
    var isbn: String?

    var bestIdentifier: String? {
        doi ?? arxivId ?? pmid ?? isbn
    }

    var isEmpty: Bool {
        doi == nil && arxivId == nil && pmid == nil && isbn == nil
    }
}
