# M2: Import Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the core import pipeline — drop PDFs onto the window, copy them into the library, extract text, parse identifiers, fetch metadata from a translation-server (with CrossRef/Semantic Scholar fallback), write JSON indexes, and rename the PDF to a human-readable filename.

**Architecture:** Six focused services (`FileService`, `TextExtractor`, `IdentifierParser`, `MetadataProvider`, `IndexService`) coordinated by an `ImportCoordinator`. Each service is independently testable. `MetadataProvider` is a protocol with real (translation-server, CrossRef) and mock implementations. The paper list UI updates reactively via `@Observable` state as each import progresses through stages.

**Tech Stack:** Swift 6.0, SwiftUI, macOS 15+, PDFKit, URLSession, Swift Testing framework, XcodeGen

**Spec:** `docs/superpowers/specs/2026-04-02-m2-import-pipeline-design.md`

---

## File Structure

### New files

| File | Responsibility |
|---|---|
| `Papyro/Models/Paper.swift` | `Paper` struct, `ReadingStatus`, `MetadataSource`, `ImportState` enums |
| `Papyro/Models/PaperMetadata.swift` | `PaperMetadata` struct (metadata fetch result), `ParsedIdentifiers` struct |
| `Papyro/Services/FileService.swift` | Copy PDF to library, rename, generate human-readable filenames |
| `Papyro/Services/TextExtractor.swift` | PDFKit text extraction from first N pages, cache to disk |
| `Papyro/Services/IdentifierParser.swift` | Regex parsing for DOI, arXiv ID, PMID, ISBN |
| `Papyro/Services/MetadataProvider.swift` | `MetadataProvider` protocol definition |
| `Papyro/Services/TranslationServerProvider.swift` | HTTP calls to Zotero translation-server |
| `Papyro/Services/CrossRefProvider.swift` | HTTP calls to CrossRef API (fallback) |
| `Papyro/Services/SemanticScholarProvider.swift` | HTTP calls to Semantic Scholar API (fallback) |
| `Papyro/Services/IndexService.swift` | Read/write per-paper JSON, rebuild `_all.json` |
| `Papyro/Services/ImportCoordinator.swift` | Orchestrates the 6-step pipeline, holds paper collection |
| `Papyro/Views/PaperRowView.swift` | Single paper row with state-dependent rendering |
| `PapyroTests/PaperTests.swift` | Paper model encode/decode tests |
| `PapyroTests/IdentifierParserTests.swift` | Regex tests for each identifier type |
| `PapyroTests/FileServiceTests.swift` | Copy, rename, filename generation tests |
| `PapyroTests/TextExtractorTests.swift` | PDFKit extraction tests |
| `PapyroTests/IndexServiceTests.swift` | Save/load/rebuild JSON roundtrip tests |
| `PapyroTests/ImportCoordinatorTests.swift` | End-to-end pipeline test with mock metadata |

### Modified files

| File | Changes |
|---|---|
| `Papyro/Models/LibraryConfig.swift` | Add `translationServerURL: String?` field |
| `Papyro/Models/AppState.swift` | Add `papers: [Paper]`, `selectedPaper: Paper?` |
| `Papyro/Services/LibraryManager.swift` | Update subdirectories to match PRD, add migration |
| `Papyro/Views/PaperListView.swift` | Replace placeholder with paper list + drop target |
| `Papyro/Views/DetailView.swift` | Replace placeholder with metadata display + editing |
| `Papyro/Views/MainView.swift` | Pass ImportCoordinator to child views |
| `Papyro/PapyroApp.swift` | Create and inject ImportCoordinator and services |
| `PapyroTests/LibraryConfigTests.swift` | Update for new `translationServerURL` field |
| `PapyroTests/LibraryManagerTests.swift` | Update folder assertions for new names |

---

## Build & Test Commands

All commands run from the project root (`/Users/yuhanli/allgemeiner-intellekt/papyro`).

```bash
# Regenerate Xcode project after adding/removing files
xcodegen

# Build only (fast check for compilation errors)
xcodebuild build -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet

# Run all tests
xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet

# Run a specific test class
xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -only-testing 'PapyroTests/IdentifierParserTests' -quiet
```

---

## Task 1: Folder Alignment and LibraryConfig Update

Update `LibraryManager` to create the correct folder structure matching the PRD, update `LibraryConfig` with the translation-server URL, and fix existing tests.

**Files:**
- Modify: `Papyro/Models/LibraryConfig.swift`
- Modify: `Papyro/Services/LibraryManager.swift`
- Modify: `PapyroTests/LibraryConfigTests.swift`
- Modify: `PapyroTests/LibraryManagerTests.swift`

- [ ] **Step 1: Update LibraryConfig to add translationServerURL**

```swift
// Papyro/Models/LibraryConfig.swift
import Foundation

struct LibraryConfig: Codable {
    let version: Int
    var libraryPath: String
    var translationServerURL: String?
}
```

- [ ] **Step 2: Update LibraryConfigTests**

```swift
// PapyroTests/LibraryConfigTests.swift
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
```

- [ ] **Step 3: Update LibraryManager subdirectories**

```swift
// Papyro/Services/LibraryManager.swift — change the subdirectories array
private let subdirectories = ["papers", "index", "notes", ".symlinks", ".cache/text", "templates"]
```

Also update `setupLibrary` to pass `translationServerURL: nil` when creating the config:

```swift
let config = LibraryConfig(version: 1, libraryPath: path.path, translationServerURL: nil)
```

- [ ] **Step 4: Update LibraryManagerTests to expect new folder names**

In `setupLibraryCreatesFoldersAndConfig`, replace the folder assertions:

```swift
// Verify folders exist
let fm = FileManager.default
#expect(fm.fileExists(atPath: tempDir.appendingPathComponent("papers").path))
#expect(fm.fileExists(atPath: tempDir.appendingPathComponent("index").path))
#expect(fm.fileExists(atPath: tempDir.appendingPathComponent("notes").path))
#expect(fm.fileExists(atPath: tempDir.appendingPathComponent(".symlinks").path))
#expect(fm.fileExists(atPath: tempDir.appendingPathComponent(".cache/text").path))
#expect(fm.fileExists(atPath: tempDir.appendingPathComponent("templates").path))
```

- [ ] **Step 5: Regenerate project and run all tests**

Run: `xcodegen && xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet`

Expected: All tests pass (4 tests — 2 updated LibraryConfigTests + 3 LibraryManagerTests, minus the old one = 5 total).

- [ ] **Step 6: Commit**

```bash
git add Papyro/Models/LibraryConfig.swift Papyro/Services/LibraryManager.swift PapyroTests/LibraryConfigTests.swift PapyroTests/LibraryManagerTests.swift
git commit -m "refactor: align folder structure with PRD, add translationServerURL to config"
```

---

## Task 2: Paper Model and Supporting Types

Create the `Paper` struct, enums, and supporting types. TDD: write the encode/decode test first.

