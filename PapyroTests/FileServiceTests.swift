// PapyroTests/FileServiceTests.swift
import Testing
import Foundation
@testable import Papyro

struct FileServiceTests {
    let fileService = FileService()

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir.appendingPathComponent("papers"), withIntermediateDirectories: true)
        return dir
    }

    private func createDummyPDF(at url: URL) {
        FileManager.default.createFile(atPath: url.path, contents: "dummy pdf content".data(using: .utf8))
    }

    @Test func copyToLibraryCopiesFileWithUUIDName() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourcePDF = FileManager.default.temporaryDirectory.appendingPathComponent("my-paper.pdf")
        createDummyPDF(at: sourcePDF)
        defer { try? FileManager.default.removeItem(at: sourcePDF) }

        let (newURL, paperId) = try fileService.copyToLibrary(source: sourcePDF, libraryRoot: tempDir)

        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(newURL.pathExtension == "pdf")
        #expect(newURL.deletingLastPathComponent().lastPathComponent == "papers")
        #expect(newURL.deletingPathExtension().lastPathComponent == paperId.uuidString)
    }

    @Test func renamePDFRenamesFile() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let originalURL = tempDir.appendingPathComponent("papers/old-name.pdf")
        createDummyPDF(at: originalURL)

        let newURL = try fileService.renamePDF(from: originalURL, to: "2024_smith_test-paper.pdf")

        #expect(!FileManager.default.fileExists(atPath: originalURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(newURL.lastPathComponent == "2024_smith_test-paper.pdf")
    }

    @Test func generateFilenameWithFullMetadata() {
        let name = fileService.generateFilename(year: 2024, author: "Chen", title: "Attention Mechanisms in Transformers")
        #expect(name == "2024_chen_attention-mechanisms-in-transformers.pdf")
    }

    @Test func generateFilenameWithoutYear() {
        let name = fileService.generateFilename(year: nil, author: "Smith", title: "Some Paper")
        #expect(name == "unknown_smith_some-paper.pdf")
    }

    @Test func generateFilenameWithoutAuthor() {
        let name = fileService.generateFilename(year: 2024, author: nil, title: "Some Paper")
        #expect(name == "2024_unknown_some-paper.pdf")
    }

    @Test func generateFilenameTruncatesLongTitles() {
        let longTitle = String(repeating: "word ", count: 50)
        let name = fileService.generateFilename(year: 2024, author: "Chen", title: longTitle)
        let stem = String(name.dropLast(4)) // remove ".pdf"
        #expect(stem.count <= 80)
    }

    @Test func generateFilenameHandlesSpecialCharacters() {
        let name = fileService.generateFilename(year: 2024, author: "O'Brien", title: "What's New? A (Brief) Review")
        #expect(!name.contains("'"))
        #expect(!name.contains("?"))
        #expect(!name.contains("("))
    }
}
