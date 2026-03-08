---
status: planned
created: 2026-02-18
updated: 2026-03-08
epic: platform
relates: [1edb, 8ae6, 8c5c, 8166]
---

# Audit LiveView usage — convert read-only pages to controllers

# Audit LiveView usage — convert read-only pages to controllers

## Problem

Every page in gallformers is a LiveView, including read-only display pages. This causes:

1. **WebSocket fragility** — all `phx-*` bindings become inert when the socket dies (tab idle 5-10 min). Modals can't be dismissed, buttons stop working, forms fail silently.
2. **Memory pressure** — long-lived process per open tab. Browse pages hold 670KB-1MB of tree data per process.
3. **Double mount** — every page load does HTTP render + WebSocket connect, even for static content.

## What we did (branch: liveview-to-controllers)

### Reconnection fix (landed on main)
Added `visibilitychange` listener to force immediate WebSocket reconnection when a backgrounded tab regains focus. Fixes the dead-socket problem for all LiveView pages.

### Hook extraction
Extracted 11 inline hooks from app.js into individual files in `assets/js/hooks/`. Pure refactor — app.js went from 714 lines to 95 lines. Benefits both LiveView and controller pages.

### Converted 5 pages to controllers
These pages are genuinely static content with zero or trivial interactivity:

| Page | Route | Events | Notes |
|------|-------|--------|-------|
| Privacy | /privacy | 0 | Pure static |
| Filter Guide | /filterguide | 0 | Pure static (loads filter field data) |
| Articles index | /articles | handle_params | Tag filtering via URL params — clean conversion |
| Article detail | /articles/:slug | 0 | Loads by slug, 404 handling |
| About | /about | 1 (easter egg) | Toggle converted to JS.toggle — no WebSocket needed |

### Keys reverted
Initially converted Keys index to controller, then reverted. Keys is a growing feature (matter 85c0) that will need image galleries and interactivity — converting now means converting back later.

## Phase 2 findings — open questions

The original plan proposed converting pages with "client-side filtering" (genus, section, browse, search) to controllers, potentially using Alpine.js or hand-rolled JS. Implementation revealed concerns that need more investigation:

### JS bloat concern
Every page with server-side interactivity would require rewriting Elixir logic in JavaScript:
- **Genus/Section** — search filters and sort comparators duplicate domain knowledge (how to sort species names, which fields to search, common name fallbacks)
- **Place** — range_map hook uses `pushEvent('navigate_to_place')` which requires a LiveView. Converting means modifying a shared hook to detect controller vs LiveView context.
- **Browse pages** — tree expand/collapse, search filtering on 670KB-1MB of data
- **Gall/Host detail** — 11-13 events each. Source modals, pagination, font size toggling all interact with data.

### Reconnection fix changes the calculus
The `visibilitychange` listener addresses the dead-socket UX problem for all LiveView pages. The remaining reasons to convert (memory, double mount) are optimization concerns that may or may not matter at current scale.

### Open questions
- Is the JS duplication cost acceptable for the memory/performance gains?
- Are there hybrid approaches (e.g., LiveView with reduced assigns, lazy loading) that address memory without full conversion?
- Does Alpine.js or a similar lightweight framework change the equation for pages like genus/section?
- What does the actual memory pressure look like in production — is it a real problem or theoretical?

## Pages not yet decided

| Page | Current interactivity | Conversion concern |
|------|----------------------|-------------------|
| Keys index + detail | Static list (growing) | Will need galleries, interactivity |
| Genus/Section | Search + sort | Duplicates domain logic in JS |
| Place | Range map navigation | Hook needs pushEvent |
| Gall/Host detail | Modals, pagination, galleries | 11-13 events, data interaction |
| Browse (galls/hosts/places) | Tree data, search, filtering | 670KB-1MB data per process |
| Home, Search | Debounced DB search | Genuinely interactive |
| ID tool | Complex filter logic | Stays LiveView (no question) |
| All admin pages | Forms, validation, PubSub | Stay LiveView (no question) |

## Status

Phase 1 complete. Phase 2 approach undecided — needs more investigation.

