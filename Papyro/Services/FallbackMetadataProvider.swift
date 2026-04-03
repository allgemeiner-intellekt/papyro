import Foundation

struct FallbackMetadataProvider: MetadataProvider {
    private let providers: [MetadataProvider]

    init(providers: [MetadataProvider]) {
        self.providers = providers
    }

    func fetchMetadata(for identifiers: ParsedIdentifiers) async throws -> PaperMetadata? {
        for provider in providers {
            if let result = try? await provider.fetchMetadata(for: identifiers) {
                return result
            }
        }
        return nil
    }

    func searchByTitle(_ title: String) async throws -> PaperMetadata? {
        for provider in providers {
            if let result = try? await provider.searchByTitle(title) {
                return result
            }
        }
        return nil
    }
}
