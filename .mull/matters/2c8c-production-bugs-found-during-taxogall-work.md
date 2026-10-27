---
status: raw
created: 2026-10-27
updated: 2026-10-27
epic: platform
relates: [50ff]
---

# Production bugs found during taxogall work

Bugs in the code running in production (main) found while building taxogall. Each gets its own small fix branch off main (Jeff pushes and opens the PR); the same fix goes onto `taxogall` when it applies there. Taxogall-only problems don't belong here.

## Open

### 1. Sources admin list crashes on species-source events
- **Where:** `lib/gallformers_web/live/admin/source_live/index.ex` (main).
- **Bug:** the page subscribes to the `"sources"` PubSub topic. `Sources.create_species_source/1` and `update_species_source/2` broadcast `{:species_source_created | :species_source_updated, _}` on that topic, but the page's `handle_info` only matches `:source_created/updated/deleted`. Creating or updating a species–Source link while anyone has the Sources list open crashes their page.
- **Also seen as:** a timing-dependent failure of `SourceLive.FormTest` "index view requires the exact source title before deletion" when another test creates a species-source link in parallel.
- **Fix:** handle (or ignore) the species-source events in the index page; test it.
- **taxogall:** not affected — the new Sources page doesn't subscribe.
- Found 2026-10-27.

### 2. e2e browser suite broken (Playwright version mismatch)
- **Where:** main's e2e suite (`make e2e`).
- **Bug:** #593's lock refresh let npm `playwright` float to 1.62.0, which `playwright_ex` 0.5 / `phoenix_test_playwright` 0.13 can't parse — every `assert_has` raises.
- **Fix (done on taxogall, 2b3dd12d):** upgrade `phoenix_test_playwright` → 0.19, `playwright_ex` → 0.15, `phoenix_test` → 0.13.1 (lock change limited to these three), npm `playwright` → `^1.64.1`; e2e timeout 10 s; `E2ECase.visit/2` waits for the LiveView to connect. Main still has the broken setup; it lands with the taxogall merge, or as its own branch if e2e on main is needed sooner.
- Found 2026-10-27.

## Fixed or awaiting merge

### 3. Content image upload and reorder crash the article and key forms
- **Bug:** `ContentImageUpload` and `SortableImages` hooks sent their events with `pushEvent` to the page, but the handlers live in `ContentImageManager` (a LiveComponent). Uploading or reordering content images on the article / key admin forms crashed the page (`FunctionClauseError` in `ArticleLive.Form`, reproduced in a test).
- **Fix:** `pushEventTo(this.el, …)` — branch `fix-content-image-upload-events`, commit 631fdd7e (awaiting push / PR); same change on taxogall.
- Found 2026-10-27.

### 4. Live navigation bypassed the superadmin and operator role checks
- **Bug:** `/admin/users`, `/admin/filter-terms` (superadmin) and `/admin/ops` (operator) relied only on pipeline plugs and shared LiveView's default live session with the other admin screens, so an ordinary admin could live-navigate into them.
- **Fix:** role-restricted `live_session`s with `on_mount` role checks — branch `fix-admin-live-session-auth`, commit 096fc5da, **merged as #596**; same fix on taxogall (1b9b2a0e).
- Found 2026-10-27.
