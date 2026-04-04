# M4: Search and Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent full-text search that filters the paper list across all metadata fields, composing with existing project and status filters.

**Architecture:** One new property on `AppState` (`searchText`), one new method on `Paper` (`matches(searchTokens:)`), and modifications to `PaperListView` to wire up SwiftUI's `.searchable()` modifier and integrate the search filter into the existing `filteredPapers` pipeline.

**Tech Stack:** Swift, SwiftUI (`.searchable()` modifier), Swift Testing framework

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `Papyro/Models/AppState.swift` | Add `searchText` property |
| Modify | `Papyro/Models/Paper.swift` | Add `matches(searchTokens:)` method |
| Modify | `Papyro/Views/PaperListView.swift` | Wire `.searchable()`, add search filter step, adapt empty state |
| Modify | `PapyroTests/PaperTests.swift` | Add tests for search matching |

---

### Task 1: Add search matching to Paper model

**Files:**
- Test: `PapyroTests/PaperTests.swift`
- Modify: `Papyro/Models/Paper.swift`

- [ ] **Step 1: Write the failing tests**

Add the following tests to `PapyroTests/PaperTests.swift`, after the existing tests:

```swift
@Test func matchesTitleSearch() {
    let paper = makePaper(title: "Attention Is All You Need", authors: ["Vaswani, A."])
    #expect(paper.matches(searchTokens: ["attention"]))
    #expect(!paper.matches(searchTokens: ["transformer"]))
}

@Test func matchesAuthorSearch() {
    let paper = makePaper(title: "Some Paper", authors: ["Smith, J.", "Chen, L."])
    #expect(paper.matches(searchTokens: ["smith"]))
    #expect(paper.matches(searchTokens: ["chen"]))
}

@Test func matchesMultipleTokensWithANDLogic() {
    let paper = makePaper(title: "Neural Plasticity", authors: ["Smith, J."], year: 2024)
    #expect(paper.matches(searchTokens: ["smith", "2024"]))
    #expect(paper.matches(searchTokens: ["neural", "smith"]))
    #expect(!paper.matches(searchTokens: ["smith", "2025"]))
}

@Test func matchesIdentifierFields() {
    let paper = makePaper(title: "Test", doi: "10.1038/s41586-024-07998-6", arxivId: "2401.12345")
    #expect(paper.matches(searchTokens: ["10.1038"]))
    #expect(paper.matches(searchTokens: ["2401.12345"]))
}

@Test func matchesJournalAndAbstract() {
    let paper = makePaper(title: "Test", journal: "Nature", abstract: "We study deep learning")
    #expect(paper.matches(searchTokens: ["nature"]))
    #expect(paper.matches(searchTokens: ["deep", "learning"]))
}

@Test func emptyTokensMatchesEverything() {
    let paper = makePaper(title: "Anything")
    #expect(paper.matches(searchTokens: []))
}

@Test func matchesIsCaseInsensitive() {
    let paper = makePaper(title: "Attention Is All You Need")
    #expect(paper.matches(searchTokens: ["ATTENTION"]))
    #expect(paper.matches(searchTokens: ["Attention"]))
}
```

Also add this helper at the bottom of the `PaperTests` struct:

```swift
private func makePaper(
    title: String = "Untitled",
    authors: [String] = [],
    year: Int? = nil,
    journal: String? = nil,
    abstract: String? = nil,
    doi: String? = nil,
    arxivId: String? = nil,
    pmid: String? = nil,
    isbn: String? = nil
) -> Paper {
    Paper(
        id: UUID(),
        canonicalId: nil,
        title: title,
        authors: authors,
        year: year,
        journal: journal,
        doi: doi,
        arxivId: arxivId,
        pmid: pmid,
        isbn: isbn,
        abstract: abstract,
        url: nil,
        pdfPath: "papers/test.pdf",
        pdfFilename: "test.pdf",
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Papyro -destination 'platform=macOS' -only-testing PapyroTests/PaperTests 2>&1 | tail -20`

Expected: Compilation error — `matches(searchTokens:)` does not exist on `Paper`.

- [ ] **Step 3: Implement matches(searchTokens:) on Paper**

Add the following at the end of `Papyro/Models/Paper.swift`, before the closing of the file:

```swift
extension Paper {
    func matches(searchTokens: [String]) -> Bool {
        if searchTokens.isEmpty { return true }
        let searchable = [
            title,
            authors.joined(separator: " "),
            year.map(String.init) ?? "",
            journal ?? "",
            abstract ?? "",
            doi ?? "",
            arxivId ?? "",
            pmid ?? "",
            isbn ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return searchTokens.allSatisfy { searchable.contains($0.lowercased()) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Papyro -destination 'platform=macOS' -only-testing PapyroTests/PaperTests 2>&1 | tail -20`

Expected: All PaperTests pass, including the 7 new search tests.

- [ ] **Step 5: Commit**

```bash
git add Papyro/Models/Paper.swift PapyroTests/PaperTests.swift
git commit -m "feat: add search matching method to Paper model"
```

---

### Task 2: Add searchText to AppState

**Files:**
- Modify: `Papyro/Models/AppState.swift`

- [ ] **Step 1: Add the searchText property**

Add `var searchText: String = ""` to `AppState`. The full file becomes:

