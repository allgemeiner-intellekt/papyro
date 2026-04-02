import Foundation

protocol MetadataProvider: Sendable {
    func fetchMetadata(for identifiers: ParsedIdentifiers) async throws -> PaperMetadata?
    func searchByTitle(_ title: String) async throws -> PaperMetadata?
}

final class MockMetadataProvider: MetadataProvider, @unchecked Sendable {
    var metadataToReturn: PaperMetadata?
    var searchResult: PaperMetadata?
    var shouldThrow: Bool = false

    func fetchMetadata(for identifiers: ParsedIdentifiers) async throws -> PaperMetadata? {
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return metadataToReturn
    }

    func searchByTitle(_ title: String) async throws -> PaperMetadata? {
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return searchResult
    }
}
