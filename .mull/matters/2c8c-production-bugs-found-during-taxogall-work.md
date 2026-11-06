---
status: raw
created: 2026-10-27
updated: 2026-11-05
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


## Found by the design-system inventory (2026-11-05)

- `live/admin/gall_live/edit.ex:349` calls `put_flash(:warning, …)`; `flash_group` renders only `:info` and `:error`, so the message never shows.
- `admin/images_component.ex:98`: a component-scoped flash with `auto_dismiss` and `phx-target={@myself}`; the AutoDismiss hook's `pushEvent` goes to the parent LiveView, so the flash hides in the browser and is never cleared on the server.
- Details: `docs/design-system/inventory/actions-and-feedback.md` (design-system branch).

- `.input` error text uses `text-error` (and wrapper classes `fieldset`/`label`), none defined in `assets/css` (DaisyUI leftovers): error text is probably not red, only the icon (`core_components.ex:332`). Not yet checked in a browser. Details: `docs/design-system/inventory/forms.md`.
- The places browse tree builds leaves with `rank: nil` (`places.ex:521`) and `tree_components.ex:120` calls `taxon_name` with the default rank, so place names are probably rendered in italics. Details: `docs/design-system/inventory/domain-and-media.md`.
- `vocabulary_live.ex:512` renders `<.header>` while also passing `page_title` to the admin layout: two h1s reading "Vocabulary".


## Found 2026-11-05 (Host and Source inventory, design-system branch)

- **Canonical is ignored site-wide:** `root.html.heex` emits the canonical URL as `<meta name="canonical" content=…>`, which search engines ignore. It should be `<link rel="canonical" href=…>`.
- **Source page shows no retraction:** a retracted Source's Facts stay listed with a bare "retracted" mark, but their Galls drop out of "Connected Galls", so the two sections disagree.
- **Unsupported Facts are public on the Source page,** though they are hidden everywhere else.
- **Host page:** Galls recorded on the plant's genus never appear on its species' pages; a variety's breadcrumb omits its species; the old `/host/:id?source=` deep link is silently ignored.


## SECURITY: stored HTML/script injection through Markdown (found 2026-11-05)

`Gallformers.Markdown.render/1` runs Earmark, which passes raw HTML through, and pages print the result with `Phoenix.HTML.raw/1`. The Gall page's Source descriptions (`gall_live.ex` ~704 and ~790, the same on `main` at 693/779) render a block-level `<script>` unchanged (checked by the gall-page inventory). Anyone who can edit or import a Source description (curators, and the import pipeline's text taken from documents) can run script on public pages.

Check every other `Markdown.render` caller (articles, glossary, notes …). The fix is to sanitize the rendered HTML to an allowlist (keeping the glossary links), or strip raw HTML before Earmark. Some content may intentionally use HTML (`<details>`, which the renderer's comment mentions), so decide what to allow. This affects production.


### Markdown HTML: an accepted risk (Jeff, 2026-11-05)

Allowing HTML in Markdown was a deliberate decision: only admins write the text, and HTML gives flexibility. Re-checked on taxogall, and it still holds. Everything that reaches `Gallformers.Markdown` raw is admin-written:
- legacy citations (frozen, migrated from the old admin);
- Gallformers notes (curator text, stored through the note package, `Sources.store_note/5`);
- articles.

Document text from the import pipeline (Docling) does not go through it.

Two conditions to keep in mind:
1. If a page ever renders imported document text (quotes, excerpts, Source-page document items) through `Markdown.render`, the premise breaks; escape it there.
2. The CSP is report-only (`Plugs.ContentSecurityPolicy`). Enforcing it (nonce `script-src`) would block an injected `<script>` as a cheap backstop.

Not a bug to fix now.