```swift
import SwiftUI

@Observable
class AppState {
    var libraryConfig: LibraryConfig?
    var selectedSidebarItem: SidebarItem = .allPapers
    var selectedStatusFilter: ReadingStatus?
    var selectedPaperId: UUID?
    var isOnboarding: Bool = true
    var isEditingText: Bool = false
    var searchText: String = ""

    var visibleColumns: Set<PaperColumn> = PaperColumn.defaultVisible
    var sortColumn: PaperColumn = .dateAdded
    var sortAscending: Bool = false
    var columnWidths: [PaperColumn: CGFloat] = PaperColumn.defaultWidths
}
```

- [ ] **Step 2: Verify the project builds**

Run: `xcodebuild build -scheme Papyro -destination 'platform=macOS' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Papyro/Models/AppState.swift
git commit -m "feat: add searchText property to AppState"
```

---

### Task 3: Wire .searchable() and search filter into PaperListView

**Files:**
- Modify: `Papyro/Views/PaperListView.swift`

- [ ] **Step 1: Add search filter step to filteredPapers**

In `PaperListView`, add the search filter between the status filter and the sort, at line 22 (after the `if let status` block). Insert:

```swift
// Filter by search text
let searchTokens = appState.searchText
    .lowercased()
    .split(separator: " ")
    .map(String.init)
if !searchTokens.isEmpty {
    result = result.filter { $0.matches(searchTokens: searchTokens) }
}
```

The `filteredPapers` computed property should now read:

```swift
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

    // Filter by search text
    let searchTokens = appState.searchText
        .lowercased()
        .split(separator: " ")
        .map(String.init)
    if !searchTokens.isEmpty {
        result = result.filter { $0.matches(searchTokens: searchTokens) }
    }

    // Sort
    result.sort { a, b in
        // ... existing sort logic unchanged ...
    }

    return result
}
```

- [ ] **Step 2: Add .searchable() modifier and adapt empty state**

Replace the `body` property with:

```swift
var body: some View {
    @Bindable var appState = appState

    Group {
        if filteredPapers.isEmpty {
            if !appState.searchText.isEmpty {
                ContentUnavailableView.search(text: appState.searchText)
            } else {
                ContentUnavailableView(
                    "No Papers",
                    systemImage: "doc.text",
                    description: Text("Drag and drop PDF files here to import them.")
                )
            }
        } else {
            List(selection: $appState.selectedPaperId) {
                Section {
                    ForEach(filteredPapers) { paper in
                        PaperRowView(
                            paper: paper,
                            visibleColumns: appState.visibleColumns,
                            columnWidths: appState.columnWidths,
                            projects: coordinator.projectService.projects
                        )
                        .tag(paper.id)
                        .draggable(paper.id.uuidString)
                        .contextMenu {
                            paperContextMenu(paper: paper)
                        }
                    }
                } header: {
                    ColumnHeaderBar(
                        visibleColumns: appState.visibleColumns,
                        columnWidths: $appState.columnWidths,
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
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
    .searchable(text: $appState.searchText, prompt: "Search papers")
    .navigationTitle(navigationTitle)
    .dropDestination(for: URL.self) { urls, _ in
        let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfURLs.isEmpty else { return false }
        Task { await coordinator.importPDFs(pdfURLs) }
        return true
    }
}
```

Key changes:
1. `.searchable(text: $appState.searchText, prompt: "Search papers")` added after the `Group` closing brace.
2. Empty state now checks `appState.searchText.isEmpty` — if search is active, shows `ContentUnavailableView.search(text:)`. Otherwise shows the original drag-and-drop message.

- [ ] **Step 3: Verify the project builds**

Run: `xcodebuild build -scheme Papyro -destination 'platform=macOS' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run all tests**

Run: `xcodebuild test -scheme Papyro -destination 'platform=macOS' 2>&1 | tail -20`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Papyro/Views/PaperListView.swift
git commit -m "feat: wire searchable modifier and search filter into paper list"
```

---

### Task 4: Manual verification

- [ ] **Step 1: Build and run the app**

Run: `xcodebuild build -scheme Papyro -destination 'platform=macOS' 2>&1 | tail -5`

Then open the app. Verify:

1. The search field appears in the toolbar area of the content column.
2. Typing text filters the paper list live.
3. Multi-word queries use AND logic (e.g., "smith 2024" narrows to papers matching both).
4. Clearing the search field restores the full list.
5. Search composes with sidebar project selection — selecting a project then searching filters within that project.
6. Search composes with status filter — toggling a status filter while searching narrows further.
7. When search has no results, `ContentUnavailableView.search` shows (not the "drag and drop" message).
8. Cmd+F focuses the search field.
9. Keyboard shortcuts 1/2/3 still work when the search field is NOT focused.
10. Typing in the search field does NOT trigger 1/2/3 status shortcuts.

- [ ] **Step 2: Handle .searchable() placement issue (if needed)**

If the search field appears in the wrong column (e.g., sidebar or detail), move `.searchable()` from `PaperListView` to `MainView`, applied on `PaperListView()` with explicit placement:

```swift
} content: {
    PaperListView()
        .searchable(text: $appState.searchText, placement: .toolbar, prompt: "Search papers")
}
```

And remove the `.searchable()` from `PaperListView.body`. Only do this if the placement is wrong — try the `PaperListView` placement first.

- [ ] **Step 3: Final commit (if placement fix was needed)**

```bash
git add Papyro/Views/PaperListView.swift Papyro/Views/MainView.swift
git commit -m "fix: adjust searchable placement to content column"
```
