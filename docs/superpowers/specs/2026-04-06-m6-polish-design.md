# M6 — External Sync & Daily-Use Polish

**Date:** 2026-04-06
**Status:** Draft for review
**Milestone:** M6 (final MVP milestone, per `docs/papyro-prd.md` §11)

---

## 1. Scope

M6 in the PRD bundles five things: filesystem watcher, offline queue, keyboard shortcuts, error-handling polish, and an "edge cases" sweep. This spec covers the three concrete pieces and explicitly defers the two vague ones until real dogfooding produces real friction:

**In scope**

1. Filesystem watcher that reacts to external changes in `papers/` and `index/`.
2. Offline / pending-resolution queue for papers whose metadata hasn't been fetched yet.
3. The two remaining keyboard shortcuts from §7.3 of the PRD: ⌘O (Open PDF) and ⌘⌫ (Delete with confirm). The 1/2/3 status toggles and ⌘E / ⌘F already exist.

**Out of scope (deferred until post-dogfooding)**

- "Error handling polish" beyond what falls naturally out of the watcher/queue work.
- A speculative "edge case" sweep.
- Background periodic retry, reachability monitoring, exponential backoff.
- Watching `notes/` or `.cache/`.
- Bulk re-resolution of already-resolved papers.
- Anything beyond last-write-wins for simultaneous app + external edits.

## 2. Design principles

- **The index is the source of truth.** No new persistent stores. The "queue" is a filter over the index (`metadata_resolved == false`). The watcher is an optimization on top of reconcile-on-launch — never the only path to correctness.
- **Index-only on external add, defer fetch.** When a PDF appears externally, Papyro records it but does **not** auto-hit the network. The user explicitly drains the pending pile with a button. This was a deliberate choice over auto-import to avoid surprise network activity and to keep the watcher path cheap and predictable.
- **Manual drain over background retry.** Drain happens at launch and when the user clicks the banner. No timers, no reachability monitor. Predictable beats clever.
- **Self-write guard, not lock-stepping.** The watcher ignores events for paths Papyro just wrote, rather than trying to coordinate with FSEvents around its own writes.

## 3. Components

Three new services. No reshuffling of existing code.

### 3.1 `FileSystemWatcher` (new)

Pure FS layer. Wraps `FSEventStreamCreate`, watches `papers/` and `index/` recursively. Debounces 500 ms. Emits on a serial background queue:

```swift
enum FSEvent {
    case pdfAdded(URL)
    case pdfRemoved(URL)
    case indexModified(URL)
    case rootChanged   // library folder moved/renamed out from under us
}
```

Knows nothing about `Paper`, `AppState`, or any other Papyro type.

### 3.2 `ExternalChangeCoordinator` (new)

Subscribes to `FileSystemWatcher`. Owns the self-write guard. Translates FS events into AppState mutations. See §4 for the per-event flows.

The self-write guard is a short-lived `Set<URL>` (TTL ~1 s). `IndexService` and `ImportCoordinator` call `coordinator.willWrite(url)` before writing; the coordinator drops any inbound FS event whose path is in the set.

### 3.3 `PendingResolutionService` (new)

Thin. No persistence.

```swift
func pendingPapers() -> [Paper]    // papers.filter { !$0.metadataResolved }
func resolveAll() async            // drain with concurrency cap = 3
```

`resolveAll` runs each pending paper through the existing pipeline that drag-and-drop import already uses (`TextExtractor` → `IdentifierParser` → `MetadataProvider` chain → `NoteGenerator` → `SymlinkService.rebuildFor`). On per-item failure, the paper stays pending and `lastResolutionError` is updated; the drain continues.

### 3.4 UI additions

- **Pending banner** in `MainView`, visible only when `pendingPapers.count > 0`. Shows "N papers need metadata" with a "Resolve" button. Button is disabled while a drain is in progress.
- **⌘O** in `DetailView`: opens the selected paper's PDF in the default app (`NSWorkspace.open`).
- **⌘⌫** in `PaperListView`: confirm sheet → `NSWorkspace.recycle` → index/symlink cleanup. The note file in `notes/` is **not** deleted (notes are user-owned per PRD §3.3).

### 3.5 Schema change

`Paper` / index JSON gains one optional field:

```swift
var lastResolutionError: String?
```

Backwards-compatible (optional, decoded permissively). Lets the UI show *why* a paper is stuck without persisting a full retry log.

## 4. Data flows

### Flow A — External PDF appears in `papers/`

```
FSEventStream fires
  → FileSystemWatcher debounces 500 ms, emits .pdfAdded(url)
  → ExternalChangeCoordinator: drop if in self-write guard
  → handlePDFAdded(url):
      • id = identifier-from-filename (reuse existing logic; falls back to slug)
      • If index already contains id → ignore (idempotent)
      • Build minimal Paper: id, pdf_path, pdf_filename, date_added=now,
        status=.toRead, metadata_resolved=false, metadata_source=.pending
      • IndexService.write(paper)            ← guarded
      • SymlinkService.rebuildFor(paper)     ← only by-status, by-date-added
                                               (no by-author / by-topic until resolved)
      • AppState.papers.append(paper)        ← on @MainActor
      • Text extraction and note generation are deferred until resolution
  → Banner count updates
```

### Flow B — External PDF deleted

```
.pdfRemoved(url) after debounce
  → handlePDFRemoved(url):
      • Look up paper by pdf_path
      • IndexService.delete(paper)            ← guarded
      • SymlinkService.removeAllFor(paper)
      • AppState.papers.removeAll { $0.id == paper.id }
      • Note file in notes/ left alone
```

### Flow C — External `index/*.json` edit

