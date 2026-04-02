import Foundation

final class CrossRefProvider: MetadataProvider, Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchMetadata(for identifiers: ParsedIdentifiers) async throws -> PaperMetadata? {
        guard let doi = identifiers.doi else { return nil }
        guard let url = URL(string: "https://api.crossref.org/works/\(doi)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Papyro/0.1 (mailto:papyro@example.com)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any] else { return nil }
        return extractCrossRefMetadata(from: message)
    }

    func searchByTitle(_ title: String) async throws -> PaperMetadata? {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.crossref.org/works?query.bibliographic=\(encoded)&rows=3") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Papyro/0.1 (mailto:papyro@example.com)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let items = message["items"] as? [[String: Any]],
              let first = items.first else { return nil }
        return extractCrossRefMetadata(from: first)
    }

    private func extractCrossRefMetadata(from item: [String: Any]) -> PaperMetadata? {
        let titleArray = item["title"] as? [String]
        let title = titleArray?.first ?? ""
        guard !title.isEmpty else { return nil }

        let authorArray = item["author"] as? [[String: Any]] ?? []
        let authors = authorArray.compactMap { author -> String? in
            guard let family = author["family"] as? String else { return nil }
            let given = author["given"] as? String
            return given != nil ? "\(family), \(given!)" : family
        }

        var year: Int?
        if let dateParts = item["published-print"] as? [String: Any] ?? item["published-online"] as? [String: Any],
           let parts = dateParts["date-parts"] as? [[Int]],
           let firstPart = parts.first, !firstPart.isEmpty {
            year = firstPart[0]
        }

        return PaperMetadata(
            title: title,
            authors: authors,
            year: year,
            journal: (item["container-title"] as? [String])?.first,
            doi: item["DOI"] as? String,
            arxivId: nil,
            abstract: item["abstract"] as? String,
            url: item["URL"] as? String,
            source: .crossRef
        )
    }
}
