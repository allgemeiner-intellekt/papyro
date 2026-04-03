import Foundation

enum SidebarItem: Hashable, Sendable {
    case allPapers
    case project(UUID)

    var projectID: UUID? {
        if case .project(let id) = self {
            return id
        }
        return nil
    }

    var isAllPapers: Bool {
        if case .allPapers = self {
            return true
        }
        return false
    }
}
