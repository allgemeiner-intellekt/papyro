import Testing
import Foundation
@testable import Papyro

struct ProjectTests {
    @Test func encodesAndDecodesCorrectly() throws {
        let project = Project(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            name: "PhD Thesis",
            slug: "phd-thesis",
            isInbox: false,
            dateCreated: Date(timeIntervalSince1970: 1712000000)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Project.self, from: data)

        #expect(decoded.id == project.id)
        #expect(decoded.name == "PhD Thesis")
        #expect(decoded.slug == "phd-thesis")
        #expect(decoded.isInbox == false)
    }

    @Test func inboxProjectFlagWorks() {
        let inbox = Project(
            id: UUID(),
            name: "Inbox",
            slug: "inbox",
            isInbox: true,
            dateCreated: Date()
        )
        #expect(inbox.isInbox == true)
    }

    @Test func generateSlugFromName() {
        #expect(Project.generateSlug(from: "PhD Thesis") == "phd-thesis")
        #expect(Project.generateSlug(from: "Side Project!") == "side-project")
        #expect(Project.generateSlug(from: "  Lots   of   Spaces  ") == "lots-of-spaces")
        #expect(Project.generateSlug(from: "Already-Slugged") == "already-slugged")
    }
}
