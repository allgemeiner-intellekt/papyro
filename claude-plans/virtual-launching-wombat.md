# Plan: Sidebar Visual Polish — Chevron, Alignment, Spacing

## Context
Using `DisclosureGroup` inside `Section` inside `List` creates three visual problems:
1. The system disclosure triangle is too small/subtle
2. The "+" button and count numbers don't share a right-edge alignment line
3. DisclosureGroup adds an extra indentation level, pushing content rightward

All three stem from the same root cause: `DisclosureGroup`'s built-in layout fighting with `Section` and `List` padding.

## Approach
Replace `Section { DisclosureGroup { ... } }` with plain `Section(header:)` using `.collapsible(false)` to suppress macOS default hover chevron, then add a **custom chevron button** in the header for manual expand/collapse. This gives full control over:
- Chevron size and style (use `chevron.right` with rotation animation)
- Right-edge alignment (chevron and "+" in the header, counts in rows — all sharing the same trailing edge)
- Indentation (no extra DisclosureGroup nesting layer)

## Changes

**File:** `Papyro/Views/SidebarView.swift`

### 1. Replace DisclosureGroup with custom collapsible sections
- Keep `@State private var isProjectsExpanded/isStatusExpanded`
- Use `Section { ... } header: { ... }.collapsible(false)` 
- In the header HStack: section title + Spacer + "+" button (Projects only) + chevron button
- Chevron: `Image(systemName: "chevron.right")` with `.rotationEffect` based on expanded state, animated
- Conditionally show section content with `if isProjectsExpanded { ... }`

### 2. Fix right-edge alignment
- The "+" and chevron sit in the section header's HStack, which shares the same trailing edge as list rows
- Counts in rows use `Spacer()` + trailing text — same alignment system
- Give the chevron a fixed small width so "+" position is stable

### 3. Eliminate excess indentation
- Removing DisclosureGroup removes its built-in indentation
- Content goes directly inside `Section`, matching standard List row padding

## Verification
1. `xcodebuild -project Papyro.xcodeproj -scheme Papyro -configuration Debug build`
2. Open app and verify:
   - Custom chevron always visible, visually prominent, animates on click
   - "+" button and count numbers share a right-edge vertical line
   - List items sit at normal indentation (no rightward drift)
   - Collapse/expand still works for both sections
   - Click-elsewhere-to-cancel still works for new project field
