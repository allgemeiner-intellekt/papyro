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
    var lastResolutionError: String?
}

// Backward-compatible decoder for pre-M3 paper JSON (had "topics"/"projects" instead of "projectIDs")
extension Paper {
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
        projectIDs = (try? container.decode([UUID].self, forKey: .projectIDs)) ?? []
        status = try container.decode(ReadingStatus.self, forKey: .status)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        dateModified = try container.decode(Date.self, forKey: .dateModified)
        metadataSource = try container.decode(MetadataSource.self, forKey: .metadataSource)
        metadataResolved = try container.decode(Bool.self, forKey: .metadataResolved)
        importState = try container.decode(ImportState.self, forKey: .importState)
        lastResolutionError = try container.decodeIfPresent(String.self, forKey: .lastResolutionError)
    }
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

extension Paper {
    func matches(searchTokens: [String]) -> Bool {
        if searchTokens.isEmpty { return true }
        var parts: [String] = []
        parts.append(title)
        parts.append(authors.joined(separator: " "))
        parts.append(year.map(String.init) ?? "")
        parts.append(journal ?? "")
        parts.append(abstract ?? "")
        parts.append(doi ?? "")
        parts.append(arxivId ?? "")
        parts.append(pmid ?? "")
        parts.append(isbn ?? "")
        let searchable = parts.joined(separator: " ").lowercased()
        return searchTokens.allSatisfy { searchable.contains($0.lowercased()) }
    }
}
