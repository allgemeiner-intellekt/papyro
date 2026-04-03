# M3: Views and Organisation — Design Spec

**Date:** 2026-04-03
**Status:** Approved
**Milestone:** M3
**Depends on:** M1 (Skeleton), M2 (Import Pipeline)

---

## Overview

M3 adds project-based organisation, a functional sidebar, a redesigned paper list with sortable columns, and a symlink layer that keeps the filesystem in sync for agents and Finder browsing.

**Key design decisions (departures from PRD):**

- **Projects replace both "projects" and "topics"** from the PRD. No tags or topic system — projects are the sole organisational unit.
- **Projects are flat** (no nesting/subprojects).
- **Sidebar categories replaced** — instead of 7 parallel view types (by-project, by-topic, by-author, by-year, etc.), the sidebar has: All Papers, Projects, and Status filters. Author/year/journal are sort/group dimensions on the list, not sidebar items.
- **Symlinks are project-only** — `.symlinks/` contains one folder per project (no `by-project/`, `by-topic/`, `by-author/` hierarchy).
- **Inbox is a special project** — every imported paper starts in Inbox; auto-removed when assigned to another project.
- **Paper list uses stacked rows** — title full-width on row 1, sortable metadata columns on row 2.

---

## 1. Data Model

### 1.1 Project struct

```swift
struct Project: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String        // Display name, e.g. "PhD Thesis"
    var slug: String        // Disk folder name, e.g. "phd-thesis"
    var isInbox: Bool       // true only for the built-in Inbox project
    var dateCreated: Date
}
```

Persisted as an array in `projects.json` at the library root. Inbox is always the first entry.

### 1.2 Paper model changes

- Replace `projects: [String]` with `projectIDs: [UUID]` — references `Project.id`.
- Remove `topics: [String]` — no longer used.
- `status: ReadingStatus` unchanged (`.toRead`, `.reading`, `.archived`).

### 1.3 Inbox rules

- Every newly imported paper gets the Inbox project ID added to `projectIDs`.
- When a paper is assigned to any non-Inbox project, Inbox is automatically removed from `projectIDs`.
- When a paper is removed from all non-Inbox projects, Inbox is automatically added back to `projectIDs`.
- Inbox cannot be renamed, deleted, or manually assigned/unassigned.

---

## 2. Sidebar

### 2.1 Structure

```
📚 All Papers
─── Projects ──────── [+]
📥 Inbox              (3)
📁 PhD Thesis         (23)
📁 Side Project       (11)
📁 Journal Club       (5)
─── Status ────────────
🔵 To Read            (12)
🟡 Reading            (4)
🟢 Archived           (87)
```

**Sections (top to bottom):**

| Section | Items | Behaviour |
|---|---|---|
| Fixed | All Papers | Shows every paper in the library |
| Projects | Inbox (pinned at top), then user-created projects alphabetically | Click to filter list. "+" button at section header to create. Right-click → rename, delete. Count badge. |
| Status | To Read, Reading, Archived | Click to filter by status. Count badge. |

### 2.2 Interactions

- Click a project → paper list shows only papers in that project.
- Click a status filter → applies as secondary filter on top of the current view.
  - Viewing "All Papers" + click "To Read" → all unread papers.
  - Viewing "PhD Thesis" + click "To Read" → unread papers in PhD Thesis.
  - Click active status filter again → deselects (shows all statuses).
- Drag paper rows from the list onto a sidebar project → assign.
- Right-click project → Rename, Delete (not available for Inbox).
- "+" button or File → New Project → name prompt, auto-generate slug.

---

## 3. Paper List (Centre Panel)

### 3.1 Layout

Stacked two-row design per paper:

- **Row 1:** Title (full width, bold, 13px, never truncated)
- **Row 2:** Metadata values aligned to sortable column headers

Column headers sit above the list. Click a header to toggle ascending/descending sort. Active sort column is visually highlighted.

### 3.2 Columns

**Default visible:**

| Column | Source | Sort behaviour |
|---|---|---|
| Authors | First author surname + "et al." | Alphabetical by first author surname |
| Year | Publication year | Numeric |
| Journal | Journal or venue name | Alphabetical |
| Status | Reading status badge | Ordered: to-read → reading → archived |
| Date Added | Date paper was imported | Chronological |

**Available (toggled via right-click on column header bar):**

| Column | Source |
|---|---|
| DOI | Paper identifier |
| arXiv ID | Paper identifier |
| Projects | Comma-separated project names |
| Metadata Source | translation-server / crossref / semantic-scholar / manual |
| Date Modified | Last metadata update |
| PMID | Paper identifier |
| ISBN | Paper identifier |

### 3.3 Column configuration

- Right-click the column header bar to show a context menu with checkmarks for each column.
- Columns are resizable by dragging column borders.
- Column visibility and sort state persisted in `config.json`.

### 3.4 Interactions

