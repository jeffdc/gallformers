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

1. **WebSocket fragility** — all `phx-*` bindings become inert when the socket dies (tab idle 5-10 min). Modals can't be dismissed, buttons stop working, forms fail silently. Discovered via source detail modal on public gall page. This affects EVERY LiveView page.
2. **Memory pressure** — long-lived process per open tab. Browse pages hold 670KB-1MB of tree data per process. Contributed to March 2-3 OOM incidents.
3. **Double mount** — every page load does HTTP render + WebSocket connect, even for static content.
4. **Flash of stale state** (matter 8166) — components depending on client data show wrong defaults during static render.

## Key finding: 95% of public interactivity is client-side state

Full audit of all 61 LiveViews revealed most public page interactivity is manipulating already-loaded data — no database queries during user interaction. Only the ID tool has genuinely complex server-driven interactivity.

## Architecture decision: two phases

### Phase 1: Convert zero-JS pages to controllers

These pages need NO JavaScript at all. Phoenix JS commands (JS.show, JS.hide, JS.toggle_class) work on controller-rendered pages without a WebSocket — verified in LiveView source code (dead view mode).

| Page | Current events | Why zero JS |
|------|---------------|-------------|
| Gall detail (/gall/:id) | 11 | Modal show/hide, font size, expand = all JS commands |
| Host detail (/host/:id) | 13 | Same pattern + sort (can use JS commands or HTML links) |
| Place detail (/place/:code) | 1 | Just navigation = `<a href>` links |
| About (/about) | 1 | Easter egg toggle = JS.toggle |
| Privacy (/privacy) | 0 | Static content |
| Filter Guide (/filterguide) | 0 | Static content |
| Articles index (/articles) | 0 | Tag filtering via URL params |
| Article detail (/articles/:slug) | 0 | Static content |
| Keys index (/keys) | 0 | Static list |
| Genus detail (/genus/:name) | 0 | Static display |
| Section detail (/section/:name) | 0 | Static display |

This phase eliminates the modal bug class entirely for the highest-traffic pages, removes per-visitor server processes, and requires zero new JS. Same HEEx templates, same components, same DX.

Detail page interactivity that currently uses handle_event (source modal, pagination, font size) converts to pure JS commands. Pagination becomes URL params (?page=2).

### Phase 2: Evaluate approach for pages with client-side filtering

These pages manipulate already-loaded data (tree toggle, sort, search). They need some JS but the question is how much structure.

| Page | Key interaction | DB queries during interaction |
|------|----------------|------|
| Browse galls (/galls) | Tree expand/collapse, search filter | 1 (undescribed lazy-load) |
| Browse hosts (/hosts) | Tree expand/collapse, search filter | 0 |
| Browse places (/places) | Tree expand/collapse, search filter | 0 |
| Family (/family/:name) | Sort + search | 0 |
| Key detail (/keys/:slug) | Couplet tree navigation, path tracking | 0 |
| Home (/) | Typeahead search | 2 (DB search, debounced) |
| Global search (/globalsearch) | Debounced search, keyboard nav, sort | 2 (DB search) |
| Analytics (/analytics) | Range selector, pagination | 1 (range change reloads) |

Options under consideration:
- **Hand-rolled JS modules** (~660 lines in assets/js/modules/). No deps. No organizational conventions.
- **Alpine.js** (vendored single file, 15KB, zero npm). Reactive attributes in templates — closest DX to LiveView. Common in Phoenix community for exactly this use case.
- **Keep as LiveViews with reconnection fix** — for pages where LiveView complexity is justified.

Decision deferred until Phase 1 is complete and we can evaluate the actual gaps in practice. Browse pages and search may be fine as LiveViews with the reconnection fix.

## Reconnection fix for pages that stay as LiveViews

For admin pages and any public pages that remain LiveView (ID tool, possibly browse/search):

Add `visibilitychange` listener in app.js to force immediate reconnection when tab regains focus. Currently the client waits up to 30s for the next heartbeat cycle to detect a dead socket.

```javascript
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) liveSocket.connect()
})
```

This is a small, independent change that helps all LiveView pages. Should land early.

## Pages that stay as LiveView

| Page | Why |
|------|-----|
| ID tool (/id) | 29 events, compound filter logic, URL sync — genuinely complex server-driven interactivity |
| All admin pages | Forms, validation, PubSub, file uploads, concurrent edit detection |

## JS strategy: extract hooks first (unchanged from prior plan)

Before any conversion, extract 11 inline hooks from app.js into assets/js/hooks/. This is cleanup that benefits both LiveView and controller pages. After extraction, app.js becomes ~30 lines.

Hook extraction list: Tabs, ImageGallery, Typeahead, CopyToClipboard, AutoDismiss, InputEvent, ScrollToCouplet, AdminNav, RegionScope, RegionPrompt, IndeterminateCheckbox.

## Sequencing

1. Add visibilitychange reconnection listener (immediate, helps everything)
2. Extract inline hooks from app.js (cleanup, no behavior change)
3. Convert zero-JS pages to controllers (Phase 1 — biggest win, zero new JS)
4. Evaluate Phase 2 approach based on experience with Phase 1

## Controller infrastructure readiness

Already in place: browser pipeline, root layout shared with LiveView, component imports wired for controllers, API controllers, auth, error pages. Adding a controller page is: create controller + HTML module, add route, write HEEx template using existing components.

## Investigation artifacts

- WebSocket vulnerability: verified in LiveView JS source — JS.push guards on isConnected(), all other JS commands (show/hide/toggle/class) are pure DOM ops that work without WebSocket
- LiveView dead view mode: controller pages still process phx-click with JS command values via bindTopLevelEvents({dead: true})
- Full interactivity audit: 61 LiveViews, 83 handle_event callbacks on public pages, only 10 hit DB
- Request log analysis: 75% bot traffic (42K req/day), all hitting LiveView pages
- Tree memory: galls ~1 MB, hosts ~670 KB, places ~760 KB per process
- March 2-3 OOM incidents documented
- JS framework evaluation: htmx rejected (round-trips for client-side ops). Alpine.js and Stimulus reconsidered now that conflict-with-LiveView-DOM-patching objection doesn't apply to controller pages. Decision deferred to Phase 2.


## Additional findings

- **Zero LiveComponents on public pages.** All 5 LiveComponents (ExclusionDrillDown, CountryDrillDown, ContentImageManager, InatImportComponent, ReclassifyLive) are admin-only. Phase 1 conversions require no LiveComponent migration — every public component is a function component that works identically in controller templates.
- **Land gall-range-curation branch first.** It touches gall_live.ex and host_live.ex with range display changes. Converting those files to controllers is a structural rewrite, so merge the feature branch first to avoid resolving conflicts against the new controller structure.

