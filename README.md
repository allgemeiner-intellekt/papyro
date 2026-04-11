# Papyro

A lightweight, local-first macOS reference manager for academic papers.

Papyro keeps your papers in a regular folder on disk — no proprietary database, no lock-in. Drag a PDF in; Papyro identifies it, pulls metadata from CrossRef / Semantic Scholar / your Zotero translation-server, and files it into a folder structure you can browse in Finder, query with AI agents, or work with in Obsidian.

**Not a reading app.** Papyro deliberately has no PDF viewer — open papers in Preview, Skim, or whatever you prefer. It focuses on *knowing what a paper is*, where it lives, and how it relates to your work.

## Status

Personal pre-release (v0.1.0). Built for the author's own research workflow; shared publicly in case it's useful to others. Expect sharp edges.

## Requirements

- macOS 15.0 (Sequoia) or later
- Xcode 16 to build from source
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation (`brew install xcodegen`)

## Build and run

```bash
git clone https://github.com/allgemeiner-intellekt/papyro.git
cd papyro
xcodegen generate
open Papyro.xcodeproj
```

Then build and run from Xcode (⌘R). On first launch, Papyro asks you to choose a folder for your library (default: `~/ResearchLibrary`).

## Features

- Drag-and-drop PDF import with automatic metadata extraction (DOI, arXiv, PMID, ISBN)
- Metadata from CrossRef, Semantic Scholar, and optionally a self-hosted Zotero translation-server
- Multiple organisation views (by project, topic, status, year, author) — all as real symlinked folders
- Live sync with filesystem changes (papers added, removed, or edited outside the app)
- Full-text search across title, authors, and extracted content
- Per-paper notes in Markdown, stored next to the PDF

## Screenshots

*Coming soon.*

## Why the name

"Papyro" from *papyrus* — the Greek word for the writing material that carried the first generation of scholarly text. Also: the app's icon is a Bodoni "P".

## License

MIT. See [LICENSE](LICENSE).
