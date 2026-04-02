import Testing
import Foundation
@testable import Papyro

struct LibraryConfigTests {
    @Test func encodesAndDecodesCorrectly() throws {
        let config = LibraryConfig(version: 1, libraryPath: "/Users/test/ResearchLibrary", translationServerURL: "https://translate.example.com")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LibraryConfig.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.libraryPath == "/Users/test/ResearchLibrary")
        #expect(decoded.translationServerURL == "https://translate.example.com")
    }

    @Test func decodesWithoutTranslationServerURL() throws {
        // Backwards compatibility: config.json files from M1 won't have this field
        let json = """
        {"version": 1, "libraryPath": "/Users/test/ResearchLibrary"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LibraryConfig.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.translationServerURL == nil)
    }
}
