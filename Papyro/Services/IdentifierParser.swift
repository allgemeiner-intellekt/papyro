import Foundation

struct IdentifierParser: Sendable {

    func parse(_ text: String) -> ParsedIdentifiers {
        ParsedIdentifiers(
            doi: extractDOI(from: text),
            arxivId: extractArXivId(from: text),
            pmid: extractPMID(from: text),
            isbn: extractISBN(from: text)
        )
    }

    private func extractDOI(from text: String) -> String? {
        // Match DOI preceded by "doi.org/", "doi:", "doi: ", "DOI ", etc.
        let prefixedPattern = #"(?:doi\.org/|doi:?\s*)(10\.\d{4,9}/[^\s]+)"#
        if let match = text.range(of: prefixedPattern, options: [.regularExpression, .caseInsensitive]) {
            let fullMatch = String(text[match])
            if let doiRange = fullMatch.range(of: #"10\.\d{4,9}/[^\s]+"#, options: .regularExpression) {
                return cleanDOI(String(fullMatch[doiRange]))
            }
        }
        // Try bare DOI (e.g. "DOI 10.xxx/yyy" where DOI is followed by space and number)
        let barePattern = #"10\.\d{4,9}/[-._;()/:A-Za-z0-9]+"#
        if let match = text.range(of: barePattern, options: .regularExpression) {
            return cleanDOI(String(text[match]))
        }
        return nil
    }

    private func cleanDOI(_ doi: String) -> String {
        var cleaned = doi
        while let last = cleaned.last, [".", ",", ";", ")", "]"].contains(String(last)) {
            cleaned.removeLast()
        }
        return cleaned
    }

    private func extractArXivId(from text: String) -> String? {
        // Prefer explicit arXiv: prefix first
        let prefixedPattern = #"[Aa]r[Xx]iv:(\d{4}\.\d{4,5}(?:v\d+)?)"#
        if let regex = try? NSRegularExpression(pattern: prefixedPattern) {
            let nsRange = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: nsRange),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        }
        // Fall back to bare YYMM.NNNNN pattern (only if not inside a DOI)
        let barePattern = #"(?<![/\w])(\d{4}\.\d{4,5}(?:v\d+)?)(?!\d)"#
        if let regex = try? NSRegularExpression(pattern: barePattern) {
            let nsRange = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: nsRange),
               let range = Range(match.range(at: 1), in: text) {
                // Make sure this match isn't part of a DOI
                let matchStart = range.lowerBound
                let lookBehind = text[text.startIndex..<matchStart]
                if !lookBehind.hasSuffix("/") {
                    return String(text[range])
                }
            }
        }
        return nil
    }

    private func extractPMID(from text: String) -> String? {
        let pattern = #"PMID:?\s*(\d{7,8})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange) else { return nil }
        guard let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func extractISBN(from text: String) -> String? {
        let pattern = #"(?:978|979)[-\s]?\d{1,5}[-\s]?\d{1,7}[-\s]?\d{1,7}[-\s]?\d"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[match])
    }
}