- Drag PDFs onto the list to import (existing M2 behaviour).
- Drag paper rows onto sidebar projects to assign.
- Multi-select with ⌘-click or Shift-click, then drag to assign multiple papers.
- Right-click paper row → context menu:
  - Add to Project → submenu with checkmarks for current assignments
  - Set Status → To Read / Reading / Archived
  - Open PDF
  - Reveal in Finder
  - Delete from Library

---

## 4. Detail Panel (Right Panel)

Extends the existing M2 detail panel with:

### 4.1 Projects section

- Shows project badges/chips for each project the paper belongs to.
- Each chip has an "×" button to remove the paper from that project.
- "Add to Project" button opens a dropdown of available projects.
- Inbox chip is displayed but cannot be manually removed (auto-managed).

### 4.2 Status control

- The status field becomes a clickable dropdown (To Read / Reading / Archived) instead of a read-only label.

All other detail panel functionality (metadata fields, abstract, action buttons, edit mode) remains unchanged from M2.

---

## 5. Symlink Service

### 5.1 Responsibilities

New `SymlinkService` handles all `.symlinks/` operations.

### 5.2 Operations

| Method | Description |
|---|---|
| `addLink(paper, project)` | Create symlink in `.symlinks/{slug}/` pointing to paper's PDF |
| `removeLink(paper, project)` | Remove paper's symlink from `.symlinks/{slug}/` |
| `createProjectFolder(project)` | Create `.symlinks/{slug}/` directory |
| `renameProjectFolder(oldSlug, newSlug)` | Rename directory |
| `deleteProjectFolder(project)` | Remove `.symlinks/{slug}/` directory |
| `rebuildAll(projects, papers)` | Delete `.symlinks/`, recreate all project folders and symlinks from current state |

### 5.3 Symlink format

- Target: relative path, e.g. `../../papers/2024_vaswani_attention.pdf`
- Link name: same as the PDF filename
- Relative paths keep the library portable if the root directory is moved.

### 5.4 Disk structure

```
.symlinks/
  inbox/
    2024_vaswani_attention.pdf → ../../papers/2024_vaswani_attention.pdf
  phd-thesis/
    2024_vaswani_attention.pdf → ../../papers/2024_vaswani_attention.pdf
  side-project/
    2023_devlin_bert.pdf → ../../papers/2023_devlin_bert.pdf
```

---

## 6. Project Service

### 6.1 Responsibilities

New `ProjectService` manages `projects.json` and coordinates with `SymlinkService` and `IndexService`.

### 6.2 Operations

| Method | Description |
|---|---|
| `createProject(name)` | Generate slug, append to `projects.json`, call `SymlinkService.createProjectFolder` |
| `renameProject(id, newName)` | Update name + slug in `projects.json`, call `SymlinkService.renameProjectFolder` |
| `deleteProject(id)` | Remove from `projects.json`, remove project ID from all papers, move orphaned papers to Inbox, call `SymlinkService.deleteProjectFolder` |
| `assignPaper(paper, project)` | Add project ID to paper's `projectIDs`, auto-remove Inbox if non-Inbox, persist paper, call `SymlinkService.addLink` |
| `unassignPaper(paper, project)` | Remove project ID from paper's `projectIDs`, auto-add Inbox if no projects left, persist paper, call `SymlinkService.removeLink` |

### 6.3 Slug generation

- Lowercase the name, replace spaces with hyphens, strip non-alphanumeric characters (except hyphens).
- If slug already exists, append `-2`, `-3`, etc.

### 6.4 Initialization

- At library setup: create `projects.json` with a single Inbox entry, create `.symlinks/inbox/` folder.
- On app launch: load `projects.json`, make project list available to sidebar.

### 6.5 Integration with ImportCoordinator

After a paper is imported and persisted, `ImportCoordinator` calls `ProjectService.assignPaper(paper, inbox)` to place it in Inbox and create the Inbox symlink.

---

## 7. Menu Bar & Keyboard Shortcuts

### 7.1 New menu items

| Menu | Item | Shortcut | Action |
|---|---|---|---|
| File | New Project | ⌘⇧N | Create project (name prompt) |
| File | Rebuild Symlinks | — | Full symlink rebuild from current state |
| Edit | Rename Project | ⏎ (when project selected in sidebar) | Inline rename |
| Edit | Delete Project | ⌘⌫ (when project selected) | Delete with confirmation alert |

### 7.2 Paper shortcuts

| Shortcut | Action |
|---|---|
| 1 / 2 / 3 | Set status: To Read / Reading / Archived |
| ⌘⌫ | Remove from current project (or delete from library if viewing All Papers) |

These extend the existing PRD shortcuts (⌘F search, ⌘O open PDF, ⌘E open note).

---

## 8. Migration

Existing papers from M2 have `projects: [String]` and `topics: [String]`. On first launch after M3 is deployed:

1. Create `projects.json` with Inbox.
2. For each paper: set `projectIDs` to `[inbox.id]`, clear legacy `projects` and `topics` fields.
3. Rebuild all symlinks.

This is a one-time migration. Papers imported before M3 had no meaningful project/topic assignments (the fields existed but were never populated from the UI), so mapping everything to Inbox is correct.
