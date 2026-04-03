# M3: Views and Organisation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add project-based organisation with a functional sidebar, redesigned paper list with sortable columns, and a symlink layer that keeps the filesystem in sync.

**Architecture:** New `Project` model persisted in `projects.json`. `ProjectService` manages CRUD and paper assignments, coordinating with `SymlinkService` for filesystem sync. The sidebar is rebuilt around three sections (All Papers, Projects, Status filters). The paper list gets stacked rows with configurable sortable columns. Paper model migrated from `projects: [String]` + `topics: [String]` to `projectIDs: [UUID]`.

**Tech Stack:** Swift, SwiftUI, Foundation (FileManager for symlinks), Swift Testing framework

---

## File Structure

### New files

| File | Responsibility |
|---|---|
| `Papyro/Models/Project.swift` | Project struct (id, name, slug, isInbox, dateCreated) |
| `Papyro/Models/PaperColumn.swift` | Column enum for configurable list columns |
| `Papyro/Models/SidebarItem.swift` | Replaces SidebarCategory — models sidebar selection state |
| `Papyro/Services/ProjectService.swift` | Project CRUD, paper assign/unassign, Inbox auto-management |
| `Papyro/Services/SymlinkService.swift` | Symlink create/remove/rebuild for `.symlinks/` |
| `Papyro/Views/ProjectChipsView.swift` | Project badges in detail panel |
| `PapyroTests/ProjectTests.swift` | Project model tests |
| `PapyroTests/SymlinkServiceTests.swift` | Symlink service tests |
| `PapyroTests/ProjectServiceTests.swift` | Project service tests |

### Modified files

| File | Changes |
|---|---|
| `Papyro/Models/Paper.swift` | Replace `projects: [String]` + `topics: [String]` with `projectIDs: [UUID]` |
| `Papyro/Models/AppState.swift` | Replace `selectedCategory: SidebarCategory` with new sidebar selection model, add `selectedStatusFilter`, column config |
| `Papyro/Models/LibraryConfig.swift` | Add `visibleColumns` and `sortColumn`/`sortAscending` |
| `Papyro/Services/ImportCoordinator.swift` | Integrate with ProjectService for Inbox assignment on import |
| `Papyro/Services/LibraryManager.swift` | Create `projects.json` with Inbox during library setup |
| `Papyro/Views/SidebarView.swift` | Complete rewrite — three sections with project management |
| `Papyro/Views/PaperListView.swift` | Complete rewrite — stacked rows, column headers, sorting, filtering |
| `Papyro/Views/PaperRowView.swift` | Rewrite to stacked layout (title row + metadata columns row) |
| `Papyro/Views/DetailView.swift` | Add projects section and status dropdown |
| `Papyro/Views/MainView.swift` | Wire ProjectService, add menu commands |
| `Papyro/PapyroApp.swift` | Create and inject ProjectService |
| `PapyroTests/PaperTests.swift` | Update Paper construction to use `projectIDs` |
| `PapyroTests/IndexServiceTests.swift` | Update `makePaper` helper to use `projectIDs` |

### Deleted files

| File | Reason |
|---|---|
| `Papyro/Models/SidebarCategory.swift` | Replaced by `SidebarItem.swift` |

---

## Task 1: Project Model

**Files:**
- Create: `Papyro/Models/Project.swift`
- Test: `PapyroTests/ProjectTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// PapyroTests/ProjectTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift test --filter ProjectTests 2>&1 | tail -20`
Expected: FAIL — `Project` type not found

- [ ] **Step 3: Write minimal implementation**

```swift
// Papyro/Models/Project.swift
import Foundation

struct Project: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var slug: String
    var isInbox: Bool
    var dateCreated: Date

    static func makeInbox() -> Project {
        Project(
            id: UUID(),
            name: "Inbox",
            slug: "inbox",
            isInbox: true,
            dateCreated: Date()
        )
    }

    static func generateSlug(from name: String) -> String {
        let lowered = name
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

- [ ] **Step 4: Add Project.swift to Xcode project**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && python3 -c "
import re
with open('Papyro.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()
# Check if Project.swift is already referenced
if 'Project.swift' in content:
    print('Already in project')
else:
    print('Need to add to Xcode project')
"`

If not already present, the Xcode project file needs to be regenerated. Use `xcodegen` or manually add the file reference. The simplest approach: open Xcode, add the file to the project navigator under `Papyro/Models/`. Alternatively, follow the pattern from prior milestones for adding files to `project.pbxproj`.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift test --filter ProjectTests 2>&1 | tail -20`
Expected: PASS — all 3 tests pass

- [ ] **Step 6: Commit**

```bash
git add Papyro/Models/Project.swift PapyroTests/ProjectTests.swift Papyro.xcodeproj/project.pbxproj
git commit -m "feat: add Project model with slug generation"
```

---

## Task 2: Update Paper Model

**Files:**
- Modify: `Papyro/Models/Paper.swift`
- Modify: `PapyroTests/PaperTests.swift`
- Modify: `PapyroTests/IndexServiceTests.swift`

- [ ] **Step 1: Update the Paper struct**

In `Papyro/Models/Paper.swift`, replace:
```swift
    var topics: [String]
    var projects: [String]
```
with:
```swift
    var projectIDs: [UUID]
```

- [ ] **Step 2: Update PaperTests.swift**

Replace all Paper constructions. The key changes — replace `topics: [], projects: []` with `projectIDs: []`:

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
            projectIDs: [],
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
        #expect(decoded.projectIDs.isEmpty)
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
            projectIDs: [],
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
        #expect(paper.projectIDs.isEmpty)
    }
}
```

- [ ] **Step 3: Update IndexServiceTests.swift makePaper helper**

Replace `topics: [], projects: []` with `projectIDs: []` in the `makePaper` helper:

```swift
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
```

- [ ] **Step 4: Update ImportCoordinator.swift**

In `importSinglePDF`, replace `topics: [], projects: []` with `projectIDs: []` in the Paper initializer:

```swift
        let paper = Paper(
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
            projectIDs: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .none,
            metadataResolved: false,
            importState: .importing
        )
```

- [ ] **Step 5: Check for any other references to `topics` or `.projects` on Paper**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && grep -rn '\.topics\|\.projects' Papyro/ PapyroTests/ --include='*.swift' | grep -v 'projectIDs'`

Fix any remaining references. Common places: other test files that construct Paper instances (e.g., `ImportCoordinatorTests.swift`, `FallbackMetadataProviderTests.swift`).

- [ ] **Step 6: Run all tests to verify**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add Papyro/Models/Paper.swift Papyro/Services/ImportCoordinator.swift PapyroTests/
git commit -m "refactor: replace projects/topics with projectIDs on Paper"
```

---

## Task 3: SymlinkService

