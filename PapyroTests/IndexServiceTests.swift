// PapyroTests/IndexServiceTests.swift
import Testing
import Foundation
@testable import Papyro

struct IndexServiceTests {
    let indexService = IndexService()

    private func makeTempLibrary() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("index"), withIntermediateDirectories: true)
        return dir
    }

    private func makePaper(id: UUID = UUID(), title: String = "Test Paper") -> Paper {
        Paper(
            id: id,
            canonicalId: "10.1234/test",
            title: title,
            authors: ["Smith, J."],
            year: 2024,
            journal: "Nature",
            doi: "10.1234/test",
            arxivId: nil,
            pmid: nil,
            isbn: nil,
            abstract: "Abstract text",
            url: nil,
            pdfPath: "papers/2024_smith_test-paper.pdf",
            pdfFilename: "2024_smith_test-paper.pdf",
            notePath: nil,
            projectIDs: [],
            status: .toRead,
            dateAdded: Date(timeIntervalSince1970: 1712000000),
            dateModified: Date(timeIntervalSince1970: 1712000000),
            metadataSource: .translationServer,
            metadataResolved: true,
            importState: .resolved
        )
    }

    @Test func savesAndLoadsASinglePaper() throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let paper = makePaper()
        try indexService.save(paper, in: libRoot)

        let indexFile = libRoot.appendingPathComponent("index/\(paper.id.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: indexFile.path))

        let papers = try indexService.loadAll(from: libRoot)
        #expect(papers.count == 1)
        #expect(papers[0].title == "Test Paper")
        #expect(papers[0].id == paper.id)
    }

    @Test func savesMultiplePapersAndLoadsAll() throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let paper1 = makePaper(title: "Paper One")
        let paper2 = makePaper(title: "Paper Two")
        try indexService.save(paper1, in: libRoot)
        try indexService.save(paper2, in: libRoot)

        let papers = try indexService.loadAll(from: libRoot)
        #expect(papers.count == 2)
        let titles = Set(papers.map(\.title))
        #expect(titles.contains("Paper One"))
        #expect(titles.contains("Paper Two"))
    }

    @Test func rebuildsCombinedIndex() throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let paper1 = makePaper(title: "Paper One")
        let paper2 = makePaper(title: "Paper Two")

        try indexService.rebuildCombinedIndex(from: [paper1, paper2], in: libRoot)

        let allJsonURL = libRoot.appendingPathComponent("index/_all.json")
        #expect(FileManager.default.fileExists(atPath: allJsonURL.path))

        let data = try Data(contentsOf: allJsonURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let papers = try decoder.decode([Paper].self, from: data)
        #expect(papers.count == 2)
    }

    @Test func updateExistingPaper() throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let paperId = UUID()
        var paper = makePaper(id: paperId, title: "Original Title")
        try indexService.save(paper, in: libRoot)

        paper.title = "Updated Title"
        try indexService.save(paper, in: libRoot)

        let papers = try indexService.loadAll(from: libRoot)
        #expect(papers.count == 1)
        #expect(papers[0].title == "Updated Title")
    }

    @Test func deletesPaper() throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let paper = makePaper()
        try indexService.save(paper, in: libRoot)
        let fileURL = libRoot.appendingPathComponent("index/\(paper.id.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        try indexService.delete(paper, in: libRoot)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func deleteIsIdempotent() throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let paper = makePaper()
        // Never saved — delete should not throw.
        try indexService.delete(paper, in: libRoot)
    }

    @Test func loadOneReturnsPaper() throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let paper = makePaper(title: "Single Load")
        try indexService.save(paper, in: libRoot)
        let url = libRoot.appendingPathComponent("index/\(paper.id.uuidString).json")

        let loaded = try indexService.loadOne(at: url)
        #expect(loaded?.id == paper.id)
        #expect(loaded?.title == "Single Load")
    }

    @Test func loadOneReturnsNilForCorruptJSON() throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let url = libRoot.appendingPathComponent("index/corrupt.json")
        try "{ not valid json".write(to: url, atomically: true, encoding: .utf8)

        let loaded = try indexService.loadOne(at: url)
        #expect(loaded == nil)
    }
}
