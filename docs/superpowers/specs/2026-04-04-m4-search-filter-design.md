# M4: Search and Filter — Design Spec

**Date:** 2026-04-04
**Milestone:** M4 (Search and filter)
**PRD reference:** Section 3.5, Section 6.1 #9

---

## Context

M1–M3 are complete. The app has a three-column layout (sidebar, paper list, detail panel), project-based organisation with drag-and-drop assignment, status filtering (to-read / reading / archived), and sortable/resizable columns. Topics were dropped during M3 as projects serve the same purpose.

M4 adds search to let users find papers quickly in a growing library.

## Design decisions

| Decision | Choice | Rationale |
|---|---|---|
| Search trigger | Persistent field (always visible) | Most discoverable; matches Finder/Mail pattern |
| Implementation | SwiftUI `.searchable()` modifier | Native look, built-in Cmd+F, zero custom UI |
| Placement | Content column (paper list) | Scoped to the paper list, not sidebar or detail |
| Search scope | All text metadata fields | Title, authors, year, journal, abstract, DOI, arXiv ID, PMID, ISBN |
| Matching logic | Tokenized AND with case-insensitive containment | Split query by whitespace; all tokens must match. "Smith 2024" finds papers where both appear across any fields |
| Filter interaction | Search within current context | Composes with existing project + status sidebar filters. Search narrows the current view. |
| Separate filter controls | None | Universal text search replaces the need for year/author/journal dropdowns |

## Architecture

### Touch points

Three changes to the existing codebase:

1. **`AppState`** — one new property: `searchText: String = ""`
2. **`Paper`** — one new method: `matches(searchTokens:) -> Bool`
3. **`PaperListView`** — `.searchable()` modifier, search filter step in `filteredPapers`, adapted empty state

No new services, files, or data structures.

### Data flow

```
coordinator.papers
  → filter by project (existing)
  → filter by status (existing)
  → filter by searchText (NEW)
  → sort by column (existing)
```

### Search matching

A `matches(searchTokens:)` method on `Paper`:

1. Concatenates all searchable fields into one lowercased string: title, authors (joined), year (as string), journal, abstract, DOI, arXiv ID, PMID, ISBN.
2. Returns `true` if every token from the query appears somewhere in that string (AND logic, case-insensitive).

Token splitting and lowercasing happen once at the call site, not per-paper.

### `.searchable()` integration

- Applied to `PaperListView` body. If SwiftUI misplaces it in the `NavigationSplitView`, fall back to applying at the `NavigationSplitView` level with `placement: .content`.
- Binds to `appState.searchText`.
- Cmd+F focus comes for free from the modifier.

### Empty state

When search yields zero results, replace the current `ContentUnavailableView("No Papers", ...)` with `ContentUnavailableView.search` (or a custom variant showing the search text). The "No Papers — drag and drop" message only shows when there are genuinely no papers, not when a search simply has no matches.

### Keyboard interaction

- `.searchable()` manages its own text field focus. The `onKeyPress("1"/"2"/"3")` handlers on `MainView` should not fire while the search field is focused, because SwiftUI routes key events to the focused responder first. If testing reveals conflicts, the existing `isEditingText` guard provides a fallback.

### Performance

For 5000 papers: ~5000 string concatenations + substring checks per keystroke. On Apple Silicon this is well under 50ms — comfortably within the PRD target of < 200ms. No debouncing, pre-computed indexes, or caching needed at this scale.

## Out of scope

- Search suggestions / autocomplete
- Relevance-ranked results (conflicts with user's chosen column sort)
- Field-specific search syntax (e.g., `author:Smith`)
- Result highlighting
- Debouncing (unnecessary at target library sizes)

These can be revisited if the need arises in later milestones.
