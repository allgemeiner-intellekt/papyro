// PapyroTests/ImportCoordinatorTests.swift
import Testing
import Foundation
@testable import Papyro

struct ImportCoordinatorTests {

    private func makeTempLibrary() throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        let subdirs = ["papers", "index", "notes", ".symlinks", ".cache/text", "templates"]
        for subdir in subdirs {
            try fm.createDirectory(at: dir.appendingPathComponent(subdir), withIntermediateDirectories: true)
        }
        return dir
    }

    private func createDummyPDF(named name: String = "test.pdf") -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        FileManager.default.createFile(atPath: url.path, contents: "dummy pdf".data(using: .utf8))
        return url
    }

    @Test func importSinglePDFWithMockMetadata() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let mock = MockMetadataProvider()
        mock.metadataToReturn = PaperMetadata(
            title: "Attention Is All You Need",
            authors: ["Vaswani, Ashish", "Shazeer, Noam"],
            year: 2017,
            journal: "NeurIPS",
            doi: "10.48550/arXiv.1706.03762",
            arxivId: "1706.03762",
            abstract: "The dominant sequence transduction models...",
            url: nil,
            source: .translationServer
        )

        let coordinator = await ImportCoordinator(
            libraryRoot: libRoot,
            metadataProvider: mock
        )

        let sourcePDF = createDummyPDF()
        defer { try? FileManager.default.removeItem(at: sourcePDF) }

        await coordinator.importPDFs([sourcePDF])

        let papers = await coordinator.papers
        #expect(papers.count == 1)

        let paper = papers[0]
        #expect(paper.title == "Attention Is All You Need")
        #expect(paper.authors == ["Vaswani, Ashish", "Shazeer, Noam"])
        #expect(paper.year == 2017)
        #expect(paper.metadataResolved == true)
        #expect(paper.importState == .resolved)

        // Verify PDF exists in papers/
        let pdfURL = libRoot.appendingPathComponent(paper.pdfPath)
        #expect(FileManager.default.fileExists(atPath: pdfURL.path))
        #expect(paper.pdfFilename.contains("vaswani"))
        #expect(paper.pdfFilename.contains("2017"))

        // Verify index JSON was written
        let indexFile = libRoot.appendingPathComponent("index/\(paper.id.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: indexFile.path))

        // Verify _all.json was regenerated
        let allJson = libRoot.appendingPathComponent("index/_all.json")
        #expect(FileManager.default.fileExists(atPath: allJson.path))
    }

    @Test func importPDFWithNoMetadataBecomesUnresolved() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let mock = MockMetadataProvider()
        mock.metadataToReturn = nil
        mock.searchResult = nil

        let coordinator = await ImportCoordinator(
            libraryRoot: libRoot,
            metadataProvider: mock
        )

        let sourcePDF = createDummyPDF(named: "mystery-paper.pdf")
        defer { try? FileManager.default.removeItem(at: sourcePDF) }

        await coordinator.importPDFs([sourcePDF])

        let papers = await coordinator.papers
        #expect(papers.count == 1)

        let paper = papers[0]
        #expect(paper.metadataResolved == false)
        #expect(paper.importState == .unresolved)
        let pdfURL = libRoot.appendingPathComponent(paper.pdfPath)
        #expect(FileManager.default.fileExists(atPath: pdfURL.path))
    }

    @Test func importMultiplePDFs() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let mock = MockMetadataProvider()
        mock.metadataToReturn = PaperMetadata(
            title: "Test Paper",
            authors: ["Author"],
            year: 2024,
            journal: nil,
            doi: nil,
            arxivId: nil,
            abstract: nil,
            url: nil,
            source: .translationServer
        )

        let coordinator = await ImportCoordinator(
            libraryRoot: libRoot,
            metadataProvider: mock
        )

        let pdf1 = createDummyPDF(named: "paper1.pdf")
        let pdf2 = createDummyPDF(named: "paper2.pdf")
        let pdf3 = createDummyPDF(named: "paper3.pdf")
        defer {
            try? FileManager.default.removeItem(at: pdf1)
            try? FileManager.default.removeItem(at: pdf2)
            try? FileManager.default.removeItem(at: pdf3)
        }

        await coordinator.importPDFs([pdf1, pdf2, pdf3])

        let papers = await coordinator.papers
        #expect(papers.count == 3)
    }

    @Test func retryMetadataLookupSucceeds() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        // First import with no metadata
        let mock = MockMetadataProvider()
        mock.metadataToReturn = nil
        mock.searchResult = nil

        let coordinator = await ImportCoordinator(
            libraryRoot: libRoot,
            metadataProvider: mock
        )

        let sourcePDF = createDummyPDF()
        defer { try? FileManager.default.removeItem(at: sourcePDF) }

        await coordinator.importPDFs([sourcePDF])

        var papers = await coordinator.papers
        #expect(papers.count == 1)
        #expect(papers[0].importState == .unresolved)

        let paperId = papers[0].id

        // Now set up metadata and retry
        mock.metadataToReturn = PaperMetadata(
            title: "Retry Success",
            authors: ["Author, Test"],
            year: 2024,
            journal: nil,
            doi: "10.1234/retry",
            arxivId: nil,
            abstract: nil,
            url: nil,
            source: .crossRef
        )

        await coordinator.retryMetadataLookup(for: paperId)

        papers = await coordinator.papers
        let paper = papers.first { $0.id == paperId }!
        #expect(paper.importState == .resolved)
        #expect(paper.title == "Retry Success")
        #expect(paper.metadataResolved == true)
    }

    @Test func retryMetadataLookupFailsGracefully() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let mock = MockMetadataProvider()
        mock.metadataToReturn = nil
        mock.searchResult = nil

        let coordinator = await ImportCoordinator(
            libraryRoot: libRoot,
            metadataProvider: mock
        )

        let sourcePDF = createDummyPDF()
        defer { try? FileManager.default.removeItem(at: sourcePDF) }

        await coordinator.importPDFs([sourcePDF])

        var papers = await coordinator.papers
        let paperId = papers[0].id

        // Retry still fails
        await coordinator.retryMetadataLookup(for: paperId)

        papers = await coordinator.papers
        #expect(papers[0].importState == .unresolved)
    }

    @Test func updatePaperMetadataPersists() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: libRoot) }

        let mock = MockMetadataProvider()
        mock.metadataToReturn = nil

        let coordinator = await ImportCoordinator(
            libraryRoot: libRoot,
            metadataProvider: mock
        )

        let sourcePDF = createDummyPDF()
        defer { try? FileManager.default.removeItem(at: sourcePDF) }

        await coordinator.importPDFs([sourcePDF])

        var papers = await coordinator.papers
        let paperId = papers[0].id

        await coordinator.updatePaperMetadata(
            paperId: paperId,
            title: "Manually Edited Title",
            authors: ["Editor, Manual"],
            year: 2025,
            journal: "Journal of Testing",
            doi: "10.1234/manual",
            abstract: "An abstract"
        )

        papers = await coordinator.papers
        let paper = papers.first { $0.id == paperId }!
        #expect(paper.title == "Manually Edited Title")
        #expect(paper.authors == ["Editor, Manual"])
        #expect(paper.year == 2025)
        #expect(paper.metadataSource == .manual)
        #expect(paper.importState == .resolved)
    }
}
