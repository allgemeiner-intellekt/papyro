# M5: Notes & Symlink Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-paper Markdown note generation from templates, and a Preferences window with a symlink management GUI for linking library folders to external destinations like Obsidian vaults.

**Architecture:** A `NoteGenerator` struct handles template loading and placeholder expansion. Note generation is integrated into `ImportCoordinator` as a pipeline step. A `ManagedSymlinkService` handles external symlink CRUD and health checking. A new `SettingsView` provides a two-tab Preferences window (General + Integrations). The `ManagedSymlink` model is stored in `LibraryConfig`.

**Tech Stack:** Swift, SwiftUI, Foundation (FileManager for symlinks), NSWorkspace (open note), NSOpenPanel (folder picker), Swift Testing framework

---

## File Structure

### New files
| File | Responsibility |
|------|---------------|
| `Papyro/Models/ManagedSymlink.swift` | Codable model for tracked external symlinks |
| `Papyro/Services/NoteGenerator.swift` | Template loading, placeholder expansion, note file writing |
| `Papyro/Services/ManagedSymlinkService.swift` | External symlink CRUD, health checking |
| `Papyro/Views/SettingsView.swift` | Preferences window with General and Integrations tabs |
| `PapyroTests/NoteGeneratorTests.swift` | Tests for template expansion and note file creation |
| `PapyroTests/ManagedSymlinkServiceTests.swift` | Tests for symlink CRUD and health checking |

### Modified files
| File | Changes |
|------|---------|
| `Papyro/Models/LibraryConfig.swift` | Add `managedSymlinks` array, `importBehavior` field |
| `Papyro/Services/ImportCoordinator.swift` | Add `NoteGenerator` dependency, call after metadata resolution, expose `createNote(for:)` |
| `Papyro/Services/LibraryManager.swift` | Write default template on setup, health check on load |
| `Papyro/Views/DetailView.swift` | Add Create Note / Open Note buttons in actions section |
| `Papyro/Views/MainView.swift` | Add notification banner for broken symlinks, ⌘E shortcut |
| `Papyro/PapyroApp.swift` | Register Settings scene, pass `ManagedSymlinkService` into environment |
| `Papyro/Models/AppState.swift` | Add `symlinkHealthIssueCount` and `showSettingsIntegrations` |

---

### Task 1: ManagedSymlink Model

**Files:**
- Create: `Papyro/Models/ManagedSymlink.swift`
- Modify: `Papyro/Models/LibraryConfig.swift`
- Test: `PapyroTests/LibraryConfigTests.swift`

- [ ] **Step 1: Write failing test for LibraryConfig with managedSymlinks**

In `PapyroTests/LibraryConfigTests.swift`, add a test that decodes a config containing `managedSymlinks`. The existing file already has tests — add to it.

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Papyro -destination 'platform=macOS' -only-testing PapyroTests/LibraryConfigTests 2>&1 | tail -20`

Expected: Compilation errors — `managedSymlinks` doesn't exist on `LibraryConfig`.

- [ ] **Step 3: Create ManagedSymlink model and update LibraryConfig**

Create `Papyro/Models/ManagedSymlink.swift`:

```swift
import Foundation

struct ManagedSymlink: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var sourceRelativePath: String
    var destinationPath: String
    var label: String
    var createdAt: Date
}
```

Update `Papyro/Models/LibraryConfig.swift` — add `managedSymlinks` with a default empty array and backward-compatible decoding:

```swift
import Foundation

struct LibraryConfig: Codable, Equatable {
    let version: Int
    var libraryPath: String
    var translationServerURL: String?
    var visibleColumns: [PaperColumn]?
    var sortColumn: PaperColumn?
    var sortAscending: Bool?
    var managedSymlinks: [ManagedSymlink]

