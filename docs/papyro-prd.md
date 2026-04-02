# Product Requirements Document: Papyro

**A lightweight, local-first macOS reference manager**

Version: 0.1 (MVP)
Last updated: April 2026
Status: Draft

---

## 1. Overview

### 1.1 What is this?

Papyro is a native macOS app for managing academic papers and research PDFs. Instead of locking your files into a proprietary database (like Zotero, Mendeley, or Papers), Papyro stores everything in a regular folder on your Mac. You drag in a PDF, Papyro figures out what it is (title, authors, journal, year), and organises it into clean folder structures you can browse in Finder, query with AI agents, or work with in Obsidian.

Think of it as a smart filing cabinet for research — not a reading app, not a citation tool, just fast, focused curation.

### 1.2 Core philosophy

- **Local-first, folder-based.** Your papers live in a normal folder tree. No database lock-in. You can move, rename, or delete files outside the app and it adapts.
- **Metadata, not reading.** Papyro does not include a PDF viewer. It focuses entirely on knowing *what* a paper is, where it lives, and how it relates to your work. You open papers in Preview, Skim, or your reader of choice.
- **Agent-friendly by default.** The on-disk layout (structured JSON indexes, cached text, symlink views) is designed so that AI coding agents — like Claude Code — can operate on your library without any special integration. The app doesn't need to "support" agents; it just needs to keep the filesystem legible.
- **Native and light.** Built in Swift/SwiftUI. Targets roughly 50 MB of RAM in normal use. No Electron, no web views.

### 1.3 Licence and distribution

Open-source (licence MIT). Distributed via GitHub releases. Not on the Mac App Store for v1 (avoids sandboxing constraints around filesystem access and symlinks).

---

## 2. Target user

The primary user for v1 is the author: a technically comfortable researcher who reads widely, works across multiple projects, uses Obsidian for notes, and often runs AI agents (e.g., Claude Code) against their paper collection. The app is built for personal use first, opened up for the community.

Broader audience (post-MVP): academics and graduate students who are computer-literate but not developers. This means the app must be usable without terminal commands, even though the initial user is comfortable with them.

---

## 3. User workflows

### 3.1 Add a paper (primary flow)

1. User drags one or more PDFs into the Papyro window (or onto the Dock icon).
2. For each PDF, Papyro immediately:
   a. Copies (or moves — user preference) the file into the library's `papers/` directory, filed by year.
   b. Extracts text from the first few pages using macOS's built-in PDFKit.
   c. Scans the extracted text for identifiers: DOI, arXiv ID, PMID, ISBN.