**Files:**
- Create: `Papyro/Services/SymlinkService.swift`
- Test: `PapyroTests/SymlinkServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// PapyroTests/SymlinkServiceTests.swift
import Testing
import Foundation
@testable import Papyro

struct SymlinkServiceTests {
    let symlinkService = SymlinkService()
    let fm = FileManager.default

    private func makeTempLibrary() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("papers"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent(".symlinks"), withIntermediateDirectories: true)
        return dir
    }

    private func createDummyPDF(named filename: String, in libraryRoot: URL) -> URL {
        let url = libraryRoot.appendingPathComponent("papers/\(filename)")
        fm.createFile(atPath: url.path, contents: "dummy".data(using: .utf8))
        return url
    }

    private func makeProject(name: String = "Test", slug: String = "test", isInbox: Bool = false) -> Project {
        Project(id: UUID(), name: name, slug: slug, isInbox: isInbox, dateCreated: Date())
    }

    private func makePaper(filename: String = "2024_smith_test.pdf") -> Paper {
        Paper(
            id: UUID(),
            canonicalId: nil,
            title: "Test",
            authors: [],
            year: nil,
            journal: nil,
            doi: nil,
            arxivId: nil,
            pmid: nil,
            isbn: nil,
            abstract: nil,
            url: nil,
            pdfPath: "papers/\(filename)",
            pdfFilename: filename,
            notePath: nil,
            projectIDs: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .none,
            metadataResolved: false,
            importState: .resolved
        )
    }

    @Test func createProjectFolderCreatesDirectory() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let project = makeProject(slug: "phd-thesis")
        try symlinkService.createProjectFolder(project: project, in: libRoot)

        let folderPath = libRoot.appendingPathComponent(".symlinks/phd-thesis").path
        #expect(fm.fileExists(atPath: folderPath))
    }

    @Test func addLinkCreatesSymlink() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let project = makeProject(slug: "my-project")
        try symlinkService.createProjectFolder(project: project, in: libRoot)
        createDummyPDF(named: "2024_smith_test.pdf", in: libRoot)

        let paper = makePaper(filename: "2024_smith_test.pdf")
        try symlinkService.addLink(paper: paper, project: project, in: libRoot)

        let symlinkPath = libRoot.appendingPathComponent(".symlinks/my-project/2024_smith_test.pdf").path
        #expect(fm.fileExists(atPath: symlinkPath))

        // Verify it's actually a symlink
        let attrs = try fm.attributesOfItem(atPath: symlinkPath)
        #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
    }

    @Test func removeLinkDeletesSymlink() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let project = makeProject(slug: "my-project")
        try symlinkService.createProjectFolder(project: project, in: libRoot)
        createDummyPDF(named: "2024_smith_test.pdf", in: libRoot)

        let paper = makePaper(filename: "2024_smith_test.pdf")
        try symlinkService.addLink(paper: paper, project: project, in: libRoot)
        try symlinkService.removeLink(paper: paper, project: project, in: libRoot)

        let symlinkPath = libRoot.appendingPathComponent(".symlinks/my-project/2024_smith_test.pdf").path
        #expect(!fm.fileExists(atPath: symlinkPath))
    }

    @Test func deleteProjectFolderRemovesDirectory() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let project = makeProject(slug: "to-delete")
        try symlinkService.createProjectFolder(project: project, in: libRoot)
        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/to-delete").path))

        try symlinkService.deleteProjectFolder(project: project, in: libRoot)
        #expect(!fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/to-delete").path))
    }

    @Test func renameProjectFolderRenamesDirectory() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let project = makeProject(slug: "old-name")
        try symlinkService.createProjectFolder(project: project, in: libRoot)

        try symlinkService.renameProjectFolder(oldSlug: "old-name", newSlug: "new-name", in: libRoot)

        #expect(!fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/old-name").path))
        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/new-name").path))
    }

    @Test func rebuildAllRecreatesEverything() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        createDummyPDF(named: "paper1.pdf", in: libRoot)
        createDummyPDF(named: "paper2.pdf", in: libRoot)

        let inbox = makeProject(name: "Inbox", slug: "inbox", isInbox: true)
        let projectA = makeProject(name: "Project A", slug: "project-a")

        var paper1 = makePaper(filename: "paper1.pdf")
        paper1.projectIDs = [inbox.id]
        var paper2 = makePaper(filename: "paper2.pdf")
        paper2.projectIDs = [projectA.id]

        try symlinkService.rebuildAll(
            projects: [inbox, projectA],
            papers: [paper1, paper2],
            in: libRoot
        )

        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/inbox/paper1.pdf").path))
        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/project-a/paper2.pdf").path))
        #expect(!fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/inbox/paper2.pdf").path))
    }

    @Test func addLinkUsesRelativePath() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let project = makeProject(slug: "my-project")
        try symlinkService.createProjectFolder(project: project, in: libRoot)
        createDummyPDF(named: "test.pdf", in: libRoot)

        let paper = makePaper(filename: "test.pdf")
        try symlinkService.addLink(paper: paper, project: project, in: libRoot)

        let symlinkPath = libRoot.appendingPathComponent(".symlinks/my-project/test.pdf").path
        let destination = try fm.destinationOfSymbolicLink(atPath: symlinkPath)
        #expect(destination == "../../papers/test.pdf")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift test --filter SymlinkServiceTests 2>&1 | tail -20`
Expected: FAIL — `SymlinkService` not found

- [ ] **Step 3: Write the implementation**

```swift
// Papyro/Services/SymlinkService.swift
import Foundation

struct SymlinkService: Sendable {
    private let fm = FileManager.default

    func createProjectFolder(project: Project, in libraryRoot: URL) throws {
        let folderURL = libraryRoot.appendingPathComponent(".symlinks/\(project.slug)")
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    func deleteProjectFolder(project: Project, in libraryRoot: URL) throws {
        let folderURL = libraryRoot.appendingPathComponent(".symlinks/\(project.slug)")
        if fm.fileExists(atPath: folderURL.path) {
            try fm.removeItem(at: folderURL)
        }
    }

    func renameProjectFolder(oldSlug: String, newSlug: String, in libraryRoot: URL) throws {
        let oldURL = libraryRoot.appendingPathComponent(".symlinks/\(oldSlug)")
        let newURL = libraryRoot.appendingPathComponent(".symlinks/\(newSlug)")
        try fm.moveItem(at: oldURL, to: newURL)
    }

    func addLink(paper: Paper, project: Project, in libraryRoot: URL) throws {
        let symlinkURL = libraryRoot
            .appendingPathComponent(".symlinks/\(project.slug)/\(paper.pdfFilename)")
        let relativePath = "../../\(paper.pdfPath)"
        try fm.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: relativePath)
    }

    func removeLink(paper: Paper, project: Project, in libraryRoot: URL) throws {
        let symlinkURL = libraryRoot
            .appendingPathComponent(".symlinks/\(project.slug)/\(paper.pdfFilename)")
        if fm.fileExists(atPath: symlinkURL.path) {
            try fm.removeItem(at: symlinkURL)
        }
    }

    func rebuildAll(projects: [Project], papers: [Paper], in libraryRoot: URL) throws {
        let symlinksRoot = libraryRoot.appendingPathComponent(".symlinks")

        // Remove existing .symlinks directory
        if fm.fileExists(atPath: symlinksRoot.path) {
            try fm.removeItem(at: symlinksRoot)
        }
        try fm.createDirectory(at: symlinksRoot, withIntermediateDirectories: true)

        // Create project folders
        let projectMap = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        for project in projects {
            try createProjectFolder(project: project, in: libraryRoot)
        }

        // Create symlinks for each paper
        for paper in papers {
            for projectID in paper.projectIDs {
                if let project = projectMap[projectID] {
                    try addLink(paper: paper, project: project, in: libraryRoot)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Add to Xcode project and run tests**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift test --filter SymlinkServiceTests 2>&1 | tail -20`
Expected: All 7 tests pass

- [ ] **Step 5: Commit**

```bash
git add Papyro/Services/SymlinkService.swift PapyroTests/SymlinkServiceTests.swift Papyro.xcodeproj/project.pbxproj
git commit -m "feat: add SymlinkService for project folder and symlink management"
```

---

## Task 4: ProjectService

