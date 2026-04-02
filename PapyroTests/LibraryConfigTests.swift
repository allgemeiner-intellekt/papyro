import Testing
import Foundation
@testable import Papyro

struct LibraryConfigTests {
    @Test func encodesAndDecodesCorrectly() throws {
        let config = LibraryConfig(version: 1, libraryPath: "/Users/test/ResearchLibrary")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LibraryConfig.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.libraryPath == "/Users/test/ResearchLibrary")
    }
}
