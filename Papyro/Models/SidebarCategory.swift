import Foundation

enum SidebarCategory: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case all
    case byProject
    case byTopic
    case byAuthor
    case byYear
    case recentlyAdded
    case unread

    var displayName: String {
        switch self {
        case .all: "All Papers"
        case .byProject: "By Project"
        case .byTopic: "By Topic"
        case .byAuthor: "By Author"
        case .byYear: "By Year"
        case .recentlyAdded: "Recently Added"
        case .unread: "Unread"
        }
    }

    var iconName: String {
        switch self {
        case .all: "books.vertical"
        case .byProject: "folder"
        case .byTopic: "tag"
        case .byAuthor: "person.2"
        case .byYear: "calendar"
        case .recentlyAdded: "clock"
        case .unread: "book.closed"
        }
    }
}