**Files:**
- Create: `Papyro/Services/ProjectService.swift`
- Test: `PapyroTests/ProjectServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// PapyroTests/ProjectServiceTests.swift
import Testing
import Foundation
@testable import Papyro

struct ProjectServiceTests {
    let fm = FileManager.default

    private func makeTempLibrary() throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("PapyroTest-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("papers"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("index"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent(".symlinks"), withIntermediateDirectories: true)
        return dir
    }

    private func makePaper(id: UUID = UUID(), filename: String = "test.pdf") -> Paper {
        Paper(
            id: id,
            canonicalId: nil,
            title: "Test",
            authors: [],
            year: nil,
            journal: nil,
            doi: nil,
            arxivId: nil,
            pmid: nil,
            isbn: nil,
            abstract: nil,
            url: nil,
            pdfPath: "papers/\(filename)",
            pdfFilename: filename,
            notePath: nil,
            projectIDs: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .none,
            metadataResolved: false,
            importState: .resolved
        )
    }

    @Test func initializeCreatesInbox() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()

        #expect(service.projects.count == 1)
        #expect(service.projects[0].isInbox == true)
        #expect(service.projects[0].slug == "inbox")

        // Verify projects.json was written
        let data = try Data(contentsOf: libRoot.appendingPathComponent("projects.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let projects = try decoder.decode([Project].self, from: data)
        #expect(projects.count == 1)
        #expect(projects[0].isInbox == true)

        // Verify .symlinks/inbox/ was created
        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/inbox").path))
    }

    @Test func loadExistingProjects() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        // Initialize to create projects.json
        let service1 = ProjectService(libraryRoot: libRoot)
        try service1.initialize()

        // Create a new service and load
        let service2 = ProjectService(libraryRoot: libRoot)
        try service2.loadProjects()
        #expect(service2.projects.count == 1)
        #expect(service2.projects[0].isInbox == true)
    }

    @Test func createProjectAddsToListAndDisk() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()

        let project = try service.createProject(name: "PhD Thesis")

        #expect(project.name == "PhD Thesis")
        #expect(project.slug == "phd-thesis")
        #expect(service.projects.count == 2) // inbox + new
        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/phd-thesis").path))
    }

    @Test func createProjectWithDuplicateSlugAppendsSuffix() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()

        let project1 = try service.createProject(name: "My Project")
        let project2 = try service.createProject(name: "My Project")

        #expect(project1.slug == "my-project")
        #expect(project2.slug == "my-project-2")
    }

    @Test func deleteProjectRemovesAndOrphansPapersToInbox() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        fm.createFile(atPath: libRoot.appendingPathComponent("papers/test.pdf").path, contents: "dummy".data(using: .utf8))

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()
        let inbox = service.inbox

        let project = try service.createProject(name: "To Delete")
        var paper = makePaper(filename: "test.pdf")

        // Assign to project (which removes from inbox)
        paper = try service.assignPaper(paper, to: project)
        #expect(!paper.projectIDs.contains(inbox.id))
        #expect(paper.projectIDs.contains(project.id))

        // Delete project — paper should go back to inbox
        let updatedPapers = try service.deleteProject(id: project.id, papers: [paper])
        #expect(service.projects.count == 1) // only inbox remains
        #expect(updatedPapers[0].projectIDs == [inbox.id])
    }

    @Test func assignPaperRemovesFromInbox() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        fm.createFile(atPath: libRoot.appendingPathComponent("papers/test.pdf").path, contents: "dummy".data(using: .utf8))

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()
        let inbox = service.inbox

        let project = try service.createProject(name: "My Project")
        var paper = makePaper(filename: "test.pdf")
        paper.projectIDs = [inbox.id]

        paper = try service.assignPaper(paper, to: project)
        #expect(paper.projectIDs.contains(project.id))
        #expect(!paper.projectIDs.contains(inbox.id))
    }

    @Test func unassignPaperReturnsToInboxWhenOrphaned() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        fm.createFile(atPath: libRoot.appendingPathComponent("papers/test.pdf").path, contents: "dummy".data(using: .utf8))

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()
        let inbox = service.inbox

        let project = try service.createProject(name: "My Project")
        var paper = makePaper(filename: "test.pdf")
        paper.projectIDs = [inbox.id]

        paper = try service.assignPaper(paper, to: project)
        #expect(!paper.projectIDs.contains(inbox.id))

        paper = try service.unassignPaper(paper, from: project)
        #expect(paper.projectIDs == [inbox.id])
    }

    @Test func renameProjectUpdatesList() throws {
        let libRoot = try makeTempLibrary()
        defer { try? fm.removeItem(at: libRoot) }

        let service = ProjectService(libraryRoot: libRoot)
        try service.initialize()

        let project = try service.createProject(name: "Old Name")
        try service.renameProject(id: project.id, newName: "New Name")

        let renamed = service.projects.first { $0.id == project.id }
        #expect(renamed?.name == "New Name")
        #expect(renamed?.slug == "new-name")
        #expect(fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/new-name").path))
        #expect(!fm.fileExists(atPath: libRoot.appendingPathComponent(".symlinks/old-name").path))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift test --filter ProjectServiceTests 2>&1 | tail -20`
Expected: FAIL — `ProjectService` not found

- [ ] **Step 3: Write the implementation**

```swift
// Papyro/Services/ProjectService.swift
import Foundation

@Observable
class ProjectService {
    private(set) var projects: [Project] = []

    private let libraryRoot: URL
    private let symlinkService: SymlinkService
    private let indexService: IndexService

    private var encoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    private var decoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    var inbox: Project {
        projects.first { $0.isInbox }!
    }

    var userProjects: [Project] {
        projects.filter { !$0.isInbox }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    init(
        libraryRoot: URL,
        symlinkService: SymlinkService = SymlinkService(),
        indexService: IndexService = IndexService()
    ) {
        self.libraryRoot = libraryRoot
        self.symlinkService = symlinkService
        self.indexService = indexService
    }

    func initialize() throws {
        let inbox = Project.makeInbox()
        projects = [inbox]
        try persist()
        try symlinkService.createProjectFolder(project: inbox, in: libraryRoot)
    }

    func loadProjects() throws {
        let url = libraryRoot.appendingPathComponent("projects.json")
        let data = try Data(contentsOf: url)
        projects = try decoder.decode([Project].self, from: data)
    }

    @discardableResult
    func createProject(name: String) throws -> Project {
        var slug = Project.generateSlug(from: name)
        let existingSlugs = Set(projects.map(\.slug))
        if existingSlugs.contains(slug) {
            var counter = 2
            while existingSlugs.contains("\(slug)-\(counter)") {
                counter += 1
            }
            slug = "\(slug)-\(counter)"
        }

        let project = Project(
            id: UUID(),
            name: name,
            slug: slug,
            isInbox: false,
            dateCreated: Date()
        )
        projects.append(project)
        try persist()
        try symlinkService.createProjectFolder(project: project, in: libraryRoot)
        return project
    }

    func renameProject(id: UUID, newName: String) throws {
        guard let index = projects.firstIndex(where: { $0.id == id }),
              !projects[index].isInbox else { return }

        let oldSlug = projects[index].slug
        let newSlug = Project.generateSlug(from: newName)

        projects[index].name = newName
        projects[index].slug = newSlug
        try persist()
        try symlinkService.renameProjectFolder(oldSlug: oldSlug, newSlug: newSlug, in: libraryRoot)
    }

    func deleteProject(id: UUID, papers: [Paper]) throws -> [Paper] {
        guard let project = projects.first(where: { $0.id == id }),
              !project.isInbox else { return papers }

        var updatedPapers = papers
        for i in updatedPapers.indices {
            if updatedPapers[i].projectIDs.contains(id) {
                updatedPapers[i].projectIDs.removeAll { $0 == id }
                if updatedPapers[i].projectIDs.isEmpty {
                    updatedPapers[i].projectIDs.append(inbox.id)
                }
            }
        }

        projects.removeAll { $0.id == id }
        try persist()
        try symlinkService.deleteProjectFolder(project: project, in: libraryRoot)
        return updatedPapers
    }

    func assignPaper(_ paper: Paper, to project: Project) throws -> Paper {
        var updated = paper
        if !updated.projectIDs.contains(project.id) {
            updated.projectIDs.append(project.id)
        }
        // Auto-remove from Inbox when assigning to a non-Inbox project
        if !project.isInbox {
            updated.projectIDs.removeAll { $0 == inbox.id }
        }
        try symlinkService.addLink(paper: updated, project: project, in: libraryRoot)
        return updated
    }

    func unassignPaper(_ paper: Paper, from project: Project) throws -> Paper {
        guard !project.isInbox else { return paper }

        var updated = paper
        updated.projectIDs.removeAll { $0 == project.id }
        // Auto-add to Inbox if no projects left
        if updated.projectIDs.isEmpty {
            updated.projectIDs.append(inbox.id)
            try symlinkService.addLink(paper: updated, project: inbox, in: libraryRoot)
        }
        try symlinkService.removeLink(paper: paper, project: project, in: libraryRoot)
        return updated
    }

    func rebuildSymlinks(papers: [Paper]) throws {
        try symlinkService.rebuildAll(projects: projects, papers: papers, in: libraryRoot)
    }

    private func persist() throws {
        let url = libraryRoot.appendingPathComponent("projects.json")
        let data = try encoder.encode(projects)
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Add to Xcode project and run tests**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift test --filter ProjectServiceTests 2>&1 | tail -20`
Expected: All 8 tests pass

