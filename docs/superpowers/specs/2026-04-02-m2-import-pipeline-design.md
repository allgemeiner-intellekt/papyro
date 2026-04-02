# M2: Import Pipeline — Design Spec

**Date:** 2026-04-02
**Status:** Approved
**Milestone:** M2 (Import Pipeline)
**Depends on:** M1 (Skeleton) — completed

---

## 1. Scope

M2 delivers the core import pipeline: a user drops PDFs onto the Papyro window, the app copies them into the library, extracts text, identifies the paper, fetches metadata from a remote translation-server (with CrossRef/Semantic Scholar fallback), writes structured JSON indexes, and renames the PDF to a human-readable filename.

### In scope

- Folder alignment: rename M1 folders to match PRD (`metadata/` → `index/`, `views/` → `.symlinks/`, add `.cache/`, `templates/`)
- `Paper` data model (Codable struct with all metadata fields)
- 6-service import pipeline coordinated by `ImportCoordinator`
- Drag-and-drop onto the paper list (window drop target)
- Paper list UI with state badges (importing → resolving → resolved / unresolved)
- Detail panel showing full metadata for the selected paper
- Manual metadata editing (inline field editing in the detail panel)
- Translation-server integration via configurable URL
- CrossRef and Semantic Scholar fallback for metadata lookup
- Text extraction cache (`.cache/text/`)
- Combined index regeneration (`index/_all.json`)
- PRD updates (flat `papers/`, copy-only import, human-readable filenames)

### Out of scope

- Symlink-based views (M3)
- Notes generation and Obsidian integration (M5)
- Search and filter (M4)
- Filesystem watcher (M6)
- Offline queue with retry (M6)
- Dock icon drop target (M6)
- Keyboard shortcuts (M6)
- Move-as-import option (removed from PRD — copy only)

---

## 2. PRD Deviations

These changes to the PRD were agreed during design:

| PRD says | M2 design says | Reason |
|---|---|---|
| `papers/` organized by year subfolders | `papers/` is flat | All organization via symlinks; avoids chicken-and-egg problem with metadata-dependent filing |
| PDFs named by identifier only (e.g., `10.1038_...pdf`) | Named `{year}_{author}_{title-slug}.pdf` | Human-readable in Finder, sortable, grep-friendly |
| Import supports copy or move (user preference) | Copy only | Simpler, safer; move adds no real value since the original file stays untouched |
| `metadata/` folder (created in M1) | Renamed to `index/` | Align with PRD Section 4 specification |
| `views/` folder (created in M1) | Renamed to `.symlinks/` | Align with PRD Section 4 specification |
| `.cache/` and `templates/` not created in M1 | Added to library setup | `.cache/text/` needed for M2 text extraction; `templates/` reserved for M5 |

---

## 3. Revised On-Disk Layout

After M2, a library with imported papers looks like:

```
~/ResearchLibrary/
├── papers/                              # Flat — all PDFs here
│   ├── 2024_chen_attention-mechanisms.pdf
│   ├── 2017_vaswani_attention-is-all-you-need.pdf
│   └── unresolved_mysterious-paper.pdf
├── index/                               # Per-paper JSON + combined index
│   ├── {uuid}.json
│   └── _all.json
├── notes/                               # Empty until M5
├── .symlinks/                           # Empty until M3
├── .cache/
│   └── text/                            # Extracted text from first 5 pages
│       └── {uuid}.txt
├── templates/                           # Empty until M5
└── config.json
```

---

## 4. Architecture

### 4.1 Service decomposition

The import pipeline is a linear chain of 6 steps, coordinated by `ImportCoordinator`. Each service is independently testable and injectable.

```
ImportCoordinator  — orchestrates the flow, updates Paper state
├── FileService         — copy PDF, rename, filesystem I/O
├── TextExtractor       — PDFKit text extraction from first N pages
├── IdentifierParser    — regex for DOI, arXiv ID, PMID, ISBN
├── MetadataService     — protocol: TranslationServerProvider (primary),
│                         CrossRefProvider / SemanticScholarProvider (fallback)
└── IndexService        — read/write per-paper JSON, rebuild _all.json
```

### 4.2 Pipeline flow