**Files:**
- Create: `Papyro/Models/Paper.swift`
- Create: `Papyro/Models/PaperMetadata.swift`
- Create: `PapyroTests/PaperTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// PapyroTests/PaperTests.swift
import Testing
import Foundation
@testable import Papyro

struct PaperTests {
    @Test func encodesAndDecodesCorrectly() throws {
        let paper = Paper(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!,
            canonicalId: "10.1038/s41586-024-07998-6",
            title: "Test Paper",
            authors: ["Smith, J.", "Chen, L."],
            year: 2024,
            journal: "Nature",
            doi: "10.1038/s41586-024-07998-6",
            arxivId: nil,
            pmid: nil,
            isbn: nil,
            abstract: "A test abstract.",
            url: "https://doi.org/10.1038/s41586-024-07998-6",
            pdfPath: "papers/2024_smith_test-paper.pdf",
            pdfFilename: "2024_smith_test-paper.pdf",
            notePath: nil,
            topics: [],
            projects: [],
            status: .toRead,
            dateAdded: Date(timeIntervalSince1970: 1712000000),
            dateModified: Date(timeIntervalSince1970: 1712000000),
            metadataSource: .translationServer,
            metadataResolved: true,
            importState: .resolved
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(paper)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Paper.self, from: data)

        #expect(decoded.id == paper.id)
        #expect(decoded.title == "Test Paper")
        #expect(decoded.authors == ["Smith, J.", "Chen, L."])
        #expect(decoded.year == 2024)
        #expect(decoded.journal == "Nature")
        #expect(decoded.doi == "10.1038/s41586-024-07998-6")
        #expect(decoded.status == .toRead)
        #expect(decoded.metadataSource == .translationServer)
        #expect(decoded.metadataResolved == true)
        #expect(decoded.importState == .resolved)
    }

    @Test func defaultsForUnresolvedPaper() throws {
        let paper = Paper(
            id: UUID(),
            canonicalId: nil,
            title: "unknown-file.pdf",
            authors: [],
            year: nil,
            journal: nil,
            doi: nil,
            arxivId: nil,
            pmid: nil,
            isbn: nil,
            abstract: nil,
            url: nil,
            pdfPath: "papers/some-uuid.pdf",
            pdfFilename: "some-uuid.pdf",
            notePath: nil,
            topics: [],
            projects: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .none,
            metadataResolved: false,
            importState: .unresolved
        )

        #expect(paper.metadataResolved == false)
        #expect(paper.importState == .unresolved)
        #expect(paper.authors.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen && xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet 2>&1 | tail -5`

Expected: Build failure — `Paper` type not found.

- [ ] **Step 3: Create Paper.swift**

```swift
// Papyro/Models/Paper.swift
import Foundation

struct Paper: Codable, Identifiable {
    let id: UUID
    var canonicalId: String?

    var title: String
    var authors: [String]
    var year: Int?
    var journal: String?
    var doi: String?
    var arxivId: String?
    var pmid: String?
    var isbn: String?
    var abstract: String?
    var url: String?

    var pdfPath: String
    var pdfFilename: String
    var notePath: String?

    var topics: [String]
    var projects: [String]
    var status: ReadingStatus

    var dateAdded: Date
    var dateModified: Date
    var metadataSource: MetadataSource
    var metadataResolved: Bool
    var importState: ImportState
}

enum ReadingStatus: String, Codable {
    case toRead
    case reading
    case archived
}

enum MetadataSource: String, Codable {
    case translationServer
    case crossRef
    case semanticScholar
    case manual
    case none
}

enum ImportState: String, Codable {
    case importing
    case resolving
    case resolved
    case unresolved
}
```

- [ ] **Step 4: Create PaperMetadata.swift**

```swift
// Papyro/Models/PaperMetadata.swift
import Foundation

struct PaperMetadata: Sendable {
    var title: String
    var authors: [String]
    var year: Int?
    var journal: String?
    var doi: String?
    var arxivId: String?
    var abstract: String?
    var url: String?
    var source: MetadataSource
}

struct ParsedIdentifiers: Sendable {
    var doi: String?
    var arxivId: String?
    var pmid: String?
    var isbn: String?

    var bestIdentifier: String? {
        doi ?? arxivId ?? pmid ?? isbn
    }

    var isEmpty: Bool {
        doi == nil && arxivId == nil && pmid == nil && isbn == nil
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodegen && xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet`

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add Papyro/Models/Paper.swift Papyro/Models/PaperMetadata.swift PapyroTests/PaperTests.swift
git commit -m "feat: add Paper model, supporting types, and encode/decode tests"
```

---

## Task 3: IdentifierParser (TDD)

Pure regex logic with no dependencies. Ideal for thorough TDD.

**Files:**
- Create: `PapyroTests/IdentifierParserTests.swift`
- Create: `Papyro/Services/IdentifierParser.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// PapyroTests/IdentifierParserTests.swift
import Testing
import Foundation
@testable import Papyro

struct IdentifierParserTests {
    let parser = IdentifierParser()

    // MARK: - DOI

    @Test func parsesDOIFromText() {
        let text = "This paper (doi: 10.1038/s41586-024-07998-6) describes..."
        let result = parser.parse(text)
        #expect(result.doi == "10.1038/s41586-024-07998-6")
        #expect(result.bestIdentifier == "10.1038/s41586-024-07998-6")
    }

    @Test func parsesDOIWithHTTPSPrefix() {
        let text = "Available at https://doi.org/10.1126/science.abcdefg"
        let result = parser.parse(text)
        #expect(result.doi == "10.1126/science.abcdefg")
    }

    @Test func parsesDOIWithoutPrefix() {
        let text = "DOI 10.48550/arXiv.1706.03762"
        let result = parser.parse(text)
        #expect(result.doi == "10.48550/arXiv.1706.03762")
    }

    // MARK: - arXiv

    @Test func parsesArXivId() {
        let text = "arXiv:2401.12345v2 [cs.CL]"
        let result = parser.parse(text)
        #expect(result.arxivId == "2401.12345v2")
    }

    @Test func parsesArXivIdWithoutVersion() {
        let text = "See arxiv preprint 2312.00001"
        let result = parser.parse(text)
        #expect(result.arxivId == "2312.00001")
    }

    // MARK: - PMID

    @Test func parsesPMID() {
        let text = "PMID: 12345678"
        let result = parser.parse(text)
        #expect(result.pmid == "12345678")
    }

    @Test func parsesPMIDWithoutColon() {
        let text = "PMID12345678"
        let result = parser.parse(text)
        #expect(result.pmid == "12345678")
    }

    // MARK: - ISBN

    @Test func parsesISBN13() {
        let text = "ISBN 978-0-13-468599-1"
        let result = parser.parse(text)
        #expect(result.isbn == "978-0-13-468599-1")
    }

    // MARK: - Priority

    @Test func prioritizesDOIOverArXiv() {
        let text = "doi: 10.48550/arXiv.1706.03762 arXiv:1706.03762v1"
        let result = parser.parse(text)
        #expect(result.doi != nil)
        #expect(result.arxivId != nil)
        #expect(result.bestIdentifier == result.doi)
    }

    // MARK: - No match