3. If an identifier is found, Papyro queries the remote Zotero translation-server (hosted on the user's VPS) to fetch structured metadata: title, authors, abstract, journal, publication date, etc.
4. If no identifier is found, Papyro falls back to a title-based search against CrossRef or Semantic Scholar.
5. If no metadata is returned at all, the paper is added with a status of "Unresolved" and the user can manually enter or correct metadata later.
6. The metadata is written to a JSON index file and a human-readable Markdown summary.
7. Symlinks are created (or updated) in every applicable view folder (by-topic, by-project, by-status, etc.).

**Offline scenario:** If the translation-server is unreachable, the paper is still imported into the folder structure and placed in a local queue. Metadata is fetched automatically next time the server is reachable.

### 3.2 Organise papers into views

Papyro offers multiple ways to see the same collection of papers. Crucially, these are not just UI filters — they are real symlinked folders on disk, so Finder and AI agents can navigate them too.

**Built-in view types (MVP):**

| View | Folder path | Organised by | Example |
|---|---|---|---|
| By project | `.symlinks/by-project/` | User-defined projects | `phd-thesis/`, `side-project/` |
| By topic | `.symlinks/by-topic/` | User-defined tags | `neural-plasticity/`, `methodology/` |
| By status | `.symlinks/by-status/` | Reading status | `to-read/`, `reading/`, `archived/` |
| By year | `papers/` (physical) | Publication year | `2024/`, `2023/` |
| By author | `.symlinks/by-author/` | First author surname | `smith/`, `chen/` |
| By date added | `.symlinks/by-date-added/` | Month added to library | `2026-04/`, `2026-03/` |

**How it works in the app:**

- The main window shows papers in a list or grid. A sidebar lets you switch between views (similar to Finder's sidebar).
- Within any view, you can drag papers into project or topic folders, or right-click to assign them.
- A single paper can appear in multiple views simultaneously (e.g., in both the "phd-thesis" project and the "neural-plasticity" topic). This is the key advantage of symlinks: one physical file, many organisational contexts.

**How it works for agents:**

- An agent working on a specific project can simply `ls ~/ResearchLibrary/.symlinks/by-project/phd-thesis/` to get every relevant paper.
- An agent can read the JSON index to get structured metadata without parsing PDFs.
- The `.cache/text/` directory provides pre-extracted text for quick full-text searches.

### 3.3 Notes and Obsidian integration

Papyro keeps a Markdown note for each paper inside the library itself, in a `notes/` directory. These are living documents — the user edits them in Obsidian, agents can read and write them, and Papyro doesn't need to manage synchronisation because there is only ever one copy of each file.

**How it works:**

1. When a paper is imported, Papyro generates a Markdown note from a user-configurable template and saves it to `notes/` (e.g., `notes/10.1038_s41586-024-07998-6.md`). The template populates frontmatter and basic metadata sections; a "Notes" section is left empty for the user.
2. To make these notes visible in Obsidian, the user symlinks the `notes/` directory into their Obsidian vault. This is a one-time setup. Papyro provides a GUI for creating and managing this symlink (see Section 3.6).
3. From that point on, the notes appear natively in Obsidian. Edits made in Obsidian are edits to the real file — there is no export, no sync, no conflict. Agents operating in the library folder read and write the same files.

**What notes contain:**

A note starts as a template-generated scaffold, but grows over time as the user and agents add to it:

- **Frontmatter** (YAML): title, authors, year, DOI, tags, status — structured for Obsidian Dataview queries.
- **Abstract**: populated at import from metadata.
- **User notes**: free-form section where the user writes annotations like "uses the same fMRI protocol I need for Chapter 3" or "contradicts Chen 2021 — check methods."
- **Agent-generated sections** (optional): an agent might append a citation analysis, a summary, or extracted key findings. Because the file is just Markdown in a known location, any agent can do this without special integration.

**Example template (user-editable, stored in `templates/note.md`):**

```markdown
---
title: "{{title}}"
authors: [[{{authors}}]]
year: {{year}}
doi: "{{doi}}"
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

**Why this is better than export:**

- No copies, no sync conflicts — one file, two access paths (Papyro's folder and the Obsidian vault).
- Agents can read your annotations and write their analysis into the same note.
- Obsidian indexes the notes automatically, making them searchable and linkable like any other vault content.
- No "Export to Obsidian" button needed — the notes are always already there.

### 3.4 Edit metadata manually

For papers where automatic lookup fails (or returns incorrect data), the user can:

- Click on any metadata field in the detail panel to edit it inline.
- Retry the metadata lookup with a corrected DOI or title.
- Merge metadata from multiple sources (e.g., correct the title from CrossRef but keep the abstract from Semantic Scholar).

### 3.5 Search and filter

- **Full-text search** across paper titles, authors, abstracts, and tags.
- **Filter by** any view dimension: project, topic, status, year, author.
- Filters are combinable (e.g., "papers in the phd-thesis project that are tagged neural-plasticity and still marked to-read").

### 3.6 Symlink management (GUI)

Creating symlinks manually in the terminal is error-prone — wrong paths, broken links, forgetting to update after moving a vault. Papyro provides a simple GUI for managing symlinks so that non-technical users (and busy technical users) don't have to think about it.

**Accessible from:** Preferences → Integrations, or via the menu bar (File → Manage Linked Folders).

**What the GUI shows:**

A list of active symlinks that Papyro has created outside the library, each showing:

- **Source:** The directory inside the library being linked (e.g., `notes/`, `.symlinks/by-project/phd-thesis/`).
- **Destination:** Where the symlink points to (e.g., `~/ObsidianVault/Papyro Notes/`).
- **Status indicator:** A green dot if the symlink is healthy, a yellow warning if the destination directory doesn't exist, a red indicator if the link is broken.

**Actions:**

- **"Link folder…"** button: Opens a two-step picker — first select a source folder from the library (presented as a clean list: "Notes", "All project views", a specific project, etc.), then choose a destination in Finder. Papyro creates the symlink and records it.
- **"Unlink"** on any row: Removes the symlink (the source data is untouched). Asks for confirmation.
- **"Repair"** on broken links: If a destination has moved, lets the user re-point the symlink.
- **Health check on launch:** Papyro silently verifies all managed symlinks when it starts. If any are broken, it shows a non-intrusive notification with a link to the management panel.

**Common setups the GUI makes easy:**

- Link `notes/` into an Obsidian vault — every paper note appears in Obsidian.
- Link a specific project folder (e.g., `.symlinks/by-project/phd-thesis/`) into a working directory so an agent can access just those papers.
- Link `.cache/text/` into a location where a search tool or agent expects plain text files.

---

## 4. On-disk layout (detailed specification)

The library root is a user-chosen directory (default: `~/ResearchLibrary/`). Everything inside it is human-readable and stable enough to be version-controlled with Git if desired.

```
~/ResearchLibrary/
│
├── papers/                          # Physical storage (canonical location of all PDFs)
│   ├── 2024/
│   │   ├── 10.1038_s41586-024-07998-6.pdf
│   │   └── 2401.12345.pdf           # arXiv papers use arXiv ID
│   └── 2023/
│       └── 10.1126_science.abcdefg.pdf
│
├── notes/                           # Markdown notes (one per paper, symlinked into Obsidian)
│   ├── 10.1038_s41586-024-07998-6.md
│   ├── 2401.12345.md
│   └── 10.1126_science.abcdefg.md
│
├── index/                           # Structured metadata (one JSON per paper + summary MDs)
│   ├── 2024/
│   │   ├── 10.1038_s41586-024-07998-6.json
│   │   └── 2401.12345.json
│   └── _all.json                    # Combined index: array of all papers (for fast agent queries)
│
├── .symlinks/                       # View layer (symlinks only — fully rebuildable)
│   ├── by-project/
│   │   └── phd-thesis/
│   │       └── attention.pdf → ../../papers/2024/10.1038_s41586-024-07998-6.pdf
│   ├── by-topic/
│   ├── by-status/
│   │   ├── to-read/
│   │   ├── reading/
│   │   └── archived/
│   ├── by-author/
│   └── by-date-added/
│
├── .cache/                          # Derived data (rebuildable, disposable)
│   ├── text/                        # PDFKit-extracted text from first N pages
│   │   └── 10.1038_s41586-024-07998-6_p1-5.txt
│   ├── markdown/                    # Deep parses generated by external agents (not by the app)
│   └── images/                      # Extracted figures (by external tools like MinerU)
│
├── .claude/                         # Claude Code context (optional, user-managed)
│   ├── CLAUDE.md
│   └── skills/
│
├── templates/                       # User-editable templates
│   └── note.md                      # Template for per-paper Markdown notes
│
└── config.json                      # App configuration (server URL, preferences, managed symlinks)
```

### 4.1 Naming conventions

- PDFs are named by their canonical identifier: `{doi_with_slashes_replaced}.pdf` or `{arxiv_id}.pdf`.
- If no identifier exists, a sanitised title slug is used: `some-paper-title.pdf`.
- JSON metadata files share the same base name as the PDF.
- Markdown notes share the same base name as the PDF (e.g., `10.1038_s41586-024-07998-6.md`).

### 4.2 The combined index (`_all.json`)

A single flat JSON array containing every paper's metadata. This exists purely for fast querying by agents. The app regenerates it whenever metadata changes. Structure:

```json
[
  {
    "id": "10.1038/s41586-024-07998-6",
    "title": "...",
    "authors": ["..."],
    "year": 2024,
    "journal": "Nature",
    "doi": "10.1038/s41586-024-07998-6",
    "abstract": "...",
    "pdf_path": "papers/2024/10.1038_s41586-024-07998-6.pdf",
    "note_path": "notes/10.1038_s41586-024-07998-6.md",
    "topics": ["neural-plasticity"],
    "projects": ["phd-thesis"],
    "status": "reading",
    "date_added": "2026-04-01",
    "has_cached_text": true
  }
]
```

### 4.3 Symlink rebuild

The entire `.symlinks/` directory is derived state. The app can blow it away and reconstruct it from `index/` at any time. This means:

- Users (or agents) can safely delete symlinks without losing data.
- If symlinks get out of sync, a "Rebuild views" command restores them.

---

## 5. Architecture

### 5.1 Technology

| Component | Choice | Rationale |
|---|---|---|
| Language | Swift | Native performance, small footprint, direct macOS API access |
| UI framework | SwiftUI | Modern macOS-native UI with minimal boilerplate |
| PDF text extraction | Apple PDFKit | Built-in, low memory, no external dependencies |
| Metadata lookup | Zotero translation-server (remote) | Battle-tested, supports DOI/ISBN/PMID/arXiv, runs on user's VPS |
| Fallback metadata | CrossRef API, Semantic Scholar API | Free, no authentication required for basic queries |
| Data storage | JSON files on disk | Human-readable, agent-friendly, no database dependency |
| Configuration | JSON config file in library root | Portable, version-controllable |

### 5.2 Translation-server integration

The app talks to the Zotero translation-server over HTTP. The server URL is user-configured (e.g., `https://translate.myserver.com`).

**Endpoints used:**

- `POST /search` — Send identifiers (DOI, arXiv ID, etc.), receive structured metadata.
- `POST /web` — Send a URL (e.g., a journal article page), receive metadata extracted from the page.
- `POST /export?format=bibtex` — Convert Zotero-format items to BibTeX (for citation export).
- `POST /import` — Parse BibTeX/RIS input into structured items (for importing existing libraries).

**Security considerations:**

- The VPS endpoint should be protected (e.g., HTTPS + API key or HTTP Basic Auth).
- The app stores credentials in the macOS Keychain, not in the config file.

### 5.3 Filesystem watcher

The app monitors the library folder using macOS `FSEvents` for changes made outside the app (e.g., by an agent dropping a PDF into `papers/`, or a user deleting a file in Finder). When changes are detected:

- New PDFs trigger the metadata-fetch pipeline.
- Deleted PDFs trigger index and symlink cleanup.
- Modified JSON index files are reloaded.

---

## 6. Feature specification (MVP)

### 6.1 Must-have (v0.1)

| # | Feature | Description |
|---|---|---|
| 1 | **Drag-and-drop import** | Drop PDFs into the window or Dock icon. Files are copied into `papers/` by year. |
| 2 | **Automatic metadata fetch** | Extract DOI/arXiv ID from PDF text → query translation-server → populate metadata. |
| 3 | **Fallback metadata search** | If no identifier found, search CrossRef/Semantic Scholar by extracted title. |
| 4 | **Offline queue** | If translation-server is unreachable, queue lookups and retry when connectivity returns. |
| 5 | **Manual metadata editing** | Inline editing of all metadata fields. Retry lookup with corrected identifiers. |
| 6 | **Symlink-based views** | by-project, by-topic, by-status, by-author, by-date-added. Rebuilt from index data. |
| 7 | **Project and topic management** | Create, rename, delete projects and topics. Assign papers via drag-and-drop or context menu. |
| 8 | **Reading status tracking** | Mark papers as to-read, reading, or archived. |
| 9 | **Search and filter** | Full-text search over metadata. Combine filters across view dimensions. |
| 10 | **Per-paper Markdown notes** | Auto-generated from template at import time, stored in `notes/`. Editable by user (in Obsidian or any editor) and agents. |
| 11 | **Symlink management GUI** | Create, inspect, repair, and remove symlinks from library folders to external destinations (e.g., Obsidian vault). Health check on launch. |
| 12 | **Text cache** | PDFKit extraction of first 5 pages, stored in `.cache/text/`. |
| 13 | **Combined index** | Auto-generated `_all.json` for agent consumption. |
| 14 | **Filesystem watcher** | Detect and react to external changes (new/deleted files, modified indexes). |
| 15 | **Preferences** | Library path, translation-server URL, note template, import behaviour (copy vs. move). |

### 6.2 Nice-to-have (v0.2+)

| # | Feature | Description |
|---|---|---|
| 15 | **BibTeX import/export** | Import from `.bib` files; export selected papers as BibTeX. |
| 16 | **Duplicate detection** | Warn when importing a PDF that matches an existing DOI or title. |
| 17 | **Apple Shortcuts support** | Expose actions (add paper, create symlink) to Shortcuts for automation. |
| 18 | **Quick Look preview** | Show a small PDF thumbnail in the detail panel (without being a full reader). |
| 19 | **Custom symlink views** | Let users define additional view dimensions beyond the built-in ones. |
| 20 | **Batch re-organise** | Select multiple papers and assign project/topic/status in bulk. |
| 21 | **Browser extension / URL handler** | Accept a URL → download PDF → import (useful for grabbing papers from journal sites). |
| 22 | **Git-friendly diffs** | Format JSON indexes with stable key ordering and pretty-printing for clean diffs. |

---

## 7. UI design direction

### 7.1 Layout

A three-column layout, similar to Apple Mail or Finder in column view:

1. **Sidebar (left):** View switcher (by-project, by-topic, by-status, etc.) with expandable folders underneath each view. Also includes a "Smart filters" section and an "All papers" entry.
2. **Paper list (centre):** Scrollable list of papers matching the current view/filter. Each row shows: title, first author, year, journal, reading status badge. Sortable by any column.
3. **Detail panel (right):** Full metadata for the selected paper. All fields editable. Action buttons: "Open PDF" (launches in default app), "Open Note" (opens the Markdown note in the default editor), "Reveal in Finder".

### 7.2 Visual style

- Native macOS appearance. Respect system light/dark mode.
- Minimal chrome. Use standard SwiftUI components (sidebars, lists, inspectors) rather than custom UI.
- The app should feel like a natural part of macOS, not a ported web app.

### 7.3 Interaction patterns

- **Drag-and-drop** is the primary import method (onto the window, the Dock icon, or a specific project/topic in the sidebar).
- **Right-click context menus** for assigning projects, topics, and status.
- **Keyboard shortcuts** for common actions: search (⌘F), open note (⌘E), open PDF (⌘O), quick status toggle (1/2/3 for to-read/reading/archived).
- **Inline editing** for metadata: click a field in the detail panel to edit it.

---

## 8. Data model

Each paper is represented by a JSON object with the following fields:

| Field | Type | Required | Source |
|---|---|---|---|
| `id` | string | Yes | DOI, arXiv ID, or generated slug |
| `title` | string | Yes | Translation-server or manual |
| `authors` | array of strings | Yes | Translation-server or manual |
| `year` | integer | No | Translation-server or manual |
| `journal` | string | No | Translation-server |
| `doi` | string | No | Extracted from PDF or translation-server |
| `arxiv_id` | string | No | Extracted from PDF |
| `pmid` | string | No | Extracted from PDF |
| `isbn` | string | No | Extracted from PDF |
| `abstract` | string | No | Translation-server or CrossRef |
| `url` | string | No | Translation-server |
| `pdf_path` | string | Yes | Relative path from library root |
| `pdf_filename` | string | Yes | Display-friendly filename |
| `topics` | array of strings | No | User-assigned |
| `projects` | array of strings | No | User-assigned |
| `status` | enum: to-read, reading, archived | Yes | Default: to-read |
| `date_added` | ISO 8601 date | Yes | Auto-generated |
| `date_modified` | ISO 8601 date | Yes | Auto-updated |
| `metadata_source` | enum: translation-server, crossref, semantic-scholar, manual | Yes | Tracked for debugging |
| `metadata_resolved` | boolean | Yes | False if metadata fetch failed/pending |
| `note_path` | string | Yes | Relative path to the paper's Markdown note in `notes/` |

---

## 9. Performance targets

| Metric | Target | Rationale |
|---|---|---|
| Memory usage (idle, 500-paper library) | ≤ 50 MB | Lightweight enough to leave running all day |
| Memory usage (idle, 5000-paper library) | ≤ 120 MB | Scales reasonably for large collections |
| App launch to interactive | < 1.5 seconds | Faster than Zotero or Mendeley |
| Import 1 PDF (with metadata fetch) | < 3 seconds | Mostly network-bound; UI should be instant |
| Symlink rebuild (500 papers) | < 1 second | Filesystem operations only |
| Search across 5000 papers | < 200 ms | In-memory index, no database roundtrip |

---

## 10. Risks and open questions

### 10.1 Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Translation-server goes down or is slow | Medium | Offline queue + fallback to CrossRef/Semantic Scholar |
| Symlinks confuse Spotlight or other tools | Low | `.symlinks/` is a hidden directory; can add `.metadata_never_index` |
| Very large libraries (10k+ papers) strain in-memory index | Low | Lazy loading, on-demand index segments by year |
| macOS sandbox restrictions if ever moving to App Store | High (future) | Defer App Store distribution; use bookmark-based file access if needed later |
| External changes cause race conditions with app state | Medium | Debounce FSEvents, reload index before writes, last-write-wins |
| Managed symlinks break when destinations move (e.g., Obsidian vault relocated) | Medium | Health check on launch, repair flow in symlink management GUI |

### 10.2 Open questions

1. **PDF filename collisions:** If two papers share a DOI prefix pattern, how do we disambiguate? Current approach (replace `/` with `_`) should be unique for DOIs but edge cases may exist.
2. **Multi-device sync:** Out of scope for MVP, but the folder-based design is compatible with Syncthing, iCloud Drive, or Git. Should `config.json` include per-device overrides?
3. **Translation-server authentication:** What auth method will the VPS use? The app should support at least API key and HTTP Basic Auth.
4. **Symlink permissions:** Creating symlinks outside the library root requires write access to the destination. If the Obsidian vault is on an external drive or a restricted location, the app may need to request access via macOS security-scoped bookmarks.
5. **Handling retractions/corrections:** If a paper is retracted, should the app surface this? Could query Retraction Watch API in a future version.
6. **Note regeneration:** If the user changes the template, should existing notes be regenerated? Risky if the user has added manual content. Safest approach: only regenerate the frontmatter/metadata sections, leave user-written sections untouched.

---

## 11. MVP milestones

| Phase | Scope | Goal |
|---|---|---|
| **M1: Skeleton** | App shell, library picker, config file, folder structure creation | Can set up a library and see the empty three-column layout |
| **M2: Import pipeline** | Drag-and-drop → file copy → PDFKit extraction → identifier regex → translation-server query → JSON write | Can add a paper and see its metadata |
| **M3: Views and organisation** | Sidebar with view types, symlink generation, project/topic CRUD, drag-to-assign | Can organise papers into projects and topics and see them on disk |
| **M4: Search and filter** | In-memory search index, combined filters, sort options | Can find papers quickly in a growing library |
| **M5: Notes and symlink management** | Note generation at import, template editor, symlink management GUI with health checks | Notes appear in Obsidian vault via symlink; managed entirely from the app |
| **M6: Polish** | Keyboard shortcuts, offline queue, filesystem watcher, error handling, edge cases | Ready for daily use |
