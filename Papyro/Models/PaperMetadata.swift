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

    init(doi: String? = nil, arxivId: String? = nil, pmid: String? = nil, isbn: String? = nil) {
        self.doi = doi
        self.arxivId = arxivId
        self.pmid = pmid
        self.isbn = isbn
    }

    var bestIdentifier: String? {
        doi ?? arxivId ?? pmid ?? isbn
    }

    var isEmpty: Bool {
        doi == nil && arxivId == nil && pmid == nil && isbn == nil
    }
}
