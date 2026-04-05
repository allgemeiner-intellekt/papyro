import Foundation

struct ManagedSymlink: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var sourceRelativePath: String
    var destinationPath: String
    var label: String
    var createdAt: Date
}
