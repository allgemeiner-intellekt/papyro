# Papyro Robustness Pass — P0/P1 Fixes

## Context

M5 shipped, completing the symlink-management UI. A parallel team review (4 view/service reviewers + a devil's-advocate critic) found that Papyro's biggest robustness gap is **silent IO failure**: dozens of `try?` sites swallow errors, so failed imports, failed note creation, failed symlink ops, and failed config saves all leave the user with zero feedback. Two specific bugs compound this:

1. **Sidebar project Delete has no confirmation** — one fat-finger right-click and a project disappears (`SidebarView.swift:47-49`). The MainView "Delete Project?" alert exists (`MainView.swift:7,40-50`) but nothing in the codebase ever sets `showDeleteConfirmation = true` — it is dead code.
2. **`SymlinkService.rebuildAll` non-atomic rename window** — a crash between `removeItem(.symlinks)` and `moveItem(temp → .symlinks)` (`SymlinkService.swift:73-77`) leaves the user with no `.symlinks/` at all.

This plan fixes those two plus the silent-failure pattern, plus a focused set of high-impact UX bugs (DetailView edit form, PDF-missing alerts, stale selection guard). Out of scope: migration transactionality, body-time filesystem I/O, WelcomeView atomicity, the symlink-naming nit, the health-banner timer (re-examination shows MainView never unmounts so the "stacking timers" concern doesn't reproduce), Retry Lookup task scoping (re-examination shows `retryMetadataLookup` writes by stable `paperId` and doesn't corrupt other papers).

## Approach

**Surface IO failures, don't change architecture.** No async refactor, no transactions, no observability framework. Add one error field to `AppState`, plug a single `.alert(item:)` into MainView, and route every user-triggered failure through it. This is the smallest change that turns the entire `try?` epidemic from invisible to actionable.

**Atomic symlink rebuild via two renames + cleanup.** `FileManager.replaceItemAt` does not reliably work for directories on macOS. Use rename-rename-remove: rename `.symlinks/` → `.symlinks-old/`, rename temp → `.symlinks/`, remove `.symlinks-old/`. Both critical renames are individually atomic; a crash between them leaves a recoverable `.symlinks-old/` for next launch to clean.

**Wire Sidebar Delete confirmation locally in SidebarView**, not by reviving the dead MainView alert. Track `@State projectToDelete: Project?` so right-clicking a non-selected project still asks the right question. Then delete the dead alert from MainView.

**Author edit field uses `; ` everywhere** — both display join and parse. Round-trips reliably for names containing commas (`"Smith, J."`). The model stays a `[String]`; only the human-facing string format changes.

## Files & Changes

### 1. `Papyro/Models/AppState.swift`
- Add small struct:
  ```swift
  struct UserFacingError: Identifiable {
      let id = UUID()
      let title: String
      let message: String
  }
  ```
- Add `var userError: UserFacingError? = nil` to `AppState`.

### 2. `Papyro/Views/MainView.swift`
- Add `.alert(item: $appState.userError)` showing `title` + `message` + OK button. The existing `@Bindable var appState = appState` (line 13) makes the binding work.
- **Remove dead code**: `@State private var showDeleteConfirmation = false` (line 9) and the entire `.alert("Delete Project?")` block (lines 40-50). Nothing sets this flag anywhere in the codebase — the alert is unreachable.

### 3. `Papyro/Views/SidebarView.swift`
- Add `@State private var projectToDelete: Project?`.
- Replace direct `coordinator.deleteProject(id: project.id)` (line 48) with `projectToDelete = project`.
- Add `.alert("Delete Project?", item: $projectToDelete)`:
  - Destructive Confirm calls `coordinator.deleteProject(id: project.id)`. If `appState.selectedSidebarItem.projectID == project.id`, set `appState.selectedSidebarItem = .allPapers`.
  - Cancel clears the binding.
- Replace `try? projectService.createProject(...)` (line 60) with `do/catch` → `appState.userError = UserFacingError(title: "Couldn't create project", message: error.localizedDescription)`.
- Replace `try? projectService.renameProject(...)` (line 219) with `do/catch` → surface.

### 4. `Papyro/Services/SymlinkService.swift`
- Replace lines 73-77 (`removeItem` + `moveItem`) with rename-rename-remove:
  ```swift
  let oldRoot = libraryRoot.appendingPathComponent(".symlinks-old")
  if fm.fileExists(atPath: oldRoot.path) { try? fm.removeItem(at: oldRoot) }
  if fm.fileExists(atPath: symlinksRoot.path) {
      try fm.moveItem(at: symlinksRoot, to: oldRoot)
  }
  try fm.moveItem(at: tempRoot, to: symlinksRoot)
  try? fm.removeItem(at: oldRoot)
  ```

### 5. `Papyro/Views/SettingsView.swift`
- `saveConfig()` (lines 244-252): change to `throws`. Replace nested `try?` with `try encoder.encode(...)` and `try data.write(...)`.
- `createLink` flow (lines 203-213), `unlinkFolder` (215-221), `repairLink` (223-241): wrap in `do/catch`, surface failures via `appState.userError`. Each calls `saveConfig()` after — surface if it throws.
- All three callers of `saveConfig()` (lines 218, 226, 246 — verify exact lines on edit) need the new error path.
- Rebuild button action (lines 70-77): wrap `coordinator.projectService.rebuildSymlinks(...)` call in `do/catch` → surface.

### 6. `Papyro/Services/ImportCoordinator.swift`
- `createNote(for paperId:)` (lines 189-198): change return type to `Result<URL, Error>` (URL = resolved note URL on disk). Replace internal `try?` on `noteGenerator.generateNote` with `try`. Internal `indexService.save` / `rebuildCombinedIndex` `try?`s **stay** — those are downstream from the user's intent and surfacing them all would be alert spam (documented gap).
- `assignPaperToProject(paperId:project:)` (lines 253-259) and `unassignPaperFromProject(paperId:project:)` (lines 263-268): change to `throws`. Replace `try?` on `projectService.assignPaper`/`unassignPaper` with `try`. Same gap policy on the trailing `indexService` calls.
- `importPaper` PDF copy site (around line 74): on `fileService.copyToLibrary` failure, set `appState.userError` directly (AppState is already injected) before returning. The drag-drop / file menu caller doesn't need to know.
- Internal call site of `createNote` during import (around line 167-168): use `try?` and ignore the new Result there — it's already inside the import flow's "best effort" tier.

### 7. `Papyro/Views/DetailView.swift`
- **Edit form field reset**: change `.onChange(of: appState.selectedPaperId)` (lines 73-75) to also reset `editTitle`, `editAuthors`, `editYear`, `editJournal`, `editDOI`, `editAbstract` to `""`. Currently only `isEditing` resets, so drafts leak across papers.
- **Save validation** (around line 130, in the Save button action):
  - Reject empty title (after `.trimmingCharacters(in: .whitespaces)`) → `appState.userError = ...`, return without saving.
  - Reject non-empty year that fails `Int(_:)` → `appState.userError = ...`, return.
- **Author separator** (consistent on both sides):
  - Edit-button initialization (line 276): `editAuthors = paper.authors.joined(separator: "; ")`.
  - Save parser (lines 124-127): `editAuthors.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }`.
  - Display (line 158): `Text(paper.authors.joined(separator: "; "))`.
- **`createProject` callback** (line 56): replace `try?` with `do/catch` → surface.
- **`assignPaperToProject` / `unassignPaperFromProject` callbacks** (lines 50-54): wrap the now-throwing coordinator calls in `do/catch` → surface.
- **`createNote` button** (around line 265): handle the new `Result<URL, Error>`. On success, optionally open the note (existing behavior). On failure → surface.
- **PDF-missing guards**: in `openPDF` (line 304+) and `revealInFinder`: check `FileManager.default.fileExists(atPath: pdfURL.path)`. On miss → `appState.userError = UserFacingError(title: "PDF Not Found", message: "The file at \(paper.pdfPath) is missing from your library.")`.

### 8. `Papyro/Views/MainView.swift` (continued from §2)
- `openOrCreateNote` (lines 87-108): handle `coordinator.createNote(for:)`'s new `Result`. On success and notePath present → open. On failure → `appState.userError = ...`.

### 9. `Papyro/Views/PaperListView.swift`
- Add `.onChange(of: coordinator.papers)` validator: if `appState.selectedPaperId` is non-nil and not in `coordinator.papers`, set it to nil.
- Context menu items at lines 168, 170 calling `assignPaperToProject` / `unassignPaperFromProject`: wrap in `do/catch` → surface.

### 10. `Papyro/Views/ProjectChipsView.swift`
- New project input field (line 53): replace `try? createProject` with `do/catch` → surface.
- `onAdd` callback (line 99): if it routes through a now-throwing coordinator method, wrap accordingly. (Verify whether `onAdd` calls into `assignPaperToProject` indirectly via DetailView's callback, in which case the catch lives in DetailView and ProjectChipsView is unchanged.)

## Implementation Order

Steps are grouped so the build never breaks mid-step. Each step ends with a successful build.

1. **Foundation** — `UserFacingError` + `userError` in AppState; `.alert(item:)` in MainView. Build.
2. **Sidebar Delete confirmation** + remove dead MainView alert. Build. Smoke: right-click project (selected and non-selected) → confirm/cancel paths.
3. **SymlinkService.rebuildAll** atomic via rename-rename-remove. Build. Smoke: hit Rebuild from Settings → Symlinks.
4. **SettingsView** `try?` → surfaces (createLink, unlink, repair, saveConfig, Rebuild button). Build.
5. **SidebarView** `try?` → surfaces (createProject, renameProject). Build.
6. **ImportCoordinator signature changes + ALL callers in one shot** — `createNote` returns `Result`, `assignPaper`/`unassignPaper` throw. Update simultaneously: ImportCoordinator internals, MainView.openOrCreateNote, DetailView createNote button + project assign/unassign callbacks, PaperListView context menu, ProjectChipsView (if applicable). This is the only step that touches multiple files in one build cycle, by necessity. Build.
7. **DetailView edit form fixes** — field reset on paper change, year validation, title validation, author separator. Build.
8. **DetailView PDF-missing guards** in openPDF and revealInFinder. Build.
9. **PaperListView stale-selection validator**. Build.
10. **Final** kill, rebuild, open. Run the verification list.

## Verification

End-to-end manual smoke tests after step 10:

- **Sidebar Delete**: right-click a *selected* project → Confirm → project gone, sidebar resets to All Papers. Right-click a *non-selected* project → Confirm → only that project deleted, selection unchanged. Cancel works in both cases.
- **Error surface end-to-end**: in Terminal, `chmod -w /Users/yuhanli/ResearchLibrary` (or wherever the library is), then in Papyro try Settings → Symlinks → Link Folder. Alert should fire with the OS error message. Restore permissions afterward.
- **Symlink atomic rebuild**: in Terminal, `while true; do ls /Users/yuhanli/ResearchLibrary/.symlinks 2>&1 | head -1; sleep 0.05; done`. From Papyro, click Settings → Symlinks → Rebuild. Confirm `.symlinks/` is never absent (may briefly appear as `.symlinks-old/` sibling).
- **Edit form validation**: enter title `"   "` → Save → alert. Enter year `"202x"` → Save → alert. Enter year `""` (empty) → Save → succeeds with year nil.
- **Edit form field reset**: click Edit on paper A, type a new title without saving, click paper B in the list, click Edit on B → form shows B's fields, not A's leaked draft.
- **Author round-trip**: enter authors `"Smith, J.; Doe, J."` → Save → reload paper → still shows two authors `["Smith, J.", "Doe, J."]`, displayed as `"Smith, J.; Doe, J."`.
- **createNote failure**: temporarily make the library's `notes/` directory read-only (`chmod -w notes`), then press Cmd-E on a paper without a note → alert fires. Restore.
- **PDF missing**: delete a paper's PDF in Finder, click "Open PDF" in DetailView → alert fires (not silent). Same for "Finder" button.
- **Stale selection guard**: this is hard to trigger without a delete-paper UI; verify it compiles and the validator runs by adding a `print` temporarily (then removing).

## Risks & Notes

- **Author display change is one-way for human eyes**. Existing libraries store authors as `[String]` arrays, so no model migration is needed — only the display join format changes. Users who memorized the comma format will need to re-learn `; ` separator. Acceptable for personal-use single-user app.
- **`try?` on `indexService.save`/`rebuildCombinedIndex`** inside ImportCoordinator's batch flows is **deliberately left in place**. These are downstream of the user-triggered op and the user can't act on them in the moment. Surfacing every one would be alert spam. This is an accepted gap; revisit only if it causes data loss in practice.
- **Step 6 is the only multi-file step.** Signature changes ripple to ~6 call sites. Edit them in one pass before building.
- **Rename-rename-remove on `.symlinks-old`**: if step 4's `removeItem(at: oldRoot)` fails (e.g. permission glitch), the directory persists across launches. Next launch's first call cleans it up via the leading `if fileExists(.symlinks-old) { try? removeItem }`. Self-healing.
- **Token budget for implementation**: if the pass runs long, drop steps 8-9 (PDF guard + stale-selection guard) without losing the P0 fixes. Don't drop steps 1-7.

## Critical Files Touched

- `Papyro/Models/AppState.swift` (new field + struct)
- `Papyro/Views/MainView.swift` (alert + remove dead alert + openOrCreateNote)
- `Papyro/Views/SidebarView.swift` (delete confirmation + try? fixes)
- `Papyro/Views/SettingsView.swift` (try? fixes + saveConfig throws)
- `Papyro/Views/DetailView.swift` (edit form + PDF guards + try? fixes)
- `Papyro/Views/PaperListView.swift` (stale-selection guard + context menu try? fixes)
- `Papyro/Views/ProjectChipsView.swift` (try? fixes if applicable)
- `Papyro/Services/ImportCoordinator.swift` (createNote/assignPaper signature changes + import PDF copy surface)
- `Papyro/Services/SymlinkService.swift` (atomic rebuildAll)
