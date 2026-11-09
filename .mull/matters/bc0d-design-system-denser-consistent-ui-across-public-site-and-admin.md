---
status: raw
created: 2026-11-04
updated: 2026-11-09
epic: design
relates: [f14c, 6611, 9119]
---

# Design system: denser, consistent UI across public site and admin

Jeff wants an improved (not redesigned) look across gallformers.org and the admin: less unnecessary whitespace, better information density, less awkward layout, and the new admin screens much less janky. The end product is a published design system that all future UI/UX work follows.

## Round 1 (2026-11-04): findings and direction

Artifact (private to Jeff): https://claude.ai/code/artifact/0089c292-87e3-4a67-aa5a-1fc70b8dbd97
Source: `docs/plans/design-system/` (gitignored). `python3 build.py` inlines the images into `design-direction.html`; republish that file to the same URL. `shoot.js` and `measure.js` take screenshots and measurements of the running local server through Playwright Firefox (`assets/node_modules/playwright-core`); the dev auth bypass lets them reach admin.

### Root cause found
The base `h1`–`h6` sizes, the global `a` color (Bootstrap `#0d6efd`) and every `.gf-*` class in `assets/css/app.css` sit outside Tailwind's cascade layers. Unlayered CSS beats layered CSS whatever the specificity, so Tailwind classes on those elements are ignored. Example: the admin title band `<h1 class="text-lg">` (layouts.ex ~598) renders at 40px. 87 of 126 headings and 78 links that set their own color are overridden. The fix is to move those rules into `@layer base` / `@layer components`, then review the pages that came to rely on the big sizes.

### Measured findings (1440×900)
- Sticky header 78px plus fixed footer 40px = 118px on every screen. Review steps add a 77px sticky step bar (195px, 22%). Admin content starts around 210px down: header, admin nav, title band.
- Admin sections are cards with a 69px sky-blue band holding a 28px heading. Admin Gall edit nests a card in a card.
- Table rows are 41px, 57px or 81–105px for similar lists. Some columns are empty in every row (Genus common name, synonymy Notes, Sources Kind/Updated).
- Width goes unused: Browse Galls is one narrow column; a Source's Galls fill a one-column, full-width table.
- Gall and Host pages have no `<h1>`. The title color varies by page.
- On a phone, the Gall photo comes after the traits, the map and the synonymy.
- In code: 4 card versions, 3 table routes, 4 message patterns, 4 modal variants, 6 public title patterns. 122 raw buttons. 118 color utilities. Unused width tokens and semantic text classes. No dark mode; `data-theme="light"` is hard-coded and unread.

### Proposed direction (pending Jeff's answers)
- Keep the brand: maroon, the sky header, autumn, League Spartan for brand and headings.
- Two densities from one set of tokens: Reading (public: 16px body, 36px rows) and Working (admin: 14px body, 32px rows).
- One page-header component.
- Sections are headings on a rule; cards only for separate objects.
- One table component.
- Admin form rows with labels on the left.
- One save model.
- Chips mean state.
- Sticky chrome no more than 100px; the footer is not fixed.
- Radius 4px for controls and 8px for panels; shadows only on things that float.

The mockups in the artifact cover the Gall page, admin Taxon edit (with a sidebar admin frame) and the admin Sources list.

### Open questions for Jeff
1. Source Sans 3 for text and data, with League Spartan kept for brand and headings? (Recommended: denser, with true italics for scientific names.)
2. Quoted Source text in a serif (Source Serif 4)?
3. Replace Bootstrap link blue with an ink blue from the palette? (Recommended.)
4. Unfix the footer? (Recommended.)
5. Admin navigation: a left sidebar (my lean) or a slim top bar?
6. Dark mode tokens now or later?
7. One admin save model: save as you go?

## Plan
- Round 2: put the tokens into app.css and fix the cascade layering. Build a living style guide page in the app with real components in both densities. Mock up the review flow, folding in Jeff's f14c ideas.
- Round 3: the shell (header, footer, admin layout), the Gall page, the one table component.
- Round 4: admin edit pages onto sections and form rows; the review steps.
- Publish: a design-system doc plus the style guide page; CLAUDE.md points to both.


## Decisions (Jeff, 2026-11-04)

1. Source Sans 3 for text and data; League Spartan for brand and headings. Decided.
2. Quoted Source text in Source Serif 4. Decided.
3. An ink blue for links, replacing Bootstrap blue. Decided.
4. The footer is no longer fixed. Decided.
5. Admin gets a left sidebar, plus a right rail for facts about the record (Jeff likes both in the Taxon edit mockup). Decided.
6. Dark mode is in the system now: every color is a token with light and dark values. Decided.
7. One admin save model: agreed there should be one, but which one is still open; Jeff is thinking. What bears on it:
   - Some saves write a version or an audit entry. Each save of the Gallformers note is a new dated version, and Facts are audited and replayed. Save-as-you-go would fill those histories with noise.
   - A rule that covers both: a single field saves at once, with a "Saved" note beside it. A change that writes a version, touches Facts or spans several fields collects in an "N unsaved changes · Save · Discard" bar.

## Information-rich Gall page and the map (2026-11-04)

The artifact's version 2 adds a whole-page mockup of `/gall/821` (Callirhytis quercuscornigera, agamic). The proposed page is about 1,440px long; today's is 3,262px. It shows:
- 14 Hosts as a four-column list under their own heading.
- Empty traits collapsed into one "Not recorded: …" line.
- The other generation linked beside the title.
- ID Notes pinned above the Sources; Sources run by year, one row each, and expand to the full excerpt.
- "Look further" links in place of the See Also logos.

Map: Jeff worries a small map is hard to read. He is considering a small map that opens a large map in a dialog, with full screen from there; still thinking. The mockup shows a 420px map card framed on the native range, with Enlarge opening a dialog (a "Map open" state).

Finding: the map hook frames everything it shades, introduced plantings included (`assets/js/hooks/range_map.js`: `fitToRange`, `WORLD_BOUNDS`). So a Host planted in Europe or New Zealand (Quercus rubra) pulls the map out to the whole world. Framing on the native range is what makes a small map readable, whatever size is chosen.


## Round 2 build: foundations (2026-11-04)

Jeff, 2026-11-04: "start building it." His requirements:
- Document the system fully, both the reusable styling and the reusable components, so future developers and agents can follow it and make mockups in its language. No hack job.
- New components that replace existing ones are welcome. Tell Jeff which new components are needed, since new UI patterns need his approval.
- Add no third-party dependencies unless they're needed, and remove ones that don't give real value.
- Apply the system to every page, not just the ones mocked up.

Where: branch `design-system`, in the worktree `.worktrees/design-system`, cut from taxogall after Jeff committed his work in progress. The dev server for it runs on :4001 with `PGDATABASE=gallformers_taxogall PORT=4001 mix phx.server`. The default `gallformers_dev` predates taxogall. The map data (`priv/static/data/boundaries.pmtiles`) is gitignored and was copied in.

