import Foundation

final class SemanticScholarProvider: MetadataProvider, Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchMetadata(for identifiers: ParsedIdentifiers) async throws -> PaperMetadata? {
        let paperId: String
        if let doi = identifiers.doi {
            paperId = "DOI:\(doi)"
        } else if let arxivId = identifiers.arxivId {
            paperId = "ARXIV:\(arxivId)"
        } else {
            return nil
        }

        guard let encoded = paperId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.semanticscholar.org/graph/v1/paper/\(encoded)?fields=title,authors,year,venue,externalIds,abstract,url") else {
            return nil
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return extractS2Metadata(from: json)
    }

    func searchByTitle(_ title: String) async throws -> PaperMetadata? {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.semanticscholar.org/graph/v1/paper/search?query=\(encoded)&limit=3&fields=title,authors,year,venue,externalIds,abstract,url") else {
            return nil
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let papers = json["data"] as? [[String: Any]],
              let first = papers.first else { return nil }
        return extractS2Metadata(from: first)
    }

    private func extractS2Metadata(from item: [String: Any]) -> PaperMetadata? {
        guard let title = item["title"] as? String, !title.isEmpty else { return nil }

        let authorArray = item["authors"] as? [[String: Any]] ?? []
        let authors = authorArray.compactMap { $0["name"] as? String }
        let externalIds = item["externalIds"] as? [String: Any]

        return PaperMetadata(
            title: title,
            authors: authors,
            year: item["year"] as? Int,
            journal: item["venue"] as? String,
            doi: externalIds?["DOI"] as? String,
            arxivId: externalIds?["ArXiv"] as? String,
            abstract: item["abstract"] as? String,
            url: item["url"] as? String,
            source: .semanticScholar
        )
    }
}
