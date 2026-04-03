import Foundation

struct Project: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var slug: String
    var isInbox: Bool
    var dateCreated: Date

    static func makeInbox() -> Project {
        Project(
            id: UUID(),
            name: "Inbox",
            slug: "inbox",
            isInbox: true,
            dateCreated: Date()
        )
    }

    static func generateSlug(from name: String) -> String {
        let lowered = name
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        var result = ""
        for char in lowered {
            if char.isLetter || char.isNumber || char == " " || char == "-" {
                result.append(char)
            }
        }

        var collapsed = ""
        var lastWasSep = false
        for char in result {
            let isSep = char == " " || char == "-"
            if isSep {
                if !lastWasSep { collapsed.append("-") }
                lastWasSep = true
            } else {
                collapsed.append(char)
                lastWasSep = false
            }
        }

        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
