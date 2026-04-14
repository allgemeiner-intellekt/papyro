import Foundation

enum CitationFormat: Sendable {
    case bibtex
    case ris
}

struct CitationExporter: Sendable {
    private static let commonTitleWords: Set<String> = [
        "the", "a", "an", "of", "for", "and", "in", "on", "to", "with",
    ]

    private static let bibtexSpecialChars: [(Character, String)] = [
        ("&", "\\&"),
        ("%", "\\%"),
        ("$", "\\$"),
        ("#", "\\#"),
        ("_", "\\_"),
        ("~", "\\~{}"),
        ("^", "\\^{}"),
    ]

    static func export(_ paper: Paper, format: CitationFormat) -> String {
        switch format {
        case .bibtex: return bibtexEntry(for: paper)
        case .ris: return risEntry(for: paper)
        }
    }

    static func exportBatch(_ papers: [Paper], format: CitationFormat) -> String {
        switch format {
        case .bibtex:
            let keys = papers.map { bibtexKey(for: $0) }
            var uniqueKeys: [String] = []
            var keyCounts: [String: Int] = [:]

            for key in keys {
                let count = keyCounts[key, default: 0]
                keyCounts[key] = count + 1
                uniqueKeys.append(key)
            }

            let needsSuffix = keyCounts.filter { $0.value > 1 }.keys
            var suffixCounters: [String: Int] = [:]
            var resolvedKeys: [String] = []

            for key in uniqueKeys {
                if needsSuffix.contains(key) {
                    let idx = suffixCounters[key, default: 0]
                    suffixCounters[key] = idx + 1
                    let suffix = String(UnicodeScalar(UInt32(97 + idx))!)
                    resolvedKeys.append(key + suffix)
                } else {
                    resolvedKeys.append(key)
                }
            }

            let entries = zip(papers, resolvedKeys).map { paper, key in
                buildBibtexEntry(for: paper, key: key)
            }
            return entries.joined(separator: "\n\n")

        case .ris:
            return papers.map { risEntry(for: $0) }.joined(separator: "\n")
        }
    }

    static func bibtexKey(for paper: Paper) -> String {
        let authorPart = firstAuthorLastName(paper.authors).lowercased()
        let yearPart = paper.year.map(String.init) ?? "nd"
        let titlePart = firstSignificantTitleWord(paper.title).lowercased()
        return sanitizeBibtexKey(authorPart + yearPart + titlePart)
    }

    static func bibtexEntry(for paper: Paper) -> String {
        buildBibtexEntry(for: paper, key: bibtexKey(for: paper))
    }

    static func risEntry(for paper: Paper) -> String {
        var lines: [String] = []
        let entryType = paper.journal != nil ? "JOUR" : "GEN"
        lines.append("TY  - \(entryType)")

        lines.append("TI  - \(paper.title)")

        for author in paper.authors {
            lines.append("AU  - \(formatAuthorName(author))")
        }

        if let year = paper.year {
            lines.append("PY  - \(year)")
        }

        if let journal = paper.journal {
            lines.append("JO  - \(journal)")
        }

        if let doi = paper.doi {
            lines.append("DO  - \(doi)")
        }

        if let url = paper.url {
            lines.append("UR  - \(url)")
        }

        if let abstract = paper.abstract {
            lines.append("AB  - \(abstract)")
        }

        lines.append("ER  - ")
        return lines.joined(separator: "\n")
    }

    static func fileExtension(for format: CitationFormat) -> String {
        switch format {
        case .bibtex: return ".bib"
        case .ris: return ".ris"
        }
    }

    // MARK: - Private

    private static func buildBibtexEntry(for paper: Paper, key: String) -> String {
        let entryType = paper.journal != nil ? "article" : "misc"
        var fields: [(String, String)] = []

        fields.append(("title", escapeBibtex(paper.title)))

        if !paper.authors.isEmpty {
            let formatted = paper.authors.map { formatAuthorName($0) }.joined(separator: " and ")
            fields.append(("author", escapeBibtex(formatted)))
        }

        if let year = paper.year {
            fields.append(("year", String(year)))
        }

        if let journal = paper.journal {
            fields.append(("journal", escapeBibtex(journal)))
        }

        if let doi = paper.doi {
            fields.append(("doi", escapeBibtex(doi)))
        }

        if let url = paper.url {
            fields.append(("url", escapeBibtex(url)))
        }

        if let abstract = paper.abstract {
            fields.append(("abstract", escapeBibtex(abstract)))
        }

        if let arxivId = paper.arxivId {
            fields.append(("note", escapeBibtex("arXiv: \(arxivId)")))
        }

        let fieldLines = fields.map { "  \($0.0) = {\($0.1)}" }.joined(separator: ",\n")
        return "@\(entryType){\(key),\n\(fieldLines)\n}"
    }

    private static func firstAuthorLastName(_ authors: [String]) -> String {
        guard let first = authors.first, !first.isEmpty else { return "unknown" }

        if first.contains(",") {
            return String(first.split(separator: ",").first ?? "unknown")
                .trimmingCharacters(in: .whitespaces)
        }

        let parts = first.split(separator: " ")
        return parts.count > 1 ? String(parts.last!) : String(parts.first ?? "unknown")
    }

    private static func firstSignificantTitleWord(_ title: String) -> String {
        let words = title.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.filter { $0.isLetter || $0.isNumber } }
            .filter { !$0.isEmpty }

        return words.first { !commonTitleWords.contains($0) } ?? words.first ?? "untitled"
    }

    private static func formatAuthorName(_ name: String) -> String {
        if name.contains(",") { return name }
        let parts = name.split(separator: " ").map(String.init)
        guard parts.count > 1 else { return name }
        let surname = parts.last!
        let given = parts.dropLast().joined(separator: " ")
        return "\(surname), \(given)"
    }

    private static func escapeBibtex(_ text: String) -> String {
        var result = text
        for (char, replacement) in bibtexSpecialChars {
            result = result.map { $0 == char ? replacement : String($0) }.joined()
        }
        return result
    }

    private static func sanitizeBibtexKey(_ key: String) -> String {
        String(key.filter { $0.isLetter || $0.isNumber })
    }
}
