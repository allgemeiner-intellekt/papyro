import Foundation
import SwiftUI

enum PaperColumn: String, Codable, CaseIterable, Identifiable {
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

    static var defaultVisible: Set<PaperColumn> {
        [.authors, .year, .journal, .status, .dateAdded]
    }

    var columnWidth: CGFloat {
        switch self {
        case .authors: 120
        case .year: 50
        case .journal: 100
        case .status: 70
        case .dateAdded, .dateModified: 80
        case .doi, .arxivId: 140
        case .projects: 120
        case .metadataSource: 80
        case .pmid, .isbn: 100
        }
    }
}