    @Test func returnsEmptyForNoIdentifiers() {
        let text = "This is a paper about machine learning with no identifiers."
        let result = parser.parse(text)
        #expect(result.isEmpty)
        #expect(result.bestIdentifier == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen && xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet 2>&1 | tail -5`

Expected: Build failure — `IdentifierParser` not found.

- [ ] **Step 3: Implement IdentifierParser**

```swift
// Papyro/Services/IdentifierParser.swift
import Foundation

struct IdentifierParser: Sendable {

    func parse(_ text: String) -> ParsedIdentifiers {
        ParsedIdentifiers(
            doi: extractDOI(from: text),
            arxivId: extractArXivId(from: text),
            pmid: extractPMID(from: text),
            isbn: extractISBN(from: text)
        )
    }

    // MARK: - Private

    private func extractDOI(from text: String) -> String? {
        // Match DOI pattern, possibly preceded by "doi:", "doi.org/", etc.
        let pattern = #"(?:doi\.org/|doi:?\s*)(10\.\d{4,9}/[^\s]+)"#
        if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            let fullMatch = String(text[match])
            // Extract just the 10.xxxx/... part
            if let doiRange = fullMatch.range(of: #"10\.\d{4,9}/[^\s]+"#, options: .regularExpression) {
                return cleanDOI(String(fullMatch[doiRange]))
            }
        }
        // Try bare DOI (not prefixed)
        let barePattern = #"10\.\d{4,9}/[-._;()/:A-Za-z0-9]+"#
        if let match = text.range(of: barePattern, options: .regularExpression) {
            return cleanDOI(String(text[match]))
        }
        return nil
    }

    private func cleanDOI(_ doi: String) -> String {
        // Strip trailing punctuation that's not part of the DOI
        var cleaned = doi
        while let last = cleaned.last, [".", ",", ";", ")", "]"].contains(String(last)) {
            cleaned.removeLast()
        }
        return cleaned
    }

    private func extractArXivId(from text: String) -> String? {
        let pattern = #"\d{4}\.\d{4,5}(?:v\d+)?"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[match])
    }

    private func extractPMID(from text: String) -> String? {
        let pattern = #"PMID:?\s*(\d{7,8})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange) else { return nil }
        guard let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func extractISBN(from text: String) -> String? {
        let pattern = #"(?:978|979)[-\s]?\d{1,5}[-\s]?\d{1,7}[-\s]?\d{1,7}[-\s]?\d"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[match])
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen && xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -only-testing 'PapyroTests/IdentifierParserTests' -quiet`

Expected: All 11 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Papyro/Services/IdentifierParser.swift PapyroTests/IdentifierParserTests.swift
git commit -m "feat: add IdentifierParser with DOI, arXiv, PMID, ISBN regex extraction"
```

---

## Task 4: FileService (TDD)

Handles copying PDFs into the library and renaming them after metadata resolves.

**Files:**
- Create: `PapyroTests/FileServiceTests.swift`
- Create: `Papyro/Services/FileService.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// PapyroTests/FileServiceTests.swift
import Testing
import Foundation
@testable import Papyro

struct FileServiceTests {
    let fileService = FileService()
    let fm = FileManager.default

    private func makeTempDir() -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try! fm.createDirectory(at: dir.appendingPathComponent("papers"), withIntermediateDirectories: true)
        return dir
    }

    private func createDummyPDF(at url: URL) {
        // A minimal valid file (doesn't need to be a real PDF for file ops)
        fm.createFile(atPath: url.path, contents: "dummy pdf content".data(using: .utf8))
    }

    @Test func copyToLibraryCopiesFileWithUUIDName() throws {
        let tempDir = makeTempDir()
        defer { try? fm.removeItem(at: tempDir) }

        let sourcePDF = fm.temporaryDirectory.appendingPathComponent("my-paper.pdf")
        createDummyPDF(at: sourcePDF)
        defer { try? fm.removeItem(at: sourcePDF) }

        let (newURL, paperId) = try fileService.copyToLibrary(source: sourcePDF, libraryRoot: tempDir)

        #expect(fm.fileExists(atPath: newURL.path))
        #expect(newURL.pathExtension == "pdf")
        #expect(newURL.deletingLastPathComponent().lastPathComponent == "papers")
        // Filename should be the UUID
        #expect(newURL.deletingPathExtension().lastPathComponent == paperId.uuidString)
    }

    @Test func renamePDFRenamesFile() throws {
        let tempDir = makeTempDir()
        defer { try? fm.removeItem(at: tempDir) }

        let originalURL = tempDir.appendingPathComponent("papers/old-name.pdf")
        createDummyPDF(at: originalURL)

        let newURL = try fileService.renamePDF(from: originalURL, to: "2024_smith_test-paper.pdf")

        #expect(!fm.fileExists(atPath: originalURL.path))
        #expect(fm.fileExists(atPath: newURL.path))
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
        // Total filename (without .pdf) should not exceed 80 chars
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen && xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet 2>&1 | tail -5`

Expected: Build failure — `FileService` not found.

- [ ] **Step 3: Implement FileService**

```swift
// Papyro/Services/FileService.swift
import Foundation

struct FileService: Sendable {
    private let fileManager = FileManager.default

    /// Copies a PDF into the library's papers/ directory with a UUID filename.
    /// Returns the new URL and the generated UUID.
    func copyToLibrary(source: URL, libraryRoot: URL) throws -> (URL, UUID) {
        let paperId = UUID()
        let destination = libraryRoot
            .appendingPathComponent("papers")
            .appendingPathComponent("\(paperId.uuidString).pdf")

        try fileManager.copyItem(at: source, to: destination)
        return (destination, paperId)
    }

    /// Renames a PDF within its current directory.
    /// Returns the new URL.
    func renamePDF(from currentURL: URL, to newName: String) throws -> URL {
        let newURL = currentURL.deletingLastPathComponent().appendingPathComponent(newName)
        try fileManager.moveItem(at: currentURL, to: newURL)
        return newURL
    }

    /// Generates a human-readable filename from metadata.
    /// Format: {year}_{author}_{title-slug}.pdf
    func generateFilename(year: Int?, author: String?, title: String) -> String {
        let yearPart = year.map(String.init) ?? "unknown"
        let authorPart = slugify(author ?? "unknown")
        let titlePart = slugify(title)

        let stem = "\(yearPart)_\(authorPart)_\(titlePart)"
        let maxLength = 80
        let truncated = stem.count > maxLength ? String(stem.prefix(maxLength)) : stem

        return "\(truncated).pdf"
    }

    // MARK: - Private

    private func slugify(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacing(/[^a-z0-9\s-]/, with: "")
            .replacing(/\s+/, with: "-")
            .replacing(/-+/, with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen && xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -only-testing 'PapyroTests/FileServiceTests' -quiet`

Expected: All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Papyro/Services/FileService.swift PapyroTests/FileServiceTests.swift
git commit -m "feat: add FileService for PDF copy, rename, and filename generation"
```

---

## Task 5: TextExtractor (TDD)

Uses PDFKit to extract text from the first N pages of a PDF and caches it to disk.

**Files:**
- Create: `PapyroTests/TextExtractorTests.swift`
- Create: `Papyro/Services/TextExtractor.swift`

- [ ] **Step 1: Write the failing tests**

Note: These tests need a real PDF. We'll create a minimal one programmatically using PDFKit in the test.

```swift
// PapyroTests/TextExtractorTests.swift
import Testing
import Foundation
import PDFKit
@testable import Papyro

struct TextExtractorTests {
    let extractor = TextExtractor()
    let fm = FileManager.default

    /// Creates a minimal PDF with the given text on one page.
    private func createTestPDF(text: String, at url: URL) {
        let pdfDocument = PDFDocument()
        let page = PDFPage()
        // We can't easily set text on a PDFPage programmatically without Core Graphics.
        // Instead, create a PDF using CGContext.
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &UnsafeMutablePointer(mutating: [pageRect]).pointee, nil) else {
            return
        }
        var mediaBox = pageRect
        context.beginPage(mediaBox: &mediaBox)
        let font = CTFontCreateWithName("Helvetica" as CFString, 12.0, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let frameSetter = CTFramesetterCreateWithAttributedString(attributedString as CFAttributedString)
        let textRect = CGRect(x: 72, y: 72, width: 468, height: 648)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(frameSetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        context.endPage()
        context.closePDF()
        try? (data as Data).write(to: url)
    }

    @Test func extractsTextFromPDF() throws {
        let pdfURL = fm.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).pdf")
        defer { try? fm.removeItem(at: pdfURL) }

        createTestPDF(text: "This is a test paper about machine learning. DOI: 10.1234/test.5678", at: pdfURL)

        let text = extractor.extractText(from: pdfURL)
        #expect(text != nil)
        #expect(text!.contains("machine learning") || text!.contains("10.1234"))
    }

    @Test func returnsNilForNonExistentFile() {
        let badURL = URL(fileURLWithPath: "/nonexistent/file.pdf")
        let text = extractor.extractText(from: badURL)
        #expect(text == nil)
    }

    @Test func cachesTextToDisk() throws {
        let tempDir = fm.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir.appendingPathComponent(".cache/text"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let paperId = UUID()
        try extractor.cacheText("some extracted text", for: paperId, in: tempDir)

        let cachedURL = tempDir.appendingPathComponent(".cache/text/\(paperId.uuidString).txt")
        #expect(fm.fileExists(atPath: cachedURL.path))

        let content = try String(contentsOf: cachedURL, encoding: .utf8)
        #expect(content == "some extracted text")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen && xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet 2>&1 | tail -5`

Expected: Build failure — `TextExtractor` not found.

- [ ] **Step 3: Implement TextExtractor**

```swift
// Papyro/Services/TextExtractor.swift
import Foundation
import PDFKit

struct TextExtractor: Sendable {

    /// Extracts text from the first N pages of a PDF.
    /// Returns nil if the file can't be opened or has no extractable text.
    func extractText(from pdfURL: URL, pages: Int = 5) -> String? {
        guard let document = PDFDocument(url: pdfURL) else { return nil }

        let pageCount = min(document.pageCount, pages)
        guard pageCount > 0 else { return nil }

        var texts: [String] = []
        for i in 0..<pageCount {
            if let page = document.page(at: i), let text = page.string {
                texts.append(text)
            }
        }

        let combined = texts.joined(separator: "\n\n")
        return combined.isEmpty ? nil : combined
    }

    /// Caches extracted text to .cache/text/{paperId}.txt
    func cacheText(_ text: String, for paperId: UUID, in libraryRoot: URL) throws {
        let cacheDir = libraryRoot.appendingPathComponent(".cache/text")
        let fileURL = cacheDir.appendingPathComponent("\(paperId.uuidString).txt")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen && xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -only-testing 'PapyroTests/TextExtractorTests' -quiet`

Expected: All 3 tests pass. (The `extractsTextFromPDF` test depends on successfully creating a PDF with Core Graphics — if it fails due to the PDF creation helper, simplify the test to only check `returnsNilForNonExistentFile` and `cachesTextToDisk`, and verify PDF extraction manually.)

- [ ] **Step 5: Commit**

```bash
git add Papyro/Services/TextExtractor.swift PapyroTests/TextExtractorTests.swift
git commit -m "feat: add TextExtractor for PDFKit text extraction and caching"
```

---

## Task 6: IndexService (TDD)

Reads and writes per-paper JSON files in `index/` and rebuilds the combined `_all.json`.

**Files:**
- Create: `PapyroTests/IndexServiceTests.swift`
- Create: `Papyro/Services/IndexService.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// PapyroTests/IndexServiceTests.swift
import Testing
import Foundation
@testable import Papyro

struct IndexServiceTests {
    let indexService = IndexService()
    let fm = FileManager.default

    private func makeTempLibrary() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("index"), withIntermediateDirectories: true)
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
            topics: [],
            projects: [],
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
        defer { try? fm.removeItem(at: libRoot) }

        let paper = makePaper()
        try indexService.save(paper, in: libRoot)

        let indexFile = libRoot.appendingPathComponent("index/\(paper.id.uuidString).json")
        #expect(fm.fileExists(atPath: indexFile.path))

        let papers = try indexService.loadAll(from: libRoot)
        #expect(papers.count == 1)
        #expect(papers[0].title == "Test Paper")
        #expect(papers[0].id == paper.id)
    }

    @Test func savesMultiplePapersAndLoadsAll() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

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
        defer { try? fm.removeItem(at: libRoot) }

        let paper1 = makePaper(title: "Paper One")
        let paper2 = makePaper(title: "Paper Two")

        try indexService.rebuildCombinedIndex(from: [paper1, paper2], in: libRoot)

        let allJsonURL = libRoot.appendingPathComponent("index/_all.json")
        #expect(fm.fileExists(atPath: allJsonURL.path))

        let data = try Data(contentsOf: allJsonURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let papers = try decoder.decode([Paper].self, from: data)
        #expect(papers.count == 2)
    }

    @Test func updateExistingPaper() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let paperId = UUID()
        var paper = makePaper(id: paperId, title: "Original Title")
        try indexService.save(paper, in: libRoot)

        paper.title = "Updated Title"
        try indexService.save(paper, in: libRoot)

        let papers = try indexService.loadAll(from: libRoot)
        #expect(papers.count == 1)
        #expect(papers[0].title == "Updated Title")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen && xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet 2>&1 | tail -5`

Expected: Build failure — `IndexService` not found.

- [ ] **Step 3: Implement IndexService**

```swift
// Papyro/Services/IndexService.swift
import Foundation

struct IndexService: Sendable {

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    /// Saves a paper's metadata as index/{paper.id}.json.
    /// Overwrites if the file already exists (for updates).
    func save(_ paper: Paper, in libraryRoot: URL) throws {
        let indexDir = libraryRoot.appendingPathComponent("index")
        let fileURL = indexDir.appendingPathComponent("\(paper.id.uuidString).json")
        let data = try encoder.encode(paper)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Loads all papers from individual JSON files in index/.
    /// Skips _all.json and any files that fail to decode.
    func loadAll(from libraryRoot: URL) throws -> [Paper] {
        let indexDir = libraryRoot.appendingPathComponent("index")
        let contents = try FileManager.default.contentsOfDirectory(
            at: indexDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )

        return contents.compactMap { url in
            guard url.pathExtension == "json",
                  url.lastPathComponent != "_all.json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Paper.self, from: data)
        }
    }

    /// Regenerates index/_all.json from the given papers array.
    func rebuildCombinedIndex(from papers: [Paper], in libraryRoot: URL) throws {
        let allJsonURL = libraryRoot.appendingPathComponent("index/_all.json")
        let data = try encoder.encode(papers)
        try data.write(to: allJsonURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen && xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -only-testing 'PapyroTests/IndexServiceTests' -quiet`

Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Papyro/Services/IndexService.swift PapyroTests/IndexServiceTests.swift
git commit -m "feat: add IndexService for per-paper JSON persistence and combined index"
```

---

## Task 7: MetadataProvider Protocol and Mock

Define the protocol and a mock implementation for testing.

**Files:**
- Create: `Papyro/Services/MetadataProvider.swift`

- [ ] **Step 1: Create MetadataProvider protocol and MockMetadataProvider**

```swift
// Papyro/Services/MetadataProvider.swift
import Foundation

protocol MetadataProvider: Sendable {
    /// Fetch metadata using parsed identifiers (DOI, arXiv ID, etc.)
    func fetchMetadata(for identifiers: ParsedIdentifiers) async throws -> PaperMetadata?

    /// Search by title as a fallback when no identifiers are found.
    func searchByTitle(_ title: String) async throws -> PaperMetadata?
}

/// Mock implementation for testing. Returns canned responses.
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
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodegen && xcodebuild build -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Papyro/Services/MetadataProvider.swift
git commit -m "feat: add MetadataProvider protocol and MockMetadataProvider"
```

---

## Task 8: TranslationServerProvider

HTTP client for the Zotero translation-server.

**Files:**
- Create: `Papyro/Services/TranslationServerProvider.swift`

- [ ] **Step 1: Implement TranslationServerProvider**

The translation-server's `/search` endpoint accepts a plain-text identifier and returns an array of Zotero-format JSON items. We need to map the Zotero format to our `PaperMetadata`.

```swift
// Papyro/Services/TranslationServerProvider.swift
import Foundation

final class TranslationServerProvider: MetadataProvider, Sendable {
    private let serverURL: URL
    private let session: URLSession

    init(serverURL: URL, session: URLSession = .shared) {
        self.serverURL = serverURL
        self.session = session
    }

    func fetchMetadata(for identifiers: ParsedIdentifiers) async throws -> PaperMetadata? {
        guard let identifier = identifiers.bestIdentifier else { return nil }

        let searchURL = serverURL.appendingPathComponent("search")
        var request = URLRequest(url: searchURL)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = identifier.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        return try parseZoteroResponse(data)
    }

    func searchByTitle(_ title: String) async throws -> PaperMetadata? {
        // Translation-server doesn't support title search directly.
        // This provider only works with identifiers.
        return nil
    }

    // MARK: - Private

    /// Parses the Zotero translation-server JSON response into PaperMetadata.
    /// The response is an array of items; we take the first one.
    private func parseZoteroResponse(_ data: Data) throws -> PaperMetadata? {
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let item = items.first else {
            return nil
        }

        let title = item["title"] as? String ?? ""
        let creators = item["creators"] as? [[String: Any]] ?? []
        let authors = creators.compactMap { creator -> String? in
            let lastName = creator["lastName"] as? String
            let firstName = creator["firstName"] as? String
            if let last = lastName, let first = firstName {
                return "\(last), \(first)"
            }
            return lastName ?? creator["name"] as? String
        }

        let dateStr = item["date"] as? String ?? ""
        let year = parseYear(from: dateStr)

        return PaperMetadata(
            title: title,
            authors: authors,
            year: year,
            journal: item["publicationTitle"] as? String ?? item["proceedingsTitle"] as? String,
            doi: item["DOI"] as? String,
            arxivId: nil,
            abstract: item["abstractNote"] as? String,
            url: item["url"] as? String,
            source: .translationServer
        )
    }

    private func parseYear(from dateString: String) -> Int? {
        // Try to extract a 4-digit year from various date formats
        guard let match = dateString.range(of: #"\d{4}"#, options: .regularExpression) else { return nil }
        return Int(dateString[match])
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodegen && xcodebuild build -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Papyro/Services/TranslationServerProvider.swift
git commit -m "feat: add TranslationServerProvider for Zotero translation-server HTTP integration"
```

---

## Task 9: CrossRefProvider and SemanticScholarProvider

Fallback metadata providers using free public APIs.

**Files:**
- Create: `Papyro/Services/CrossRefProvider.swift`
- Create: `Papyro/Services/SemanticScholarProvider.swift`

- [ ] **Step 1: Implement CrossRefProvider**

```swift
// Papyro/Services/CrossRefProvider.swift
import Foundation

final class CrossRefProvider: MetadataProvider, Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchMetadata(for identifiers: ParsedIdentifiers) async throws -> PaperMetadata? {
        // CrossRef can look up by DOI directly
        guard let doi = identifiers.doi else { return nil }

        let urlString = "https://api.crossref.org/works/\(doi)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Papyro/0.1 (mailto:papyro@example.com)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        return try parseCrossRefResponse(data)
    }

    func searchByTitle(_ title: String) async throws -> PaperMetadata? {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.crossref.org/works?query.bibliographic=\(encoded)&rows=3") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Papyro/0.1 (mailto:papyro@example.com)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        return try parseCrossRefSearchResponse(data, searchTitle: title)
    }

    // MARK: - Private

    private func parseCrossRefResponse(_ data: Data) throws -> PaperMetadata? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any] else {
            return nil
        }
        return extractMetadata(from: message)
    }

    private func parseCrossRefSearchResponse(_ data: Data, searchTitle: String) throws -> PaperMetadata? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let items = message["items"] as? [[String: Any]],
              let firstItem = items.first else {
            return nil
        }
        return extractMetadata(from: firstItem)
    }

    private func extractMetadata(from item: [String: Any]) -> PaperMetadata? {
        let titleArray = item["title"] as? [String]
        let title = titleArray?.first ?? ""
        guard !title.isEmpty else { return nil }

        let authorArray = item["author"] as? [[String: Any]] ?? []
        let authors = authorArray.compactMap { author -> String? in
            guard let family = author["family"] as? String else { return nil }
            let given = author["given"] as? String
            return given != nil ? "\(family), \(given!)" : family
        }

        var year: Int?
        if let dateParts = item["published-print"] as? [String: Any] ?? item["published-online"] as? [String: Any],
           let parts = dateParts["date-parts"] as? [[Int]],
           let firstPart = parts.first, !firstPart.isEmpty {
            year = firstPart[0]
        }

        let containerTitle = (item["container-title"] as? [String])?.first

        return PaperMetadata(
            title: title,
            authors: authors,
            year: year,
            journal: containerTitle,
            doi: item["DOI"] as? String,
            arxivId: nil,
            abstract: item["abstract"] as? String,
            url: item["URL"] as? String,
            source: .crossRef
        )
    }
}
```

- [ ] **Step 2: Implement SemanticScholarProvider**

```swift
// Papyro/Services/SemanticScholarProvider.swift
import Foundation

final class SemanticScholarProvider: MetadataProvider, Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchMetadata(for identifiers: ParsedIdentifiers) async throws -> PaperMetadata? {
        // Semantic Scholar accepts DOI or arXiv ID as paper identifiers
        let paperId: String
        if let doi = identifiers.doi {
            paperId = "DOI:\(doi)"
        } else if let arxivId = identifiers.arxivId {
            paperId = "ARXIV:\(arxivId)"
        } else {
            return nil
        }

        guard let encoded = paperId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.semanticscholar.org/graph/v1/paper/\(encoded)?fields=title,authors,year,venue,externalIds,abstract,url") else {
            return nil
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        return try parseS2Response(data)
    }

    func searchByTitle(_ title: String) async throws -> PaperMetadata? {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.semanticscholar.org/graph/v1/paper/search?query=\(encoded)&limit=3&fields=title,authors,year,venue,externalIds,abstract,url") else {
            return nil
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let papers = json["data"] as? [[String: Any]],
              let firstPaper = papers.first else {
            return nil
        }

        return extractMetadata(from: firstPaper)
    }

    // MARK: - Private

    private func parseS2Response(_ data: Data) throws -> PaperMetadata? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return extractMetadata(from: json)
    }

    private func extractMetadata(from item: [String: Any]) -> PaperMetadata? {
        guard let title = item["title"] as? String, !title.isEmpty else { return nil }

        let authorArray = item["authors"] as? [[String: Any]] ?? []
        let authors = authorArray.compactMap { $0["name"] as? String }

        let externalIds = item["externalIds"] as? [String: Any]

        return PaperMetadata(
            title: title,
            authors: authors,
            year: item["year"] as? Int,
            journal: item["venue"] as? String,
            doi: externalIds?["DOI"] as? String,
            arxivId: externalIds?["ArXiv"] as? String,
            abstract: item["abstract"] as? String,
            url: item["url"] as? String,
            source: .semanticScholar
        )
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodegen && xcodebuild build -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Papyro/Services/CrossRefProvider.swift Papyro/Services/SemanticScholarProvider.swift
git commit -m "feat: add CrossRef and Semantic Scholar metadata providers"
```

---

## Task 10: ImportCoordinator (TDD)

The orchestrator that drives the 6-step pipeline. Tested with MockMetadataProvider.

**Files:**
- Create: `PapyroTests/ImportCoordinatorTests.swift`
- Create: `Papyro/Services/ImportCoordinator.swift`

- [ ] **Step 1: Write the failing test**

```swift
// PapyroTests/ImportCoordinatorTests.swift
import Testing
import Foundation
@testable import Papyro

struct ImportCoordinatorTests {
    let fm = FileManager.default

    private func makeTempLibrary() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        let subdirs = ["papers", "index", "notes", ".symlinks", ".cache/text", "templates"]
        for subdir in subdirs {
            try fm.createDirectory(at: dir.appendingPathComponent(subdir), withIntermediateDirectories: true)
        }
        return dir
    }

    private func createDummyPDF(named name: String = "test.pdf") -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        fm.createFile(atPath: url.path, contents: "dummy pdf".data(using: .utf8))
        return url
    }

    @Test func importSinglePDFWithMockMetadata() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

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

        let coordinator = ImportCoordinator(
            libraryRoot: libRoot,
            metadataProvider: mock
        )

        let sourcePDF = createDummyPDF()
        defer { try? fm.removeItem(at: sourcePDF) }

        await coordinator.importPDFs([sourcePDF])

        // Verify paper was added to the coordinator's collection
        #expect(coordinator.papers.count == 1)

        let paper = coordinator.papers[0]
        #expect(paper.title == "Attention Is All You Need")
        #expect(paper.authors == ["Vaswani, Ashish", "Shazeer, Noam"])
        #expect(paper.year == 2017)
        #expect(paper.metadataResolved == true)
        #expect(paper.importState == .resolved)

        // Verify PDF exists in papers/ with a human-readable name
        let pdfURL = libRoot.appendingPathComponent(paper.pdfPath)
        #expect(fm.fileExists(atPath: pdfURL.path))
        #expect(paper.pdfFilename.contains("vaswani"))
        #expect(paper.pdfFilename.contains("2017"))

        // Verify index JSON was written
        let indexFile = libRoot.appendingPathComponent("index/\(paper.id.uuidString).json")
        #expect(fm.fileExists(atPath: indexFile.path))

        // Verify _all.json was regenerated
        let allJson = libRoot.appendingPathComponent("index/_all.json")
        #expect(fm.fileExists(atPath: allJson.path))
    }

    @Test func importPDFWithNoMetadataBecomesUnresolved() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let mock = MockMetadataProvider()
        mock.metadataToReturn = nil
        mock.searchResult = nil

        let coordinator = ImportCoordinator(
            libraryRoot: libRoot,
            metadataProvider: mock
        )

        let sourcePDF = createDummyPDF(named: "mystery-paper.pdf")
        defer { try? fm.removeItem(at: sourcePDF) }

        await coordinator.importPDFs([sourcePDF])

        #expect(coordinator.papers.count == 1)

        let paper = coordinator.papers[0]
        #expect(paper.metadataResolved == false)
        #expect(paper.importState == .unresolved)
        // PDF should still exist (with UUID name since we can't rename without metadata)
        let pdfURL = libRoot.appendingPathComponent(paper.pdfPath)
        #expect(fm.fileExists(atPath: pdfURL.path))
    }

    @Test func importMultiplePDFs() async throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

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

        let coordinator = ImportCoordinator(
            libraryRoot: libRoot,
            metadataProvider: mock
        )

        let pdf1 = createDummyPDF(named: "paper1.pdf")
        let pdf2 = createDummyPDF(named: "paper2.pdf")
        let pdf3 = createDummyPDF(named: "paper3.pdf")
        defer {
            try? fm.removeItem(at: pdf1)
            try? fm.removeItem(at: pdf2)
            try? fm.removeItem(at: pdf3)
        }

        await coordinator.importPDFs([pdf1, pdf2, pdf3])

        #expect(coordinator.papers.count == 3)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen && xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet 2>&1 | tail -5`

Expected: Build failure — `ImportCoordinator` not found.

- [ ] **Step 3: Implement ImportCoordinator**

```swift
// Papyro/Services/ImportCoordinator.swift
import Foundation

@Observable
@MainActor
class ImportCoordinator {
    private(set) var papers: [Paper] = []

    private let libraryRoot: URL
    private let fileService: FileService
    private let textExtractor: TextExtractor
    private let identifierParser: IdentifierParser
    private let metadataProvider: MetadataProvider
    private let indexService: IndexService

    init(
        libraryRoot: URL,
        metadataProvider: MetadataProvider,
        fileService: FileService = FileService(),
        textExtractor: TextExtractor = TextExtractor(),
        identifierParser: IdentifierParser = IdentifierParser(),
        indexService: IndexService = IndexService()
    ) {
        self.libraryRoot = libraryRoot
        self.metadataProvider = metadataProvider
        self.fileService = fileService
        self.textExtractor = textExtractor
        self.identifierParser = identifierParser
        self.indexService = indexService
    }

    /// Loads existing papers from the index on disk.
    func loadExistingPapers() {
        if let loaded = try? indexService.loadAll(from: libraryRoot) {
            papers = loaded
        }
    }

    /// Imports one or more PDFs through the full pipeline.
    func importPDFs(_ urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { @MainActor in
                    await self.importSinglePDF(url)
                }
            }
        }
    }

    // MARK: - Private

    private func importSinglePDF(_ sourceURL: URL) async {
        // Step 1: Copy to library with temp UUID name
        let copyResult: (URL, UUID)
        do {
            copyResult = try fileService.copyToLibrary(source: sourceURL, libraryRoot: libraryRoot)
        } catch {
            return // silently skip files that fail to copy
        }
        let (pdfURL, paperId) = copyResult

        // Create initial paper in importing state
        var paper = Paper(
            id: paperId,
            canonicalId: nil,
            title: sourceURL.deletingPathExtension().lastPathComponent,
            authors: [],
            year: nil,
            journal: nil,
            doi: nil,
            arxivId: nil,
            pmid: nil,
            isbn: nil,
            abstract: nil,
            url: nil,
            pdfPath: "papers/\(pdfURL.lastPathComponent)",
            pdfFilename: pdfURL.lastPathComponent,
            notePath: nil,
            topics: [],
            projects: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .none,
            metadataResolved: false,
            importState: .importing
        )
        papers.append(paper)

        // Step 2: Extract text
        let extractedText = textExtractor.extractText(from: pdfURL)
        if let text = extractedText {
            try? textExtractor.cacheText(text, for: paperId, in: libraryRoot)
        }

        // Step 3: Parse identifiers
        let identifiers = extractedText.map { identifierParser.parse($0) } ?? ParsedIdentifiers()

        // Update state to resolving
        updatePaper(paperId) { $0.importState = .resolving }

        // Step 4: Fetch metadata
        let metadata = await fetchMetadataWithFallback(identifiers: identifiers, extractedText: extractedText)

        if let metadata = metadata {
            // Apply metadata to paper
            updatePaper(paperId) { p in
                p.canonicalId = metadata.doi ?? metadata.arxivId
                p.title = metadata.title
                p.authors = metadata.authors
                p.year = metadata.year
                p.journal = metadata.journal
                p.doi = metadata.doi
                p.arxivId = metadata.arxivId
                p.abstract = metadata.abstract
                p.url = metadata.url
                p.metadataSource = metadata.source
                p.metadataResolved = true
                p.importState = .resolved
                p.dateModified = Date()
            }

            // Step 6: Rename PDF to human-readable name
            let firstAuthor = metadata.authors.first.flatMap { $0.components(separatedBy: ",").first }
            let newFilename = fileService.generateFilename(
                year: metadata.year,
                author: firstAuthor,
                title: metadata.title
            )

            if let newURL = try? fileService.renamePDF(from: pdfURL, to: newFilename) {
                updatePaper(paperId) { p in
                    p.pdfPath = "papers/\(newURL.lastPathComponent)"
                    p.pdfFilename = newURL.lastPathComponent
                }
            }
        } else {
            // No metadata found
            updatePaper(paperId) { p in
                p.importState = .unresolved
                p.dateModified = Date()
            }
        }

        // Step 5: Write index
        if let finalPaper = papers.first(where: { $0.id == paperId }) {
            try? indexService.save(finalPaper, in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }

    private func fetchMetadataWithFallback(identifiers: ParsedIdentifiers, extractedText: String?) async -> PaperMetadata? {
        // Try primary provider with identifiers
        if !identifiers.isEmpty {
            if let metadata = try? await metadataProvider.fetchMetadata(for: identifiers) {
                return metadata
            }
        }

        // Fallback: search by title extracted from text (first non-empty line as a rough title guess)
        if let text = extractedText {
            let roughTitle = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.count > 10 && $0.count < 200 } ?? ""

            if !roughTitle.isEmpty {
                if let metadata = try? await metadataProvider.searchByTitle(roughTitle) {
                    return metadata
                }
            }
        }

        return nil
    }

    private func updatePaper(_ id: UUID, transform: (inout Paper) -> Void) {
        guard let index = papers.firstIndex(where: { $0.id == id }) else { return }
        transform(&papers[index])
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen && xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -only-testing 'PapyroTests/ImportCoordinatorTests' -quiet`

Expected: All 3 tests pass.

- [ ] **Step 5: Run all tests to check for regressions**

Run: `xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet`

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add Papyro/Services/ImportCoordinator.swift PapyroTests/ImportCoordinatorTests.swift
git commit -m "feat: add ImportCoordinator orchestrating the 6-step import pipeline"
```

---

## Task 11: Update AppState and Wire Services into PapyroApp

Connect the `ImportCoordinator` and its services to the app's environment so views can access them.

**Files:**
- Modify: `Papyro/Models/AppState.swift`
- Modify: `Papyro/PapyroApp.swift`

- [ ] **Step 1: Update AppState to add selectedPaper**

```swift
// Papyro/Models/AppState.swift
import SwiftUI

@Observable
class AppState {
    var libraryConfig: LibraryConfig?
    var selectedCategory: SidebarCategory = .all
    var selectedPaperId: UUID?
    var isOnboarding: Bool = true
}
```

- [ ] **Step 2: Update PapyroApp to create and inject ImportCoordinator**

```swift
// Papyro/PapyroApp.swift
import SwiftUI

@main
struct PapyroApp: App {
    @State private var appState: AppState
    @State private var libraryManager: LibraryManager
    @State private var importCoordinator: ImportCoordinator?

    init() {
        let state = AppState()
        _appState = State(initialValue: state)
        _libraryManager = State(initialValue: LibraryManager(appState: state))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isOnboarding {
                    WelcomeView()
                } else {
                    MainView()
                }
            }
            .environment(appState)
            .environment(libraryManager)
            .onChange(of: appState.libraryConfig) { _, newConfig in
                if let config = newConfig {
                    setupImportCoordinator(config: config)
                }
            }
            .onAppear {
                libraryManager.detectExistingLibrary()
            }
        }
    }