1. **FileService.copyToLibrary** — copy PDF to `papers/{uuid}.pdf` (temporary name)
2. **TextExtractor.extractText** — PDFKit extracts text from first 5 pages → save to `.cache/text/{uuid}.txt`
3. **IdentifierParser.parse** — regex scan extracted text for DOI, arXiv ID, PMID, ISBN
4. **MetadataService.fetchMetadata** — query translation-server with identifier; fall back to CrossRef/Semantic Scholar by title if needed
5. **IndexService.save** — write per-paper JSON to `index/{uuid}.json`, regenerate `_all.json`
6. **FileService.renamePDF** — rename from `{uuid}.pdf` to `{year}_{author}_{title-slug}.pdf`

### 4.3 State transitions

A paper progresses through these states during import:

```
Importing → Resolving → Resolved
                     → Unresolved
```

- **Importing** — PDF dropped, file being copied. Paper appears in list with original filename + spinner + blue badge.
- **Resolving** — Text extracted, identifiers parsed, metadata fetch in progress. Row shows extracted title (if found) + amber badge.
- **Resolved** — Full metadata populated, PDF renamed, index written. Row shows title, authors, year, journal + reading status badge.
- **Unresolved** — Metadata fetch failed or no identifiers found. Row shows filename + red badge. User can edit manually or retry.

### 4.4 Concurrency

When multiple PDFs are dropped at once, each enters the pipeline independently via `Task`. The paper list updates reactively as each paper progresses through its states. No global serialization — papers resolve in parallel.

---

## 5. Data Model

### 5.1 Paper

```swift
struct Paper: Codable, Identifiable {
    // Identity
    let id: UUID                          // stable internal ID, assigned at import
    var canonicalId: String?              // DOI, arXiv ID, or nil if unresolved

    // Metadata
    var title: String                     // from metadata, or original filename as fallback
    var authors: [String]                 // empty array if unresolved
    var year: Int?
    var journal: String?
    var doi: String?
    var arxivId: String?
    var pmid: String?
    var isbn: String?
    var abstract: String?
    var url: String?

    // File paths (relative to library root)
    var pdfPath: String                   // e.g., "papers/2024_chen_attention.pdf"
    var pdfFilename: String               // display name
    var notePath: String?                 // nil until M5

    // Organization (populated in M3)
    var topics: [String]
    var projects: [String]
    var status: ReadingStatus

    // Tracking
    var dateAdded: Date
    var dateModified: Date
    var metadataSource: MetadataSource
    var metadataResolved: Bool
}

enum ReadingStatus: String, Codable {
    case toRead, reading, archived
}

enum MetadataSource: String, Codable {
    case translationServer, crossRef, semanticScholar, manual, none
}
```

### 5.2 Supporting types

```swift
struct ParsedIdentifiers {
    var doi: String?
    var arxivId: String?
    var pmid: String?
    var isbn: String?
    var bestIdentifier: String?  // first non-nil in priority: DOI > arXiv > PMID > ISBN
}

struct PaperMetadata {
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
```

---

## 6. Service Contracts

### 6.1 FileService

```swift
class FileService {
    func copyToLibrary(source: URL, libraryRoot: URL) throws -> URL
    // Copies PDF to papers/{uuid}.pdf, returns new URL

    func renamePDF(from currentURL: URL, to newName: String) throws -> URL
    // Renames file in papers/, returns new URL

    func generateFilename(year: Int?, author: String?, title: String) -> String
    // Returns "2024_chen_attention-mechanisms.pdf" or "unresolved_original-name.pdf"
}
```

### 6.2 TextExtractor

```swift
class TextExtractor {
    func extractText(from pdfURL: URL, pages: Int = 5) -> String?
    // Returns concatenated text from first N pages, or nil

    func cacheText(_ text: String, for paperId: UUID, in libraryRoot: URL) throws
    // Writes to .cache/text/{uuid}.txt
}
```

### 6.3 IdentifierParser

```swift
struct IdentifierParser {
    func parse(_ text: String) -> ParsedIdentifiers
    // Scans text for DOI, arXiv ID, PMID, ISBN
}
```

Identifier patterns:

| Identifier | Pattern | Example |
|---|---|---|
| DOI | `10.\d{4,9}/[-._;()/:A-Z0-9]+` (case-insensitive) | `10.1038/s41586-024-07998-6` |
| arXiv ID | `\d{4}\.\d{4,5}(v\d+)?` | `2401.12345v2` |
| PMID | `PMID:?\s*\d{7,8}` | `PMID: 12345678` |
| ISBN | `(?:978\|979)[-\s]?\d{1,5}[-\s]?\d{1,7}[-\s]?\d{1,7}[-\s]?\d` | `978-0-13-468599-1` |