```
.indexModified(url) after debounce
  → Drop if in self-write guard
  → IndexService.reload(url) → updated Paper or nil on parse failure
  → On nil: log error, leave in-memory copy authoritative
  → On success: AppState replaces existing entry; SymlinkService.rebuildFor(paper)
                (topics/projects may have changed)
```

### Flow D — User drains pending

```
PendingResolutionService.resolveAll():
  for paper in pendingPapers (max 3 concurrent):
    • TextExtractor.extract(paper.pdfURL)
    • IdentifierParser.parse(text)
    • MetadataProvider.fetch(identifiers)
    • Success:
        - merge metadata into Paper
        - metadata_resolved = true
        - lastResolutionError = nil
        - IndexService.write (guarded)
        - NoteGenerator.generate(paper)
        - SymlinkService.rebuildFor(paper)   ← now full set incl. by-author, by-topic
        - AppState updates
    • Failure:
        - lastResolutionError = error.localizedDescription
        - paper stays pending
        - drain continues
  → Show summary: "Resolved X of N. Y still pending."
```

### Flow E — App launch

```
LibraryManager.load():
  ... existing index load ...
  → Start FileSystemWatcher
  → ExternalChangeCoordinator.reconcile():
       • Walk papers/ — any PDF on disk not in index? → handlePDFAdded
       • Any index entry whose pdf_path is missing on disk? → handlePDFRemoved
     (Catches everything that happened while the app was closed.)
  → If pendingPapers.count > 0: PendingResolutionService.resolveAll()
```

Reconcile-on-launch is the unsung hero: even if FSEvents misses something (sleep, crash, network volume hiccup), the next launch corrects it. The watcher is an optimization, not a correctness requirement.

## 5. Error handling

| Failure | Behavior |
|---|---|
| FSEventStream fails to start | Report via existing user-facing error reporter (commit 6c00d1e), continue without live sync. Banner: "Live sync unavailable — restart to retry." |
| PDF appears with no parseable identifier | Index entry created with `id = filename slug`, stays pending. User can rename or edit metadata manually. |
| Resolution fetch fails (network, 404, server down) | Paper stays `metadata_resolved=false`, `lastResolutionError` set, banner count unchanged. No retry storm. |
| Index file corrupt JSON | `IndexService.reload` returns nil, log error, in-memory copy stays authoritative. Don't crash, don't wipe. |
| External delete races with app's own write | Self-write guard suppresses the FS event; if missed, reconcile-on-launch fixes it. |
| Drain in progress, user clicks "Resolve" again | Button disabled while `resolveAll` is running. |
| Cmd+⌫ delete | Confirm sheet → `NSWorkspace.recycle` → index/symlink cleanup. Note file untouched. |
| Library folder moved/renamed externally | `kFSEventStreamEventFlagRootChanged` → tear down watcher, banner: "Library folder moved — relocate in Settings." |

## 6. Edge cases worth naming

1. **Library on iCloud Drive / network volume.** FSEvents may be laggy. Reconcile-on-launch is the safety net.
2. **Same PDF imported twice from different paths.** `handlePDFAdded` checks index by `id`; second one is ignored. The duplicate file on disk is left alone (don't auto-delete user files).
3. **Agent rewrites a `.json` index file with missing required fields.** Decoder fails → log, ignore the change, in-memory version stays authoritative.
4. **FSEvent storm during a 500-file batch.** Watcher debounces 500 ms; coordinator processes serially on a background queue; AppState updates batched per debounce cycle.
5. **Notes directory edits.** Explicitly **not** watched. Obsidian owns it.

## 7. Testing

**Unit**

- `IdentifierParser` (already exists; add coverage for filename-only path used by watcher).
- `PendingResolutionService.resolveAll` with mock providers: success / total failure / partial failure.
- `Paper` decode with the new optional `lastResolutionError` field — back-compat with M5-era index files.

**Service-level (real FS in temp dir)**

- `FileSystemWatcher` debounces a burst of N writes into one event.
- `ExternalChangeCoordinator.reconcile` from a known starting state (PDF on disk, no index entry → entry appears; index entry, no PDF → entry removed).
- Self-write guard: write a file via `IndexService` → assert no event delivered to coordinator.
- Add → modify → delete cycle end-to-end.

**Manual smoke (documented for the implementation phase)**

- Drop a PDF into `papers/2024/` from Finder while app is open → appears in list as pending within ~1 s.
- Delete same PDF in Finder → disappears from list.
- Quit app, drop PDF, relaunch → reconcile picks it up.
- Click Resolve with translation server unreachable → all stay pending, error visible in detail panel.
- Cmd+⌫ on selected paper → confirm → file in Trash, index entry gone, note file still present.

## 8. Risks

| Risk | Mitigation |
|---|---|
| FSEventStream subtle behavior differences across macOS versions / volume types | Reconcile-on-launch makes the watcher non-load-bearing for correctness. |
| Self-write guard misses an event due to a write taking >1 s | Reconcile-on-launch covers it; worst case is a stale list until next launch. |
| Drain blocks UI on a large pending pile | Drain is `async` with concurrency cap; UI shows progress. If it becomes painful, move off launch path in a follow-up. |
| Schema change to `Paper` breaks older index files | New field is optional; decoder is permissive; covered by unit test. |

## 9. Out of scope, with reasons

- **Background periodic retry / reachability monitoring.** YAGNI until dogfooding shows the manual button is annoying.
- **Watching `notes/` or `.cache/`.** Notes are user-owned per PRD §3.3; cache is rebuildable noise.
- **Generic "error handling polish" pass.** User-facing error reporting just landed (commit 6c00d1e). Hardening should follow real friction, not speculation.
- **Generic "edge cases" sweep.** Same reasoning. The edge cases listed in §6 are the ones that fall directly out of the watcher/queue work.
