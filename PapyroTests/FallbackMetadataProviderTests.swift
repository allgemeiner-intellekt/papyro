import Testing
import Foundation
@testable import Papyro

struct FallbackMetadataProviderTests {
    private let sampleMetadata = PaperMetadata(
        title: "Test Paper",
        authors: ["Author"],
        year: 2024,
        journal: nil,
        doi: "10.1234/test",
        arxivId: nil,
        abstract: nil,
        url: nil,
        source: .crossRef
    )

    private let sampleIdentifiers = ParsedIdentifiers(doi: "10.1234/test")

    @Test func firstProviderSucceeds() async throws {
        let first = MockMetadataProvider()
        first.metadataToReturn = sampleMetadata
        let second = MockMetadataProvider()
        second.metadataToReturn = nil

        let fallback = FallbackMetadataProvider(providers: [first, second])
        let result = try await fallback.fetchMetadata(for: sampleIdentifiers)

        #expect(result?.title == "Test Paper")
    }

    @Test func firstNilFallsThrough() async throws {
        let first = MockMetadataProvider()
        first.metadataToReturn = nil
        let second = MockMetadataProvider()
        second.metadataToReturn = sampleMetadata

        let fallback = FallbackMetadataProvider(providers: [first, second])
        let result = try await fallback.fetchMetadata(for: sampleIdentifiers)

        #expect(result?.title == "Test Paper")
    }

    @Test func firstThrowsFallsThrough() async throws {
        let first = MockMetadataProvider()
        first.shouldThrow = true
        let second = MockMetadataProvider()
        second.metadataToReturn = sampleMetadata

        let fallback = FallbackMetadataProvider(providers: [first, second])
        let result = try await fallback.fetchMetadata(for: sampleIdentifiers)

        #expect(result?.title == "Test Paper")
    }

    @Test func allFailReturnsNil() async throws {
        let first = MockMetadataProvider()
        first.shouldThrow = true
        let second = MockMetadataProvider()
        second.metadataToReturn = nil

        let fallback = FallbackMetadataProvider(providers: [first, second])
        let result = try await fallback.fetchMetadata(for: sampleIdentifiers)

        #expect(result == nil)
    }
}
