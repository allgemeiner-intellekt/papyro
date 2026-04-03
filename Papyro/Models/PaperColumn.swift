import SwiftUI

enum PaperColumn: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case authors
    case year
    case journal
    case status
    case dateAdded
    case doi
    case arxivId
    case projects
    case metadataSource
    case dateModified
    case pmid
    case isbn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .authors: "Authors"
        case .year: "Year"
        case .journal: "Journal"
        case .status: "Status"
        case .dateAdded: "Date Added"
        case .doi: "DOI"
        case .arxivId: "arXiv ID"
        case .projects: "Projects"
        case .metadataSource: "Source"
        case .dateModified: "Date Modified"
        case .pmid: "PMID"
        case .isbn: "ISBN"
        }
    }

    var width: CGFloat {
        switch self {
        case .authors: 140
        case .year: 56
        case .journal: 140
        case .status: 90
        case .dateAdded, .dateModified: 96
        case .doi, .arxivId: 160
        case .projects: 160
        case .metadataSource: 120
        case .pmid, .isbn: 120
        }
    }

    static var defaultVisible: Set<PaperColumn> {
        [.authors, .year, .journal, .status, .dateAdded]
    }
}
