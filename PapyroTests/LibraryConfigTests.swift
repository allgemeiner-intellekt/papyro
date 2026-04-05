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

    @Test func decodesConfigWithManagedSymlinks() throws {
        let json = """
        {
            "version": 1,
            "libraryPath": "/tmp/test",
            "managedSymlinks": [
                {
                    "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                    "sourceRelativePath": "notes",
                    "destinationPath": "/Users/me/Vault/Notes",
                    "label": "Notes → Vault",
                    "createdAt": "2026-04-05T12:00:00Z"
                }
            ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let config = try decoder.decode(LibraryConfig.self, from: json)
        #expect(config.managedSymlinks.count == 1)
        #expect(config.managedSymlinks[0].sourceRelativePath == "notes")
        #expect(config.managedSymlinks[0].label == "Notes → Vault")
    }

    @Test func decodesLegacyConfigWithoutManagedSymlinks() throws {
        let json = """
        {
            "version": 1,
            "libraryPath": "/tmp/test"
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(LibraryConfig.self, from: json)
        #expect(config.managedSymlinks.isEmpty)
    }
}