- [ ] **Step 5: Run all tests to check for regressions**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add Papyro/Services/ProjectService.swift PapyroTests/ProjectServiceTests.swift Papyro.xcodeproj/project.pbxproj
git commit -m "feat: add ProjectService with CRUD, assign/unassign, and Inbox management"
```

---

## Task 5: Sidebar Selection Model and AppState Changes

**Files:**
- Create: `Papyro/Models/SidebarItem.swift`
- Create: `Papyro/Models/PaperColumn.swift`
- Modify: `Papyro/Models/AppState.swift`
- Modify: `Papyro/Models/LibraryConfig.swift`
- Delete: `Papyro/Models/SidebarCategory.swift`

- [ ] **Step 1: Create SidebarItem**

```swift
// Papyro/Models/SidebarItem.swift
import Foundation

enum SidebarItem: Hashable {
    case allPapers
    case project(UUID)

    var isAllPapers: Bool {
        if case .allPapers = self { return true }
        return false
    }

    var projectID: UUID? {
        if case .project(let id) = self { return id }
        return nil
    }
}
```

- [ ] **Step 2: Create PaperColumn**

```swift
// Papyro/Models/PaperColumn.swift
import Foundation

enum PaperColumn: String, Codable, CaseIterable, Identifiable {
    case authors
    case year
    case journal
    case status
    case dateAdded
    case doi
    case arxivId
    case projects
    case metadataSource
    case dateModified
    case pmid
    case isbn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .authors: "Authors"
        case .year: "Year"
        case .journal: "Journal"
        case .status: "Status"
        case .dateAdded: "Date Added"
        case .doi: "DOI"
        case .arxivId: "arXiv ID"
        case .projects: "Projects"
        case .metadataSource: "Source"
        case .dateModified: "Date Modified"
        case .pmid: "PMID"
        case .isbn: "ISBN"
        }
    }

    static var defaultVisible: Set<PaperColumn> {
        [.authors, .year, .journal, .status, .dateAdded]
    }
}
```

- [ ] **Step 3: Update AppState**

Replace the contents of `Papyro/Models/AppState.swift`:

```swift
// Papyro/Models/AppState.swift
import SwiftUI

@Observable
class AppState {
    var libraryConfig: LibraryConfig?
    var selectedSidebarItem: SidebarItem = .allPapers
    var selectedStatusFilter: ReadingStatus?
    var selectedPaperId: UUID?
    var isOnboarding: Bool = true

    var visibleColumns: Set<PaperColumn> = PaperColumn.defaultVisible
    var sortColumn: PaperColumn = .dateAdded
    var sortAscending: Bool = false
}
```

- [ ] **Step 4: Update LibraryConfig to persist column preferences**

```swift
// Papyro/Models/LibraryConfig.swift
import Foundation

struct LibraryConfig: Codable, Equatable {
    let version: Int
    var libraryPath: String
    var translationServerURL: String?
    var visibleColumns: [PaperColumn]?
    var sortColumn: PaperColumn?
    var sortAscending: Bool?
}
```

- [ ] **Step 5: Delete SidebarCategory.swift**

Delete the file `Papyro/Models/SidebarCategory.swift` and remove its reference from the Xcode project.

- [ ] **Step 6: Fix compilation — update any remaining references to `SidebarCategory` or `selectedCategory`**

Search for remaining uses:

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && grep -rn 'SidebarCategory\|selectedCategory' Papyro/ --include='*.swift'`

Update `MainView.swift` and `PaperListView.swift` (will be fully rewritten in Tasks 7-8, but fix enough for compilation now). Minimal fix for `MainView.swift`:

```swift
// Papyro/Views/MainView.swift
import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView()
        } content: {
            PaperListView()
        } detail: {
            DetailView()
        }
    }
}
```

Minimal fix for `PaperListView.swift` — remove the `category` parameter and use `appState.selectedSidebarItem`:

```swift
// Papyro/Views/PaperListView.swift (temporary minimal fix)
import SwiftUI

struct PaperListView: View {
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
        .navigationTitle("Papers")
        .dropDestination(for: URL.self) { urls, _ in
            let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            guard !pdfURLs.isEmpty else { return false }
            Task { await coordinator.importPDFs(pdfURLs) }
            return true
        }
    }
}
```

Minimal fix for `SidebarView.swift`:

```swift
// Papyro/Views/SidebarView.swift (temporary minimal fix)
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedSidebarItem) {
            Label("All Papers", systemImage: "books.vertical")
                .tag(SidebarItem.allPapers)
        }
        .navigationTitle("Papyro")
    }
}
```

- [ ] **Step 7: Run all tests to verify compilation and existing tests still pass**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift test 2>&1 | tail -20`
Expected: All tests pass (some tests may need `selectedCategory` references updated)

- [ ] **Step 8: Commit**

```bash
git add Papyro/Models/ Papyro/Views/ Papyro.xcodeproj/project.pbxproj
git rm Papyro/Models/SidebarCategory.swift
git commit -m "refactor: replace SidebarCategory with SidebarItem, add PaperColumn model"
```

---

## Task 6: Wire ProjectService into App and ImportCoordinator

**Files:**
- Modify: `Papyro/PapyroApp.swift`
- Modify: `Papyro/Services/ImportCoordinator.swift`
- Modify: `Papyro/Services/LibraryManager.swift`

- [ ] **Step 1: Update LibraryManager to create projects.json on setup**

In `Papyro/Services/LibraryManager.swift`, add project initialization. After the config write in `setupLibrary`:

```swift
import Foundation

@Observable
class LibraryManager {
    private let appState: AppState
    private let fileManager = FileManager.default

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

