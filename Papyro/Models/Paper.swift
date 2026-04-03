import Foundation

struct Paper: Codable, Identifiable, Sendable {
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

    var projectIDs: [UUID]
    var status: ReadingStatus

    var dateAdded: Date
    var dateModified: Date
    var metadataSource: MetadataSource
    var metadataResolved: Bool
    var importState: ImportState

    init(
        id: UUID,
        canonicalId: String?,
        title: String,
        authors: [String],
        year: Int?,
        journal: String?,
        doi: String?,
        arxivId: String?,
        pmid: String?,
        isbn: String?,
        abstract: String?,
        url: String?,
        pdfPath: String,
        pdfFilename: String,
        notePath: String?,
        projectIDs: [UUID],
        status: ReadingStatus,
        dateAdded: Date,
        dateModified: Date,
        metadataSource: MetadataSource,
        metadataResolved: Bool,
        importState: ImportState
    ) {
        self.id = id
        self.canonicalId = canonicalId
        self.title = title
        self.authors = authors
        self.year = year
        self.journal = journal
        self.doi = doi
        self.arxivId = arxivId
        self.pmid = pmid
        self.isbn = isbn
        self.abstract = abstract
        self.url = url
        self.pdfPath = pdfPath
        self.pdfFilename = pdfFilename
        self.notePath = notePath
        self.projectIDs = projectIDs
        self.status = status
        self.dateAdded = dateAdded
        self.dateModified = dateModified
        self.metadataSource = metadataSource
        self.metadataResolved = metadataResolved
        self.importState = importState
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case canonicalId
        case title
        case authors
        case year
        case journal
        case doi
        case arxivId
        case pmid
        case isbn
        case abstract
        case url
        case pdfPath
        case pdfFilename
        case notePath
        case projectIDs
        case status
        case dateAdded
        case dateModified
        case metadataSource
        case metadataResolved
        case importState
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case topics
        case projects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        canonicalId = try container.decodeIfPresent(String.self, forKey: .canonicalId)
        title = try container.decode(String.self, forKey: .title)
        authors = try container.decode([String].self, forKey: .authors)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        journal = try container.decodeIfPresent(String.self, forKey: .journal)
        doi = try container.decodeIfPresent(String.self, forKey: .doi)
        arxivId = try container.decodeIfPresent(String.self, forKey: .arxivId)
        pmid = try container.decodeIfPresent(String.self, forKey: .pmid)
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        abstract = try container.decodeIfPresent(String.self, forKey: .abstract)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        pdfPath = try container.decode(String.self, forKey: .pdfPath)
        pdfFilename = try container.decode(String.self, forKey: .pdfFilename)
        notePath = try container.decodeIfPresent(String.self, forKey: .notePath)
        projectIDs = try container.decodeIfPresent([UUID].self, forKey: .projectIDs) ?? []
        status = try container.decode(ReadingStatus.self, forKey: .status)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        dateModified = try container.decode(Date.self, forKey: .dateModified)
        metadataSource = try container.decode(MetadataSource.self, forKey: .metadataSource)
        metadataResolved = try container.decode(Bool.self, forKey: .metadataResolved)
        importState = try container.decode(ImportState.self, forKey: .importState)

        _ = try? decoder.container(keyedBy: LegacyCodingKeys.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(canonicalId, forKey: .canonicalId)
        try container.encode(title, forKey: .title)
        try container.encode(authors, forKey: .authors)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(journal, forKey: .journal)
        try container.encodeIfPresent(doi, forKey: .doi)
        try container.encodeIfPresent(arxivId, forKey: .arxivId)
        try container.encodeIfPresent(pmid, forKey: .pmid)
        try container.encodeIfPresent(isbn, forKey: .isbn)
        try container.encodeIfPresent(abstract, forKey: .abstract)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(pdfPath, forKey: .pdfPath)
        try container.encode(pdfFilename, forKey: .pdfFilename)
        try container.encodeIfPresent(notePath, forKey: .notePath)
        try container.encode(projectIDs, forKey: .projectIDs)
        try container.encode(status, forKey: .status)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(dateModified, forKey: .dateModified)
        try container.encode(metadataSource, forKey: .metadataSource)
        try container.encode(metadataResolved, forKey: .metadataResolved)
        try container.encode(importState, forKey: .importState)
    }
}

enum ReadingStatus: String, Codable, CaseIterable, Sendable {
    case toRead
    case reading
    case archived
}

enum MetadataSource: String, Codable, Sendable {
    case translationServer
    case crossRef
    case semanticScholar
    case manual
    case none
}

enum ImportState: String, Codable, Sendable {
    case importing
    case resolving
    case resolved
    case unresolved
}