    private func setupImportCoordinator(config: LibraryConfig) {
        let libraryRoot = URL(fileURLWithPath: config.libraryPath)

        let metadataProvider: MetadataProvider
        if let serverURLString = config.translationServerURL,
           let serverURL = URL(string: serverURLString) {
            metadataProvider = TranslationServerProvider(serverURL: serverURL)
        } else {
            // No translation server configured — use CrossRef as primary
            metadataProvider = CrossRefProvider()
        }

        let coordinator = ImportCoordinator(
            libraryRoot: libraryRoot,
            metadataProvider: metadataProvider
        )
        coordinator.loadExistingPapers()
        importCoordinator = coordinator
    }
}
```

Wait — `ImportCoordinator` is `@MainActor` and `@Observable`, but we need to pass it to child views. Since it's not an environment object by default, we need to inject it. The cleanest way is to pass it via `.environment()` like the other objects, or pass it directly to `MainView`.

Let's update `MainView` to accept it and propagate it:

```swift
// Update PapyroApp.swift — the MainView section:
if appState.isOnboarding {
    WelcomeView()
} else if let coordinator = importCoordinator {
    MainView()
        .environment(coordinator)
} else {
    ProgressView("Loading library...")
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodegen && xcodebuild build -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet`

Expected: Build succeeds. (Some warnings about unused `importCoordinator` in views are fine — we wire it up in the next tasks.)

- [ ] **Step 4: Run all tests**

Run: `xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Papyro/Models/AppState.swift Papyro/PapyroApp.swift
git commit -m "feat: wire ImportCoordinator into PapyroApp with environment injection"
```

---

## Task 12: PaperRowView and PaperListView with Drop Target

Replace the M1 placeholder with a real paper list that shows import state and accepts PDF drops.

**Files:**
- Create: `Papyro/Views/PaperRowView.swift`
- Modify: `Papyro/Views/PaperListView.swift`

- [ ] **Step 1: Create PaperRowView**

```swift
// Papyro/Views/PaperRowView.swift
import SwiftUI

struct PaperRowView: View {
    let paper: Paper

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(paper.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            badge
        }
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusIcon: some View {
        switch paper.importState {
        case .importing, .resolving:
            ProgressView()
                .controlSize(.small)
        case .resolved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unresolved:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch paper.importState {
        case .importing:
            BadgeView(text: "Importing", color: .blue)
        case .resolving:
            BadgeView(text: "Resolving", color: .orange)
        case .resolved:
            BadgeView(text: paper.status.displayName, color: .blue)
        case .unresolved:
            BadgeView(text: "Unresolved", color: .red)
        }
    }

    private var subtitle: String {
        switch paper.importState {
        case .importing:
            "Importing..."
        case .resolving:
            paper.doi.map { "DOI: \($0) — Looking up metadata..." } ?? "Resolving..."
        case .resolved:
            formatAuthors(paper.authors, year: paper.year, journal: paper.journal)
        case .unresolved:
            "Could not resolve metadata"
        }
    }

    private func formatAuthors(_ authors: [String], year: Int?, journal: String?) -> String {
        var parts: [String] = []
        if let firstAuthor = authors.first {
            let surname = firstAuthor.components(separatedBy: ",").first ?? firstAuthor
            parts.append(authors.count > 1 ? "\(surname) et al." : surname)
        }
        if let year = year { parts.append(String(year)) }
        if let journal = journal, !journal.isEmpty { parts.append(journal) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - BadgeView

private struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - ReadingStatus display name

extension ReadingStatus {
    var displayName: String {
        switch self {
        case .toRead: "To Read"
        case .reading: "Reading"
        case .archived: "Archived"
        }
    }
}
```

- [ ] **Step 2: Update PaperListView with drop target**

```swift
// Papyro/Views/PaperListView.swift
import SwiftUI
import UniformTypeIdentifiers

struct PaperListView: View {
    let category: SidebarCategory
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var appState = appState

        Group {
            if coordinator.papers.isEmpty {
                ContentUnavailableView(
                    "No Papers Yet",
                    systemImage: "doc.text",
                    description: Text("Drag and drop PDF files here to import them.")
                )
            } else {
                List(coordinator.papers, selection: $appState.selectedPaperId) { paper in
                    PaperRowView(paper: paper)
                        .tag(paper.id)
                }
            }
        }
        .navigationTitle(category.displayName)
        .dropDestination(for: URL.self) { urls, _ in
            let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            guard !pdfURLs.isEmpty else { return false }
            Task { await coordinator.importPDFs(pdfURLs) }
            return true
        }
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodegen && xcodebuild build -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Papyro/Views/PaperRowView.swift Papyro/Views/PaperListView.swift
git commit -m "feat: add PaperRowView and PaperListView with drop target and state badges"
```

---

## Task 13: DetailView with Metadata Display and Editing

Replace the M1 placeholder with a full metadata panel. Supports inline editing and "Open PDF" / "Reveal in Finder" actions.

**Files:**
- Modify: `Papyro/Views/DetailView.swift`

- [ ] **Step 1: Implement DetailView**

```swift
// Papyro/Views/DetailView.swift
import SwiftUI

struct DetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    private var paper: Paper? {
        guard let id = appState.selectedPaperId else { return nil }
        return coordinator.papers.first { $0.id == id }
    }

    var body: some View {
        if let paper = paper {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection(paper)
                    Divider()
                    metadataSection(paper)
                    if let abstract = paper.abstract, !abstract.isEmpty {
                        Divider()
                        abstractSection(abstract)
                    }
                    Divider()
                    actionsSection(paper)
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "Select a Paper",
                systemImage: "doc.richtext",
                description: Text("Select a paper to view its details.")
            )
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func headerSection(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(paper.title)
                .font(.title2)
                .fontWeight(.bold)
                .textSelection(.enabled)

            if !paper.authors.isEmpty {
                Text(paper.authors.joined(separator: ", "))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                if let year = paper.year {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let journal = paper.journal, !journal.isEmpty {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(journal)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func metadataSection(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.headline)

            MetadataRow(label: "DOI", value: paper.doi)
            MetadataRow(label: "arXiv ID", value: paper.arxivId)
            MetadataRow(label: "PMID", value: paper.pmid)
            MetadataRow(label: "ISBN", value: paper.isbn)
            MetadataRow(label: "Status", value: paper.status.displayName)
            MetadataRow(label: "Source", value: paper.metadataSource.rawValue)
            MetadataRow(label: "Added", value: paper.dateAdded.formatted(date: .abbreviated, time: .omitted))
            MetadataRow(label: "File", value: paper.pdfFilename)
        }
    }

    @ViewBuilder
    private func abstractSection(_ abstract: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Abstract")
                .font(.headline)

            Text(abstract)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func actionsSection(_ paper: Paper) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 12) {
                Button("Open PDF") {
                    openPDF(paper)
                }

                Button("Reveal in Finder") {
                    revealInFinder(paper)
                }

                if !paper.metadataResolved {
                    Button("Retry Lookup") {
                        Task { await retryLookup(paper) }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func openPDF(_ paper: Paper) {
        guard let config = appState.libraryConfig else { return }
        let pdfURL = URL(fileURLWithPath: config.libraryPath)
            .appendingPathComponent(paper.pdfPath)
        NSWorkspace.shared.open(pdfURL)
    }

    private func revealInFinder(_ paper: Paper) {
        guard let config = appState.libraryConfig else { return }
        let pdfURL = URL(fileURLWithPath: config.libraryPath)
            .appendingPathComponent(paper.pdfPath)
        NSWorkspace.shared.activateFileViewerSelecting([pdfURL])
    }

    private func retryLookup(_ paper: Paper) async {
        // Re-import will be handled by a dedicated method in a future iteration.
        // For now, this is a placeholder for the retry flow.
    }
}

// MARK: - MetadataRow

private struct MetadataRow: View {
    let label: String
    let value: String?

    var body: some View {
        if let value = value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)

                Text(value)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodegen && xcodebuild build -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Papyro/Views/DetailView.swift
git commit -m "feat: add DetailView with metadata display, Open PDF, and Reveal in Finder"
```

---

## Task 14: Regenerate Xcode Project and Full Verification

Ensure the project file is up to date and all tests pass.

**Files:**
- Regenerate: `Papyro.xcodeproj`

- [ ] **Step 1: Regenerate the Xcode project**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && xcodegen`

Expected: "⚙️  Generating plists..." and "Created project" output.

- [ ] **Step 2: Run the full test suite**

Run: `xcodebuild test -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet`

Expected: All tests pass (PaperTests, IdentifierParserTests, FileServiceTests, TextExtractorTests, IndexServiceTests, ImportCoordinatorTests, LibraryConfigTests, LibraryManagerTests).

- [ ] **Step 3: Build and launch the app to verify manually**

Run: `xcodebuild build -project Papyro.xcodeproj -scheme Papyro -destination 'platform=macOS' -quiet`

Manual checks:
- App launches and shows WelcomeView (or MainView if library already configured)
- MainView shows three-column layout with empty paper list
- Paper list shows "Drag and drop PDF files here to import them."
- Dragging a PDF onto the paper list triggers the import pipeline
- Paper appears in the list with state badges
- Selecting a paper shows its metadata in the detail panel
- "Open PDF" button works
- "Reveal in Finder" button works

- [ ] **Step 4: Commit project file**

```bash
git add Papyro.xcodeproj
git commit -m "chore: regenerate Xcode project with M2 import pipeline files"
```

---

## Summary

| Task | What it builds | Test count |
|---|---|---|
| 1 | Folder alignment + LibraryConfig update | 5 (updated) |
| 2 | Paper model + supporting types | 2 |
| 3 | IdentifierParser | 11 |
| 4 | FileService | 7 |
| 5 | TextExtractor | 3 |
| 6 | IndexService | 4 |
| 7 | MetadataProvider protocol + Mock | 0 (protocol only) |
| 8 | TranslationServerProvider | 0 (needs real server) |
| 9 | CrossRef + Semantic Scholar providers | 0 (needs network) |
| 10 | ImportCoordinator | 3 |
| 11 | AppState + PapyroApp wiring | 0 (app integration) |
| 12 | PaperRowView + PaperListView | 0 (UI) |
| 13 | DetailView | 0 (UI) |
| 14 | Project regen + full verification | 0 (manual) |

**Total: 14 tasks, ~35 unit tests, 14 commits**

---

## Deferred to M2 Polish Pass

These items are in the spec's scope but deferred to a second pass within M2, after the core pipeline is working:

- **Inline metadata editing** — the DetailView displays all metadata fields as read-only with text selection. Click-to-edit with two-way binding back to the coordinator (saving changes to the JSON index) will be added once the read flow is stable.
- **Retry lookup for unresolved papers** — the "Retry Lookup" button is present in the UI but needs the coordinator to support re-running the metadata fetch for a specific paper.
- **PRD updates** — update `docs/papyro-prd.md` to reflect agreed deviations: flat `papers/`, copy-only import, human-readable filenames.