        // Write config.json
        let config = LibraryConfig(version: 1, libraryPath: path.path, translationServerURL: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
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
        let config = try JSONDecoder().decode(LibraryConfig.self, from: data)

        appState.libraryConfig = config
        appState.isOnboarding = false
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
}
```

- [ ] **Step 2: Add ProjectService dependency to ImportCoordinator**

Update `ImportCoordinator` to accept and use `ProjectService`:

In `Papyro/Services/ImportCoordinator.swift`, add `projectService` property and update the init and `importSinglePDF`:

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
    let projectService: ProjectService

    init(
        libraryRoot: URL,
        metadataProvider: MetadataProvider,
        projectService: ProjectService,
        fileService: FileService = FileService(),
        textExtractor: TextExtractor = TextExtractor(),
        identifierParser: IdentifierParser = IdentifierParser(),
        indexService: IndexService = IndexService()
    ) {
        self.libraryRoot = libraryRoot
        self.metadataProvider = metadataProvider
        self.projectService = projectService
        self.fileService = fileService
        self.textExtractor = textExtractor
        self.identifierParser = identifierParser
        self.indexService = indexService
    }

    func loadExistingPapers() {
        if let loaded = try? indexService.loadAll(from: libraryRoot) {
            papers = loaded.map { paper in
                var p = paper
                if p.importState == .importing || p.importState == .resolving {
                    p.importState = .unresolved
                }
                return p
            }
        }

        // Migration: if papers have empty projectIDs, assign to Inbox
        let inboxID = projectService.inbox.id
        for i in papers.indices {
            if papers[i].projectIDs.isEmpty {
                papers[i].projectIDs = [inboxID]
                try? indexService.save(papers[i], in: libraryRoot)
            }
        }
    }

    func importPDFs(_ urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { await self.importSinglePDF(url) }
            }
        }
    }

    private func importSinglePDF(_ sourceURL: URL) async {
        let copyResult: (URL, UUID)
        do {
            copyResult = try fileService.copyToLibrary(source: sourceURL, libraryRoot: libraryRoot)
        } catch {
            return
        }
        let (pdfURL, paperId) = copyResult

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
            projectIDs: [],
            status: .toRead,
            dateAdded: Date(),
            dateModified: Date(),
            metadataSource: .none,
            metadataResolved: false,
            importState: .importing
        )

        // Assign to Inbox
        if let assigned = try? projectService.assignPaper(paper, to: projectService.inbox) {
            paper = assigned
        }

        papers.append(paper)

        let extractedText = textExtractor.extractText(from: pdfURL)
        if let text = extractedText {
            try? textExtractor.cacheText(text, for: paperId, in: libraryRoot)
        }

        let identifiers = extractedText.map { identifierParser.parse($0) } ?? ParsedIdentifiers()
        await resolveMetadata(paperId: paperId, pdfURL: pdfURL, identifiers: identifiers, extractedText: extractedText)
    }

    private func resolveMetadata(paperId: UUID, pdfURL: URL, identifiers: ParsedIdentifiers, extractedText: String?) async {
        updatePaper(paperId) { $0.importState = .resolving }

        let metadata = await fetchMetadataWithFallback(identifiers: identifiers, extractedText: extractedText)

        if let metadata = metadata {
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

            let firstAuthor = metadata.authors.first.flatMap { $0.components(separatedBy: ",").first }
            let newFilename = fileService.generateFilename(year: metadata.year, author: firstAuthor, title: metadata.title)

            if let newURL = try? fileService.renamePDF(from: pdfURL, to: newFilename) {
                updatePaper(paperId) { p in
                    p.pdfPath = "papers/\(newURL.lastPathComponent)"
                    p.pdfFilename = newURL.lastPathComponent
                }
            }
        } else {
            updatePaper(paperId) { p in
                p.importState = .unresolved
                p.dateModified = Date()
            }
        }

        if let finalPaper = papers.first(where: { $0.id == paperId }) {
            try? indexService.save(finalPaper, in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }

    func retryMetadataLookup(for paperId: UUID) async {
        guard let paper = papers.first(where: { $0.id == paperId }),
              paper.importState == .unresolved else { return }

        let cachedText = textExtractor.loadCachedText(for: paperId, in: libraryRoot)
        let identifiers = cachedText.map { identifierParser.parse($0) } ?? ParsedIdentifiers()
        let pdfURL = libraryRoot.appendingPathComponent(paper.pdfPath)

        await resolveMetadata(paperId: paperId, pdfURL: pdfURL, identifiers: identifiers, extractedText: cachedText)
    }

    func updatePaperMetadata(
        paperId: UUID,
        title: String,
        authors: [String],
        year: Int?,
        journal: String?,
        doi: String?,
        abstract: String?
    ) {
        guard let paper = papers.first(where: { $0.id == paperId }) else { return }

        updatePaper(paperId) { p in
            p.title = title
            p.authors = authors
            p.year = year
            p.journal = journal
            p.doi = doi
            p.abstract = abstract
            p.metadataSource = .manual
            p.metadataResolved = true
            p.importState = .resolved
            p.dateModified = Date()
        }

        let firstAuthor = authors.first.flatMap { $0.components(separatedBy: ",").first }
        let newFilename = fileService.generateFilename(year: year, author: firstAuthor, title: title)
        let pdfURL = libraryRoot.appendingPathComponent(paper.pdfPath)

        if let newURL = try? fileService.renamePDF(from: pdfURL, to: newFilename) {
            updatePaper(paperId) { p in
                p.pdfPath = "papers/\(newURL.lastPathComponent)"
                p.pdfFilename = newURL.lastPathComponent
            }
        }

        if let finalPaper = papers.first(where: { $0.id == paperId }) {
            try? indexService.save(finalPaper, in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }

    func updatePaperStatus(paperId: UUID, status: ReadingStatus) {
        updatePaper(paperId) { p in
            p.status = status
            p.dateModified = Date()
        }
        if let paper = papers.first(where: { $0.id == paperId }) {
            try? indexService.save(paper, in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }

    func assignPaperToProject(paperId: UUID, project: Project) {
        guard let index = papers.firstIndex(where: { $0.id == paperId }) else { return }
        if let updated = try? projectService.assignPaper(papers[index], to: project) {
            papers[index] = updated
            try? indexService.save(papers[index], in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }

    func unassignPaperFromProject(paperId: UUID, project: Project) {
        guard let index = papers.firstIndex(where: { $0.id == paperId }) else { return }
        if let updated = try? projectService.unassignPaper(papers[index], from: project) {
            papers[index] = updated
            try? indexService.save(papers[index], in: libraryRoot)
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }

    func deleteProject(id: UUID) {
        if let updatedPapers = try? projectService.deleteProject(id: id, papers: papers) {
            papers = updatedPapers
            for paper in papers {
                try? indexService.save(paper, in: libraryRoot)
            }
            try? indexService.rebuildCombinedIndex(from: papers, in: libraryRoot)
        }
    }

    private func fetchMetadataWithFallback(identifiers: ParsedIdentifiers, extractedText: String?) async -> PaperMetadata? {
        if let metadata = try? await metadataProvider.fetchMetadata(for: identifiers) {
            return metadata
        }

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

- [ ] **Step 3: Update PapyroApp to create and inject ProjectService**

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
    }

    private func setupImportCoordinator(config: LibraryConfig) {
        let libraryRoot = URL(fileURLWithPath: config.libraryPath)

        // Load column preferences from config
        if let columns = config.visibleColumns {
            appState.visibleColumns = Set(columns)
        }
        if let sortCol = config.sortColumn {
            appState.sortColumn = sortCol
        }
        if let sortAsc = config.sortAscending {
            appState.sortAscending = sortAsc
        }

        var providers: [MetadataProvider] = []
        if let serverURLString = config.translationServerURL,
           let serverURL = URL(string: serverURLString) {
            providers.append(TranslationServerProvider(serverURL: serverURL))
        }
        providers.append(CrossRefProvider())
        providers.append(SemanticScholarProvider())
        let metadataProvider: MetadataProvider = FallbackMetadataProvider(providers: providers)

        let projectService = ProjectService(libraryRoot: libraryRoot)
        // Load or initialize projects
        if FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent("projects.json").path) {
            try? projectService.loadProjects()
        } else {
            try? projectService.initialize()
        }

        let coordinator = ImportCoordinator(
            libraryRoot: libraryRoot,
            metadataProvider: metadataProvider,
            projectService: projectService
        )
        coordinator.loadExistingPapers()
        importCoordinator = coordinator
    }
}
```

- [ ] **Step 4: Fix any remaining test compilation issues**

The `ImportCoordinatorTests.swift` will need updating since `ImportCoordinator.init` now requires `projectService`. Check:

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && grep -n 'ImportCoordinator(' PapyroTests/ --include='*.swift' -r`

Update any test that constructs `ImportCoordinator` to pass a `ProjectService`. Create a temp library and initialize it for test use.

- [ ] **Step 5: Run all tests**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift test 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add Papyro/PapyroApp.swift Papyro/Services/ImportCoordinator.swift Papyro/Services/LibraryManager.swift PapyroTests/ Papyro.xcodeproj/project.pbxproj
git commit -m "feat: wire ProjectService into app lifecycle and ImportCoordinator"
```

---

## Task 7: Sidebar View Rewrite

**Files:**
- Modify: `Papyro/Views/SidebarView.swift`

- [ ] **Step 1: Rewrite SidebarView**

```swift
// Papyro/Views/SidebarView.swift
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var isAddingProject = false
    @State private var newProjectName = ""
    @State private var renamingProjectID: UUID?
    @State private var renameText = ""

    private var projectService: ProjectService {
        coordinator.projectService
    }

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedSidebarItem) {
            // All Papers
            Label("All Papers", systemImage: "books.vertical")
                .tag(SidebarItem.allPapers)

            // Projects section
            Section {
                // Inbox (pinned)
                projectRow(projectService.inbox)

                // User projects (alphabetical)
                ForEach(projectService.userProjects) { project in
                    if renamingProjectID == project.id {
                        renameField(project: project)
                    } else {
                        projectRow(project)
                            .contextMenu {
                                Button("Rename") {
                                    renameText = project.name
                                    renamingProjectID = project.id
                                }
                                Button("Delete", role: .destructive) {
                                    coordinator.deleteProject(id: project.id)
                                }
                            }
                    }
                }

                if isAddingProject {
                    TextField("Project name", text: $newProjectName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !newProjectName.isEmpty {
                                try? projectService.createProject(name: newProjectName)
                            }
                            newProjectName = ""
                            isAddingProject = false
                        }
                        .onExitCommand {
                            newProjectName = ""
                            isAddingProject = false
                        }
                }
            } header: {
                HStack {
                    Text("Projects")
                    Spacer()
                    Button {
                        isAddingProject = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Status section
            Section("Status") {
                statusRow(.toRead)
                statusRow(.reading)
                statusRow(.archived)
            }
        }
        .navigationTitle("Papyro")
        .dropDestination(for: PaperDragData.self) { items, location in
            false // Handled per-project row
        }
    }

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        let count = coordinator.papers.filter { $0.projectIDs.contains(project.id) }.count

        HStack {
            Label(project.name, systemImage: project.isInbox ? "tray" : "folder")
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tag(SidebarItem.project(project.id))
        .dropDestination(for: String.self) { paperIDStrings, _ in
            for idString in paperIDStrings {
                if let paperId = UUID(uuidString: idString) {
                    coordinator.assignPaperToProject(paperId: paperId, project: project)
                }
            }
            return !paperIDStrings.isEmpty
        }
    }

    @ViewBuilder
    private func statusRow(_ status: ReadingStatus) -> some View {
        let count = coordinator.papers.filter { $0.status == status }.count
        let isSelected = appState.selectedStatusFilter == status

        Button {
            if isSelected {
                appState.selectedStatusFilter = nil
            } else {
                appState.selectedStatusFilter = status
            }
        } label: {
            HStack {
                Image(systemName: status.iconName)
                    .foregroundStyle(status.color)
                Text(status.displayName)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func renameField(project: Project) -> some View {
        TextField("Project name", text: $renameText)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                if !renameText.isEmpty {
                    try? projectService.renameProject(id: project.id, newName: renameText)
                }
                renamingProjectID = nil
            }
            .onExitCommand {
                renamingProjectID = nil
            }
    }
}
```

- [ ] **Step 2: Add helper properties to ReadingStatus**

In `Papyro/Views/PaperRowView.swift` (where `ReadingStatus.displayName` extension already lives), add:

```swift
extension ReadingStatus {
    var iconName: String {
        switch self {
        case .toRead: "circle.fill"
        case .reading: "circle.dotted.circle"
        case .archived: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .toRead: .blue
        case .reading: .orange
        case .archived: .green
        }
    }
}
```

Note: These extensions need `import SwiftUI` which is already at the top of PaperRowView.swift.

- [ ] **Step 3: Build and verify**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift build 2>&1 | tail -20`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Papyro/Views/SidebarView.swift Papyro/Views/PaperRowView.swift
git commit -m "feat: rewrite sidebar with Projects section, Status filters, and project management"
```

---

## Task 8: Paper List View Rewrite

**Files:**
- Modify: `Papyro/Views/PaperListView.swift`
- Modify: `Papyro/Views/PaperRowView.swift`

- [ ] **Step 1: Rewrite PaperListView with filtering, sorting, and column headers**

```swift
// Papyro/Views/PaperListView.swift
import SwiftUI

struct PaperListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    private var filteredPapers: [Paper] {
        var result = coordinator.papers

        // Filter by sidebar selection
        switch appState.selectedSidebarItem {
        case .allPapers:
            break
        case .project(let projectID):
            result = result.filter { $0.projectIDs.contains(projectID) }
        }

        // Filter by status
        if let status = appState.selectedStatusFilter {
            result = result.filter { $0.status == status }
        }

        // Sort
        result.sort { a, b in
            let ascending = appState.sortAscending
            let cmp: Bool
            switch appState.sortColumn {
            case .authors:
                let aAuthor = a.authors.first ?? ""
                let bAuthor = b.authors.first ?? ""
                cmp = aAuthor.localizedCaseInsensitiveCompare(bAuthor) == .orderedAscending
            case .year:
                cmp = (a.year ?? 0) < (b.year ?? 0)
            case .journal:
                cmp = (a.journal ?? "").localizedCaseInsensitiveCompare(b.journal ?? "") == .orderedAscending
            case .status:
                cmp = a.status.sortOrder < b.status.sortOrder
            case .dateAdded:
                cmp = a.dateAdded < b.dateAdded
            case .dateModified:
                cmp = a.dateModified < b.dateModified
            case .doi:
                cmp = (a.doi ?? "") < (b.doi ?? "")
            case .arxivId:
                cmp = (a.arxivId ?? "") < (b.arxivId ?? "")
            case .pmid:
                cmp = (a.pmid ?? "") < (b.pmid ?? "")
            case .isbn:
                cmp = (a.isbn ?? "") < (b.isbn ?? "")
            case .projects, .metadataSource:
                cmp = a.dateAdded < b.dateAdded
            }
            return ascending ? cmp : !cmp
        }

        return result
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Column header bar
            ColumnHeaderBar(
                visibleColumns: appState.visibleColumns,
                sortColumn: appState.sortColumn,
                sortAscending: appState.sortAscending
            ) { column in
                if appState.sortColumn == column {
                    appState.sortAscending.toggle()
                } else {
                    appState.sortColumn = column
                    appState.sortAscending = true
                }
            }

            if filteredPapers.isEmpty {
                ContentUnavailableView(
                    "No Papers",
                    systemImage: "doc.text",
                    description: Text("Drag and drop PDF files here to import them.")
                )
            } else {
                List(filteredPapers, selection: $appState.selectedPaperId) { paper in
                    PaperRowView(
                        paper: paper,
                        visibleColumns: appState.visibleColumns,
                        projects: coordinator.projectService.projects
                    )
                    .tag(paper.id)
                    .draggable(paper.id.uuidString)
                    .contextMenu {
                        paperContextMenu(paper: paper)
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .dropDestination(for: URL.self) { urls, _ in
            let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            guard !pdfURLs.isEmpty else { return false }
            Task { await coordinator.importPDFs(pdfURLs) }
            return true
        }
    }

    private var navigationTitle: String {
        switch appState.selectedSidebarItem {
        case .allPapers:
            "All Papers"
        case .project(let id):
            coordinator.projectService.projects.first { $0.id == id }?.name ?? "Papers"
        }
    }

    @ViewBuilder
    private func paperContextMenu(paper: Paper) -> some View {
        Menu("Add to Project") {
            ForEach(coordinator.projectService.userProjects) { project in
                Button {
                    if paper.projectIDs.contains(project.id) {
                        coordinator.unassignPaperFromProject(paperId: paper.id, project: project)
                    } else {
                        coordinator.assignPaperToProject(paperId: paper.id, project: project)
                    }
                } label: {
                    HStack {
                        Text(project.name)
                        if paper.projectIDs.contains(project.id) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Menu("Set Status") {
            ForEach([ReadingStatus.toRead, .reading, .archived], id: \.self) { status in
                Button {
                    coordinator.updatePaperStatus(paperId: paper.id, status: status)
                } label: {
                    HStack {
                        Text(status.displayName)
                        if paper.status == status {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()

        Button("Open PDF") {
            if let config = appState.libraryConfig {
                let pdfURL = URL(fileURLWithPath: config.libraryPath)
                    .appendingPathComponent(paper.pdfPath)
                NSWorkspace.shared.open(pdfURL)
            }
        }

        Button("Reveal in Finder") {
            if let config = appState.libraryConfig {
                let pdfURL = URL(fileURLWithPath: config.libraryPath)
                    .appendingPathComponent(paper.pdfPath)
                NSWorkspace.shared.activateFileViewerSelecting([pdfURL])
            }
        }
    }
}

// MARK: - Column Header Bar

private struct ColumnHeaderBar: View {
    let visibleColumns: Set<PaperColumn>
    let sortColumn: PaperColumn
    let sortAscending: Bool
    let onTapColumn: (PaperColumn) -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Title column (no sort — always present)
            Spacer()
                .frame(maxWidth: .infinity)

            ForEach(sortedVisibleColumns, id: \.self) { column in
                Button {
                    onTapColumn(column)
                } label: {
                    HStack(spacing: 4) {
                        Text(column.displayName)
                        if sortColumn == column {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(sortColumn == column ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: columnWidth(for: column), alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .contextMenu {
            ForEach(PaperColumn.allCases) { column in
                Toggle(column.displayName, isOn: Binding(
                    get: { visibleColumns.contains(column) },
                    set: { isOn in
                        // This is handled through AppState in the parent
                    }
                ))
            }
        }
    }

    private var sortedVisibleColumns: [PaperColumn] {
        PaperColumn.allCases.filter { visibleColumns.contains($0) }
    }

    private func columnWidth(for column: PaperColumn) -> CGFloat {
        switch column {
        case .authors: 120
        case .year: 50
        case .journal: 100
        case .status: 70
        case .dateAdded, .dateModified: 80
        case .doi, .arxivId: 140
        case .projects: 120
        case .metadataSource: 80
        case .pmid, .isbn: 100
        }
    }
}
```

- [ ] **Step 2: Add sortOrder to ReadingStatus**

In `Papyro/Views/PaperRowView.swift`, add to the `ReadingStatus` extension:

```swift
extension ReadingStatus {
    var sortOrder: Int {
        switch self {
        case .toRead: 0
        case .reading: 1
        case .archived: 2
        }
    }
}
```

- [ ] **Step 3: Rewrite PaperRowView with stacked layout**

```swift
// Papyro/Views/PaperRowView.swift
import SwiftUI

struct PaperRowView: View {
    let paper: Paper
    let visibleColumns: Set<PaperColumn>
    let projects: [Project]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Row 1: Title (full width)
            Text(paper.title)
                .font(.system(size: 13, weight: .semibold))

            // Row 2: Metadata columns
            HStack(spacing: 0) {
                Spacer()
                    .frame(maxWidth: .infinity)

                ForEach(sortedVisibleColumns, id: \.self) { column in
                    columnValue(for: column)
                        .frame(width: columnWidth(for: column), alignment: .leading)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var sortedVisibleColumns: [PaperColumn] {
        PaperColumn.allCases.filter { visibleColumns.contains($0) }
    }

    @ViewBuilder
    private func columnValue(for column: PaperColumn) -> some View {
        switch column {
        case .authors:
            Text(formatAuthors(paper.authors))
                .lineLimit(1)
        case .year:
            Text(paper.year.map(String.init) ?? "—")
        case .journal:
            Text(paper.journal ?? "—")
                .lineLimit(1)
        case .status:
            BadgeView(text: paper.status.displayName, color: paper.status.color)
        case .dateAdded:
            Text(paper.dateAdded.formatted(.dateTime.month(.abbreviated).day()))
        case .dateModified:
            Text(paper.dateModified.formatted(.dateTime.month(.abbreviated).day()))
        case .doi:
            Text(paper.doi ?? "—")
                .lineLimit(1)
        case .arxivId:
            Text(paper.arxivId ?? "—")
                .lineLimit(1)
        case .pmid:
            Text(paper.pmid ?? "—")
        case .isbn:
            Text(paper.isbn ?? "—")
        case .projects:
            Text(projectNames)
                .lineLimit(1)
        case .metadataSource:
            Text(paper.metadataSource.rawValue)
                .lineLimit(1)
        }
    }

    private var projectNames: String {
        let names = paper.projectIDs.compactMap { id in
            projects.first { $0.id == id }?.name
        }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    private func formatAuthors(_ authors: [String]) -> String {
        guard let first = authors.first else { return "—" }
        let surname = first.components(separatedBy: ",").first ?? first
        return authors.count > 1 ? "\(surname) et al." : surname
    }

    private func columnWidth(for column: PaperColumn) -> CGFloat {
        switch column {
        case .authors: 120
        case .year: 50
        case .journal: 100
        case .status: 70
        case .dateAdded, .dateModified: 80
        case .doi, .arxivId: 140
        case .projects: 120
        case .metadataSource: 80
        case .pmid, .isbn: 100
        }
    }
}

struct BadgeView: View {
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

extension ReadingStatus {
    var displayName: String {
        switch self {
        case .toRead: "To Read"
        case .reading: "Reading"
        case .archived: "Archived"
        }
    }

    var iconName: String {
        switch self {
        case .toRead: "circle.fill"
        case .reading: "circle.dotted.circle"
        case .archived: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .toRead: .blue
        case .reading: .orange
        case .archived: .green
        }
    }

    var sortOrder: Int {
        switch self {
        case .toRead: 0
        case .reading: 1
        case .archived: 2
        }
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift build 2>&1 | tail -20`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Papyro/Views/PaperListView.swift Papyro/Views/PaperRowView.swift
git commit -m "feat: rewrite paper list with stacked rows, sortable columns, and filtering"
```

---

## Task 9: Detail Panel Updates

**Files:**
- Create: `Papyro/Views/ProjectChipsView.swift`
- Modify: `Papyro/Views/DetailView.swift`

- [ ] **Step 1: Create ProjectChipsView**

```swift
// Papyro/Views/ProjectChipsView.swift
import SwiftUI

struct ProjectChipsView: View {
    let paper: Paper
    let projects: [Project]
    let onRemove: (Project) -> Void
    let onAdd: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects")
                .font(.headline)

