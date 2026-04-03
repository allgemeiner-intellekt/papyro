# M2 Polish — Implementation Plan

## Context

M2 (Import Pipeline) is complete with 34 passing tests. The core pipeline works — drop a PDF, get metadata, see it in the list. However, the code review identified five polish items that should be addressed before moving to M3 (Views and Organisation). These are all scoped and low-risk improvements to the existing pipeline.

## Tasks

### Task 1: Full Metadata Fallback Chain

**Problem:** Only one provider is used at runtime (TranslationServer OR CrossRef). SemanticScholar is never used. If CrossRef fails, the paper is unresolved even though Semantic Scholar might have it.

**Approach:** Create `FallbackMetadataProvider` — a composite that wraps an ordered list of providers and tries each until one succeeds. ImportCoordinator stays unchanged (still receives a single `MetadataProvider`).

**Files:**
- Create: `Papyro/Services/FallbackMetadataProvider.swift`
- Create: `PapyroTests/FallbackMetadataProviderTests.swift`
- Modify: `Papyro/PapyroApp.swift` — change `setupImportCoordinator` to build provider list

**Tests:** 4 tests — first succeeds, first nil falls through, first throws falls through, all fail returns nil.

---

### Task 2: Parallel Import

**Problem:** Dropping 10 PDFs processes them one at a time. Metadata fetches are network-bound, so this is unnecessarily slow.

**Approach:** Replace sequential `for` loop in `importPDFs` with `withTaskGroup`. Safe because `@MainActor` serializes mutations to the `papers` array.

**Files:**
- Modify: `Papyro/Services/ImportCoordinator.swift` — change `importPDFs` method (~3 lines)

**Tests:** Existing `importMultiplePDFs` test still passes (doesn't check order).

---

### Task 3: Filename Collision Handling

**Problem:** Two papers with same year/author/title generate identical filenames. The rename silently fails and the paper keeps its UUID name.

**Approach:** Modify `FileService.renamePDF` to check if destination exists and append `-2`, `-3`, etc.

**Files:**
- Modify: `Papyro/Services/FileService.swift` — update `renamePDF`
- Modify: `PapyroTests/FileServiceTests.swift` — add collision tests

**Tests:** 2 new tests — single collision gets `-2`, multiple collisions increment.

---

### Task 4: Retry Metadata Lookup

**Problem:** Unresolved papers have no way to re-attempt metadata fetch (e.g., after server comes back online or user corrects a DOI).

**Approach:**
1. Add `loadCachedText(for:in:)` to `TextExtractor` (reads from `.cache/text/`)
2. Add `retryMetadataLookup(for:)` to `ImportCoordinator` — loads cached text, re-parses identifiers, re-runs fallback chain, renames on success
3. Extract shared `resolveMetadata` helper from `importSinglePDF` to avoid duplication
4. Add "Retry Lookup" button in DetailView for unresolved papers

**Files:**
- Modify: `Papyro/Services/TextExtractor.swift` — add `loadCachedText`
- Modify: `Papyro/Services/ImportCoordinator.swift` — add `retryMetadataLookup`, extract shared helper
- Modify: `Papyro/Views/DetailView.swift` — add retry button
- Modify: `PapyroTests/TextExtractorTests.swift` — test loadCachedText

**Tests:** 1 new TextExtractor test + 2 new ImportCoordinator tests (retry succeeds, retry fails).

**Depends on:** Task 1 (fallback chain), Task 3 (collision-safe rename).

---

### Task 5: Inline Metadata Editing (Edit Mode)

**Problem:** Users can't correct wrong metadata or fill in missing fields for unresolved papers.

**Approach:** Add edit-mode toggle to DetailView. "Edit" button switches to TextField-based form. "Save" persists changes via new `updatePaperMetadata` method on ImportCoordinator. "Cancel" discards.

- Authors displayed as comma-separated text in a single TextField
- Changing selection while editing discards unsaved changes
- On save, re-generate filename and rename PDF if title/author/year changed
- Set `metadataSource` to `.manual` after user edits

**Files:**
- Modify: `Papyro/Services/ImportCoordinator.swift` — add `updatePaperMetadata`
- Modify: `Papyro/Views/DetailView.swift` — add edit mode with `@State` fields, TextField bindings, Save/Cancel buttons

**Tests:** 1 new ImportCoordinator test (updatePaperMetadata persists and sets source to manual).

**Depends on:** Task 3 (collision-safe rename for post-edit filename changes).

---

## Task Order

```
Task 1 (fallback chain) ──┐
Task 2 (parallel import)   ├── Task 4 (retry lookup) ── Task 5 (inline editing)
Task 3 (filename collision)┘
```

Tasks 1, 2, 3 are independent. Task 4 depends on 1 and 3. Task 5 depends on 3.

## Verification

1. Run `xcodegen && xcodebuild test` — all existing + new tests pass
2. Manual: drop a PDF without translation server configured — verify CrossRef then S2 fallback works
3. Manual: drop 5+ PDFs at once — verify they appear immediately and resolve in parallel
4. Manual: drop two PDFs that would generate the same filename — verify `-2` suffix
5. Manual: drop a PDF that can't be resolved, then click "Retry Lookup" — verify it retries
6. Manual: select a paper, click "Edit", change the title, click "Save" — verify title updates in list and JSON on disk
