import Foundation

final class TranslationServerProvider: MetadataProvider, Sendable {
    private let serverURL: URL
    private let session: URLSession

    init(serverURL: URL, session: URLSession = .shared) {
        self.serverURL = serverURL
        self.session = session
    }

    func fetchMetadata(for identifiers: ParsedIdentifiers) async throws -> PaperMetadata? {
        guard let identifier = identifiers.bestIdentifier else { return nil }

        let searchURL = serverURL.appendingPathComponent("search")
        var request = URLRequest(url: searchURL)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = identifier.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        return try parseZoteroResponse(data)
    }

    func searchByTitle(_ title: String) async throws -> PaperMetadata? {
        return nil // Translation-server doesn't support title search
    }

    private func parseZoteroResponse(_ data: Data) throws -> PaperMetadata? {
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let item = items.first else {
            return nil
        }

        let title = item["title"] as? String ?? ""
        let creators = item["creators"] as? [[String: Any]] ?? []
        let authors = creators.compactMap { creator -> String? in
            let lastName = creator["lastName"] as? String
            let firstName = creator["firstName"] as? String
            if let last = lastName, let first = firstName {
                return "\(last), \(first)"
            }
            return lastName ?? creator["name"] as? String
        }

        let dateStr = item["date"] as? String ?? ""
        let year = parseYear(from: dateStr)

        return PaperMetadata(
            title: title,
            authors: authors,
            year: year,
            journal: item["publicationTitle"] as? String ?? item["proceedingsTitle"] as? String,
            doi: item["DOI"] as? String,
            arxivId: nil,
            abstract: item["abstractNote"] as? String,
            url: item["url"] as? String,
            source: .translationServer
        )
    }

    private func parseYear(from dateString: String) -> Int? {
        guard let match = dateString.range(of: #"\d{4}"#, options: .regularExpression) else { return nil }
        return Int(dateString[match])
    }
}
