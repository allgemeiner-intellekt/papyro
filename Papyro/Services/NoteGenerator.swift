import Foundation

struct NoteGenerator: Sendable {
    static let defaultTemplate = """
    ---
    title: "{{title}}"
    authors: [{{authors_linked}}]
    year: {{year}}
    doi: "{{doi}}"
    status: "{{status}}"
    ---

    # {{title}}

    **Authors:** {{authors_formatted}}
    **Published:** {{journal}}, {{year}}
    **DOI:** [{{doi}}](https://doi.org/{{doi}})
    **PDF:** [[{{pdf_filename}}]]

    ## Abstract

    {{abstract}}

    ## Notes

    """

    static func expandTemplate(_ template: String, with paper: Paper) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        let statusRawValue: String = {
            switch paper.status {
            case .toRead: return "to-read"
            case .reading: return "reading"
            case .archived: return "archived"
            }
        }()

        let replacements: [(String, String)] = [
            ("{{title}}", paper.title),
            ("{{authors_formatted}}", paper.authors.joined(separator: ", ")),
            ("{{authors_linked}}", paper.authors.map { "[[\($0)]]" }.joined(separator: ", ")),
            ("{{year}}", paper.year.map(String.init) ?? ""),
            ("{{journal}}", paper.journal ?? ""),
            ("{{doi}}", paper.doi ?? ""),
            ("{{arxiv_id}}", paper.arxivId ?? ""),
            ("{{abstract}}", paper.abstract ?? ""),
            ("{{pdf_filename}}", paper.pdfFilename),
            ("{{status}}", statusRawValue),
            ("{{date_added}}", dateFormatter.string(from: paper.dateAdded)),
        ]

        var result = template
        for (placeholder, value) in replacements {
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        return result
    }

    static func noteFilename(for paper: Paper) -> String {
        if let canonicalId = paper.canonicalId, !canonicalId.isEmpty {
            let sanitized = canonicalId.replacingOccurrences(of: "/", with: "_")
            return "\(sanitized).md"
        }
        return "\(slugify(paper.title)).md"
    }

    func generateNote(for paper: Paper, libraryRoot: URL) throws -> String {
        let template = loadTemplate(libraryRoot: libraryRoot)
        let content = Self.expandTemplate(template, with: paper)
        let filename = Self.noteFilename(for: paper)
        let relativePath = "notes/\(filename)"
        let noteURL = libraryRoot.appendingPathComponent(relativePath)
        try content.write(to: noteURL, atomically: true, encoding: .utf8)
        return relativePath
    }

    private func loadTemplate(libraryRoot: URL) -> String {
        let templateURL = libraryRoot.appendingPathComponent("templates/note.md")
        if let custom = try? String(contentsOf: templateURL, encoding: .utf8), !custom.isEmpty {
            return custom
        }
        try? Self.defaultTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
        return Self.defaultTemplate
    }

    private static func slugify(_ text: String) -> String {
        let lowered = text
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