            FlowLayout(spacing: 6) {
                ForEach(assignedProjects) { project in
                    HStack(spacing: 4) {
                        Text(project.name)
                            .font(.caption)
                            .fontWeight(.medium)

                        if !project.isInbox {
                            Button {
                                onRemove(project)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
                }

                Menu {
                    ForEach(availableProjects) { project in
                        Button(project.name) {
                            onAdd(project)
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(availableProjects.isEmpty)
            }
        }
    }

    private var assignedProjects: [Project] {
        paper.projectIDs.compactMap { id in
            projects.first { $0.id == id }
        }
    }

    private var availableProjects: [Project] {
        projects.filter { !$0.isInbox && !paper.projectIDs.contains($0.id) }
    }
}

// Simple flow layout for chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
```

- [ ] **Step 2: Update DetailView with projects section and status dropdown**

In `Papyro/Views/DetailView.swift`, add the projects section after `metadataSection` and replace the status row with a Picker. Add after the `metadataSection(paper)` call in the body:

Add before the `metadataSection`:

```swift
                        // Projects section
                        ProjectChipsView(
                            paper: paper,
                            projects: coordinator.projectService.projects,
                            onRemove: { project in
                                coordinator.unassignPaperFromProject(paperId: paper.id, project: project)
                            },
                            onAdd: { project in
                                coordinator.assignPaperToProject(paperId: paper.id, project: project)
                            }
                        )
                        Divider()
```

In the `metadataSection`, replace the status `MetadataRow` with a Picker:

Replace:
```swift
            MetadataRow(label: "Status", value: paper.status.displayName)
```
With:
```swift
            HStack(alignment: .top) {
                Text("Status")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)

                Picker("", selection: Binding(
                    get: { paper.status },
                    set: { newStatus in
                        coordinator.updatePaperStatus(paperId: paper.id, status: newStatus)
                    }
                )) {
                    Text("To Read").tag(ReadingStatus.toRead)
                    Text("Reading").tag(ReadingStatus.reading)
                    Text("Archived").tag(ReadingStatus.archived)
                }
                .labelsHidden()
                .fixedSize()
            }
```

- [ ] **Step 3: Build and verify**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift build 2>&1 | tail -20`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Papyro/Views/ProjectChipsView.swift Papyro/Views/DetailView.swift Papyro.xcodeproj/project.pbxproj
git commit -m "feat: add project chips and status dropdown to detail panel"
```

---

## Task 10: Menu Commands and Keyboard Shortcuts

**Files:**
- Modify: `Papyro/Views/MainView.swift`

- [ ] **Step 1: Add menu commands to MainView**

```swift
// Papyro/Views/MainView.swift
import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @Environment(ImportCoordinator.self) private var coordinator

    @State private var showNewProjectPrompt = false
    @State private var newProjectName = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView()
        } content: {
            PaperListView()
        } detail: {
            DetailView()
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
    }

    private func setSelectedPaperStatus(_ status: ReadingStatus) -> KeyPress.Result {
        guard let paperId = appState.selectedPaperId else { return .ignored }
        coordinator.updatePaperStatus(paperId: paperId, status: status)
        return .handled
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift build 2>&1 | tail -20`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Papyro/Views/MainView.swift
git commit -m "feat: add menu commands and keyboard shortcuts for project and status management"
```

---

## Task 11: Column Configuration Context Menu

**Files:**
- Modify: `Papyro/Views/PaperListView.swift`

- [ ] **Step 1: Fix the column header context menu to actually toggle columns**

In `PaperListView.swift`, the `ColumnHeaderBar` context menu needs to write to `AppState`. Update the context menu in `ColumnHeaderBar`:

Replace the `contextMenu` block:

```swift
        .contextMenu {
            ForEach(PaperColumn.allCases) { column in
                Button {
                    if visibleColumns.contains(column) {
                        onToggleColumn(column, false)
                    } else {
                        onToggleColumn(column, true)
                    }
                } label: {
                    HStack {
                        Text(column.displayName)
                        if visibleColumns.contains(column) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
```

Add `onToggleColumn` parameter to `ColumnHeaderBar`:

```swift
private struct ColumnHeaderBar: View {
    let visibleColumns: Set<PaperColumn>
    let sortColumn: PaperColumn
    let sortAscending: Bool
    let onTapColumn: (PaperColumn) -> Void
    let onToggleColumn: (PaperColumn, Bool) -> Void
```

Update the call site in `PaperListView.body`:

```swift
            ColumnHeaderBar(
                visibleColumns: appState.visibleColumns,
                sortColumn: appState.sortColumn,
                sortAscending: appState.sortAscending,
                onTapColumn: { column in
                    if appState.sortColumn == column {
                        appState.sortAscending.toggle()
                    } else {
                        appState.sortColumn = column
                        appState.sortAscending = true
                    }
                },
                onToggleColumn: { column, isOn in
                    if isOn {
                        appState.visibleColumns.insert(column)
                    } else {
                        appState.visibleColumns.remove(column)
                    }
                }
            )
```

- [ ] **Step 2: Build and verify**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift build 2>&1 | tail -20`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Papyro/Views/PaperListView.swift
git commit -m "feat: add column visibility toggle via context menu"
```

---

## Task 12: Xcode Project File Update and Final Integration Test

**Files:**
- Modify: `Papyro.xcodeproj/project.pbxproj`

- [ ] **Step 1: Ensure all new files are in the Xcode project**

Verify all new files are included:

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && for f in Project.swift PaperColumn.swift SidebarItem.swift ProjectService.swift SymlinkService.swift ProjectChipsView.swift; do grep -l "$f" Papyro.xcodeproj/project.pbxproj && echo "$f: OK" || echo "$f: MISSING"; done`

If any are missing, open Xcode and add them, or manually edit `project.pbxproj` following the existing file reference patterns.

- [ ] **Step 2: Verify SidebarCategory.swift is removed from the project**

Run: `grep 'SidebarCategory' Papyro.xcodeproj/project.pbxproj`

If references remain, remove them from `project.pbxproj`.

- [ ] **Step 3: Run all tests**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift test 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 4: Build the full app**

Run: `cd /Users/yuhanli/allgemeiner-intellekt/papyro && swift build 2>&1 | tail -20`
Expected: Build succeeds with no warnings

- [ ] **Step 5: Commit if any project file changes were needed**

```bash
git add Papyro.xcodeproj/project.pbxproj
git commit -m "chore: regenerate Xcode project with M3 files"
```

---

## Task Summary

| Task | Component | Tests | Estimated Complexity |
|---|---|---|---|
| 1 | Project model | 3 tests | Low |
| 2 | Paper model migration | Update existing tests | Low |
| 3 | SymlinkService | 7 tests | Medium |
| 4 | ProjectService | 8 tests | Medium |
| 5 | Sidebar selection model + AppState | — (compilation check) | Low |
| 6 | Wire services into app | Update existing tests | Medium |
| 7 | Sidebar view rewrite | — (visual verification) | Medium |
| 8 | Paper list view rewrite | — (visual verification) | High |
| 9 | Detail panel updates | — (visual verification) | Medium |
| 10 | Menu commands + shortcuts | — (visual verification) | Low |
| 11 | Column configuration | — (visual verification) | Low |
| 12 | Xcode project + integration | Run all tests | Low |
