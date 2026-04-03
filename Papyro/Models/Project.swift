import Foundation

struct Project: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var slug: String
    var isInbox: Bool
    var dateCreated: Date

    static func makeInbox(now: Date = Date()) -> Project {
        Project(
            id: UUID(),
            name: "Inbox",
            slug: "inbox",
            isInbox: true,
            dateCreated: now
        )
    }

    static func generateSlug(from name: String) -> String {
        let lowered = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        let filtered = lowered.map { character -> Character in
            if character.isLetter || character.isNumber || character == " " || character == "-" {
                return character
            }
            return " "
        }

        var collapsed = ""
        var lastWasSeparator = false

        for character in filtered {
            let isSeparator = character == " " || character == "-"
            if isSeparator {
                if !lastWasSeparator {
                    collapsed.append("-")
                }
                lastWasSeparator = true
            } else {
                collapsed.append(character)
                lastWasSeparator = false
            }
        }

        let slug = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "project" : slug
    }
}
