# M5: Notes & Symlink Management — Design Spec

**Date:** 2026-04-05
**Milestone:** M5
**Status:** Approved

---

## Overview

M5 adds two features to Papyro:

1. **Per-paper Markdown notes** — auto-generated from a user-editable template at import time, with on-demand creation for papers that don't yet have a note.
2. **Symlink management GUI** — a general-purpose interface for creating, inspecting, repairing, and removing symlinks from any library subfolder to any external destination (e.g., linking `notes/` into an Obsidian vault).

Both features are housed in a new **Preferences window** that also surfaces existing settings (library path, translation server URL, import behavior).

---

## Decisions

| Question | Decision |
|----------|----------|
| Handle existing papers without notes? | On-demand only — "Create Note" button in detail panel. No backfill. |
| Symlink GUI scope? | General-purpose: any library subfolder → any external destination. |
| Where does symlink GUI live? | Preferences window → Integrations tab, plus `File → Manage Linked Folders…` menu shortcut. |
| Template system? | User-editable `templates/note.md` with `{{placeholder}}` substitution. Not an in-app editor. |
| Note display in detail panel? | No preview. Just "Create Note" or "Open Note" button in actions section. |
| Architecture? | Note generation in ImportCoordinator pipeline + small NoteGenerator helper. Symlink management as standalone service + UI. |

---

## 1. Data Model Changes

### Paper model

`notePath: String?` already exists on `Paper`. M5 starts populating it with the relative path to the note file (e.g., `"notes/10.1038_s41586-024-07998-6.md"`).

### Note naming convention

Follows the PRD: uses the paper's canonical ID as the filename.
- DOI-based: `notes/{doi_with_slashes_replaced}.md` (e.g., `notes/10.1038_s41586-024-07998-6.md`)
- arXiv-based: `notes/{arxiv_id}.md` (e.g., `notes/2401.12345.md`)
- Fallback: sanitized title slug (e.g., `notes/some-paper-title.md`)

### Managed symlinks in config.json

A new `managedSymlinks` array in `LibraryConfig`:

```json
{
  "managedSymlinks": [
    {
      "id": "uuid",
      "sourceRelativePath": "notes",
      "destinationPath": "/Users/me/ObsidianVault/Papyro Notes",
      "label": "Notes → Obsidian",
      "createdAt": "2026-04-05T12:00:00Z"
    }
  ]
}
```

Each entry represents a symlink created *at* the destination path that *points to* the source folder inside the library. For example, `~/ObsidianVault/Papyro Notes` is a symlink pointing to `~/ResearchLibrary/notes/`. The app tracks these so it can verify health on launch and offer repair/unlink actions.

---

## 2. Note Template System

### Default template

Stored at `templates/note.md` in the library root. Created on library initialization if missing. The app reads this file at note generation time.

```markdown
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

```

### Supported placeholders

| Placeholder | Value |
|-------------|-------|
| `{{title}}` | Paper title |
| `{{authors_formatted}}` | Comma-separated author names |
| `{{authors_linked}}` | Obsidian `[[wiki-link]]` format per author |
| `{{year}}` | Publication year |
| `{{journal}}` | Journal name |
| `{{doi}}` | DOI string |
| `{{arxiv_id}}` | arXiv ID |
| `{{abstract}}` | Paper abstract |
| `{{pdf_filename}}` | Display-friendly PDF filename |
| `{{status}}` | Reading status (to-read, reading, archived) |
| `{{date_added}}` | ISO 8601 date added |

Missing values render as empty strings (no leftover `{{placeholders}}` in output).

### User editing

Users edit `templates/note.md` in any text editor. They can also use the symlink management GUI to link the `templates/` folder into their Obsidian vault for easy editing there.

---

## 3. Note Generation Pipeline

### NoteGenerator helper

A small struct with two responsibilities:

1. **Load template** — read `templates/note.md` from the library root. If the file doesn't exist, use the hardcoded default and write it to disk so the user can find and edit it.
2. **Expand placeholders** — takes a `Paper` and the template string, replaces all `{{placeholder}}` tokens via simple string replacement.

### Integration into ImportCoordinator

Note generation is a new step at the end of the import pipeline, after metadata resolution and index writing:

1. Call `NoteGenerator.generate(for: paper, libraryRoot: url)`
2. Write the expanded template to `notes/{canonical-id}.md`
3. Set `paper.notePath` to the relative path
4. Save the updated paper to the index

If metadata resolution fails (unresolved paper), still generate a note with whatever fields are available.

### On-demand creation

For papers imported before M5 or where the note file was deleted externally:

- Detail panel shows "Create Note" button if `paper.notePath` is nil or the file doesn't exist on disk
- Clicking it runs the same `NoteGenerator` pipeline
- Button swaps to "Open Note" once the note exists