    init(version: Int, libraryPath: String, translationServerURL: String?, visibleColumns: [PaperColumn]? = nil, sortColumn: PaperColumn? = nil, sortAscending: Bool? = nil, managedSymlinks: [ManagedSymlink] = []) {
        self.version = version
        self.libraryPath = libraryPath
        self.translationServerURL = translationServerURL
        self.visibleColumns = visibleColumns
        self.sortColumn = sortColumn
        self.sortAscending = sortAscending
        self.managedSymlinks = managedSymlinks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        libraryPath = try container.decode(String.self, forKey: .libraryPath)
        translationServerURL = try container.decodeIfPresent(String.self, forKey: .translationServerURL)
        visibleColumns = try container.decodeIfPresent([PaperColumn].self, forKey: .visibleColumns)
        sortColumn = try container.decodeIfPresent(PaperColumn.self, forKey: .sortColumn)
        sortAscending = try container.decodeIfPresent(Bool.self, forKey: .sortAscending)
        managedSymlinks = (try? container.decode([ManagedSymlink].self, forKey: .managedSymlinks)) ?? []
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Papyro -destination 'platform=macOS' -only-testing PapyroTests/LibraryConfigTests 2>&1 | tail -20`

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Papyro/Models/ManagedSymlink.swift Papyro/Models/LibraryConfig.swift PapyroTests/LibraryConfigTests.swift
git commit -m "feat: add ManagedSymlink model and update LibraryConfig"
```

---

### Task 2: NoteGenerator — Template Loading & Placeholder Expansion

**Files:**
- Create: `Papyro/Services/NoteGenerator.swift`
- Create: `PapyroTests/NoteGeneratorTests.swift`

- [ ] **Step 1: Write failing tests for placeholder expansion**

Create `PapyroTests/NoteGeneratorTests.swift`:

```swift
import Testing
import Foundation
@testable import Papyro

struct NoteGeneratorTests {
    let fm = FileManager.default

    private func makeTempLibrary() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("templates"), withIntermediateDirectories: true)
        return dir
    }

    private func makePaper(
        title: String = "Attention Is All You Need",
        authors: [String] = ["Vaswani, Ashish", "Shazeer, Noam"],
        year: Int? = 2017,
        journal: String? = "NeurIPS",
        doi: String? = "10.5555/3295222.3295349",
        arxivId: String? = "1706.03762",
        abstract: String? = "We propose a new architecture...",
        pdfFilename: String = "2017_vaswani_attention-is-all-you-need.pdf",
        canonicalId: String? = "10.5555/3295222.3295349"
    ) -> Paper {
        Paper(
            id: UUID(),
            canonicalId: canonicalId,
            title: title,
            authors: authors,
            year: year,
            journal: journal,
            doi: doi,
            arxivId: arxivId,
            pmid: nil,
            isbn: nil,
            abstract: abstract,
            url: nil,
            pdfPath: "papers/\(pdfFilename)",
            pdfFilename: pdfFilename,
            notePath: nil,
            projectIDs: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .semanticScholar,
            metadataResolved: true,
            importState: .resolved
        )
    }

    @Test func expandsAllPlaceholders() throws {
        let template = """
        ---
        title: "{{title}}"
        authors: [{{authors_linked}}]
        year: {{year}}
        doi: "{{doi}}"
        status: "{{status}}"
        ---

        # {{title}}

        **Authors:** {{authors_formatted}}
        **Published:** {{journal}}, {{year}}
        **DOI:** [{{doi}}](https://doi.org/{{doi}})
        **PDF:** [[{{pdf_filename}}]]
        **arXiv:** {{arxiv_id}}

        ## Abstract

        {{abstract}}

        ## Notes

        """

        let paper = makePaper()
        let result = NoteGenerator.expandTemplate(template, with: paper)

        #expect(result.contains("title: \"Attention Is All You Need\""))
        #expect(result.contains("authors: [[[Vaswani, Ashish]], [[Shazeer, Noam]]]"))
        #expect(result.contains("year: 2017"))
        #expect(result.contains("doi: \"10.5555/3295222.3295349\""))
        #expect(result.contains("status: \"to-read\""))
        #expect(result.contains("**Authors:** Vaswani, Ashish, Shazeer, Noam"))
        #expect(result.contains("**Published:** NeurIPS, 2017"))
        #expect(result.contains("**PDF:** [[2017_vaswani_attention-is-all-you-need.pdf]]"))
        #expect(result.contains("**arXiv:** 1706.03762"))
        #expect(result.contains("We propose a new architecture..."))
    }

    @Test func missingValuesRenderAsEmptyStrings() {
        let template = "DOI: {{doi}}, Journal: {{journal}}, arXiv: {{arxiv_id}}"
        let paper = makePaper(journal: nil, doi: nil, arxivId: nil)
        let result = NoteGenerator.expandTemplate(template, with: paper)
        #expect(result == "DOI: , Journal: , arXiv: ")
    }

    @Test func noteFilenameFromDOI() {
        let paper = makePaper(doi: "10.1038/s41586-024-07998-6", arxivId: nil, canonicalId: "10.1038/s41586-024-07998-6")
        let filename = NoteGenerator.noteFilename(for: paper)
        #expect(filename == "10.1038_s41586-024-07998-6.md")
    }

    @Test func noteFilenameFromArxivId() {
        let paper = makePaper(doi: nil, arxivId: "2401.12345", canonicalId: "2401.12345")
        let filename = NoteGenerator.noteFilename(for: paper)
        #expect(filename == "2401.12345.md")
    }

    @Test func noteFilenameFromTitleFallback() {
        let paper = makePaper(title: "Some Interesting Paper!", doi: nil, arxivId: nil, canonicalId: nil)
        let filename = NoteGenerator.noteFilename(for: paper)
        #expect(filename == "some-interesting-paper.md")
    }

    @Test func generatesNoteFileOnDisk() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let paper = makePaper()
        let generator = NoteGenerator()
        let notePath = try generator.generateNote(for: paper, libraryRoot: libRoot)

        #expect(notePath == "notes/10.5555_3295222.3295349.md")
        let noteURL = libRoot.appendingPathComponent(notePath)
        #expect(fm.fileExists(atPath: noteURL.path))

        let content = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(content.contains("Attention Is All You Need"))
    }

    @Test func usesCustomTemplateWhenPresent() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let customTemplate = "# {{title}}\nBy {{authors_formatted}}"
        try customTemplate.write(
            to: libRoot.appendingPathComponent("templates/note.md"),
            atomically: true,
            encoding: .utf8
        )

        let paper = makePaper()
        let generator = NoteGenerator()
        let notePath = try generator.generateNote(for: paper, libraryRoot: libRoot)

        let content = try String(contentsOf: libRoot.appendingPathComponent(notePath), encoding: .utf8)
        #expect(content == "# Attention Is All You Need\nBy Vaswani, Ashish, Shazeer, Noam")
    }

    @Test func writesDefaultTemplateIfMissing() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let paper = makePaper()
        let generator = NoteGenerator()
        _ = try generator.generateNote(for: paper, libraryRoot: libRoot)

        let templateURL = libRoot.appendingPathComponent("templates/note.md")
        #expect(fm.fileExists(atPath: templateURL.path))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Papyro -destination 'platform=macOS' -only-testing PapyroTests/NoteGeneratorTests 2>&1 | tail -20`

Expected: Compilation errors — `NoteGenerator` doesn't exist.

- [ ] **Step 3: Implement NoteGenerator**

Create `Papyro/Services/NoteGenerator.swift`:

```swift
import Foundation

struct NoteGenerator: Sendable {
    static let defaultTemplate = """
    ---
    title: "{{title}}"
    authors: [{{authors_linked}}]
    year: {{year}}
    doi: "{{doi}}"
    status: "{{status}}"
    ---

    # {{title}}

    **Authors:** {{authors_formatted}}
    **Published:** {{journal}}, {{year}}
    **DOI:** [{{doi}}](https://doi.org/{{doi}})
    **PDF:** [[{{pdf_filename}}]]

    ## Abstract

    {{abstract}}

    ## Notes

    """

    static func expandTemplate(_ template: String, with paper: Paper) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        let statusRawValue: String = {
            switch paper.status {
            case .toRead: return "to-read"
            case .reading: return "reading"
            case .archived: return "archived"
            }
        }()

        let replacements: [(String, String)] = [
            ("{{title}}", paper.title),
            ("{{authors_formatted}}", paper.authors.joined(separator: ", ")),
            ("{{authors_linked}}", paper.authors.map { "[[\\($0)]]" }.joined(separator: ", ")),
            ("{{year}}", paper.year.map(String.init) ?? ""),
            ("{{journal}}", paper.journal ?? ""),
            ("{{doi}}", paper.doi ?? ""),
            ("{{arxiv_id}}", paper.arxivId ?? ""),
            ("{{abstract}}", paper.abstract ?? ""),
            ("{{pdf_filename}}", paper.pdfFilename),
            ("{{status}}", statusRawValue),
            ("{{date_added}}", dateFormatter.string(from: paper.dateAdded)),
        ]

        var result = template
        for (placeholder, value) in replacements {
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        return result
    }

    static func noteFilename(for paper: Paper) -> String {
        if let canonicalId = paper.canonicalId, !canonicalId.isEmpty {
            let sanitized = canonicalId.replacingOccurrences(of: "/", with: "_")
            return "\(sanitized).md"
        }
        return "\(slugify(paper.title)).md"
    }

    func generateNote(for paper: Paper, libraryRoot: URL) throws -> String {
        let template = loadTemplate(libraryRoot: libraryRoot)
        let content = Self.expandTemplate(template, with: paper)
        let filename = Self.noteFilename(for: paper)
        let relativePath = "notes/\(filename)"
        let noteURL = libraryRoot.appendingPathComponent(relativePath)
        try content.write(to: noteURL, atomically: true, encoding: .utf8)
        return relativePath
    }

    private func loadTemplate(libraryRoot: URL) -> String {
        let templateURL = libraryRoot.appendingPathComponent("templates/note.md")
        if let custom = try? String(contentsOf: templateURL, encoding: .utf8), !custom.isEmpty {
            return custom
        }
        // Write default to disk so user can find and edit it
        try? Self.defaultTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
        return Self.defaultTemplate
    }

    private static func slugify(_ text: String) -> String {
        let lowered = text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        var result = ""
        for char in lowered {
            if char.isLetter || char.isNumber || char == " " || char == "-" {
                result.append(char)
            }
        }

        var collapsed = ""
        var lastWasSep = false
        for char in result {
            let isSep = char == " " || char == "-"
            if isSep {
                if !lastWasSep { collapsed.append("-") }
                lastWasSep = true
            } else {
                collapsed.append(char)
                lastWasSep = false
            }
        }

        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Papyro -destination 'platform=macOS' -only-testing PapyroTests/NoteGeneratorTests 2>&1 | tail -20`

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Papyro/Services/NoteGenerator.swift PapyroTests/NoteGeneratorTests.swift
git commit -m "feat: add NoteGenerator with template loading and placeholder expansion"
```

---

### Task 3: Integrate Note Generation into Import Pipeline

**Files:**
- Modify: `Papyro/Services/ImportCoordinator.swift`

- [ ] **Step 1: Add NoteGenerator to ImportCoordinator and wire into pipeline**

In `Papyro/Services/ImportCoordinator.swift`, add `NoteGenerator` as a dependency and call it after metadata resolution.

Add to the stored properties (after `let projectService: ProjectService`):

```swift
private let noteGenerator: NoteGenerator
```

Update the `init` to accept and store it:

```swift
init(
    libraryRoot: URL,
    metadataProvider: MetadataProvider,
    projectService: ProjectService,
    fileService: FileService = FileService(),
    textExtractor: TextExtractor = TextExtractor(),
    identifierParser: IdentifierParser = IdentifierParser(),
    indexService: IndexService = IndexService(),
    noteGenerator: NoteGenerator = NoteGenerator()
) {
    self.libraryRoot = libraryRoot
    self.metadataProvider = metadataProvider
    self.projectService = projectService
    self.fileService = fileService
    self.textExtractor = textExtractor
    self.identifierParser = identifierParser
    self.indexService = indexService
    self.noteGenerator = noteGenerator
}
```

At the end of `resolveMetadata(...)`, after the final `indexService.save` and `rebuildCombinedIndex`, add note generation:

```swift
// Generate note
if let finalPaper = papers.first(where: { $0.id == paperId }) {
    if let notePath = try? noteGenerator.generateNote(for: finalPaper, libraryRoot: libraryRoot) {
        updatePaper(paperId) { $0.notePath = notePath }
        if let updated = papers.first(where: { $0.id == paperId }) {
            try? indexService.save(updated, in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }
}
```

Add a public method for on-demand note creation:

```swift
func createNote(for paperId: UUID) {
    guard let index = papers.firstIndex(where: { $0.id == paperId }) else { return }
    let paper = papers[index]
    if let notePath = try? noteGenerator.generateNote(for: paper, libraryRoot: libraryRoot) {
        papers[index].notePath = notePath
        papers[index].dateModified = Date()
        try? indexService.save(papers[index], in: libraryRoot)
        try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme Papyro -destination 'platform=macOS' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Papyro/Services/ImportCoordinator.swift
git commit -m "feat: integrate note generation into import pipeline"
```

---

### Task 4: Detail Panel — Create Note / Open Note Buttons

**Files:**
- Modify: `Papyro/Views/DetailView.swift`

- [ ] **Step 1: Add note helper methods and buttons to DetailView**

Add a computed property to check if the note exists on disk. Add this inside the `DetailView` struct, after the `paper` computed property:

```swift
private func noteExistsOnDisk(_ paper: Paper) -> Bool {
    guard let notePath = paper.notePath,
          let config = appState.libraryConfig else { return false }
    let noteURL = URL(fileURLWithPath: config.libraryPath)
        .appendingPathComponent(notePath)
    return FileManager.default.fileExists(atPath: noteURL.path)
}
```

Add a method to open the note:

```swift
private func openNote(_ paper: Paper) {
    guard let notePath = paper.notePath,
          let config = appState.libraryConfig else { return }
    let noteURL = URL(fileURLWithPath: config.libraryPath)
        .appendingPathComponent(notePath)
    NSWorkspace.shared.open(noteURL)
}
```

In `actionsSection(_:)`, add note buttons after the existing `HStack`. Replace the entire `actionsSection` method:

```swift
@ViewBuilder
private func actionsSection(_ paper: Paper) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Actions")
            .font(.headline)

        HStack(spacing: 12) {
            Button("Open PDF") {
                openPDF(paper)
            }
            .buttonStyle(.bordered)

            Button("Reveal in Finder") {
                revealInFinder(paper)
            }
            .buttonStyle(.bordered)

            if paper.importState == .unresolved {
                Button("Retry Lookup") {
                    Task {
                        await coordinator.retryMetadataLookup(for: paper.id)
                    }
                }
                .buttonStyle(.bordered)
            }

            Button("Edit") {
                editTitle = paper.title
                editAuthors = paper.authors.joined(separator: ", ")
                editYear = paper.year.map(String.init) ?? ""
                editJournal = paper.journal ?? ""
                editDOI = paper.doi ?? ""
                editAbstract = paper.abstract ?? ""
                isEditing = true
            }
            .buttonStyle(.bordered)
        }

        // Note actions
        if noteExistsOnDisk(paper) {
            Button {
                openNote(paper)
            } label: {
                Label("Open Note", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("e", modifiers: .command)
        } else {
            Button {
                coordinator.createNote(for: paper.id)
            } label: {
                Label("Create Note", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.bordered)
            .tint(.green)
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme Papyro -destination 'platform=macOS' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Papyro/Views/DetailView.swift
git commit -m "feat: add Create Note and Open Note buttons to detail panel"
```

---

### Task 5: ManagedSymlinkService

**Files:**
- Create: `Papyro/Services/ManagedSymlinkService.swift`
- Create: `PapyroTests/ManagedSymlinkServiceTests.swift`

- [ ] **Step 1: Write failing tests**

Create `PapyroTests/ManagedSymlinkServiceTests.swift`:

```swift
import Testing
import Foundation
@testable import Papyro

struct ManagedSymlinkServiceTests {
    let fm = FileManager.default

    private func makeTempDir(_ name: String = "PapyroTest") -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func createLinkCreatesSymlinkAtDestination() throws {
        let libRoot = makeTempDir("lib")
        let destParent = makeTempDir("dest")
        defer { try? fm.removeItem(at: libRoot) }
        defer { try? fm.removeItem(at: destParent) }

        // Create source folder
        let notesDir = libRoot.appendingPathComponent("notes")
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let destPath = destParent.appendingPathComponent("Papyro Notes").path
        let service = ManagedSymlinkService()
        let symlink = try service.createLink(
            sourceRelativePath: "notes",
            destinationPath: destPath,
            libraryRoot: libRoot
        )

        #expect(symlink.sourceRelativePath == "notes")
        #expect(symlink.destinationPath == destPath)
        #expect(symlink.label.contains("notes"))

        // Verify symlink exists on disk
        var isDir: ObjCBool = false
        #expect(fm.fileExists(atPath: destPath, isDirectory: &isDir))

        let resolved = try fm.destinationOfSymbolicLink(atPath: destPath)
        #expect(resolved == notesDir.path)
    }

    @Test func removeLinkDeletesSymlinkFromDisk() throws {
        let libRoot = makeTempDir("lib")
        let destParent = makeTempDir("dest")
        defer { try? fm.removeItem(at: libRoot) }
        defer { try? fm.removeItem(at: destParent) }

        let notesDir = libRoot.appendingPathComponent("notes")
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let destPath = destParent.appendingPathComponent("Papyro Notes").path
        let service = ManagedSymlinkService()
        let symlink = try service.createLink(
            sourceRelativePath: "notes",
            destinationPath: destPath,
            libraryRoot: libRoot
        )

        try service.removeLink(symlink)
        #expect(!fm.fileExists(atPath: destPath))
    }

    @Test func checkHealthReturnsHealthyForValidSymlink() throws {
        let libRoot = makeTempDir("lib")
        let destParent = makeTempDir("dest")
        defer { try? fm.removeItem(at: libRoot) }
        defer { try? fm.removeItem(at: destParent) }

        let notesDir = libRoot.appendingPathComponent("notes")
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let destPath = destParent.appendingPathComponent("Papyro Notes").path
        let service = ManagedSymlinkService()
        let symlink = try service.createLink(
            sourceRelativePath: "notes",
            destinationPath: destPath,
            libraryRoot: libRoot
        )

        let health = service.checkHealth(symlink)
        #expect(health == .healthy)
    }

    @Test func checkHealthReturnsBrokenWhenSymlinkRemoved() throws {
        let libRoot = makeTempDir("lib")
        let destParent = makeTempDir("dest")
        defer { try? fm.removeItem(at: libRoot) }
        defer { try? fm.removeItem(at: destParent) }

        let notesDir = libRoot.appendingPathComponent("notes")
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let destPath = destParent.appendingPathComponent("Papyro Notes").path
        let service = ManagedSymlinkService()
        let symlink = try service.createLink(
            sourceRelativePath: "notes",
            destinationPath: destPath,
            libraryRoot: libRoot
        )

        // Remove the symlink manually
        try fm.removeItem(atPath: destPath)

        let health = service.checkHealth(symlink)
        #expect(health == .broken)
    }

    @Test func checkHealthReturnsDestinationMissingWhenSourceRemoved() throws {
        let libRoot = makeTempDir("lib")
        let destParent = makeTempDir("dest")
        defer { try? fm.removeItem(at: libRoot) }
        defer { try? fm.removeItem(at: destParent) }

        let notesDir = libRoot.appendingPathComponent("notes")
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let destPath = destParent.appendingPathComponent("Papyro Notes").path
        let service = ManagedSymlinkService()
        let symlink = try service.createLink(
            sourceRelativePath: "notes",
            destinationPath: destPath,
            libraryRoot: libRoot
        )

        // Remove the source directory
        try fm.removeItem(at: notesDir)

        let health = service.checkHealth(symlink)
        #expect(health == .destinationMissing)
    }

    @Test func repairLinkUpdatesDestination() throws {
        let libRoot = makeTempDir("lib")
        let destParent = makeTempDir("dest")
        let newDestParent = makeTempDir("newdest")
        defer { try? fm.removeItem(at: libRoot) }
        defer { try? fm.removeItem(at: destParent) }
        defer { try? fm.removeItem(at: newDestParent) }

        let notesDir = libRoot.appendingPathComponent("notes")
        try fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let destPath = destParent.appendingPathComponent("Papyro Notes").path
        let service = ManagedSymlinkService()
        let symlink = try service.createLink(
            sourceRelativePath: "notes",
            destinationPath: destPath,
            libraryRoot: libRoot
        )

        let newDestPath = newDestParent.appendingPathComponent("New Notes").path
        let repaired = try service.repairLink(symlink, newDestinationPath: newDestPath, libraryRoot: libRoot)

        #expect(repaired.destinationPath == newDestPath)
        #expect(!fm.fileExists(atPath: destPath))
        #expect(fm.fileExists(atPath: newDestPath))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Papyro -destination 'platform=macOS' -only-testing PapyroTests/ManagedSymlinkServiceTests 2>&1 | tail -20`

Expected: Compilation errors — `ManagedSymlinkService` doesn't exist.

- [ ] **Step 3: Implement ManagedSymlinkService**

Create `Papyro/Services/ManagedSymlinkService.swift`:

```swift
import Foundation

enum SymlinkHealth: Equatable, Sendable {
    case healthy
    case destinationMissing
    case broken
}

struct ManagedSymlinkService: Sendable {
    private nonisolated(unsafe) let fm = FileManager.default

    func createLink(sourceRelativePath: String, destinationPath: String, libraryRoot: URL) throws -> ManagedSymlink {
        let sourceAbsolutePath = libraryRoot.appendingPathComponent(sourceRelativePath).path

        // Create symlink at destination pointing to source
        try fm.createSymbolicLink(atPath: destinationPath, withDestinationPath: sourceAbsolutePath)

        let sourceName = URL(fileURLWithPath: sourceRelativePath).lastPathComponent
        let destName = URL(fileURLWithPath: destinationPath).lastPathComponent
        let label = "\(sourceName) → \(destName)"

        return ManagedSymlink(
            id: UUID(),
            sourceRelativePath: sourceRelativePath,
            destinationPath: destinationPath,
            label: label,
            createdAt: Date()
        )
    }

    func removeLink(_ symlink: ManagedSymlink) throws {
        if fm.fileExists(atPath: symlink.destinationPath) {
            try fm.removeItem(atPath: symlink.destinationPath)
        }
    }

    func repairLink(_ symlink: ManagedSymlink, newDestinationPath: String, libraryRoot: URL) throws -> ManagedSymlink {
        // Remove old symlink if it exists
        if fm.fileExists(atPath: symlink.destinationPath) {
            try fm.removeItem(atPath: symlink.destinationPath)
        }

        let sourceAbsolutePath = libraryRoot.appendingPathComponent(symlink.sourceRelativePath).path
        try fm.createSymbolicLink(atPath: newDestinationPath, withDestinationPath: sourceAbsolutePath)

        let destName = URL(fileURLWithPath: newDestinationPath).lastPathComponent
        let sourceName = URL(fileURLWithPath: symlink.sourceRelativePath).lastPathComponent

        var repaired = symlink
        repaired.destinationPath = newDestinationPath
        repaired.label = "\(sourceName) → \(destName)"
        return repaired
    }

    func checkHealth(_ symlink: ManagedSymlink) -> SymlinkHealth {
        // Check if the symlink itself exists at the destination path
        let attrs = try? fm.attributesOfItem(atPath: symlink.destinationPath)
        guard let fileType = attrs?[.type] as? FileAttributeType,
              fileType == .typeSymbolicLink else {
            return .broken
        }

        // Check if the target the symlink points to is reachable
        let resolvedPath = try? fm.destinationOfSymbolicLink(atPath: symlink.destinationPath)
        guard let resolved = resolvedPath else {
            return .broken
        }

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: resolved, isDirectory: &isDir) {
            return .healthy
        } else {
            return .destinationMissing
        }
    }

    func checkAllHealth(_ symlinks: [ManagedSymlink]) -> [(ManagedSymlink, SymlinkHealth)] {
        symlinks.map { ($0, checkHealth($0)) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Papyro -destination 'platform=macOS' -only-testing PapyroTests/ManagedSymlinkServiceTests 2>&1 | tail -20`

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Papyro/Services/ManagedSymlinkService.swift PapyroTests/ManagedSymlinkServiceTests.swift
git commit -m "feat: add ManagedSymlinkService for external symlink CRUD and health checking"
```

---

### Task 6: SettingsView — Preferences Window

**Files:**
- Create: `Papyro/Views/SettingsView.swift`
- Modify: `Papyro/PapyroApp.swift`
- Modify: `Papyro/Models/AppState.swift`

- [ ] **Step 1: Add state properties to AppState**

In `Papyro/Models/AppState.swift`, add:

```swift
var symlinkHealthIssueCount: Int = 0
var showSettingsIntegrations: Bool = false
```

- [ ] **Step 2: Create SettingsView with General and Integrations tabs**

Create `Papyro/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            IntegrationsSettingsTab()
                .tabItem {
                    Label("Integrations", systemImage: "link")
                }
        }
        .frame(width: 550, height: 400)
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Library Path") {
                    HStack {
                        Text(appState.libraryConfig?.libraryPath ?? "Not set")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                }

                LabeledContent("Translation Server") {
                    Text(appState.libraryConfig?.translationServerURL ?? "Not configured")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Integrations Tab

private struct IntegrationsSettingsTab: View {
    @Environment(AppState.self) private var appState

    @State private var managedSymlinks: [ManagedSymlink] = []
    @State private var symlinkHealthMap: [UUID: SymlinkHealth] = [:]
    @State private var showingSourcePicker = false
    @State private var showingUnlinkConfirmation = false
    @State private var symlinkToUnlink: ManagedSymlink?

    private let symlinkService = ManagedSymlinkService()

    private var libraryRoot: URL? {
        guard let path = appState.libraryConfig?.libraryPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Linked Folders")
                        .font(.headline)
                    Text("Symlinks from your library to external locations like Obsidian vaults")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Link Folder…") {
                    showingSourcePicker = true
                }
                .buttonStyle(.borderedProminent)
            }

            // Symlink list
            if managedSymlinks.isEmpty {
                ContentUnavailableView(
                    "No Linked Folders",
                    systemImage: "link.badge.plus",
                    description: Text("Link library folders to external destinations for easy access in Obsidian or by agents.")
                )
            } else {
                List {
                    ForEach(managedSymlinks) { symlink in
                        symlinkRow(symlink)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
            }
        }
        .padding()
        .onAppear { refreshSymlinks() }
        .sheet(isPresented: $showingSourcePicker) {
            SourcePickerSheet(
                libraryRoot: libraryRoot,
                onLink: { sourceRelativePath, destinationPath in
                    createLink(sourceRelativePath: sourceRelativePath, destinationPath: destinationPath)
                }
            )
        }
        .alert("Unlink Folder?", isPresented: $showingUnlinkConfirmation) {
            Button("Unlink", role: .destructive) {
                if let symlink = symlinkToUnlink {
                    unlinkFolder(symlink)
                }
            }
            Button("Cancel", role: .cancel) {
                symlinkToUnlink = nil
            }
        } message: {
            if let symlink = symlinkToUnlink {
                Text("Remove link from \(symlink.sourceRelativePath) to \(URL(fileURLWithPath: symlink.destinationPath).lastPathComponent)? The source files are not affected.")
            }
        }
    }

    @ViewBuilder
    private func symlinkRow(_ symlink: ManagedSymlink) -> some View {
        let health = symlinkHealthMap[symlink.id] ?? .healthy

        HStack(spacing: 12) {
            Circle()
                .fill(healthColor(health))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(symlink.label)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text(symlink.sourceRelativePath)
                        .foregroundStyle(.secondary)
                    Text("→")
                        .foregroundStyle(.quaternary)
                    Text(abbreviatePath(symlink.destinationPath))
                        .foregroundStyle(health == .healthy ? .secondary : healthColor(health))
                }
                .font(.caption)
            }

            Spacer()

            if health != .healthy {
                Button("Repair") {
                    repairLink(symlink)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Reveal") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: symlink.destinationPath)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(health == .broken)

            Button("Unlink") {
                symlinkToUnlink = symlink
                showingUnlinkConfirmation = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }

    private func healthColor(_ health: SymlinkHealth) -> Color {
        switch health {
        case .healthy: .green
        case .destinationMissing: .yellow
        case .broken: .red
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func refreshSymlinks() {
        managedSymlinks = appState.libraryConfig?.managedSymlinks ?? []
        for symlink in managedSymlinks {
            symlinkHealthMap[symlink.id] = symlinkService.checkHealth(symlink)
        }
        appState.symlinkHealthIssueCount = symlinkHealthMap.values.filter { $0 != .healthy }.count
    }

    private func createLink(sourceRelativePath: String, destinationPath: String) {
        guard let libRoot = libraryRoot else { return }
        guard let symlink = try? symlinkService.createLink(
            sourceRelativePath: sourceRelativePath,
            destinationPath: destinationPath,
            libraryRoot: libRoot
        ) else { return }
        appState.libraryConfig?.managedSymlinks.append(symlink)
        saveConfig()
        refreshSymlinks()
    }

    private func unlinkFolder(_ symlink: ManagedSymlink) {
        try? symlinkService.removeLink(symlink)
        appState.libraryConfig?.managedSymlinks.removeAll { $0.id == symlink.id }
        saveConfig()
        refreshSymlinks()
        symlinkToUnlink = nil
    }

    private func repairLink(_ symlink: ManagedSymlink) {
        guard let libRoot = libraryRoot else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select New Destination"

        guard panel.runModal() == .OK, let newURL = panel.url else { return }
        let newDestPath = newURL.appendingPathComponent(URL(fileURLWithPath: symlink.destinationPath).lastPathComponent).path

        guard let repaired = try? symlinkService.repairLink(symlink, newDestinationPath: newDestPath, libraryRoot: libRoot) else { return }

        if let index = appState.libraryConfig?.managedSymlinks.firstIndex(where: { $0.id == symlink.id }) {
            appState.libraryConfig?.managedSymlinks[index] = repaired
        }
        saveConfig()
        refreshSymlinks()
    }

    private func saveConfig() {
        guard let config = appState.libraryConfig else { return }
        let configURL = URL(fileURLWithPath: config.libraryPath).appendingPathComponent("config.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
    }
}

// MARK: - Source Picker Sheet

private struct SourcePickerSheet: View {
    let libraryRoot: URL?
    let onLink: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSource: String?

    private var sourceFolders: [(label: String, relativePath: String)] {
        var folders: [(String, String)] = [
            ("Notes", "notes"),
            ("Templates", "templates"),
            ("Text Cache", ".cache/text"),
        ]

        // Add project folders if they exist
        if let libRoot = libraryRoot {
            let symlinksDir = libRoot.appendingPathComponent(".symlinks")
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: symlinksDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            ) {
                for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        let slug = url.lastPathComponent
                        folders.append(("Project: \(slug)", ".symlinks/\(slug)"))
                    }
                }
            }
        }

        return folders
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Source Folder")
                .font(.headline)

            List(sourceFolders, id: \.relativePath, selection: $selectedSource) { folder in
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(folder.label)
                    Spacer()
                    Text(folder.relativePath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .tag(folder.relativePath)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Choose Destination…") {
                    pickDestination()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSource == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
    }

    private func pickDestination() {
        guard let source = selectedSource else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Create Link"
        panel.message = "Choose where to create the symlink for \(source)"

        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        let sourceName = URL(fileURLWithPath: source).lastPathComponent
        let finalDest = destURL.appendingPathComponent(sourceName).path

        onLink(source, finalDest)
        dismiss()
    }
}
```

- [ ] **Step 3: Register Settings scene in PapyroApp**

In `Papyro/PapyroApp.swift`, add a `Settings` scene after the `WindowGroup`. The full `body` becomes:

```swift
var body: some Scene {
    WindowGroup {
        Group {
            if appState.isOnboarding {
                WelcomeView()
            } else if let coordinator = importCoordinator {
                MainView()
                    .environment(coordinator)
            } else {
                ProgressView("Loading library...")
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

    Settings {
        SettingsView()
            .environment(appState)
    }
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild build -scheme Papyro -destination 'platform=macOS' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Papyro/Views/SettingsView.swift Papyro/PapyroApp.swift Papyro/Models/AppState.swift
git commit -m "feat: add Preferences window with General and Integrations tabs"
```

---

### Task 7: Health Check on Launch & Notification Banner

**Files:**
- Modify: `Papyro/Services/LibraryManager.swift`
- Modify: `Papyro/Views/MainView.swift`

- [ ] **Step 1: Add health check to LibraryManager**

In `Papyro/Services/LibraryManager.swift`, add a method to check symlink health and write the default template. Update `loadLibrary(from:)` to call health check:

```swift
import Foundation

@Observable
@MainActor
class LibraryManager {
    private let appState: AppState
    private let fileManager = FileManager.default
    private let symlinkService = ManagedSymlinkService()

    private let subdirectories = ["papers", "index", "notes", ".symlinks", ".cache/text", "templates"]

    init(appState: AppState) {
        self.appState = appState
    }

    func setupLibrary(at path: URL, using defaults: UserDefaults = .standard) throws {
        // Create subdirectories
        for subdir in subdirectories {
            try fileManager.createDirectory(
                at: path.appendingPathComponent(subdir),
                withIntermediateDirectories: true
            )
        }

        // Write default note template if it doesn't exist
        let templateURL = path.appendingPathComponent("templates/note.md")
        if !fileManager.fileExists(atPath: templateURL.path) {
            try NoteGenerator.defaultTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
        }

        // Write config.json
        let config = LibraryConfig(version: 1, libraryPath: path.path, translationServerURL: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        try data.write(to: path.appendingPathComponent("config.json"))

        // Initialize projects.json with Inbox
        let projectService = ProjectService(libraryRoot: path)
        try projectService.initialize()

        // Save to UserDefaults
        defaults.set(path.path, forKey: "libraryPath")

        // Update app state
        appState.libraryConfig = config
        appState.isOnboarding = false
    }

    func loadLibrary(from path: URL) throws {
        let configURL = path.appendingPathComponent("config.json")
        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let config = try decoder.decode(LibraryConfig.self, from: data)

        appState.libraryConfig = config
        appState.isOnboarding = false

        // Check symlink health
        checkSymlinkHealth(config.managedSymlinks)
    }

    @discardableResult
    func detectExistingLibrary(using defaults: UserDefaults = .standard) -> Bool {
        guard let path = defaults.string(forKey: "libraryPath") else {
            return false
        }

        let url = URL(fileURLWithPath: path)
        let configURL = url.appendingPathComponent("config.json")

        guard fileManager.fileExists(atPath: configURL.path) else {
            return false
        }

        do {
            try loadLibrary(from: url)
            return true
        } catch {
            return false
        }
    }

    private func checkSymlinkHealth(_ symlinks: [ManagedSymlink]) {
        let issues = symlinks.filter { symlinkService.checkHealth($0) != .healthy }
        appState.symlinkHealthIssueCount = issues.count
    }
}
```

- [ ] **Step 2: Add notification banner to MainView**

In `Papyro/Views/MainView.swift`, add a banner overlay and the ⌘E keyboard shortcut. Replace the full file:

```swift
import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var showNewProjectPrompt = false
    @State private var newProjectName = ""
    @State private var showDeleteConfirmation = false
    @State private var showHealthBanner = false

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView()
        } content: {
            PaperListView()
        } detail: {
            DetailView()
        }
        .overlay(alignment: .top) {
            if showHealthBanner {
                healthBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("New Project", isPresented: $showNewProjectPrompt) {
            TextField("Project name", text: $newProjectName)
            Button("Create") {
                if !newProjectName.isEmpty {
                    try? coordinator.projectService.createProject(name: newProjectName)
                }
                newProjectName = ""
            }
            Button("Cancel", role: .cancel) {
                newProjectName = ""
            }
        }
        .alert("Delete Project?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let projectID = appState.selectedSidebarItem.projectID {
                    coordinator.deleteProject(id: projectID)
                    appState.selectedSidebarItem = .allPapers
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Papers will remain in your library but will be moved to Inbox.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Project") {
                        showNewProjectPrompt = true
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])

                    Button("Rebuild Symlinks") {
                        try? coordinator.projectService.rebuildSymlinks(papers: coordinator.papers)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onKeyPress("1") {
            setSelectedPaperStatus(.toRead)
        }
        .onKeyPress("2") {
            setSelectedPaperStatus(.reading)
        }
        .onKeyPress("3") {
            setSelectedPaperStatus(.archived)
        }
        .onKeyPress("e", modifiers: .command) {
            openOrCreateNote()
        }
        .onAppear {
            if appState.symlinkHealthIssueCount > 0 {
                withAnimation { showHealthBanner = true }
                // Auto-dismiss after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    withAnimation { showHealthBanner = false }
                }
            }
        }
    }

    @ViewBuilder
    private var healthBanner: some View {
        let count = appState.symlinkHealthIssueCount
        Button {
            showHealthBanner = false
            // Open Settings to Integrations tab
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("\(count) linked \(count == 1 ? "folder" : "folders") \(count == 1 ? "needs" : "need") attention")
                    .font(.callout)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func openOrCreateNote() -> KeyPress.Result {
        guard !appState.isEditingText else { return .ignored }
        guard let paperId = appState.selectedPaperId else { return .ignored }
        guard let paper = coordinator.papers.first(where: { $0.id == paperId }) else { return .ignored }

        // Check if note exists on disk
        if let notePath = paper.notePath, let config = appState.libraryConfig {
            let noteURL = URL(fileURLWithPath: config.libraryPath).appendingPathComponent(notePath)
            if FileManager.default.fileExists(atPath: noteURL.path) {
                NSWorkspace.shared.open(noteURL)
                return .handled
            }
        }

        // Create note first, then open
        coordinator.createNote(for: paperId)
        if let updatedPaper = coordinator.papers.first(where: { $0.id == paperId }),
           let notePath = updatedPaper.notePath,
           let config = appState.libraryConfig {
            let noteURL = URL(fileURLWithPath: config.libraryPath).appendingPathComponent(notePath)
            NSWorkspace.shared.open(noteURL)
        }
        return .handled
    }

    private func setSelectedPaperStatus(_ status: ReadingStatus) -> KeyPress.Result {
        guard !appState.isEditingText else { return .ignored }
        guard let paperId = appState.selectedPaperId else { return .ignored }
        coordinator.updatePaperStatus(paperId: paperId, status: status)
        return .handled
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild build -scheme Papyro -destination 'platform=macOS' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Papyro/Services/LibraryManager.swift Papyro/Views/MainView.swift
git commit -m "feat: add symlink health check on launch and notification banner"
```

---

### Task 8: Write Default Template on Library Setup

**Files:**
- Modify: `Papyro/Services/LibraryManager.swift` (already modified in Task 7 — this step is included there)

This task is already completed as part of Task 7. The `setupLibrary(at:)` method now writes the default template to `templates/note.md` during library initialization.

- [ ] **Step 1: Verify default template is written**

This was already handled in Task 7's `setupLibrary` changes. Run the full test suite to make sure nothing is broken:

Run: `xcodebuild test -scheme Papyro -destination 'platform=macOS' 2>&1 | tail -30`

Expected: All tests PASS.

- [ ] **Step 2: Commit (if any additional changes needed)**

If tests revealed issues, fix and commit. Otherwise, no commit needed — Task 7 already covers this.

---

### Task 9: File → Manage Linked Folders Menu Command

**Files:**
- Modify: `Papyro/PapyroApp.swift`

- [ ] **Step 1: Add menu command**

In `Papyro/PapyroApp.swift`, add a `.commands` modifier to the `WindowGroup`. Place it after the `WindowGroup` closing brace and before `Settings`:

```swift
var body: some Scene {
    WindowGroup {
        // ... existing content unchanged ...
    }
    .commands {
        CommandGroup(after: .newItem) {
            Button("Manage Linked Folders…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: [.command, .option])
        }
    }

    Settings {
        SettingsView()
            .environment(appState)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme Papyro -destination 'platform=macOS' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Papyro/PapyroApp.swift
git commit -m "feat: add File > Manage Linked Folders menu command"
```

---

### Task 10: Run Full Test Suite

**Files:** None (verification only)

- [ ] **Step 1: Run all tests**

Run: `xcodebuild test -scheme Papyro -destination 'platform=macOS' 2>&1 | tail -40`

Expected: All tests PASS, including new `NoteGeneratorTests` and `ManagedSymlinkServiceTests`.

- [ ] **Step 2: Build and launch the app manually**

Run: `xcodebuild build -scheme Papyro -destination 'platform=macOS' 2>&1 | tail -10`

Verify: BUILD SUCCEEDED. Manually test:
1. Open app → Preferences (⌘,) shows General and Integrations tabs
2. Import a PDF → note is auto-generated in `notes/`
3. Select paper → "Open Note" button appears in detail panel
4. ⌘E opens the note
5. "Link Folder…" creates a symlink at the chosen destination
6. "Unlink" removes it

- [ ] **Step 3: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address any issues from full test run"
```