Done, uncommitted:
- CSS is split into `assets/css/system/{tokens,fonts,base,components}.css`; the old rules moved to `assets/css/legacy.css` inside `@layer components`, with nothing to be added there. Nothing is unlayered except the vendor MapLibre CSS, so utility classes win again (the root cause from round 1).
- Tokens: the colors are semantic, light and dark, and exposed as Tailwind utilities (`text-ink`, `bg-surface`, `text-autumn-ink` …). Two densities: Reading by default, and Working via `.gf-density-working`. Semantic text sizes (`text-page`, `text-section` … `text-caption`), radius (`rounded-ctl`, `rounded-panel`), `shadow-float`, widths (`max-w-page`, `max-w-text`, `max-w-form`). Contrast is measured and meets AA everywhere. `autumn-ink` (#a0521d) was added because autumn as text was 4.0:1.
- Fonts are self-hosted under OFL: Source Sans 3 (variable, upright and italic) and Source Serif 4 (regular and italic).
- Dark mode: the tokens are defined, but the root keeps `data-theme="light"` pinned until no palette colors are left, because pages on raw Tailwind grays would break.
- Conformance ratchet: `GallformersWeb.DesignSystem.Conformance`, its test, `mix gallformers.design_system.baseline`, and `test/support/design_system_baseline.json`. The baseline is 3,432 findings in 77 files: palette 1,767, type scale 740, radius 295, legacy palette 278, hex 202, arbitrary 88, shadow 50, inline style 9, dark 3.
- Docs in `docs/design-system/`: README (rules, layout, the ratchet), foundations, components (the catalog, all **Proposed**, for Jeff's approval), patterns, content, mockups. CLAUDE.md's UI section now points to them.
- Effect of the layering fix: pages render as their templates were written. Admin title bands are compact (18px). Some public titles are now small (the Genus title is 24px); the page-header migration fixes that. A bug of my own, base headings forcing a color, was fixed: they inherit it.

Third parties: remove d3 (four modules, used only by the analytics chart) in favor of a server-rendered SVG `bar_chart`. Remove `@tailwindcss/typography` in favor of a token-based `prose`. Keep MapLibre and pmtiles, topbar (recolored), and Phosphor.

Rule for page migrations: each starts with an inventory of everything the current page shows (edit pencil, data-complete status, image info and edit buttons, range tooltip, region bar, synonym type, created and updated, the ID Notes banner …), so nothing is silently dropped. Jeff noticed items missing from the mockups.

## Page proposals (2026-11-04, for discussion)

**Home.** It's for three visitors: someone with a gall in hand, a returning naturalist, a would-be contributor. Proposed:
- The ID tool's first step on the page ("What plant is it on?" with a Host search) and a name search.
- "In season now": `gall_card`s for Galls whose Season matches this month in the visitor's region. The Season trait and region scope exist; the phenology work is in matter `439a`.
- Entry points by common Host genera (oaks, willows, goldenrods …), with counts and a photo.
- Recently added or updated Sources (the ingestion dates from `f14c`).
- The numbers as one quiet line rather than a band.
- A Gall to meet: a smaller random Gall.
- A one-line contribution invitation.

**ID.** It's the strongest page. Tweaks:
- Filters move into a left facet column with counts ("leaf 41 · stem 22").
- Six `gall_card`s across instead of four, each with a line of distinguishing traits.
- Active filters shown as chips.
- Advanced filters folded into the facets.
- Galls with no photo get a form icon instead of an empty grey box.

Larger efforts:
- (a) **"Most useful next question"**: order the facets by how evenly they split the remaining Galls, and show the best one first.
- (b) **Compare**: pick 2–4 candidates and see their traits side by side with the differences marked. ID Notes often name the confusable Galls.

**Browse.** One collection pattern for Galls, Hosts and Places.
- By Inducer: groups a beginner recognises (gall wasps, gall midges, mites, aphids, fungi …), then families as sections with genera flowing in columns, counts and a representative photo. Plain-language group names are data that may need adding.
- By Host: Host families, then genera.
- A filter, and jump-to-letter.
- Today it's one 250px column of families with expanders.

**Rank pages** (genus, family …) use the collection template:
- A header with the lineage and a summary (Galls, Hosts, Host genera, places).
- A `gall_card` grid with facets (Host genus, plant part), instead of a table with an empty Common name column.
- Children with counts at higher ranks.
- Any Gallformers or Source notes about the taxon.

Possible bug: on `/family/Cynipidae` the children table shows Hosts 0 for Cynipinae (1,349 Galls).


## Round 2, continued: components, style guide, mockups (2026-11-04)

Jeff approved the component catalog. He wants to see the home, ID, browse and rank pages before approving them, especially the home page.

**Built, with tests:**
- `Layouts.app` (site_shell), `Layouts.admin` (admin_shell).
- PageComponents: page_header, section, panel, rail.
- ActionComponents: button, menu.
- DataComponents: chip, data_table, fact_list, name_list, stat, empty_state.
- DomainComponents: gall_card, source_entry, source_quote.
- FormComponents: field, search_field, facet_group.
- FeedbackComponents: notice, dialog.
- taxon_name is reworked: `Gallformers.TaxonName.segments/1` keeps qualifiers, rank words, authorities and Unknown placeholders upright.

Wave 2 was built by four agents in parallel. One file per agent worked; the one clash was id_live.ex's private `gall_card`, now renamed `result_card`.

**Shell, now on every page:**
- A 56px public header with the `/` search shortcut (`assets/js/search_shortcut.js`), and the footer at the end of the page.
- Admin sidebar with Host ranges and `aria-current` (the AdminNav hook no longer dims links). The admin shell renders `page_title` as the page_header for pages not yet migrated.
- "Log in" / "Log out" wording.

**Style guide:** `/dev/design-system` (in `dev/gallformers_web/dev/`, dev only), with every token and built component in light and dark, plus code.

**Mockups**, with real data, at `/dev/mockups/home`, `/id` (`?h=`), `/browse` and `/genus/:name`. The ID and rank mockups filter in memory.
- **ID:** facets with counts, plus a "most useful next question" picked by an entropy × coverage score.
- **Browse:** families mapped to 15 plain-language groups. This is proposed content, because the tree has nothing above family.

Conformance baseline: 3,290 findings. `mix precommit` is clean: 3,373 tests and 188 asset tests. Nothing is committed.

**Open follow-ups:**
- A quiet icon button whose X takes the surrounding text color; on a tinted notice the ghost X shows in link blue.
- Facet rows use `min-h-row`; they may want a tighter row.
- source_entry's excerpt is plain text; Gall-page excerpts are Markdown today.
- taxon_name: names inside a parenthetical (synonyms in the host typeahead) are upright.
- Then the page migrations, each starting with an inventory of the current page; the remaining approved components (photo_viewer, range_map rework, typeahead consolidation, bar_chart, prose, save_bar once the save model is decided); dark mode switched on once palette findings reach 0; the export task for artifact mockups.


## Jeff's feedback on the mockups, round 1 (2026-11-05), and round 2

**Feedback:**
- **General:** the logo and name were too small; the layout didn't expand on wide screens.
- **Home:** drop "In season now", because it needs per-visitor data and abundance we don't have. Keep "Start from the plant". Make the Sources list "Recently changed" (added or modified). Make Identify stand out in the header.
- **ID:** the first mock was scrapped. Changing the Host is the most frequent action and must never be behind a click. Checkbox facets eat space and fail on mobile. The photos were about 50% smaller than today's, and photos are the most important thing on the page.
- **Genus:** the ID-mock layout suits it. Restore the Host counts per Gall (Galls per Host on plant pages), which are vital for higher taxa. Show a plant non-species taxon page; Hosts rarely have photos, and filters make no sense there.
- **Browse:** "so much better". Add a host view by Host family, sorted by count like the inducer view. Place: not sure. Undescribed is just a filter on the inducer view.

**Round 2, done:**
- **Header:** 64px with a 48px logo, and Identify as the header's one filled button.
- **Width:** `--container-page` is now 120rem (fluid up to 1920px). New `gf-photo-grid` class: photos at least 280px, `data-size=sm` at least 176px; wide screens add columns.
- **Home:** "Browse by what causes them" tiles, "Start from the plant" tiles, and "Recently changed" (a data_table of Sources by updated_at, labelled Added or Updated).
  - The galls table's updated_at is the migration date for all 3,976 galls, so it's useless here.
  - The replay_log holds the true change history. It is internal, and mapping it to public lines is its own task (with f14c).
- **ID v2:** close to today's page. Host picker, genus picker and region always visible; one row of `filter_select` dropdowns with counts plus "More filters" (behind a Filters button on phones); gall_cards in gf-photo-grid, four across at 1312px and six at 1920px.
- **Genus:** each card leads with "N hosts"; a Photos/Table switch, with the table sortable by Hosts; facets only at 8 or more Galls.
- **New plant genus mockup** (`/dev/mockups/plant-genus/:name`): stats, a Species data_table ranked by Galls, and a rail with the gall-former genera with counts and the Galls on the genus as a whole.
- **Browse:** "By host plant" (Host families by distinct Gall count) and an "Undescribed galls only" filter. The inducer groups live in `Dev.Mockups.Data`.
- **Proposed components awaiting approval:** `filter_select` (dropdown with counts) and `category_tile` (photo tile with name and count).
- **Docs:** foundations, components, patterns and mockups updated. Precommit is clean.


## Round 3 (2026-11-05): Jeff's feedback, the inventories, and fixes

**Feedback:**
- Browse by place needs a redesign.
- The home page left a gap in the middle on wide screens.
- ID: the clear-filters action was lost and the existing one is confusing.
- **Typeahead behavior must not change. Look and feel may improve, but the exact mechanics are hard-won and must be reused or replicated.**
- filter_select must handle multi-select exactly as the current screens do.
- category_tile approved by look.
- Say "Gallformer(s)", never "gall-former".
- Which design applies to higher taxa?
- Inventory **every** usage of current components before replacing anything.

**Inventories:** five read-only agents covered typeaheads and the ID page, actions and feedback, structure and data, domain and media, and forms. They are written up in `docs/design-system/inventory/*.md`, each with every call site, the hard-won lessons, a "Must preserve" checklist and an "Approved changes" log. README rule added: a replacement starts from its inventory; behavior changes need approval; prefer new markup around unchanged logic.

**Found by the inventories** (logged in matter 2c8c):
- `put_flash(:warning)` never renders.
- The images component's flash auto-dismiss targets the wrong process.
- `text-error` is undefined, so field errors are probably not red.
- Place-tree leaves are probably in italics.
- The vocabulary page has two h1s.

Also found:
- `phx:focus_input` is dead.
- The typeahead `phx-debounce` attrs do nothing.
- Several components have no callers (species_card, tabs, back_link, edit_button, skeleton, field_wrapper, radio_group, file_dropzone, source_citation, source_list, species_synonymy, host_list, abundance and data-completeness indicators).

**Regressions of mine, fixed:** the key path tracker and the review step bar were pinned at the old 78px header height, and ScrollToCouplet used a fixed 130px. The new tokens `top-header` (64px) and `top-admin-bar` (44px) fix the pinning. The scroll now measures everything marked `data-sticky-chrome`, with a test. My earlier button and chip moves were checked against the inventory: the button passes every attribute through, and soft and pill changed only in look.

**Mockups:**
- **ID (round 3):** a copy of `IDLive` with only the template changed, so every behavior is today's, including the real typeaheads.
  - Host and genus pickers in a panel.
  - The filter row in today's order. Multi-select filters keep the multi_select_typeahead mechanics plus ANY/ALL; single filters are selects showing counts from the loaded results while unset.
  - "More filters", and "Clear filters (N)" as a secondary button with a tooltip saying what it keeps. Its behavior is unchanged; whether it should also clear the name filter is open for Jeff.
  - gall_card in gf-photo-grid.
  - On phones, the filters fold behind a button.
  - The dev routes moved into live_session `:dev_mockups` with the public pages' user and continent hooks.
- **Home:** "Start from the plant" moved beside the intro on wide screens; "A gall to meet" became a compact card.
- **Higher taxa:** `/dev/mockups/taxon/:rank/:name` for Gallformer taxa ("Within it" children table; Table view by default above 150 galls; family names upright). `/dev/mockups/plant-taxon/:rank/:name` for plant families (a Genera table with species counts and distinct galls on each genus).
- **Browse by place** (`/dev/mockups/places`): the same tabs; continent cards with possible-gall counts; the chosen continent's countries ranked by galls, each with its busiest states and provinces inline; a filter by name. Counts come from `gall_index.place_ids`; the 5 galls with no range data are excluded and said so.
  - Data caveat: states of a country where Hosts are recorded only at country level all get the same count (e.g. Mexico, 1,681).

Precommit is clean (3,373 tests and 189 asset tests). Baseline: 3,288 findings.


## Round 4 (2026-11-05)

**Jeff's feedback on round 3:**
- **Home:** the random gall is one of the most joyful parts of the site and was de-emphasized; the page had become a wall of images. A non-starter.
- **ID:** "I want the same behaviors, not the same look." The understand-and-don't-break request was not a mandate to unwind the improved design. The dropdowns aligned poorly with the typeaheads, and the text was too large.
  - Clear filters: keep the behavior (traits only, not the Host). Make it less confusing if possible.
  - "(0 unfiltered)": a bug, fix it.
- **Higher taxa:** the children table was too sparse for the room it took, and the Galls table was hidden below it. Use tabs or similar. Cynipini scrolled forever: paginate.
- **Fagaceae:** fine. **Places:** a great start; go with it.

**Done:**
- **ID bug fixed in the real IDLive:** `total_count` is counted with the filters reset whenever filters are set (test added).
- **Controls restyled on tokens, CSS and class strings only:**
  - `.gf-label`, `.gf-input`, `.gf-select`, `.gf-textarea`, `.gf-checkbox`, `.gf-search-input`, `.gf-hint` and `.gf-error` moved from `legacy.css` to `components.css`.
  - The class strings in `typeahead` and `multi_select_typeahead` now use tokens. Every id, data attribute, ARIA attribute, event and mousedown guard is unchanged, and the selected text keeps its explicit color. Recorded under "Approved changes" in the inventories.
- **ID mockup v4:** generated from the real IDLive by `dev/gallformers_web/dev/mockups/build_id_mockup.py` (template in `id_live_template.ex.txt`), so behavior is always today's.
  - Round-2 look: Host and genus pickers in a panel.
  - The "Narrow it down" row (plant parts, detachable, region, family, season) with "More filters" for the rest.
  - "Clear N filters" next to the filters; the controls align at one size.
  - gall_card in gf-photo-grid; on phones the filters fold behind a button.
- **Home mockup v4:** generated from the real HomeLive by `build_home_mockup.py`, so the Host typeahead and the random gall are real; the extra data is added in a wrapping mount.
  - The random gall is the centerpiece: large, shown whole (object-contain; many images are drawings), with its name, credit, "See this gall" and a new "Show me another" (`shuffle` event).
  - "Start from the plant" and "Browse by what causes them" are compact two-column lists with thumbnails; then Recently changed.
- **Higher taxa** (`RankLive`): Galls and Genera ("Within it" when ranks are mixed) are tabs. Children show as a dense four-column list with counts. Pagination is 48 photos or 50 rows, back to page 1 on sort, filter or view change. Cynipini: 1,259 galls over 26 pages.
- **Docs:** patterns updated (home, rank tabs and pagination). Precommit clean (3,374 tests); baseline 3,203.


## Approvals (Jeff, 2026-11-05)

- **Page designs approved:** ID (round-4 mockup), home (round-4 mockup), higher taxa (tabs and pagination). Earlier: the places page as a starting point, the Fagaceae plant-family page, and the browse page's inducer and host views.
- **Components approved:** `filter_select` and `category_tile` (catalog updated).

**Next** (pending Jeff's priority): move the real pages onto the approved designs.
- The ID and home templates already exist as mockup templates over the real code, so moving those two means swapping in the template and its tests.
- Rank pages, browse and places need new read models (Gall cards with photos, Host and place counts) taking the place of the mockup data module.
- Still open: the Gall, Host and Source detail pages (photo_viewer, the range_map rework, source_entry with Markdown); the admin pages; the review flow (f14c); the admin save model; switching on dark mode; retiring the dead components.


## ID + home moved onto the system (2026-11-05)

Jeff chose "ID + home" first. Both real pages now run on the approved designs; their mockups, build scripts and routes are deleted. Nothing is committed. `mix precommit` is clean (3,388 tests); the baseline is 3,081.

**ID** (`IDLive`): the round-4 template is the real render. `filter_select` (Built) backs the single-value filters via `phx-change="change_filter" phx-value-filter=…`. Plant parts keep the multi_select_typeahead and ANY/ALL. "Clear N filters" clears traits only. The "(0 unfiltered)" bug is fixed.

**Home** (`HomeLive`): the round-4 template over the same Host typeahead (events and limits unchanged; the inventory records the change).
- New reads:
  - `Catalog.top_host_genera/1`: Host genera by distinct Galls from `gall_index`, with a small photo.
  - `Catalog.inducer_groups/0`: inducer families gathered by `Gallformers.Catalog.InducerGroups`, the plain-language group list, now in lib (proposed content; unknown families fall in "Other"; the mockup Data module uses it too).
  - `Sources.list_recently_changed/1`: by `updated_at`, "added" when unchanged since the minute it was added, until f14c records data changes.
- New event `shuffle` ("Show me another").
- Removed: the dead `go_to_id` event and "Find Galls" button (a pick already navigates).
- `category_tile` is Built (`:row` for the home lists, `:tile` for photo grids), with tests and a style guide entry; `filter_select` also has its style guide entry.
- Interim link: the group rows go to `/galls#group-<slug>` until Browse is moved onto the system and provides those anchors.
- "Recently changed" has no "All Sources" link: there is no public Sources list.

**Next:** Browse (by Gallformer group and by Host family; gives the home group links their anchors), then the rank pages and places with real read models.


## Browse moved onto the system (2026-11-05)

`/galls` and `/hosts` now run on the approved browse design. The browse mockup is deleted; the places mockup's tabs point at the real pages. Nothing is committed. `mix precommit` is clean (3,401 tests); the baseline is 3,068.

**New components (Built, in the catalog and the style guide):**
- `tab_nav` (PageComponents): link tabs. The tab list is `BrowseHelpers.browse_tabs/0`.
- `family_card` (DomainComponents): the approved browse card, which is also the browse tree. Its toggle opens it across the grid to every genus, flowing in columns; each genus has a caret listing its Galls or plants.

**New reads:**
- `Catalog.host_gall_counts/0`: distinct Galls per plant genus and family, from `gall_index`, with a photo.
- `Catalog.gall_photo_urls/0`.
- `BrowseHelpers.family_cards/2`: tree to card view model.
- `BrowseHelpers.filter_cards_tree/2`.

**Kept from the tree:** the search form ids, field, debounce and events; `toggle_node`, `expand_all`, `collapse_all`; smart expand; leaf links; the empty messages; the lazy undescribed tree and `data-active-view`.

**Changes, logged in `inventory/domain-and-media.md`, for Jeff to confirm:**
- The undescribed toggle is a checkbox.
- A family or genus whose own name matches the filter keeps its children. With `filter_tree/2` it became a bare link; that function is unchanged for `/places`.
- `/hosts` is ordered by Galls, not by name; families with no Galls stay, last.
- Both pages have an h1 "Browse galls".
- `/galls` sections carry `#group-<slug>` anchors, so the home page's group links land on them.

**Next:** places (`/places`, from the places mockup; the last `tree_browser` user), then the rank pages (tabs and pagination).


## Places moved onto the system; tree_browser retired (2026-11-05)

`/places` runs on the approved places design. The places mockup is deleted. Nothing is committed. Precommit is clean (3,403 tests); the baseline is 3,052.

**Page:**
- Continent tiles (`?c=`; default the visitor's region, else the busiest continent).
- The chosen continent's countries in a sortable `data_table`, each with its busiest five states or provinces.
- A filter across every continent.
- A country's toggle shows all its states.
- "Show all states and provinces" and "Collapse all".

**Reads:** `Catalog.place_gall_counts/0`: possible-range Gall counts per place, read once connected. It takes 0.7s on real data, because ranges average about 425 leaf places per Gall (1.7M pairs). A recursive-CTE form took 6s. It relies on ranges listing leaves and the hierarchy being two levels deep, as documented in the code.

**Retired:** `TreeComponents` (no callers left) and the old `filter_tree/2`. `BrowseHelpers.filter_tree/2` now has the card semantics on all three Browse pages. `list_separator/2` moved into `GallformersWeb.Helpers`, with a doctest.

**Next:** the higher-taxa pages (RankLive mockup: tabs and pagination; plant family and genus pages).


## Rank pages moved onto the system (2026-11-05)

Genus, section, family and the intermediate ranks run on the approved higher-taxa and plant-page designs. All page mockups are now built, so `dev/gallformers_web/dev/mockups/` is deleted, and only `/dev/design-system` stays in the dev scope. Nothing is committed. Precommit is clean (3,413 tests); the baseline is 2,934.

**Inventory:** `docs/design-system/inventory/rank-pages.md`, written by a subagent, with an "Approved changes" entry listing every change.

**Code:**
- `GallformersWeb.RankGalls`: the Galls list, via `Catalog.identify(%{inducer_family_id: id})` plus Host counts, common names and Host genera; facets, the search, sort, Photos/Table and pagination; tested.
- `RankPageComponents`: `rank_galls`, `plant_table`, `inducer_genera_panel` (the plants' related-genus filter, now in the rail), `galls_on_panel`, `children_list`, and the restyled `admin_edit_link`. `species_table` is removed.
- `RankPage.crumbs/1`: URL-encoded breadcrumbs.
- `/family` now routes to `IntermediateLive` `:family`; `FamilyLive` is deleted. The tabs are `?tab=galls|within` through `tab_nav` patch links.
- `Catalog.host_gall_counts/0` now covers every plant rank that has a page.

**Behavior changes for Jeff to confirm:**
- The Galls' related-genus filter is now the Host genus facet, which needs 8 or more Galls and 2 or more options.
- The family and tribe Galls tab lists the whole subtree, not just the Galls placed at the taxon.
- A plant family's genera table counts the Galls on each genus. Before, it counted Galls induced, which is almost always 0.
- The always-zero Hosts column is gone.
- Unknown names are still a 200, not a 404; that decision is open.

**Still open from the inventory:** case-sensitive lookups, synonyms not redirecting, and the dead `/infratribe`, `/supertribe` and `/infrafamily` routes.

**Next:** the Gall, Host and Source detail pages (photo_viewer, the range_map rework, source_entry with Markdown), then admin.


## 404s, the place page, and a count fix (2026-11-05)

Nothing is committed. Precommit is clean (3,415 tests); the baseline is 2,917.

**Done:**
- **404s:** an unknown name on a rank page (genus, family, section, intermediate, a dead intermediate route, or a wrong rank) and an unknown old numeric ID now raise `GallformersWeb.NotFoundError` (`plug_status` 404), as Jeff decided. The old in-page "not found" boxes are gone.
- **Place page:** `/place/:code` is on the system, proposed for Jeff's review.
  - Crumbs, type and code; the large range map (`h-96 md:h-140`), still navigable; a rail of the sub-places with Gall counts, scrolling within the map's height.
  - New: "Galls that may occur here", from `RankGalls.load(%{place_codes: [code]})` without the galls that range everywhere (`Catalog.everywhere_gall_ids/0`). It loads once connected, in about 2s for the US.
  - `RankGalls.load/1` now takes ID-tool filters.
- **Count bug:** `place_gall_counts/0` took the larger of its two counts where it should have combined them, so a continent reached both from leaf countries and through states was undercounted (the Caribbean read 584; it has 613). Fixed with a test, still 0.66s, and checked against an independent recursive count.

**Open, for Jeff (asked 2026-11-05):** the counts include Hosts' introduced ranges, as decided on 2026-10-25 (b5bd), so Europe shows 1,577. With native host ranges only it would be about 468; Oceania 707 vs 88; Asia 1,161 vs 516. Jeff: "if a plant is introduced AND the gall is shown to be in the country then it should count." That changes the potential range rule.
- Scope: the potential range itself (ID tool region filter, gall maps, place pages), or only the place counts and lists?
- Evidence: what shows a Gall is in a country? Recorded-occurrence Facts are the obvious source, but only 4 exist (one Gall).
- Until this is decided, an introduced region would almost never count.


## Place counts are known places (2026-11-05)

Jeff ruled that the place counts were "wildly inaccurate" and can't ship. A gall counts in a place where its Hosts are native, or where a Host is introduced and the gall itself is recorded in that country. With no data, the count is 0.

**Built (tested):**
- `PotentialRange.known_for_galls/1`: the potential range filtered to native host places, plus introduced places in countries with a current recorded occurrence. A record in a subdivision shows its country; a continent-level record shows none. Galls with no range data give `[]`.
- `Current.occurrences/1`.
- Migration `20261105120000_add_known_place_ids_to_gall_index` adds `gall_index.known_place_ids` with a GIN index, filled on refresh.
- `place_gall_counts/0` counts `known_place_ids`.
- An Identify filter `:known_place_codes`; the place page lists through it ("Galls known here").
- `everywhere_gall_ids` removed. The wording on `/places` and `/place` is updated.

**Real counts** (read-only run on taxogall): NA 3,486 · Asia 516 · Europe 467 · Central America 421 · Africa 405 · South America 336 · Caribbean 279 · Oceania 88.

**Open:**
- The ID tool's region filter still uses the potential range (native and introduced, plus galls with no range data everywhere). It has the same inaccuracy; Jeff to decide.
- The dev DB (`gallformers_taxogall`) needs the migration and a full gall_index rebuild before the running server shows this; awaiting Jeff's OK, since it writes to the shared dev DB.

Precommit is clean (3,421 tests). Nothing is committed.


## Detail pages: inventories and the Gall page mockup (2026-11-05)

**Inventories (written by subagents):**
- `docs/design-system/inventory/gall-page.md`.
- `docs/design-system/inventory/host-and-source-pages.md`.
- Bugs they found are in 2c8c: a site-wide canonical tag search engines ignore; the Source page hiding retraction; **stored HTML/script injection through `Gallformers.Markdown`**. That last one affects production: Gall-page Source descriptions and articles.

**Gall page mockup:** `/dev/mockups/gall/:id`, generated from today's `GallLive` by `dev/gallformers_web/dev/mockups/build_gall_mockup.py`; only the template changed, plus the map dialog's two events.
- **Header:** lineage crumbs; the name with the generation tooltip (italics now through `page_header`); Undescribed and Complete / In progress chips; common names and abundance as meta; Edit.
- **Undescribed:** a warn notice with the copyable code and the iNaturalist link.
- **Main column:**
  - Hosts as a 4-column name_list.
  - Traits as a fact_list, with the unrecorded traits on one "Not recorded: …" line.
  - Sources: the ID Notes pinned as an info panel ("Read the ID Notes" opens the dialog), then one row per Source (year, title, authors, external and copy-link icons, two serif lines, "Read more" opening the full-text dialog with the A−/A+ font sizes, copy link, external link and Source page). Today's order, 8 at first, "Show all N sources".
  - Names (data_table, paginated), Related galls, See Also, created and updated.
- **Rail:**
  - Today's gallery, until photo_viewer exists.
  - The map card (h-72) with the legend and the caveat. "Enlarge" opens a full dialog with a large map, which has its own full-screen button.
  - The map now frames the native range: the mockup computes bounds without the introduced places (gall 821's red-oak plantings in Europe had framed it on Europe).
- **Phones:** name, photo, map, Hosts, Traits, Sources.
- **Behavior changes proposed:**
  - The ID Notes banner ("Show notes", dismissible) is replaced by the pinned panel.
  - Source excerpts are plain text (Markdown stripped) in the list; the full text in the dialog is still Markdown.

**Next:** Jeff reviews the Gall mockup; then the Host and Source mockups, the real build, and fixing the Markdown sanitizing.


### Gall mockup, round 2 (2026-11-05)

Jeff's feedback on round 1:
- Related galls were buried.
- Synonymy and "Look further" looked like today's.
- Follow the **second** round-1 proposal ("A fuller Gall: Callirhytis quercuscornigera, whole page").
- The Gallformers notes are pinned and visible when present; they will hold non-Fact prose too.

Round 2 follows that proposal:
- Under the title, a summary line: Other generation (or Related galls) linked · Common name · Season · Location · Form.
- Hosts in four columns.
- Traits "6 of 11 recorded", with Abundance as a trait; the empty ones on a "Not recorded: …" line.
- The ID Notes pinned in full (year and license, copy link).
- Sources by year with an Oldest first / Newest first switch. Each row is year · title · authors · one serif line, and opens in place (caret) to the whole formatted text with license, Source page, Original ↗ and Copy link. `?source=` opens that one. 8 at first, then "Show all".
- The rail: photos; the map card framed on the native range, with Enlarge opening a dialog; "Also known as" (synonyms, labels, codes, with misapplied/sensu notes); "Look further" as text links; created and updated dates.
- About 1,650px long; today's page is 3,262px.

Changes this implies (Jeff to approve with the mockup):
- The source dialog and its A−/A+ font sizes are gone (Sources open in place).
- The names table becomes a line.
- See Also's logos become links.
- The ID Notes banner is replaced by the pinned notes.


### Gall mockup, round 3 (2026-11-05)

Jeff's feedback on round 2:
- "Look further" becomes **"More info"**.
- Inline Sources are out: the reader dialog is "extremely valuable", and a deep link must open it directly. Reverted to today's behavior.
- The synonymy must include every synonym, old common names included.
- Otherwise approved.

Round 3:
- Source rows (year · title · authors, external and copy-link icons, two serif lines, license) open the **reader dialog** with "Read": A−/A+, license, Copy link, External link, Source page. `?source=` opens it directly; checked.
- The ID Notes panel is in full and has a "Reader" button.
- "Also known as" lists the common names (marked), then the synonyms, misapplied names, former labels and codes.
- The by-year order with Oldest/Newest stays.

The migration gap (224 old Gall aliases missing from the new names) is logged in b5bd.

Next: build the real Gall page from round 3, then the Host and Source mockups.


## The Gall page is built (2026-11-05)

Jeff approved mockup round 3, asking that the ID Notes' read action match the Sources' ("Read"). `GallLive` now runs on the system and the mockup is deleted. Precommit is clean (3,423 tests); the baseline is 2,821. Nothing is committed.

**Built, as in round 3:**
- The h1 name with crumbs from the Inducer's lineage, encoded.
- The summary line: other generation, common name, season, location, form.
- Hosts; Traits (`fact_list`, "N of 11 recorded", Abundance as a trait).
- The ID Notes pinned in full, with "Read" opening the reader.
- Sources by year (`sources_order`), "Read" opening the reader `#source-detail-modal` (A−/A+), `?source=` opening it directly.
- The rail: gallery; map card framed on the native range (`range_bounds` now excludes introduced places); Enlarge → `#range-dialog`; "Also known as" (common names, synonyms, misapplied names, labels, codes); "More info"; created/updated.
- Unknown or malformed IDs are 404s.

**Shared changes:**
- `see_also` restyled to "More info" text links (the Host page shows them too).
- `record_metadata` moved onto tokens.
- Removed: the banner, the names-table pagination, `dismiss_notes_alert` and `aliases_page`.

**Docs:** the inventory's approved changes, the catalog (`see_also`, `range_map` framing) and the Gall page pattern.

**Open:**
- photo_viewer (the gallery is still the old component).
- The 224 old Gall aliases missing from the new names (b5bd).

**Next:** the Host and Source page mockups.


## Host and Source page mockups (2026-11-05)

Both are generated from today's LiveViews with a new template by `dev/gallformers_web/dev/mockups/build_detail_mockups.py`, which also strips the old template's unused helpers. Routes: `/dev/mockups/host/:id` and `/dev/mockups/source/:id`.

**Host:**
- **Header:** crumbs from the lineage, with sections shown as "sect. Quercus"; the italic name as h1; chips for rank, Host plant and Complete / In progress; common name and abundance as meta.
- **Actions:** "Identify a gall on …", replacing the hidden link on the name; Edit.
- **Main:** "Galls on it" as the rank pages' list (`RankGalls.load(%{host_id: id})`: photos or table, facets, pagination, host-count subtitles). Below it, a pointer to the Galls recorded on the genus as a whole, which today never appear on a species page.
- **Rail:** gallery (only when there are images); the range card framed on the native range, with Enlarge; "Also known as" (synonyms, misapplied with sensu); More info; created/updated.

**Behavior changes proposed:**
- The Complete column, its sort and each gall's admin pencil are gone from the galls list.
- The paged synonymy table becomes a line.
- The two old pagers become the list's one pagination.

**Source:**
- **Header:** title h1; chips for kind (when set), Retracted and Complete; meta for authors (new list, else old field), year, DOI (links doi.org), ISBN, license.
- **Actions:** Original ↗ and Edit.
- A danger notice when retracted, linking the notice Source.
- **Main:** Citation in serif; "Galls it covers" as a three-column name_list (60 a page instead of 20; links keep `?source=`); "What this Source says" (`facts_view`, still loaded once connected); the dates line.
- **Rail:** gallery only when there are images, so the empty "No images available" box is gone.

Precommit is clean.


Jeff, 2026-11-05: the Host page's per-gall pencil (to `/admin/galls/:id`, where the Gall's Hosts are edited) is essential, since without it an admin must go through the admin to find the gall. Restored. `rank_galls` takes an `edit_path` (gall → admin path), passed for admins only. It shows as a pencil button on each photo card (a sibling of the card link, not nested in it) and as an Edit column in the table. Tested in `rank_page_components_test.exs`. The rank pages could pass it too.

Correction (Jeff, 2026-11-05: "the link goes to the wrong place"). In production the Host page's per-gall pencil opens the old gall-host editor `/admin/gallhost?id=<gall>`; taxogall's HostLive pointed it at `/admin/galls/:id` (the top of the page). The new admin has no gall-host editor (Hosts arrive with imports); the gall-host range is edited in the Gall admin's "Range exclusions" section. The pencil now links to `/admin/galls/:id#range-exclusions`, which lands on that section (checked). Open question for Jeff: whether admins need to add or remove a Gall's Hosts directly, which the new admin can't do.


## Host and Source pages built (2026-11-05)

Jeff approved both mockups ("build it"); he doesn't need to edit a Gall's Hosts in admin. `HostLive` and `SourceLive` now run on the system. The mockups are deleted, so there are none left. Precommit is clean (3,431 tests); the baseline is 2,747. Nothing is committed.

- **Host:** as the mockup.
  - "Identify a gall on …"; the Galls as `rank_galls`, with admin pencils to `/admin/galls/:id#range-exclusions`; `#on-genus` pointer; the range card framed on the native range, with Enlarge; "Also known as"; More info.
  - The Edit button is the shared `admin_edit_link`.
  - Unknown, malformed, Gall or higher-rank IDs are 404s.
- **Source:** as the mockup.
  - Kind, DOI, ISBN; Retracted chip and notice; the citation in serif; Galls 60 a page in three columns; facts; dates; images only when present.
  - Unknown or malformed IDs are 404s.
- **Tests:** updated, plus new ones for the identify link, the genus pointer, Enlarge, the DOI and original link, retraction, and no empty photo box. The e2e and integration tests follow the h1 and the 404s.
- **Docs:** the inventory's approved changes, the patterns.

**Every public detail page is now built.** Next, in order:
1. The remaining public pages: search, articles, glossary, keys, about, analytics, the filter guide, and the error pages.
2. photo_viewer.
3. The admin pages, which need Jeff's save-model decision.
4. Dark mode.
5. Retiring dead components.


## photo_viewer built; image_gallery retired (2026-11-05)

`photo_viewer` (DomainComponents) and the `PhotoViewer` hook replace `image_gallery` and the ImageGallery hook, both deleted with their tests, on the Gall, Host and Source pages. Precommit is clean (3,435 tests, 176 JS tests); the baseline is 2,672.

**Design:** the server renders every photo's slide (the photo shown whole in a 320px stage, its caption and its own credit), full-size figure and details; the hook only shows the current one.
- **Moving:** arrows, thumbnails (strip of small images; current marked via `.gf-thumbs [aria-current=true]` in components.css), arrow keys (wrapping; in the full-size view too) and a horizontal swipe (40px).
- **Dialogs:** full size (native `<dialog>`, dark, photos loaded via `data-src` when shown) and Details (source, license, attribution, creator, uploader, last changed by, caption). Escape or Close closes, and focus returns to the opener.
- **Events:** `gallery_index_changed {index}` on every move.
- **Empty:** "No photos yet." plus admin "Add images".
- Attributes: `id`, `photos` (maps, atom or string keys; `thumb` = the small variant), `name`, `edit_href`, `admin`.
- **Fixed:** credits no longer depend on the first photo; alt text "Photo n of <name>" instead of "Gall image"; focus return.
- **Pages:** Host shows the viewer when it has photos or to an admin; Source only with photos; Gall always (empty state).
- **Docs:** the catalog entry is Built and the inventory's approved changes are updated; the style guide has an example.

Jeff, 2026-11-05, on photo_viewer ("otherwise looks great"):
- Escape must close the full-size view. The hook now closes an open dialog on any Escape (a window listener), because some browsers leave focus outside the modal after a click on its photo; tested.
- The arrows should be subtler, like the old control. On the photo they are translucent dark (`bg-ink/40`, `text-paper`, 32×48); in the full-size view, faint light (`bg-paper/10`).


## Public pages: search, glossary and error pages built (2026-11-05)

Jeff said to start the remaining public pages with the easy ones. Precommit is clean (3,445 tests, 178 JS tests); the baseline is 2,594. Nothing is committed.

**Search (`SearchLive`):**
- Kept: `?q=` push_patch, 300 ms debounce, submit, the region bar with "All Regions" when a region leaves nothing, the sort by type and name (default relevance), 50 a page, ↑/↓ highlight (window keydown), Enter opens, a click highlights, the name formats and aliases, and the empty and no-results states.
- Now on `page_header`, `search_field`, `empty_state`, `data_table` (type icon plus its label; `active` row; `sort` with `field`) and `pagination`.
- The tests that asserted nothing (`… or is_binary(html)`) are replaced by real ones.

**Glossary (`GlossaryLive`):** it had no tests; 7 now.
- Kept: row ids are the lowercase word, so `/glossary#word` links from search and the tooltips still work; the filter; the sort by word and definition; numbered reference links; the edit link for signed-in users; definitions linking other terms; "Showing N entries".
- Definitions show in full.

**Error pages:** one `ErrorHTML.error_page/1` for 403, 404 and 500.
- Standalone, with the wordmark home; no inline CSS.
- Bug fixed: they linked `/assets/app.css`, which doesn't exist (the real path is `/assets/css/app.css`), so only their inline CSS styled them.
- Go Back is kept through `{:javascript, "history.back()"}`; it would be blocked once the CSP is enforced.
- The 404 keeps the scale-insect joke and its iNaturalist link.

**data_table additions:** `active` (the keyboard-highlighted row) and a column's `full` (the whole text). Both are tested and in the catalog.

**Next public pages:** articles and keys (mockups first), then filter guide, about and analytics.


## Search refinements, Go Back, filter guide and About (2026-11-05)

Precommit is clean (3,457 tests, 178 JS tests); the baseline is 2,542. Nothing is committed.

**Go Back on the error pages:** a link to the Referer (`ErrorHTML.back_href/1`, web addresses only), with no script, so an enforced CSP won't break it. With no referrer there is no Go Back.

**Filter guide:** a `page_header`, jump links, and one `section` per Trait with a count (anchors kept), two columns on wide screens.

**About:** the same text, in a reading column of sections. The rail holds the site stats (the exact sentences the tests pin) and the co-founder cards. Administrators are a 3-column `name_list`. The version line and the easter egg are kept.

**Search (Jeff chose ideas 1 and 2):**
- **Result types:** a `tab_nav` with counts (All plus each type present), kept in the URL as `?type=`. An unknown type shows All; a new query or a region change resets it.
- **Two-line rows**, read for the page shown only:
  - Galls: a small photo (or the gall icon) and "on <Host> and N more · plant part · season", from `Catalog.gall_search_details/1`, a batched read over `gall_index`.
  - Plants: the Gall count (common names are already in the bracketed aliases).
  - Genera and families: common names and Galls (whichever is larger of Galls induced and Galls on it).
  - Glossary terms: the definition.
  - Places: the kind (`Search.search_places` now returns `kind`).
- The page's rows and second lines are computed when the query, type, sort, page or region changes, not on a keyboard highlight.

**Ideas not built:** a best-match card (idea 3) and why-it-matched (idea 4).

**Next:** the articles and keys mockups, then analytics.


## Articles and keys built; prose built; typography plugin removed (2026-11-05)

Jeff approved the mockups (inventory and approved changes: `docs/design-system/inventory/articles-and-keys.md`).

- **`prose`** (PageComponents, Built): rendered Markdown (`markdown`, through `Gallformers.Markdown`) or inner markup; sizes 14/16/18/20px, `font` sans or serif; Markdown headings start at section level; styles lists, quotes, tables, code, `details`. Used by articles (18px), Privacy, the Gall page's ID Notes and source reader (A−/A+), the admin article preview. `@tailwindcss/typography` (bundled in the Tailwind CLI) and the legacy `.prose` rules are gone. Glossary links moved to components.css: text color, dotted underline.
- **Articles**: list with Topics tabs (`?tag=`); article page with `page_header`, Draft notice, Related articles in the rail. Contents list considered and dropped (not worth the work).
- **Keys**: list with scope and couplet count (`Keys.list_keys/0` gives `couplet_count`). Key page: `key_couplet` (lettered leads, destination at the right, choosable leads are buttons) and `key_path` (panel in the rail on wide screens with each step's lead text; sticky bar on narrow). Results covering several Galls name each Gall (`Catalog.list_galls_by_id/1`). Missing key is a 404.
- **Copy** split in two: Copy link (the `?path=` link, whenever there is a path) and Copy as text (at a result). Steps in the text read as on the page ("9b. …"), per Jeff.
- Baseline 2,373. Precommit clean (3,467 tests, 178 JS).

**Next:** analytics (`bar_chart` replacing d3).


### Articles list made livelier (2026-11-05)

Jeff found the reading list stark; approved a mockup and it's built: topics as `chip_nav` chips; the newest article featured (`article_card featured`, "Newest") on the unfiltered list; the rest as `article_card`s in a 3/2/1 grid, each band tinted by its first topic (sky: identification, guide; autumn: faq, taxonomy, undescribed; brand: meta, contributing, supporters; plain otherwise) with a large tilted Phosphor icon (`ArticlesHTML` holds the mapping); admin pencils on cards; "More to read" `link_tile`s (keys with count, glossary, filter guide). New catalog entries: `article_card`, `chip_nav`, `link_tile` (Built, style guide examples). Previews now drop Markdown list markers. Keys list keeps the reading-list layout for now. Precommit clean (3,475 tests, 178 JS).


### Home page title restored (2026-11-05)

Per Jeff: the page title is again "Welcome to Gallformers", over the old site's definition of plant galls with its "Learn more →" link to the ID guide (`page_header` description). "Identify a plant gall" is now the h2 above the plant search, with the "narrows N galls" line. The "Or …" line keeps search and browse (the ID guide link moved up to Learn more). E2E titles updated (home, Articles).


## Analytics built; bar_chart and share_list built; d3 removed (2026-11-05)

Jeff approved the mockup (inventory and approved changes: `docs/design-system/inventory/analytics.md`). Every old feature kept (periods, single-day totals, grouped daily bars with per-bar values on hover, thinned day labels, the per-day visitors note, top pages, referrers 15 a page, devices and browsers with count and %, empty messages). Changes: period in the URL (`?range=`, `chip_nav`); totals for every period (views, visitors a day on average, busiest day); `bar_chart` (server SVG, percentage x positions, round y scale, `<title>` tooltips, legend, sr-only table); `data_table`s (paths link, no name lookup per Jeff); `share_list` for devices and browsers (new catalog entry). Removed: d3-array/axis/scale/selection (package.json + lock), the `DailyChart` hook and its tests. First LiveView test for the page (7). Baseline 2,306. Precommit clean (3,489 tests, 170 JS).

**Public pages are all on the system.** Next on the plan: admin pages (needs Jeff's save-model decision), dark mode activation, retiring dead components.


### Page descriptions get a lead measure (2026-11-06)

Jeff: the analytics description shouldn't wrap. `page_header`'s description now runs to `max-w-lead` (new token `--container-lead`, 56rem, about 100 characters at lead size) instead of `max-w-text`, so a one-sentence description stays on one line site-wide; longer ones wrap at the wider measure. Documented in foundations.md.


## Host table view gone; unused components removed; dark mode on (2026-11-06)

Per Jeff:
- **Host page:** Galls are photos only. `RankGalls.new(galls, views: [:photos])`; a list's `views` decides whether `rank_galls` shows the Photos/Table switch, and `view/2` ignores a view the list doesn't offer. A large Host no longer opens as a table.
- **Unused components removed** (nothing called them): species_card, data_complete_badge, list, abundance_indicator, data_completeness_indicator, edit_button, external_links, host_list, source_citation, source_list, species_synonymy, taxonomy_breadcrumb, field_wrapper, file_dropzone, multi_select, radio_group, back_link, SEO head/species_json_ld/website_json_ld, skeleton, tabs (+ Tabs hook), and the unrouted generator PageController/home template. Catalog records them. LineageBreadcrumb stays (Host page).
- **Dark mode on for the public site.** No pin on `<html>`: OS setting by default; header `theme_switch` (Match my device / Light / Dark, `gf-sun`/`gf-moon`/`gf-contrast` icons drawn in-house) saves `gf-theme`, applied pre-paint by `#theme-init` (CSP nonce); `assets/js/theme.js` (6 JS tests). Tokens: light values on `:root, [data-theme="light"]` so the admin shell (`data-theme="light"`) stays light until migrated. White wordmark in dark (`gf-only-light`/`gf-only-dark`). Moved onto tokens for public pages: region prompt + scope bar (aria-current, data-filtered), pagination, glossary tooltip (+ legacy tooltip CSS), spinner, range-map legend (map tokens, `.gf-hatch`), Facts components (Source page), user profile, preview/maintenance banners. Checked in dark: home, Gall, ID, Source, Articles, key, analytics; admin light.
- Known: the range map keeps its light basemap in dark.
- Baseline 1,941. Precommit clean (3,488 tests, 167 JS).

**Next:** admin pages (save-model decision), which also lets the admin go dark.


### Admin dashboard: direction (2026-11-06)

Jeff chose option A (work first) with changes: the Source review queue front and center; drop the open-questions-by-kind section; a large Recent changes panel with named curators below the queue (curators named, unlike the public view). The admin logo now links to the public site (built, tested). The admin's edit model is now matter 15db: every Fact edit goes through Source ingestion (Gallformers Source for curators' own edits); only non-Fact content (glossary, articles, keys, vocabulary, users) keeps direct forms. That replaces the open "save model" question.


### Admin dashboard round 3 + Changes page mockup (2026-11-06)

Per Jeff: group consecutive changes; rich (Galls named, each Fact in words); drop import re-checks; add search and a Flag action (matter 15db). Mockups: `/dev/mockups/admin-dashboard` (review queue, then the latest 8 grouped changes, "All changes") and `/dev/mockups/admin-changes` (search, curator, kind, period; Flag dialog, not saved). Found: Fact updates in an import are unsupported → current ("made current"), not superseded; a Fact added and made current in one change reads as added.


### Changes: View and Edit, one component (2026-11-06)

Per Jeff: no flags, no copy-link. Each Fact in a change links out to **View** (the public page it shows on: the Gall's; a taxon's own page, a search in the mockup) and **Edit** (placeholder: the Gall's admin page until the 15db edit process exists). The dashboard's recent changes and the Changes page render the exact same `change_entry` component, links included (no variant switch).


### Paused for the edit model (2026-11-06)

Jeff is deciding the admin edit model elsewhere (likely inline edits on the public data pages, eliminating most admin pages; matter 15db). The dashboard and Changes page build waits for that. Ready meanwhile: mockups `/dev/mockups/admin-dashboard`, `/dev/mockups/admin-changes`, and their read `dev/.../mockups/changes_read.ex` (the basis for an `Audit` read model). Built and tested: the admin logo goes to the public site.


## Admin dashboard and Changes page built (2026-11-06)

Jeff's decisions on curation are in matter **ec2c** (it lives in the main checkout's `.mull`, not this worktree): every Gallformers edit goes through the Fact process via a **change set** (the curator's tray); inline edits on the public pages with Edit on; ⌘K palette for everyone; editorial edits in the same tray; roles; delete safeguards; restating Gallformers' position. **Inline editing is built on this branch** (Jeff); the ingestion side is another agent's.

Built here (TDD; precommit clean, 3,496 tests, 167 JS; baseline 1,862):
- `Gallformers.Audit.ChangeLog` (exported; web reaches it as `Catalog.changes/1`): curator transactions (system work, re-checks and empty transactions left out), grouped (same curator, operation, Source), worded for every curator operation, with the Source (through the package), each Fact in words with its Gall or taxon and what happened to it, the Galls and taxa touched, new names with rank and kingdom. Tests write curator changes into the trail directly (`Gallformers.AuditFixtures`).
- `change_entry` (DomainComponents, catalog): View (public page, `#fact-<id>`) and Edit (`?edit`, the inline editor to come) on every Gall, taxon and Fact; taxon pages via `TaxonomyURL.taxon_path/1` (new); `Helpers.time_ago/2` (new).
- `Admin.DashboardLive` rebuilt: Sources to review, Recent changes (8), Find / Create / Site.
- `Admin.ChangesLive` (`/admin/changes`, sidebar "Changes"): search, curator, kind, period in the URL.
- Admin logo goes to the public site.

**Next (ec2c on this branch):** design the curation pieces as catalog components with mockups, with Jeff: ⌘K palette (header search for everyone), Edit mode and per-Fact actions on the Gall page, the change tray and its persistent indicator, Review and apply (Facts preview, evidence), add-from-observation, delete with impact. Then build. The dashboard gets "Your changes" once the tray exists; Find/Create shrink as admin pages give way to inline editing.


### ⌘K palette mockup (2026-11-06)

`/dev/mockups/palette`: the palette (proposed `command_palette`) open over the home page, over the real `Search.global_search/2` plus articles, with ↑ ↓ Enter Esc. Empty: Go to (Identify, Browse galls/plants/places, Articles, Keys, Glossary) and, for curators, Edit this page, Add from observation…, Sources to review, Changes. Typing: Go to shortcuts into the ID tool ("Galls on *Quercus alba*", "… in <place>", "Galls in <place>"), then Galls, Host plants, Groups, Places, Sources, Glossary, Articles (4/4/4/3/3/2/2), curators' "Review: <Source>", and "See every result" (/globalsearch). The header's search box becomes a trigger button (Search Gallformers ⌘K). Built: a sticky LiveView in the site and admin shells; arbitrary sizes in the mockup (12vh, 70vh) become tokens.


#### Palette decisions (Jeff, 2026-11-06)

- Not ⌘K: many browsers bind Cmd/Ctrl-K to their own search. Keys: `/` and `s` (letters work on every keyboard layout; `/` needs Shift on many), both only when not typing in a field. The trigger shows "/". (Called "the command palette" from here; the ⌘K name is retired.)
- The empty palette shows the fixed Go to list (and Curators' commands for admins), not recents.
- In the admin shell too; it replaces the dashboard's Find panel once inline editing lands.
- The header's search box is replaced by the trigger button.


### Command palette built (2026-11-06)

`GallformersWeb.PaletteLive` (rendered once from the root layout, through `Layouts.outside_live_session/1` so a page's live-session on_mount, e.g. a superadmin check, doesn't run for it), `GallformersWeb.Palette` (the groups; `Articles.search_published/2` new), the `Palette` hook (open on `gf:open-palette`, Enter follows the selection, keeps it in view), `search_shortcut.js` (`/` and `s` open it when the palette is on the page), `Layouts.palette_trigger` (header field-like button and phone icon; admin top bar). The header's search box and the phone menu's search field are gone. `gf-palette`, `gf-palette-overlay`, `gf-kbd` in components.css; catalog entry `command_palette`. Precommit clean (3,512 tests, 173 JS). Open: the keys (Jeff: `/` is Firefox's quick find); commands still to come with their targets: Add from observation…, Review: <Source>.


#### Palette keys settled (Jeff, 2026-11-06)

`/` and `s` stay. On our pages `/` opens the palette rather than Firefox's quick find (as on GitHub, MDN, Wikipedia); Ctrl/⌘-F still finds in the page.


### Edit mode mockup (2026-11-06)

`/dev/mockups/gall-edit/:id` (add `?edit`): a copy of `GallLive` with Edit mode (ec2c). Proposed: `edit_toggle` in the page header (Edit / Editing · Done, `?edit`); an "Editing" notice; an Editorial panel (completeness, abundance, Gallformers code with confirmation, name parts); Hosts as `fact_row`s (each with its Sources and Withdraw / Correct… / Note…; "in your tray" once acted on; Add a host); Traits with each value's ✕ withdraw (Sources on hover) and "+ Add" per Trait; the `change_tray` bar pinned at the foot (count, the changes, Discard, Review and apply); `review_apply` dialog (each change: action, what, status chip — New / Already held: <Sources> / Supersedes <Sources>: a reason is needed / Editorial: no evidence needed / asks for confirmation; take out; evidence once: an iNaturalist observation, a Source, or my judgement with a reason). In memory only; nothing is written.


#### Edit mode: what's edited here, elsewhere, or follows (2026-11-06)

Jeff: keep the Host actions as three text buttons; editorial fields as in the mockup's panel; build order back end → Hosts/Traits → the rest. Jeff asked for a way to show what is NOT editable here and what is edited on another page. Mocked as a proposed `edit_scope` marker, with a key in the Editing notice (✎ actions: edit here · ↗ edited on another page · ⓘ follows from other data):
- **Edit here:** Inducer (a Fact on the Gall: Correct…/Note…), Hosts, Traits, common names (Facts); completeness, abundance, code, name parts (editorial; name parts and code still link out for now).
- **↗ Edited on another page:** the lineage and the Inducer's synonyms (the Inducer's taxonomy), the plants' ranges (each plant's page), photos (photo manager), the ID note (note editor until notes split, 20e5), range exclusions (their editor, until inline).
- **ⓘ Follows from other data:** the other generation (same Inducer), Season/Location/Form in the header (from Traits), the Sources list (what the Facts cite), the range map (Hosts' ranges + the Gall's range Facts), former labels (renames).
The same three-way scope applies to every page with Edit mode (plant, taxon pages).


#### Edit scope decisions (Jeff, 2026-11-06)

- The three kinds and their markers (✎ here, ↗ elsewhere, ⓘ follows) are right.
- Direction: over time, pull the "elsewhere" edits onto the Gall page where it makes sense: the image manager, the range (exclusions) editor and the Gallformers note editor become components opened as dialogs on the page, not dedicated pages.
- Name parts and the Gallformers code move onto the Gall page, keeping exactly the strict logic already implemented (name parts: `Catalog.update_name_parts/3` and its derivation and name-taken checks; code: `Catalog.gallformers_code_taken?/2`, confirmation because iNaturalist and outside references use it), just moved.


#### Change-set back end handed off (2026-11-06)

Jeff chose option B: the ingestion agent builds the change-set back end (store, preview, apply); this worktree builds the UI on it. The interface the UI needs is written into matter ec2c (main checkout), section "Hand-off: the change-set back end". Meanwhile here: UI pieces that don't need it (the tray bar and Review and apply as components with test data; Edit-mode rows), built against that interface.


### Curation components built (2026-11-06)

Against the settled change-set contract (matter ec2c, "Change-set interface"), with sample data, before the back end exists: `GallformersWeb.CurationComponents` (`edit_toggle`, `edit_scope`, `fact_row`, `change_tray`, `review_apply`; imported in every template; catalog section "Inline editing"; style guide examples) and `GallformersWeb.FactKey` (contract keys as strings for page events). Assumed flag shape `%{kind, text}` noted in ec2c for the ingestion agent. The Gall edit mockup now uses the real `edit_scope`. Fixed a latent flake: `AuditFixtures` ids are now monotonic (the change log orders by transaction id). Precommit clean.

**Next:** wire Edit mode into `GallLive` (Inducer, Hosts, Traits, common names as `fact_row`s; name parts and code moved in with their checks; edit_scope markers) and a tray LiveView (indicator on every page, Review and apply) once `Gallformers.Curation` lands on this branch.


### 2026-11-06: content admins converted

Glossary, Articles, Keys, Users, Ops, Profile and Vocabulary are on the admin list and edit patterns (page_header, data_table, gf-with-rail, danger panel). Deletes moved off the lists onto the edit pages' danger panels; the typed-title confirmation is unchanged. Articles' Edit/Preview tabs became a Preview / Back to editing button (same `switch_tab` events); its image browser, insert and delete-image panels became `dialog`s. The keys list no longer loads every key to count couplets.

Shared components restyled to tokens: `input` (labels, required mark, errors), `toggle` (role=switch, token track; legacy CSS removed), `dangerous_delete_modal` (now a `dialog`, so keys, taxonomy and articles all get it), new `.gf-file`. Baseline 1,850 → 1,492.

Left in content admin: `ContentImageManager` (articles, keys; 35 findings). The vocabulary page's review components belong to the import review.

Test DB: `gallformers_test` is shared by every checkout. A concurrent run in the main checkout caused a deadlock (names_step_test) and the snapshot test fails on its new tables (change_sets, change_set_items, fact_notes, taxon_notes). Needs a per-checkout test DB (decision for Jeff).


### 2026-11-06: a test database per checkout

`config/test_db_names.exs` names the test databases: `gallformers_test` / `wcvp_test` in the main checkout and CI, `gallformers_test_<worktree>` / `wcvp_test_<worktree>` in `.worktrees/<worktree>`. Read by `config/test.exs`, the Makefile (`test-db`, `load-prod-data-test`) and the WCVP build test. This worktree now runs on its own; precommit clean (3,560 tests).


### 2026-11-06: Edit mode wired to `Gallformers.Curation` (Hosts and Traits first)

taxogall's change-set commit (e741f848) fast-forwarded in; dev DB `gallformers_taxogall` migrated (the dev server uses it).

- `UserAuth.curator/1` and `on_mount(:fetch_curator)` on the public session: an admin's `Actor` (`:curator`), nil otherwise.
- `GallformersWeb.TrayLive`: sticky LiveView in the root layout beside the palette, curators only. The bar while the set holds items, PubSub-fed; Review and apply dialog (`review_apply` with the back end's flags; take out, confirm, apply one, apply all; evidence once: why, observation links parsed for iNaturalist/BugGuide, a Source by title); Discard with a confirmation; held reasons shown after apply.
- `GallLive`: `?edit` for curators; the Edit switch replaces the old admin link (the admin page is linked from Edit mode's ↗ note). `GallLive.Editor` (LiveComponent) replaces Hosts and Traits in Edit mode: Inducer (Note…; correcting it is taxonomy), Hosts (Withdraw / Correct… with a plant picker / Note…; Add a host), Traits (`fact_chip` ✕ withdraw, + Add per Trait). Marks what's in the tray; refreshed on PubSub; names other curators' unapplied changes here.
- New: `fact_chip`; `fact_row` `target`; `review_apply` Source typeahead. Sources per Fact labelled from the attributions ("Weld (1959)").
- Next: the editorial panel (completeness, abundance, code and name parts with their checks), common names, then pulling photos, range exclusions and the ID note in as dialogs. Keep `/dev/mockups/gall-edit` until then.
- For the back end (relay to the ingestion agent): withdrawing a Fact only Gallformers states (the migrated data) is flagged "supersedes" and needs a reason; and the wording says "Gallformers's" (should be "Gallformers'").


### 2026-11-06: Edit mode's editorial panel

taxogall merged again (through 2539dc67: Add from observation back end; no reason needed to withdraw Gallformers' own statements). `GallLive.Editor` gains the Editorial panel (the mockup's): Completeness (Mark complete / in progress; disabled with the reason when `Catalog.datacomplete_lock/1` locks it), Abundance (select), the Gallformers code (dialog; another Gall's code refused as you type, `Catalog.gallformers_code_taken?/2`; blank removes it; confirmation at Review), Name parts (dialog: derived name, name shown, name taken, Host qualifier picker). The name logic moved out of the admin Gall page into `GallformersWeb.GallNameParts`, which both pages use. Each field marks "in your tray". `GallLive` reloads the Gall when the tray changes, so applied edits show at once. Review styles the new `:adds_statement` flag as info (each flag carries `data-flag`, `data-variant`). Precommit clean (3,678 tests).


## Handoff (2026-11-06): what is done, what is left

**Done: the system and its enforcement.** CLAUDE.md sends every UI change to `docs/design-system/` (README: five rules, where things live, replacing a component, adding to the system, the conformance ratchet; foundations, components catalog, patterns, content, mockups, inventory). The style guide `/dev/design-system` has an entry for every built component. `conformance_test.exs` fails on any new off-system styling (baseline in `test/support/design_system_baseline.json`, relock after every reduction). Public pages are on the system, in light and dark.

**Left: the migration.** ~1,500 off-system findings remain, nearly all admin (largest: `review_components.ex`, `images_component.ex`, `host_range_live.ex`, `country_drill_down.ex`, `powo_diff_review.ex`, the taxonomy admin pages, the admin Gall page, the Source admin, `content_image_manager.ex`, `inat_import_component.ex`). Legacy components still in use: `modal` (→ `dialog`), `card` (→ `panel`), `.header` (→ `page_header`), `.table` (→ `data_table`), `multi_select_dropdown` (→ `typeahead`, approved consolidation). The admin shell is pinned light until its pages are on tokens; then drop `data-theme="light"` from `Layouts.admin`.

**Left: Edit mode (ec2c).** On the Gall page: common names; the lead Source; photos, range exclusions and the ID note as dialogs (then delete `/dev/mockups/gall-edit`). Add from observation (back end built: `Curation.from_observation/3`). Palette commands still to wire: "Add from observation…", "Review: <Source>". Dashboard: "Your changes"; remove the Find panel once Edit mode covers it. Swap `Curation.Wording` for `Audit.ChangeLog`'s phrasing. Plant pages' Edit mode (editorial). Deletes and merges when taxogall lands them (the public Gall page calls the redirect lookup).


### Handoff update (2026-11-06, later): admin migration done

- **Admin Gall pages deleted.** `/admin/galls` and `/admin/galls/:id` are gone (301 to `/galls` and `/gall/:id?edit`). Their parts moved onto the Gall page's Edit mode: photos (the image manager in a panel: it has dialogs of its own), the ID note (dialog, saved at once as before), range exclusions (dialog with the map and drill-down, `GallLive.RangeEdit`; now into the tray as Fact items, `RangeExclusions.batch/4` removed), the lead Source (tray). Common names added to Edit mode. The Gall-edit mockup is deleted.
- **Admin on the design system.** Six parallel agents converted review components and screens, taxonomy, host ranges and drill-downs, the image managers, the Source admin and the shared components; the lead removed `admin_edit_layout`, `modal`, `badge`, `card`, `error_message`, `info_tip`, `show_modal`/`hide_modal`, moved the review pages' breadcrumbs into `page_header`, added `--spacing-reader`, put the upload hooks on tokens, moved the still-used legacy rules into `components.css` on tokens and deleted `legacy.css` and the legacy palette. **Baseline 1,850 → 15** (the rest are intentional: the conformance module's own rules, the HTML head's theme colours, the unsupported-browser banner and the read-only plug's plain-HTML page, one radius on the profile's prefixed input).
- **Dark mode on for admin**, with the theme switch in its top bar; the sidebar logo swaps to white.
- **Behaviour/look changes made during the migration, for Jeff to review:** image manager copy-mode controls moved above the table, row tints gone, table rows lost `data-image-id`, hover actions also on keyboard focus, info tips shown as help lines, "Delete image" wording; host range select-all above the table (not in the header); country drill-down Native/Introduced as a switch, rows marked by swatch and hatch rather than green/amber; the discard dialog's wording ("Discard your changes?", "Keep editing", "Discard changes"); Retracted/Complete chips on the Source edit page; notices now carry role status/alert; card titles no longer on a sky band.
- **Components the agents needed and hand-built from tokens (candidates to build):** a segmented switch (three hand copies of `view_switch`); a progress bar; `file_drop` (approved, unbuilt); `data_table` per-row attributes and state, header select-all, and a `select` event that can target a LiveComponent; a `loading_spinner` colour for primary buttons; a "recommended" chip variant; radio-card options for the review.
