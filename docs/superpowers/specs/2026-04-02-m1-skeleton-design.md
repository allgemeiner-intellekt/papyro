# M1: Skeleton — Technical Spec

**Milestone:** M1 (Skeleton)
**Goal:** App shell with library picker, config file, folder structure, and empty three-column layout.
**PRD reference:** `docs/papyro-prd.md`, Milestone M1

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Minimum macOS version | 15 Sequoia | MVP is personal-use; simplest code path, latest SwiftUI APIs |
| First-run experience | Welcome screen with default path + change option | Respects "you own your files" philosophy |
| Config scope for M1 | Library path only | YAGNI; extend in later milestones |
| UI interactivity | Navigable shell (sidebar selection works, no real data) | Proves navigation architecture without filesystem coupling |
| Project structure | Single target, flat file groups | Standard for small-to-medium SwiftUI apps |
| Dependencies | Zero | Nothing beyond SwiftUI needed for M1 |
| Architecture approach | Model-first | Define models + service, then build UI on top; M2+ slots in cleanly |

## 1. Data Model

### LibraryConfig

Codable struct, persisted as `config.json` at the library root.

```swift
struct LibraryConfig: Codable {
    let version: Int          // schema version, starts at 1
    var libraryPath: String   // absolute path to library root
}
```

### SidebarCategory

Enum representing the sidebar view switcher items.

```swift
enum SidebarCategory: String, CaseIterable, Identifiable {
    case all            // "All Papers"
    case byProject      // "By Project"
    case byTopic        // "By Topic"
    case byAuthor       // "By Author"
    case byYear         // "By Year"
    case recentlyAdded  // "Recently Added"
    case unread         // "Unread"
}
```

### AppState

Observable class holding in-memory app state.

```swift
@Observable
class AppState {
    var libraryConfig: LibraryConfig?        // nil until library is set up
    var selectedCategory: SidebarCategory = .all
    var isOnboarding: Bool = true            // true on first launch
}
```

## 2. Service Layer

### LibraryManager

Single service for M1. Handles library setup and config persistence.

**Methods:**

- **`setupLibrary(at path: URL)`** — Creates the folder structure at the chosen path, writes `config.json`, saves the path to UserDefaults, flips `AppState.isOnboarding` to false.
- **`loadLibrary(from path: URL)`** — Reads `config.json`, populates `AppState`.
- **`detectExistingLibrary()`** — Checks UserDefaults for a previously saved library path. If found and valid, loads it automatically (skips welcome screen). If invalid, returns nil.

**Folder structure created by `setupLibrary`:**

```
~/ResearchLibrary/
├── config.json
├── papers/          # where PDFs will live (M2+)
├── metadata/        # paper metadata JSONs (M2+)
├── notes/           # Obsidian-compatible markdown (M4+)
└── views/           # symlink trees (M3+)
```

Folders are empty in M1 but created upfront so the structure is established. `LibraryManager` is injected into the SwiftUI environment so views can access it.

## 3. Views & Navigation

### Navigation Flow

```
Launch → isOnboarding? → yes → WelcomeView → setupLibrary → MainView
                       → no  → detectExisting → MainView
                                (invalid path) → WelcomeView
```

### PapyroApp (entry point)

- `@main` struct, creates `AppState` and `LibraryManager`
- On launch: checks `AppState.isOnboarding`
- If `true` → show `WelcomeView`
- If `false` → call `LibraryManager.detectExistingLibrary()`, then show `MainView`

### WelcomeView

- Displays app name and brief tagline
- Shows default path (`~/ResearchLibrary/`) in a text field
- "Choose Folder..." button opens `NSOpenPanel` (folder picker)
- "Create Library" button calls `LibraryManager.setupLibrary()`, transitions to `MainView`

### MainView (three-column layout)

Uses `NavigationSplitView` with three columns:

- **Sidebar (leading):** `SidebarView` — list of `SidebarCategory` cases. Selection bound to `AppState.selectedCategory`.
- **Content (centre):** `PaperListView` — shows selected category name and "No papers yet" placeholder. Becomes the paper list in M2.
- **Detail (trailing):** `DetailView` — shows "Select a paper to view details" placeholder. Becomes the metadata/PDF panel in M2.

Column resizing uses SwiftUI's default `NavigationSplitView` behavior. No custom constraints in M1.

### SidebarView

- Renders a `List` with `SidebarRow` for each `SidebarCategory`
- `SidebarRow` is a private subview: SF Symbol icon + label
- Icons: `books.vertical` (all), `folder` (by-project), `tag` (by-topic), `person.2` (by-author), `calendar` (by-year), `clock` (recently added), `book.closed` (unread)

## 4. Persistence & App Lifecycle

### Config file (`config.json`)

- Written to library root by `LibraryManager.setupLibrary()`
- Read by `LibraryManager.loadLibrary()` on subsequent launches
- Standard `JSONEncoder`/`JSONDecoder` with `.prettyPrinted` output

### Library path bookmark (UserDefaults)

- Key: `libraryPath`
- Stored after library setup
- Read on launch by `detectExistingLibrary()`
- If stored path is invalid (folder deleted/moved), fall back to `WelcomeView`

### Error handling

- Folder creation failure → alert with error message, stay on `WelcomeView`
- Config read failure (corrupt JSON) → alert, offer to re-create library
- No crash-on-error patterns — graceful fallback to `WelcomeView` for any startup issue

### No database

No Core Data, no SQLite for M1. Everything is file-based. Database added only if needed in later milestones (e.g., search index in M5).

## 5. Project Structure

```
Papyro/
├── PapyroApp.swift              # @main entry point, AppState setup
├── Models/
│   ├── LibraryConfig.swift      # LibraryConfig struct
│   ├── SidebarCategory.swift    # SidebarCategory enum
│   └── AppState.swift           # Observable app state
├── Services/
│   └── LibraryManager.swift     # Library setup, config I/O, path detection
├── Views/
│   ├── WelcomeView.swift        # First-run welcome screen
│   ├── MainView.swift           # NavigationSplitView three-column layout
│   ├── SidebarView.swift        # Sidebar list with SidebarRow
│   ├── PaperListView.swift      # Centre column (placeholder in M1)
│   └── DetailView.swift         # Right column (placeholder in M1)
└── Assets.xcassets/             # App icon, accent color
```

11 source files. Single Xcode target. Zero third-party dependencies.

## 6. Testing Strategy

### Unit tests (3 tests)

1. `LibraryConfig` encodes and decodes correctly to/from JSON
2. `LibraryManager.setupLibrary()` creates expected folder structure and valid `config.json`
3. `LibraryManager.detectExistingLibrary()` returns nil when no path is stored; returns config when valid path exists

### Manual verification checklist

- [ ] Launch app → welcome screen appears with default path
- [ ] Change path via folder picker → path updates in text field
- [ ] Click "Create Library" → folders appear on disk, transitions to three-column layout
- [ ] Sidebar categories are selectable, centre column updates with category name
- [ ] Quit and relaunch → skips welcome, goes straight to main view
- [ ] Delete library folder, relaunch → falls back to welcome screen

No automated UI tests in M1. Added when UI stabilizes with real interactions (M3+).

## Out of Scope for M1

Everything not listed above is deferred to later milestones:

- PDF import and file management (M2)
- Metadata resolution via translation-server (M2)
- Symlink view layer (M3)
- Obsidian notes integration (M4)
- Search (M5)
- Filesystem watcher (M6)
