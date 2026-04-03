import Foundation

enum SidebarItem: Hashable {
    case allPapers
    case project(UUID)

    var isAllPapers: Bool {
        if case .allPapers = self { return true }
        return false
    }

    var projectID: UUID? {
        if case .project(let id) = self { return id }
        return nil
    }
}
