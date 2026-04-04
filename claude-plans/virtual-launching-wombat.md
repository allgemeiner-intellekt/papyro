# Plan: Sidebar UI Polish — Collapse, Plus Button, Click-to-Cancel

## Context
The sidebar's "Projects" section header has three UX issues visible in the screenshots:
1. The collapse chevron only appears on hover (macOS default `Section` behavior), which feels inconsistent
2. The "+" button shifts position when the chevron appears/disappears
3. The "add project" text field can only be cancelled with Escape (`onExitCommand`), not by clicking elsewhere

## Changes

**File:** `Papyro/Views/SidebarView.swift`

### 1. Remove default collapsible behavior, make section always expanded
Replace `Section { ... } header: { ... }` (lines 25-74) with a non-collapsible structure using a plain `Section` with a fixed header that has no disclosure indicator. Use `Section(header:)` with `.collapsible(false)` or restructure to avoid the default disclosure chevron entirely.

Approach: Keep `Section` but apply the SwiftUI modifier to disable collapsibility. If that's not available on the target macOS version, restructure to use a `Text` header + manual grouping so macOS doesn't inject its hover chevron.

### 2. Fix "+" button position
Since removing the collapse chevron removes the layout shift, the "+" button will stay in a fixed position in the header `HStack`. No additional changes needed beyond fix #1.

### 3. Add click-elsewhere-to-cancel for new project text field
Add `.onLossOfFocus` behavior to the `TextField` at lines 48-61. Use `@FocusState` to track focus on the text field, and watch for focus loss to cancel adding:

- Add `@FocusState private var isNewProjectFieldFocused: Bool` 
- Apply `.focused($isNewProjectFieldFocused)` to the TextField
- Set `isNewProjectFieldFocused = true` when `isAddingProject` becomes true (via `.onChange`)
- Add `.onChange(of: isNewProjectFieldFocused)` — when focus is lost and field is empty or user clicked away, cancel the add operation

## Verification
1. Build: `xcodebuild -project Papyro.xcodeproj -scheme Papyro -configuration Debug build`
2. Open app and verify:
   - "Projects" section header shows no collapse chevron (not on hover, not ever)
   - "+" button stays fixed in position
   - Click "+" to start adding a project, then click elsewhere in the sidebar — the text field should dismiss
   - Adding a project by typing + Enter still works
   - Escape to cancel still works