---

## 4. Detail Panel Changes

### Actions section

Two new buttons in the existing actions section (alongside Open PDF, Reveal in Finder):

**When note doesn't exist:**
- "Create Note" button with a subtle green tint to draw attention
- Hint text: "Generates a Markdown note from your template"

**When note exists:**
- "Open Note" button (standard style, with `⌘E` shortcut hint)
- Calls `NSWorkspace.shared.open(noteURL)` to open in default `.md` handler

**Edge case:** If `paper.notePath` is set but the file was deleted externally, fall back to showing "Create Note".

### Keyboard shortcut

`⌘E` — open note for the currently selected paper. If no note exists, creates one first then opens it.

---

## 5. Preferences Window

### Window structure

Standard macOS Settings/Preferences window with a tab bar. Two tabs:

**General tab:**
- Library path (display + "Change…" button)
- Translation server URL (text field)
- Import behavior (radio: Copy files / Move files)

**Integrations tab:**
- Linked Folders section (see below)

### Menu access

- `Papyro → Settings…` (standard `⌘,` shortcut) opens to the last-used tab
- `File → Manage Linked Folders…` opens Settings directly to the Integrations tab

---

## 6. Symlink Management GUI

### Integrations tab layout

**Header:** "Linked Folders" title + subtitle explaining what symlinks do + "Link Folder…" button.

**Symlink list:** Each row shows:
- **Health indicator dot:** green (healthy), yellow (destination directory missing), red (symlink broken)
- **Label:** user-readable name (e.g., "Notes → Obsidian Vault")
- **Paths:** source relative path → destination absolute path
- **Action buttons:** "Reveal" (opens destination in Finder), "Repair" (for yellow/red), "Unlink"

### "Link Folder…" flow

Two-step process:

**Step 1 — Pick source folder:** A list showing library subfolders in a readable format:
- Notes (`notes/`)
- Templates (`templates/`)
- Text Cache (`.cache/text/`)
- Individual projects under a "Projects" header (`.symlinks/by-project/{slug}/`)

**Step 2 — Pick destination:** Native macOS `NSOpenPanel` folder picker. User selects where the symlink should point.

On confirmation, the app:
1. Creates the symlink on disk
2. Adds the entry to `managedSymlinks` in `config.json`
3. Refreshes the list

### Auto-generated label

The label is derived from the source and destination: `"{source name} → {destination folder name}"`. E.g., selecting `notes/` → `~/ObsidianVault/Papyro Notes/` produces `"Notes → Papyro Notes"`.

---

## 7. Health Check & Notifications

### Launch-time verification

On app launch, `LibraryManager` iterates through `managedSymlinks` and checks each:
- Does the symlink still exist on disk?
- Does the destination directory still exist?

Three health states:
- **Healthy (green):** symlink exists and destination is reachable
- **Destination missing (yellow):** symlink exists but destination folder was deleted or moved
- **Broken (red):** symlink itself is gone

### Notification banner

If any managed symlinks are unhealthy on launch:
- A non-intrusive banner appears at the top of the main window: *"1 linked folder needs attention"*
- Clicking the banner opens Preferences → Integrations
- Banner auto-dismisses after 10 seconds

### Repair flow

"Repair" button on a broken/warning row:
1. Opens native folder picker to select a new destination
2. Removes the old symlink (if it exists)
3. Creates a new symlink to the selected destination
4. Updates the entry in `config.json`

### Unlink flow

"Unlink" button:
1. Shows confirmation alert: *"Remove link from notes/ to ~/ObsidianVault/Papyro Notes/? The source files are not affected."*
2. On confirm: removes symlink from disk, removes entry from `config.json`

---

## 8. File Changes Summary

### New files
- `Papyro/Services/NoteGenerator.swift` — template loading and placeholder expansion
- `Papyro/Services/ManagedSymlinkService.swift` — external symlink CRUD, health checking
- `Papyro/Views/SettingsView.swift` — Preferences window with General and Integrations tabs
- `Papyro/Models/ManagedSymlink.swift` — model for tracked external symlinks

### Modified files
- `Papyro/Models/LibraryConfig.swift` — add `managedSymlinks` array
- `Papyro/Services/ImportCoordinator.swift` — add note generation step after metadata resolution
- `Papyro/Services/LibraryManager.swift` — launch-time health check, write default template on init
- `Papyro/Views/DetailView.swift` — add Create Note / Open Note buttons
- `Papyro/Views/MainView.swift` — notification banner for broken symlinks, menu bar entries
- `Papyro/PapyroApp.swift` — Settings window registration, keyboard shortcut for ⌘E

### New test files
- `PapyroTests/NoteGeneratorTests.swift`
- `PapyroTests/ManagedSymlinkServiceTests.swift`