Priority: DOI > arXiv > PMID > ISBN. DOIs are normalized by stripping `doi:` and `https://doi.org/` prefixes.

### 6.4 MetadataService

```swift
protocol MetadataProvider {
    func fetchMetadata(for identifiers: ParsedIdentifiers) async throws -> PaperMetadata?
    func searchByTitle(_ title: String) async throws -> PaperMetadata?
}
```

Three implementations:
- **TranslationServerProvider** — `POST {serverURL}/search` with identifier as plain text body. Returns Zotero-format JSON.
- **CrossRefProvider** — `GET https://api.crossref.org/works?query.bibliographic={title}&rows=3`. Free, no auth.
- **MockMetadataProvider** — returns canned responses for tests.

Fallback chain: translation-server → CrossRef → Semantic Scholar → unresolved.

Server URL is configured in `config.json` as `translationServerURL`. Credentials (if needed) stored in macOS Keychain — Keychain integration deferred until auth is needed.

### 6.5 IndexService

```swift
class IndexService {
    func save(_ paper: Paper, in libraryRoot: URL) throws
    // Writes index/{paper.id}.json (pretty-printed, stable key order)

    func loadAll(from libraryRoot: URL) throws -> [Paper]
    // Reads all JSON files from index/

    func rebuildCombinedIndex(from papers: [Paper], in libraryRoot: URL) throws
    // Regenerates index/_all.json
}
```

### 6.6 ImportCoordinator

```swift
@Observable class ImportCoordinator {
    func importPDFs(_ urls: [URL]) async
    // For each URL: runs the 6-step pipeline
    // Papers appear in the UI immediately with "importing" state
    // UI updates reactively as each paper's state changes
}
```

Holds an `@Observable` array of `Paper` objects that drives the paper list view. Each pipeline step mutates the paper in place; SwiftUI re-renders automatically.

---

## 7. UI Changes

### 7.1 Drop target

The `PaperListView` gains a `.dropDestination(for: URL.self)` modifier. Accepted types: `.pdf` only. Visual feedback: dashed border overlay with "Drop PDFs to import" text when dragging over.

```swift
.dropDestination(for: URL.self) { urls, _ in
    let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
    guard !pdfURLs.isEmpty else { return false }
    Task { await importCoordinator.importPDFs(pdfURLs) }
    return true
}
```

### 7.2 Paper list rows

Each row displays based on the paper's current state:

- **Importing:** original filename, spinner, blue "Importing" badge
- **Resolving:** extracted title or filename, spinner, amber "Resolving" badge
- **Resolved:** title, "Author et al. · Year · Journal" subtitle, reading status badge
- **Unresolved:** filename, red "Unresolved" badge

### 7.3 Detail panel

Replaces the M1 placeholder. Shows all metadata fields for the selected paper. Fields are editable inline (click to edit). Action buttons: "Open PDF" (launches in default app), "Reveal in Finder". "Retry Lookup" button for unresolved papers.

### 7.4 Config UI

`config.json` gains a `translationServerURL` field. For M2, this is edited directly in the config file or via a minimal preferences field. Full preferences UI is deferred.

---

## 8. Folder Alignment

M1 created `metadata/` and `views/`. M2 renames these and adds missing folders:

1. Update `LibraryManager.setupLibrary()` to create the correct folders: `papers/`, `index/`, `notes/`, `.symlinks/`, `.cache/text/`, `templates/`
2. Update `LibraryConfig` to include `translationServerURL: String?`
3. For existing libraries: `LibraryManager.loadLibrary()` checks for old folder names and renames them (one-time migration)

---

## 9. Testing Strategy

### Unit tests

- **IdentifierParser** — test each regex pattern with known-good and edge-case text snippets
- **FileService** — test copy, rename, filename generation with temp directories
- **IndexService** — test save/load/rebuild roundtrip with temp directories
- **Paper model** — test Codable encode/decode roundtrip
- **MetadataService** — test with MockMetadataProvider; test fallback chain logic

### Integration tests

- **ImportCoordinator** — end-to-end test with mock metadata provider: drop a real PDF, verify file copied, text extracted, identifiers parsed, mock metadata applied, index written, file renamed

### Manual verification

- Drop a PDF with a DOI → verify full pipeline completes, file renamed, metadata populated
- Drop a PDF without identifiers → verify unresolved state, manual edit works
- Drop multiple PDFs → verify concurrent import, all resolve independently
- Drop a non-PDF file → verify rejection
