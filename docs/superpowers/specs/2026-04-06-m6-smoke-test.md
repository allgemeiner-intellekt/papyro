# M6 Smoke Test Checklist

**Goal:** Verify the M6 external-sync feature (FileSystemWatcher + ExternalChangeCoordinator + drain UI + shortcuts) actually works end-to-end in a running app.

**Build artifact:** `/tmp/papyro-m6-build/Build/Products/Debug/Papyro.app`
**Spec:** `docs/superpowers/specs/2026-04-06-m6-polish-design.md`
**Plan:** `docs/superpowers/plans/2026-04-06-m6-polish.md`

If the build artifact is gone, rebuild with:
```bash
xcodebuild -scheme Papyro -destination 'platform=macOS' \
  -derivedDataPath /tmp/papyro-m6-build build
```

---

## 0. Pre-flight setup

- [ ] **0.1** Quit any existing Papyro instance: `killall Papyro 2>/dev/null` (or just check it's not running).
- [ ] **0.2** Decide which library to test against. **Recommended:** make a disposable copy of your real library so you can drag random PDFs into it without polluting:
  ```bash
  cp -R ~/ResearchLibrary /tmp/papyro-smoke-lib
  ```
  Or use a fresh empty library — Papyro's onboarding will let you point it at any directory.
- [ ] **0.3** Have a few test PDFs ready in some scratch directory you can drag from. Real papers are best (so the metadata fetch has something to find), but any PDF works.
- [ ] **0.4** Open Console.app, filter by `process:Papyro`, and start streaming. Keep the Console window visible alongside Papyro for the duration of the test. If anything goes wrong, the console output is your first diagnostic.
- [ ] **0.5** Open Finder to `<library>/papers/2024/` (or any year folder) so you can drop files in quickly.
- [ ] **0.6** Launch the build artifact:
  ```
  open /tmp/papyro-m6-build/Build/Products/Debug/Papyro.app
  ```
  Or in your prompt: `! open /tmp/papyro-m6-build/Build/Products/Debug/Papyro.app`
- [ ] **0.7** If you're prompted for a library, point it at the smoke library. Confirm Papyro shows the existing papers (if any) and the three-pane layout looks normal.
- [ ] **0.8** Note the count of papers currently visible. You'll use this as a baseline.

**If launch fails or onboarding is broken, STOP** — that's a regression in something pre-M6 and needs investigation before continuing the smoke test.

---

## 1. The seven plan checks

These are the seven scenarios from the plan's Task 14. Each should produce a specific observable outcome.

### Check 1 — Reconcile catches an offline drop

The most important check: it proves the launch backstop works even when FSEvents was completely off.

- [ ] **1.1** Quit Papyro completely (⌘Q).
- [ ] **1.2** In Finder, drop a fresh PDF into `<library>/papers/2024/` (or any year folder). Use a PDF that's NOT already in the library.
- [ ] **1.3** Note the filename you dropped.
- [ ] **1.4** Relaunch Papyro from the build artifact.
- [ ] **1.5** **Within ~2 seconds of the main window appearing**, the new paper should be visible in the paper list.
- [ ] **1.6** The orange pending banner ("1 paper needs metadata", or however many) should appear at the top of the window.
- [ ] **1.7** Wait ~5 seconds. If the initial drain succeeds against your translation server, the paper may transition to a fully resolved state and the banner may drop. If the drain fails (no server, no DOI), the paper stays as the pending count.
- [ ] **1.8** Click on the new paper. The detail panel should show its filename as the title (placeholder, since metadata didn't resolve), and metadata source should be `none` or `unresolved`.

**If the paper does not appear:** the reconcile-on-launch is broken. Check Console for any errors. Quit and check `<library>/index/` — was a new JSON file created for the paper? If no, the issue is in `ExternalChangeCoordinator.reconcile()` or `addPaperFromExternalSync`. If yes, the issue is in the in-memory list update.

---

### Check 2 — Live add while running

- [ ] **2.1** With Papyro still running and the main window in front, drop a SECOND new PDF into `<library>/papers/2024/`.
- [ ] **2.2** **Within ~1 second**, the paper appears in the list as `.unresolved`.
- [ ] **2.3** The pending banner count increments by 1.
- [ ] **2.4** The new paper is selectable.

**If the paper does NOT appear within ~3 seconds:** the live watcher is broken. Possible causes:
- FSEvents stream failed to start (you should have seen a "Live sync unavailable" error dialog at launch — did you?).
- The watcher's debounce is too long.
- The path classification is rejecting the file (check that the file actually has `.pdf` extension, not something else).

---

### Check 3 — Live delete

- [ ] **3.1** In Finder, locate one of the PDFs you dropped in checks 1 or 2.
- [ ] **3.2** Move it to the Trash via Finder (⌘⌫ in Finder, or right-click → Move to Trash).
- [ ] **3.3** **Within ~1 second**, the paper disappears from the Papyro list.
- [ ] **3.4** No error dialog appears in Papyro.
- [ ] **3.5** Check `<library>/index/` — the JSON file for that paper is gone.

**If the paper stays in Papyro after the file is gone:** the watcher delete handler is broken. Check Console for FS event delivery issues.

---

### Check 4 — External index edit

- [ ] **4.1** With Papyro running, open one of the JSON files in `<library>/index/` in a text editor (TextEdit, VS Code, whatever).
- [ ] **4.2** Find the `"title"` field. Change its value to `"EDITED EXTERNALLY VIA SMOKE TEST"`. Save the file.
- [ ] **4.3** **Within ~1 second**, the title in the Papyro list updates to match.
- [ ] **4.4** The detail pane (if that paper is selected) also updates.

**If the title does not update:** `handleIndexModified` is broken or the watcher isn't classifying the JSON edit as `.indexModified`. Check that the JSON edit was actually saved (some editors do atomic writes that may look different to FSEvents).

**Bonus:** Edit the JSON to be invalid (insert `{ broken` at the top). Save. Papyro should NOT crash, and the in-memory title should remain whatever it was last set to. Then fix the JSON and re-save; the in-memory copy should re-sync.

---

### Check 5 — In-app ⌘⌫ delete with confirm

This is the most user-facing change.

- [ ] **5.1** Select any paper in the list (click on it). Confirm the detail pane shows it.
- [ ] **5.2** Press `⌘⌫` (Command + Backspace).
- [ ] **5.3** A confirmation dialog appears with title `"Move to Trash?"` and a message that includes the paper's title and `"will be moved to the Trash. The note file in notes/ will be left alone."`
- [ ] **5.4** Click `"Move to Trash"`.
- [ ] **5.5** The paper disappears from the list. The detail pane reverts to "Select a Paper".
- [ ] **5.6** Open Finder → Trash. The PDF should be there with its original filename.
- [ ] **5.7** Check `<library>/notes/`. If a note file existed for this paper (`<id>.md`), it should STILL be there. **This is critical** — the PRD §3.3 says notes are user-owned and must not be deleted automatically.
- [ ] **5.8** Check `<library>/index/`. The JSON file for the deleted paper is gone.
- [ ] **5.9** Try ⌘⌫ again on a different paper. Click "Cancel" on the dialog. The paper should remain.

**If the dialog doesn't appear:** the keyboard shortcut isn't being captured. Possible causes:
- Focus is in a text field somewhere (the `isEditingText` guard suppresses the shortcut).
- `⌘⌫` is being intercepted by something else.
- The `.onKeyPress(.delete, phases: .down)` isn't recognizing Backspace as `.delete`.

**If the file move fails (error dialog "Couldn't move to Trash"):** check filesystem permissions on the library folder. Some directories don't allow trashing.

**If the note file IS deleted:** that's a critical bug. The plan explicitly excluded note deletion. Halt and report immediately.

---

### Check 6 — ⌘O opens PDF

- [ ] **6.1** Select a paper.
- [ ] **6.2** Press `⌘O`.
- [ ] **6.3** The PDF opens in Preview (or whichever app is set as default for `.pdf`).
- [ ] **6.4** Close Preview, return to Papyro.
- [ ] **6.5** Press `⌘O` on a different paper to confirm the shortcut works for the current selection, not a cached one.

**If nothing opens:** `keyboardShortcut("o", modifiers: .command)` may not be reaching the button action. Try clicking the "Open PDF" button manually — if THAT works but ⌘O doesn't, the shortcut binding is the issue. If neither works, `openPDF()` itself is broken.

**Edge case:** Try ⌘O on a paper whose PDF file you just deleted via Finder. You should see a "PDF Not Found" error dialog (existing behavior, not new in M6).

---

### Check 7 — Resolve button drains pending

- [ ] **7.1** Make sure there is at least one `.unresolved` paper visible. If the banner is gone, drop a fresh PDF to create one (Check 2 procedure).
- [ ] **7.2** Click the orange "Resolve" button in the banner.
- [ ] **7.3** The button text changes to "Resolving…" and becomes disabled (greyed out / not clickable).
- [ ] **7.4** Wait. Drain runs concurrently for up to 3 papers at a time, hitting your translation server / CrossRef / Semantic Scholar in turn.
- [ ] **7.5** When the drain finishes:
  - Papers that resolved successfully: drop out of the pending count, banner count decreases.
  - Papers that failed (no DOI, no network, server error): stay pending, the banner count for them stays the same.
  - The button re-enables (text returns to "Resolve").
- [ ] **7.6** If everything resolved, the banner disappears entirely.
- [ ] **7.7** Click on a paper that failed to resolve. In the detail pane, the metadata should still be sparse, and (if you exposed it in UI — note: M6 doesn't add a UI for `lastResolutionError`) the field would show "Metadata lookup failed".

**If the button never re-enables:** the `defer { isResolvingPending = false }` in `resolveAllPending` may have been bypassed somehow. Check Console.

**If clicking Resolve does nothing visible:** maybe `pendingPapers` is already empty. Confirm by opening an unresolved paper's index JSON and checking `"importState": "unresolved"`.

---

## 2. Self-write guard verification

The self-write guard is the subtlest part of M6 and the easiest place for a bug to hide. These checks specifically exercise it.

- [ ] **2.1** **Drag-and-drop import doesn't double-fire.** Drop a fresh PDF into the Papyro window (NOT into Finder — drop directly onto the app window). The existing import pipeline runs (file copy, metadata fetch, etc.). **Expect:** Exactly ONE paper appears in the list. No duplicate, no error dialog. The watcher would have fired an FSEvent for the file copy and another for the rename, both of which should be suppressed by the self-write guard.

- [ ] **2.2** **Manual metadata edit doesn't trigger external-edit handling.** Select a paper. Click the Edit button in the detail pane. Change the title. Click Save. **Expect:** The change persists, no error dialog, no flicker as if the in-memory state were being overwritten by a re-read of the index file.

- [ ] **2.3** **Status change doesn't trigger external-edit handling.** Use the 1/2/3 keyboard shortcuts to change a paper's reading status. **Expect:** The change persists, no flicker.

- [ ] **2.4** **In-app delete doesn't double-process.** Use ⌘⌫ to delete a paper (Check 5 above). After confirming, watch for any error dialog or duplicate processing. **Expect:** Single deletion event, no "couldn't find paper" follow-up errors.

- [ ] **2.5** **Project assignment doesn't flicker.** Drop a paper into a project from the sidebar (or use the right-click context menu). **Expect:** The assignment persists, the project chip appears in the detail pane, no re-read flicker.

**If any of these double-fire or flicker:** the self-write guard at one of the call sites in `ImportCoordinator` is missing. Check `git log --oneline d40aeb7 -1` and `git show d40aeb7` to see which sites were guarded.

---

## 3. Regression checks (M1–M5 functionality should still work)

M6 should not have broken anything from earlier milestones. Quick spot-checks:

- [ ] **3.1** **Drag-and-drop import works.** Drop a fresh PDF onto the Papyro window. It imports normally and resolves metadata.
- [ ] **3.2** **Search works.** Press ⌘F. Type a search term. The list filters. Press Esc to clear.
- [ ] **3.3** **Sidebar projects work.** Click on a project in the sidebar. The list filters to that project. Click "All Papers" to return.
- [ ] **3.4** **Status toggles work.** Select a paper, press 1, 2, or 3. The status changes. The status badge updates in the row.
- [ ] **3.5** **⌘E open note works.** Select a paper, press ⌘E. The note opens in the default markdown editor (Obsidian, etc.). If no note exists yet, one is created.
- [ ] **3.6** **Settings window works.** Open Settings (⌘,). The General and Symlinks tabs both render. Managed symlinks (M5) still listed.
- [ ] **3.7** **Project create/rename/delete works.** Open Settings → projects. Create a new project. Rename it. Delete it. No crashes.
- [ ] **3.8** **Reveal in Finder works.** Select a paper, click "Finder" in the action grid. Finder opens with the PDF highlighted.
- [ ] **3.9** **Inline metadata edit works.** Click Edit in the detail pane. Change a field. Save. The change persists across app restart.

**If any of these break:** that's a regression and a serious problem. The only files M6 modified that touch existing flows are `ImportCoordinator.swift`, `MainView.swift`, `DetailView.swift`, `PaperListView.swift`, and `PapyroApp.swift`. Bisect by reverting M6 commits in reverse order to find which task broke the regression.

---

## 4. Edge cases (subtle, but worth checking once)

- [ ] **4.1** **⌘⌫ inside a text field is suppressed.** Select a paper, click Edit, focus the title field. Press ⌘⌫. **Expect:** It just deletes characters (or does nothing) — does NOT pop up the delete confirmation dialog. (The `appState.isEditingText` guard should suppress it.)
- [ ] **4.2** **⌘⌫ with no selection does nothing.** Click in the empty list area to clear selection. Press ⌘⌫. **Expect:** No dialog.
- [ ] **4.3** **Bare Backspace does nothing.** Select a paper. Press Backspace alone (NOT Cmd+Backspace). **Expect:** Nothing — the dialog should NOT appear. (The `press.modifiers == .command` guard.)
- [ ] **4.4** **Idempotent watcher add.** Touch the same PDF file twice in quick succession (e.g., `touch <library>/papers/2024/<existing-file>.pdf` followed by another `touch`). **Expect:** No new entry created (the path is already in `papers`). No errors.
- [ ] **4.5** **Reconcile is idempotent.** Quit Papyro, immediately relaunch (no filesystem changes in between). **Expect:** No new papers appear, none disappear, no error dialogs. The paper count is exactly what it was at quit.
- [ ] **4.6** **Banner shows correct grammar.** When count == 1, banner says "1 paper needs metadata" (singular). When count == 2+, it says "N papers need metadata" (plural).
- [ ] **4.7** **Drain failure doesn't crash.** Disconnect from the network (or set the translation server URL to something invalid). Click Resolve on a pending banner. **Expect:** The drain runs and reports failure (papers stay pending, button re-enables, no crash).
- [ ] **4.8** **Pending banner doesn't show when count is 0.** Resolve all pending papers. The banner should disappear entirely (not just show "0 papers need metadata").
- [ ] **4.9** **External index edit with mid-air corruption.** Open an index JSON, type random garbage, save. **Expect:** Papyro doesn't crash. The in-memory title for that paper stays whatever it was. Fix the JSON and re-save — the in-memory copy re-syncs.
- [ ] **4.10** **External delete during selection.** Select a paper. In Finder, delete its PDF. **Expect:** Within ~1 second the paper disappears AND the detail pane reverts to "Select a Paper" (because `deletePaper` clears `appState.selectedPaperId` when the deleted paper was selected).

---

## 5. Observability — what to watch

While running the checks, keep these visible so you can spot issues:

- [ ] **5.1** **Console.app filtered to `process:Papyro`.** Any printed errors, exceptions, or `try?` failures will surface here. Particularly watch for:
  - "Couldn't decode index file" — corrupt JSON or schema mismatch
  - FSEvents-related warnings
  - Any stack traces
- [ ] **5.2** **`<library>/index/` directory in Finder.** As you add/delete papers, the JSON files should appear and disappear in step.
- [ ] **5.3** **`<library>/papers/2024/` directory in Finder.** The PDFs you dropped should be there. After ⌘⌫, the file should be gone (in Trash).
- [ ] **5.4** **`<library>/.symlinks/inbox/` directory in Finder** (if Inbox project exists). Externally-added papers should create symlinks here, since Task 6 routes through `ProjectService.assignPaper`.
- [ ] **5.5** **macOS Activity Monitor → Papyro process.** Memory should sit around 50–120 MB depending on library size (per PRD §9 targets). CPU should be near 0% when idle, briefly spike during drain or import.

---

## 6. Reporting back

When you finish, report:

1. **Pass/fail** for each numbered check (1.1, 1.2, … 5.5).
2. **For any failure:** what you did, what you expected, what happened, and any console output.
3. **Anything weird that wasn't a clean pass or fail.** Subjective things ("the banner felt slow", "the dialog popped up on the wrong monitor") are valuable too.
4. **Things you noticed that weren't on the checklist.** First-touch dogfooding always surfaces things the spec didn't anticipate.

---

## 7. If something is badly broken

- **Don't panic.** All changes are committed. Revert to before M6 with:
  ```bash
  git log --oneline | grep -E "(M6|m6|watcher|sync|pending|resolveAll|deletePaper|lastResolutionError)" | head
  ```
  to find the M6 commit range, then reset or revert as needed.
- **Quit the smoke build before making code changes.** Otherwise the build artifact is locked.
- **The smoke library is disposable.** If something corrupts it, just `rm -rf /tmp/papyro-smoke-lib` and recreate from your real one.

---

## 8. Sign-off

When all checks pass:

- [ ] Mark Task 14 complete in the implementation plan
- [ ] Update memory: M6 is done, app is daily-use ready, candidate for first sustained dogfood period
- [ ] Optional: tag the commit `git tag m6-complete`
- [ ] Decide whether to merge `superpowers-init` into `main` or keep iterating
