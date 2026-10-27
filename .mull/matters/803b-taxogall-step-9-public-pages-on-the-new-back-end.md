---
status: planned
created: 2026-10-26
updated: 2026-10-26
epic: taxonomy
relates: [50ff, b5bd, 9449, 86e7]
---

# Taxogall step 9: public pages on the new back-end

# Taxogall step 9: public pages on the new back-end

`50ff` step 9 (`b5bd` M3): every public page and the API read the new back-end (`Catalog`, `Taxa`, `Facts`, `Sources`) instead of the old "everything is a species" tables. Design agreed with Jeff on 2026-10-26.

## Scope (inventory, 2026-10-26)

Every public read still goes to the old tables; nothing in `gallformers_web` calls the new contexts yet. Affected: about 7,300 lines of public LiveViews and API controllers, reading through about 4,000 lines of old read functions (`Galls`, `Galls.Identification`, `Plants`, `Species`, `Taxonomy`, `Search`, `Ranges`, `Images`, `FilterFields`, and the two old readers in `Sources`).

| Page | Module | Old reads |
|---|---|---|
| Gall | `gall_live.ex` (833) | gall, Hosts, images, Sources, aliases, display range, Trait values, related galls, taxonomy path |
| Host | `host_live.ex` (790) | host, its galls, images, Sources, aliases, host range, taxonomy path |
| Taxon ranks | `family_live`, `genus_live`, `section_live`, `intermediate_live` | taxonomy lookups, lineage, children with counts, species of a genus/section, associated genera; gall vs host genus from the first species' taxoncode |
| Source | `source_live.ex` | species of a Source, images of a Source |
| Browse | `galls_browse_live`, `hosts_browse_live` | raw recursive SQL trees over taxonomy and species |
| ID tool | `id_live.ex` (1,519) + `Galls.Identification` (627) | everything, live, no cache; images of every gall on each filter change; N+1 summaries |
| Search | `search_live.ex`, `API.SearchController` | ILIKE over species, aliases, taxonomy, glossary, Sources, places; continent filter over ranges |
| Home, about, stats | `home_live`, `about_controller`, `API.StatsController` | random gall, counts, host typeahead, family/genus counts |
| Sitemap | `sitemap_controller.ex` | inline Ecto queries over species and taxonomy |
| Redirects | `redirect_controller.ex` | `/taxonomy/:id` through the old taxonomy table |
| Filter guide | `filter_guide_controller.ex` | old Trait vocabulary tables |
| API v2 | gall, host, taxonomy, source, stats, search controllers; `schemas/api_schemas.ex` | as the pages |

Not affected: places, glossary, articles, keys (beyond embedded gall IDs, which are kept), user profiles, analytics. No public LiveView subscribes to PubSub; no search index, materialized view or ID cache exists.

## Design

### Approach

One page at a time (approach A, Jeff 2026-10-26): add the read functions a page needs to `Catalog` / `Taxa`, point the page at them, port its tests, and delete each old read function in the commit that removes its last caller. Every page step is a working, committable state. Rejected: building every read function first (designed before its consumer; nothing works end to end until late) and an adapter returning the old data shapes (the facade dropped in `8567` *Build approach*).

Order: Gall page (touches most of the model, so it tests the design first) → Host → taxon ranks and browse trees → Source → ID tool (with its stored lookup table) → global search → home, about, stats, sitemap, redirects, filter guide → API v2.

### 1. Data while building

- **Local development** runs against `gallformers_taxogall`, the converted production copy (clone a fresh download, apply migrations, `MIX_ENV=dev PGDATABASE=gallformers_taxogall mix gallformers.catalog.migrate --no-s3`, about 3 minutes).
- **Automated tests** use a small set of seeds, grown as needed (Jeff): `make test-db` loads the old seeds and then runs the catalog migration over them (tried 2026-10-26: reconciles clean; 6 galls, 9 plants). Each page step adds the old-style seed rows for the cases it tests (generation pairs, gall forms, images, notes, citations first). At release (M7) the converted tables become the new seed file.
- **`:prod_data` tests** (old-schema invariants and old writes) are rewritten as new-schema invariants (every Gall named, no taxon cycles, every Host a plant taxon, …) against the converted copy, late in step 9.

### 2. Read functions

- Pages call only `Catalog` and `Taxa` public functions (Boundary exports), each shaped for the page that uses it. Nothing in `gallformers_web` reads tables directly (the sitemap controller does today).
- Built on the existing read models: `GallSummary` (current Inducer, Hosts, Traits) and `PotentialRange`.
- **Sources on pages stay as today** (Jeff): the Gallformers note and the legacy citations. Per-Fact attributions are loaded by the read functions but not shown; per-Fact Source display is designed after the backscan, against real data.
- Shared components (maps, trees, cards, galleries) are reused; templates change only where the data's shape does.
- Old write code used by the old admin stays until step 10.

### 3. ID tool

- **A stored per-Gall lookup table:** Inducer and its family/genus, Host taxa with their genera and families, Trait values, detachable, undescribed, default image, and the place IDs of the potential range (empty = every region). Filtering is one query over it.
- **Refreshed** by an Oban job when a Gall's Facts or its taxa change; fully rebuilt at the end of the data migration. `PotentialRange` stays the one definition of a range; the table stores its result.
- **Bookmarks:** old Trait filter parameters (`co`, `sh`, `fo`, `se`, …) hold old vocabulary row IDs, translated by a small fixed file generated once from the old vocabulary tables; new URLs use readable values. `fa` (old taxonomy ID) goes through `legacy_taxon_ids`; an unknown ID is ignored, never matched to another taxon. `ng` (show non-galls) is ignored. The v1 parameter mapping stays.
- **Parity check** on a sample of real queries. Expected differences only: Galls gain their Hosts' introduced ranges, and every Gall's range is its Hosts' whole WCVP range except the range-confirmed Galls (`b5bd` M5).

### 4. URLs and redirects

- `/gall/:id` and `/host/:id` keep their IDs; key links keep working.
- Taxon pages (`/family/:name`, `/genus/:name`, `/section/:name`, intermediate ranks) look names up in `Taxa`. A genus with both galls and Hosts shows both lists.
- `/taxonomy/:id` through `legacy_taxon_ids`.
- The 128 non-gall URLs redirect to a gall-lookalikes Article (Jeff or Adam write it; a short placeholder Article until then).
- The sitemap is built from `Catalog` and `Taxa`.

### 5. API v2

- Keeps today's response shapes; fields keep their names with the nearest new meaning (`taxoncode` stays "gall" / "plant").
- Gall and Host IDs are unchanged; higher-taxon IDs change (`/families/:id` etc. answer to the new IDs, documented). Traffic is trivial (`b5bd` M3).
- `/galls/:id/sources` returns the Gallformers note and the legacy citations.

## Implementation Plan

**Goal:** every public page, the sitemap, redirects and API v2 read `Catalog` / `Taxa` / `Sources` (new tables) instead of the old species tables, with today's URLs and behaviour kept except the decided differences.

**Architecture:** one page at a time. Each page gets read functions in `Catalog` (Galls and their Facts; may call `Taxa`) or `Taxa` (taxa, names, trees; never calls `Catalog`), shaped for the page, built on `GallSummary`, `PotentialRange` and `Current`. The ID tool and search read a stored per-Gall lookup table refreshed by Oban. Old read functions are deleted in the commit that removes their last caller; functions the old admin still calls stay until step 10.

**Tech stack:** Phoenix LiveView, Ecto/PostgreSQL, Oban, Boundary, OpenApiSpex; tests with `Phoenix.LiveViewTest` against seeds converted by the real catalog migration.

**Standing rules for every task:**
- TDD: write the failing test first. Page tests use the converted seeds plus in-test fixtures (`CatalogFixtures`, `TaxaFixtures`); a test that needs a new seed case adds old-style rows to `priv/repo/test_seeds.sql` (the migration converts them).
- Pages call only exported `Catalog` / `Taxa` / `Sources` / `Images` / `Ranges` / `Places` functions; no inline Ecto in `gallformers_web`.
- After switching a page, find old read functions with no caller left (`mix xref callers <Module>` / ElixirLS) and delete them with their tests in the same commit. Old functions the admin still calls stay.
- `mix precommit` passes on every commit (warnings as errors, credo strict).
- On the branch, the old admin still writes the old tables, so admin edits don't show on re-pointed pages until step 10 (expected; not a bug).

### Task 1: Test data through the real migration

**Files:**
- Modify: `lib/mix/tasks/gallformers/catalog/migrate.ex` (`--curated DIR`: every curated input and the name-suffix file read from `DIR/<input>.csv` / `DIR/name_suffixes.csv` when present)
- Create: `test/support/fixtures/catalog_migration/` — `name_suffixes.csv` (the token rows only), `non_galls.csv`, `range_decisions.csv`, `aliases.csv`, `keys.csv`, `taxon_merges.csv`, `kingdoms.csv` (headers plus the decisions the seeds need)
- Modify: `Makefile` (`test-db`: after loading the seeds, `MIX_ENV=test mix gallformers.catalog.migrate --curated test/support/fixtures/catalog_migration --no-s3`, strict), `.github/workflows/ci.yml` (same step after `test_seeds.sql`)
- Modify: `priv/repo/test_seeds.sql` (cases the pages need: an agamic/sexgen pair of one species with genus and family links; a gall form pair like `N. saltatorius (australis) (agamic)`; an undescribed gall in a real genus; a gall with a Gallformers note (Source 58 `species_source`) and another Source citation; an image on a gall and on a host; a common and a scientific alias; a host in a real genus with `host_range` rows, native and introduced)
- Test: `test/gallformers/catalog_migration/test_seeds_test.exs`

**Behavior:** `make test-db` and CI build a test database whose new tables are the migration of the seeds, so page tests read converted data. The shipped curated CSVs hold production IDs that can collide with seed IDs (a shipped non-gall exclusion would silently drop a seed gall), so the test run reads its own curated directory.

**Testing:** `--curated` reads every file from the directory and falls back to the shipped file only for a missing one; the seeds convert (each seed gall is a Gall with its Inducer link at the right rank; the generation pair shares one Inducer; the note is a `source_documents` note; the citation is a `legacy_citations` row; images carry `gall_id` / `taxon_id`); a strict run has 0 pending.

**Notes:** Catalog-migration tests that call `CatalogMigration.run/1` delete and rebuild the new tables inside their sandbox transaction; if they block async page tests on row locks, make those test modules `async: false`. Dev setup is unchanged: the local server runs with `PGDATABASE=gallformers_taxogall`.

### Task 2: Ranges and images by the new references

**Files:**
- Modify: `lib/gallformers/ranges.ex` (`get_display_range_for_taxa/1`: the `%DisplayRange{}` split — `in_range`, `inherited_range`, `introduced_range` — of `host_range` rows by `taxon_id`, reusing today's split logic), `lib/gallformers/images.ex` (`list_images_for_gall/1`, `list_images_for_taxon/1` by `image.gall_id` / `image.taxon_id`; `list_images_for_source/1` ordering by Gall display name / taxon name instead of `species`)
- Modify: `lib/gallformers/catalog.ex` (`display_range(gall_id)`: the Hosts' display split from `Ranges.get_display_range_for_taxa/1` for the current `host_of` taxa, minus current `exclude` Facts, restricted by `only`; `:everywhere` when `PotentialRange` says so)
- Test: `test/gallformers/ranges_test.exs`, `test/gallformers/images_test.exs`, `test/gallformers/catalog/display_range_test.exs`

**Behavior:** maps keep their exact / inherited / introduced colouring. `PotentialRange` stays the one definition of a Gall's range: the display range is a presentation of the same set.

**Testing:** the display range's places equal `PotentialRange.for_gall/1` (as sets) for: Hosts with exact rows, a country-level row, introduced rows, an `exclude`, an `only`, no Hosts (`:everywhere`); images by gall and by taxon; source images order by name.

### Task 3: Gall page read function

**Files:**
- Create: `lib/gallformers/catalog/read_models/gall_page.ex`
- Modify: `lib/gallformers/catalog.ex` (`gall_page(id)` → `{:ok, GallPage.t()} | :not_found`; export the struct), `lib/gallformers/taxa.ex` (`lineage(taxon_id)`: ancestors root-first with rank and accepted name, if not covered by `ancestors/1`; `list_synonyms(taxon_id)`)
- Test: `test/gallformers/catalog/gall_page_test.exs`

**Behavior:** everything the Gall page shows, in one struct:
- the Gall: display name, Gallformers Code, abundance, `datacomplete`, generation value and its definition;
- `undescribed?`: no current species-rank Inducer;
- the Inducer (`GallSummary.inducers`) with its lineage for the taxonomy breadcrumb;
- Hosts, each with its link target (a species-rank plant → `/host/:id`; a genus Host, today's placeholder → `/genus/:name`);
- Traits by Trait (`GallSummary.traits`) in the shape the template and `Galls.Summary` need;
- names: current gall alias Facts (common names, former labels) and the Inducer's synonyms;
- related Galls: other Galls with the same current Inducer (alternate generations and forms), replacing today's name-prefix match;
- Sources: the newest Gallformers note's text (`Sources.list_gall_notes/1`, its item text) and the legacy citations with their Sources (`useasdefault` first, as today; Source 58 sorts as today);
- images (`Images.list_images_for_gall/1`) and the display range (Task 2).
Each Fact's attributions are loaded and carried in the struct but not rendered.

**Testing:** a described gall with an Inducer, Hosts, Traits and range; an undescribed gall (genus Inducer) is `undescribed?`; a genus Host links to the genus page; the generation pair lists each other as related; the gall form pair too; a gall with no Inducer; the note text and the citations in today's order; `:not_found` for a missing ID and for a non-gall ID.

### Task 4: Gall page re-pointed

**Files:**
- Modify: `lib/gallformers_web/live/gall_live.ex`, `lib/gallformers/galls/summary.ex` (take the new Traits map; keep it pure)
- Test: `test/gallformers_web/live/gall_live_test.exs` (ported), `test/gallformers/galls/summary_test.exs`

**Behavior:** `/gall/:id` renders from `Catalog.gall_page/1`; the page looks as today. `?source=` deep-linking works on legacy citations and the note. SEO description from the summary.

**Testing:** today's page tests, ported: rendering, page title, Host links (species and genus), Source links and `?source=`, images, undescribed indicator, iNaturalist link for an undescribed gall with a Code; related Galls; a 404 for a missing ID.

**Notes:** delete `Galls.get_related_galls/1`, `Galls.get_gall_filter_values/1` (if the ID tool no longer needs it after Task 10; else then), `Species.get_aliases_for_species/1`, `Sources.get_sources_for_species/1` and `Ranges.get_display_range_for_gall/1` when their last caller goes (the API uses some until Task 13).

### Task 5: Host page

**Files:**
- Create: `lib/gallformers/taxa/read_models/host_page.ex` (or in `Taxa` directly if small)
- Modify: `lib/gallformers/taxa.ex` (`host_page(id)`: plant taxon, accepted name, synonyms, common names, lineage), `lib/gallformers/catalog.ex` (`list_galls_for_hosts(taxon_ids)`: Gall cards for current `host_of`), `lib/gallformers_web/live/host_live.ex`
- Test: `test/gallformers/taxa/host_page_test.exs`, `test/gallformers_web/live/host_live_test.exs` (ported)

**Behavior:** `/host/:id` for a plant taxon (same IDs as today's plants). Galls on the host from current `host_of` Facts (a genus Host's galls appear on the genus page, Task 6). Images by `taxon_id`; range map from `Ranges.get_display_range_for_taxa([id])`. No Sources block: citations on plants were not migrated (dropped, decision 1 below).

**Testing:** ported page tests; synonyms and common names shown; galls listed by display name; 404 for a non-plant or missing ID.

### Task 6: Taxon rank pages and browse trees

**Files:**
- Modify: `lib/gallformers/taxa.ex` (`get_by_name(name, rank)`; `children_with_ranks(taxon_id)`; `lineage/1`; `plant_tree/0` — family → genus → species of Plantae), `lib/gallformers/catalog.ex` (`gall_tree/0` — Inducer family → genus → Galls, from current `inducer_of` and `Taxa` ancestry; `undescribed_gall_tree/0`; `count_galls_under(taxon_ids)` — Galls whose current Inducer is in each subtree; `list_galls_for_inducers(taxon_ids)`)
- Modify: `lib/gallformers_web/live/family_live.ex`, `genus_live.ex`, `section_live.ex`, `intermediate_live.ex`, `galls_browse_live.ex`, `hosts_browse_live.ex`
- Test: `test/gallformers/taxa/tree_pages_test.exs`, `test/gallformers/catalog/gall_tree_test.exs`, the six LiveView tests (ported)

**Behavior:** rank pages look up the taxon by name and rank. A genus page lists its Galls (Inducers in the genus, including undescribed Galls linked at the genus) **and** its host species (plants in the genus) when it has both; today it shows one or the other. Family and intermediate pages list children with gall / host counts. The browse trees come from `Catalog.gall_tree/0` and `Taxa.plant_tree/0` through today's `Taxonomy.TreeBuilder` shape (move the builder if it reads old tables).

**Testing:** family with children and counts; intermediate ranks; genus with galls only, hosts only, and both (Phoradendron-like); section; trees include the generation pair once per Gall; undescribed tree; unknown name → 404.

### Task 7: Source page

**Files:**
- Modify: `lib/gallformers/catalog.ex` (`list_galls_for_source(source_id)`: Galls with a legacy citation or a current attribution from that Source, by display name), `lib/gallformers_web/live/source_live.ex`
- Test: `test/gallformers/catalog/source_galls_test.exs`, `test/gallformers_web/live/source_live_test.exs` (create if missing)

**Behavior:** `/source/:id` lists the Galls citing it and the Source's images (Task 2). Source 58 (Gallformers) lists the Galls with a note.

**Testing:** a Source with legacy citations; a Source attributing Facts only; Source 58; images listed.

### Task 8: Stored per-Gall lookup table

**Files:**
- Create: `priv/repo/migrations/<ts>_create_gall_index.exs` (one row per Gall: `gall_id`, `name`, `inducer_taxon_id`, `inducer_ancestor_ids[]`, `host_taxon_ids[]`, `host_ancestor_ids[]` (genera and families of the Hosts), `trait_value_ids[]`, `detachable`, `undescribed`, `image_id`, `place_ids[]` (leaf places of the potential range; empty = everywhere), `everywhere` boolean; GIN indexes on the arrays)
- Create: `lib/gallformers/catalog/read_models/gall_index.ex` (`refresh(gall_ids)`, `rebuild_all/0`), `lib/gallformers/catalog/read_models/gall_index_worker.ex` (Oban, unique per Gall, queue `catalog`)
- Create: `lib/gallformers/facts/events.ex` (behaviour: `facts_changed(fact_ids)`, listener from config, called after standings are stored, like `Taxa.Events`), `lib/gallformers/catalog/fact_listener.ex` (maps Fact IDs to Gall IDs, enqueues the worker)
- Modify: `lib/gallformers/facts.ex` (call the listener), `lib/gallformers/catalog/taxon_listener.ex` (on `:move` / `:rename`, enqueue the Galls whose Inducer or Host is in the subtree), `lib/gallformers/catalog_migration.ex` (`rebuild_all` at the end), `config/config.exs` (listener, queue), `priv/snapshot/tables.txt` (public)
- Test: `test/gallformers/catalog/gall_index_test.exs`

**Behavior:** the ID tool and search filter one table. `place_ids` is `PotentialRange.for_gall/1`'s result (never re-derived). A Fact change or a taxon move/rename refreshes the affected rows asynchronously; the migration rebuilds everything.

**Testing:** a row matches `GallSummary` + `PotentialRange` for a fixture Gall; `everywhere` for a Gall without Host ranges; asserting a Host enqueues a refresh for its Gall; denying it (standing change) removes the Host on refresh; moving the Inducer's genus updates `inducer_ancestor_ids`; `rebuild_all` covers every Gall.

### Task 9: ID tool query, filter options and bookmark translation

**Files:**
- Create: `lib/gallformers/catalog/identify.ex` (`Catalog.identify(filters)`, `Catalog.count_identified(filters)`, `Catalog.identify_options/0`)
- Create: `lib/mix/tasks/gallformers/catalog/export_legacy_trait_ids.ex` and its output `priv/catalog_migration/legacy_trait_ids.csv` (`table, old_id, trait, value`; generated once from the old vocabulary tables while they exist, then committed)
- Modify: `lib/gallformers/taxa.ex` (`search_plants(q, limit)` over accepted names, synonyms and common names; `search_genera_and_sections(q, limit, kingdom: "Plantae")`), `lib/gallformers/catalog.ex` (`gall_families_for_hosts(taxon_ids)`)
- Create: `lib/mix/tasks/gallformers/catalog/id_parity.ex` (runs a sample of real filter sets through `Galls.Identification` and `Catalog.identify` on the converted copy; prints differences classed as expected — introduced range, Hosts' whole WCVP range — or unexpected)
- Test: `test/gallformers/catalog/identify_test.exs`, `test/mix/tasks/gallformers/catalog/export_legacy_trait_ids_test.exs`

**Behavior:** filters over `gall_index`: Host (taxon, matching its genus Host too, as today's genus-placeholder rule), genus / section of the Host, Inducer family, each Trait (plant part and texture with AND/OR logic as today), detachable, undescribed, place (a Gall matches if `everywhere` or its `place_ids` meet the place's leaves). Non-galls no longer exist. Results carry the default image and summary without per-Gall queries.

**Testing:** each filter alone; combined filters; place with an `everywhere` Gall; AND/OR for plant parts; Host genus matches a Gall whose Host is the genus; the result count without the place filter; legacy trait IDs map to values; parity task runs on fixtures.

**Notes:** run the parity task on `gallformers_taxogall` and record the result in this matter before Task 10 deletes `Galls.Identification`.

### Task 10: ID tool page and filter guide re-pointed

**Files:**
- Modify: `lib/gallformers_web/live/id_live.ex`, `lib/gallformers_web/controllers/filter_guide_controller.ex` (definitions from `Catalog.list_trait_values/0`)
- Test: `test/gallformers_web/live/id_live_test.exs` (ported), `test/gallformers_web/controllers/filter_guide_controller_test.exs`

**Behavior:** the page reads `Catalog.identify*` and the `Taxa` typeaheads. URLs write readable Trait values; old integer Trait parameters translate through `legacy_trait_ids.csv`; `fa` goes through `Taxa.get_by_legacy_id(:taxonomy, id)` and an unknown ID is dropped; `ng` is ignored; the v1 mapping stays. Season filter label reads "forms and grows" (contract wording).

**Testing:** ported filter tests; an old bookmark with integer Trait IDs and an old `fa` restores the same filters; an unknown `fa` is ignored; `ng=1` is harmless; v1 parameters still work.

**Notes:** delete `Galls.Identification`, `FilterFields` and the old vocabulary readers once nothing calls them (the admin may still use `FilterFields`).

### Task 11: Global search

**Files:**
- Modify: `lib/gallformers/search.ex` (gall and taxon parts read `Catalog.search_galls/2` and `Taxa.search/2`; glossary, Sources and places unchanged; continent filter through `gall_index.place_ids` and `host_range.taxon_id`), `lib/gallformers/catalog.ex` (`search_galls(q, opts)`: display name, alias Facts, Inducer accepted name and synonyms), `lib/gallformers/taxa.ex` (`search(q, opts)`: accepted names, synonyms, common names, by rank and kingdom)
- Modify: `lib/gallformers_web/live/search_live.ex`, `lib/gallformers_web/controllers/api/search_controller.ex`
- Test: `test/gallformers/search_test.exs` (ported), `test/gallformers_web/live/search_live_test.exs`, `test/gallformers_web/controllers/api/search_controller_test.exs`

**Behavior:** same results page and ranking (`Search.Ranking`); a synonym or common name finds its taxon; an old gall name (alias Fact or Inducer synonym) finds the Gall; continent filter keeps `everywhere` Galls.

**Testing:** ported search tests; synonym hit; gall alias hit; a name shared by two taxa returns both; continent filter.

### Task 12: Home, about, stats, sitemap, redirects

**Files:**
- Modify: `lib/gallformers_web/live/home_live.ex` (random Gall with an image; counts; host picker via `Taxa.search_plants/2`), `lib/gallformers_web/controllers/about_controller.ex`, `lib/gallformers_web/controllers/sitemap_controller.ex` (Galls, plants, taxa by rank, places, Sources through context functions), `lib/gallformers_web/controllers/redirect_controller.ex` (`/taxonomy/:id` through `legacy_taxon_ids`)
- Create: `priv/repo/migrations/<ts>_create_non_gall_redirects.exs` (`species_id`, `name`) written by the data migration for every excluded non-gall; `/gall/:id` for such an ID redirects (301) to `/articles/gall-lookalikes`
- Old genus-placeholder plant URLs (`/host/:id` of the 159 "Genus spp" rows, which have no taxon): the data migration records each placeholder's species ID against its genus taxon (e.g. a `legacy_taxon_ids` kind `:genus_placeholder`), and `/host/:id` for such an ID redirects (301) to the genus page (found by Task 5)
- Create: a placeholder `gall-lookalikes` Article (data migration inserting it only if missing; Jeff or Adam replace the text)
- Modify: `lib/gallformers/catalog_migration/non_galls.ex` (write the redirect rows)
- Test: `test/gallformers_web/live/home_live_test.exs`, `test/gallformers_web/controllers/about_controller_test.exs`, `test/gallformers_web/controllers/sitemap_controller_test.exs`, `test/gallformers_web/live/taxonomy_redirect_test.exs`, `test/gallformers_web/live/gall_live_test.exs` (non-gall redirect)

**Behavior:** counts come from `Catalog` / `Taxa` (Galls, undescribed Galls, plants, families and genera with galls, Sources, images). The sitemap lists every Gall, plant, rank page, place and Source URL.

**Testing:** counts on seeds; sitemap contains a Gall, a plant, a family, a genus, a section URL; `/taxonomy/:old_id` redirects to the right rank page and 404s for an unknown ID; a non-gall ID redirects to the Article.

### Task 13: API v2

**Files:**
- Modify: `lib/gallformers_web/controllers/api/gall_controller.ex`, `host_controller.ex`, `taxonomy_controller.ex`, `source_controller.ex`, `stats_controller.ex`, `lib/gallformers_web/schemas/api_schemas.ex` (descriptions: higher-taxon IDs are new IDs)
- Modify: `lib/gallformers/catalog.ex` / `lib/gallformers/taxa.ex` (paginated list and count functions the controllers need)
- Test: the four API controller tests (ported), plus `source_controller_test.exs` and `stats_controller_test.exs`

**Behavior:** same paths and response shapes; fields keep names with the nearest new meaning; `/galls/:id/sources` returns the note and legacy citations; taxonomy endpoints use new taxon IDs.

**Testing:** ported tests; response shapes validate against the OpenAPI schemas (`OpenApiSpex.TestAssertions`).

### Task 14: End-to-end and production-data tests; final sweep

**Files:**
- Modify: `test/e2e/browse/browse_test.exs`, `test/e2e/search/search_test.exs` (pick IDs from `Catalog` / `Taxa`)
- Replace: `test/prod_data/invariants_test.exs` with new-schema invariants (every Gall has a display name; no taxon cycles and ancestry matches `parent_id`; every current Host is a Plantae taxon; every Gall's current Inducer count ≤ 1 or flagged; every `gall_index` row matches `PotentialRange` on a sample; every legacy citation's Source exists); `test/prod_data/write_operations_test.exs` stays only for old-admin writes still in use, else goes with step 10
- Modify: `test/support/prod_data_case.ex` (the "≥ 1000 species" check becomes ≥ 1000 Galls)
- Sweep: `mix xref` — no module in `lib/gallformers_web` outside `live/admin` and admin controllers calls `Galls`, `Plants`, `Species`, `Taxonomy`, `Ranges` (old readers), `Search` old parts or `FilterFields`; delete what has no callers.

**Testing:** `make e2e` and the `:prod_data` suite pass against the converted copy.

## Decisions during planning (Jeff, 2026-10-26)

1. **Plant Sources are dropped (Task 5):** the Host page has no Sources block. Only 6 citations sit on plants (Chromolaena odorata — Source 834; Quercus alba — Gallformers ID Notes; Quercus berberidifolia — Gallformers ID Notes, Sources 643 and 642; Quercus bicolor — Source 56); the rest of the "citations on species that are not Galls" are on excluded non-galls.
2. **ID tool place-match tags are dropped (Task 10):** every match is the potential range; results carry no `documented` / `country_level` / `genus_placeholder` marker.
3. **Default description (Jeff, 2026-10-26):** each Gall gets an editorial `default_source_id` (nullable), filled by the migration from today's `species_source.useasdefault` — note or citation alike. 88 Galls lead with their Gallformers note today; the migration had kept the flag on citations only. The Gall page leads with that Source.
4. **Alias Facts get a `kind` (Jeff, 2026-10-26):** `common_name | former_label | code` on `alias_facts` (not part of the natural key, Gall + name). The migration sets it from the `aliases.csv` decision; imports from the contract are `common_name`. The Gall page shows common names under Common Name(s) and former labels / codes in the names table.
6. **Plant editorial flags carried over (Jeff, 2026-10-26):** plant `datacomplete` (112 plants) and `abundance_id` (114) become editorial fields on plant taxa, filled by the migration; the Host page shows the data-complete badge and Abundance line as today.
7. **Taxonomy descriptions (Jeff, 2026-10-26):** old `taxonomy.description` on genera, sections and intermediate ranks (165, mostly common names like "Elms") become common names of the taxon; family descriptions (264 types: Wasp, Midge, Plant, …) are dropped — the kingdom now tells plant from gall families.
8. **A genus Host's range is the union of its species' ranges (Jeff, 2026-10-26, option B):** a Gall whose Host is a genus (today's "Genus spp" placeholder) can occur wherever any species of that genus grows — the union of the host ranges of every plant taxon in the genus's subtree (plus any rows stored on the genus itself). Replaces "only the placeholder's own range rows", which lost 12 parity matches (e.g. *Xanthoteras pumiliventris* (sexgen) on "Quercus spp" in El Salvador). Implement in `PotentialRange` (`for_galls/1`), so `gall_index`, the display range and the ID tool follow; re-run the parity check (placeholder_waiver should drop to 0 or near it).
5. **Label synonyms corrected (2026-10-26, found by the Gall page check):** 46 gall "scientific" aliases that are Gallformers labels ("Unknown q-…", host-code epithets like "Andricus q-laceyi-midrib-cluster", "Feron quercus-pot-gall", "… on Juniper") had become Inducer synonyms; `aliases.csv` now makes them former labels (rule 3). "Andricus sp. E" → former label; "refdfd" → dropped. Historical hyphenated binomials (*Cynips quercus-batatus*) stay synonyms.


## Status

**All 14 tasks built (2026-10-27), uncommitted on `taxogall`.** `mix precommit` green (2,699 tests), `MIX_ENV=dev mix dialyzer` 0 errors. Rehearsal on `gallformers_taxogall` strict and clean (incl. 128 non-gall redirects, 159 genus-placeholder redirects, the gall-lookalikes Article, `gall_index` 3,976). `:prod_data` suite 28/28 on a copy of the converted database (`make test-prod-data PROD_DATA_DB=gallformers_taxogall`; e2e: `make e2e PROD_DATA_DB=gallformers_taxogall`).
- Tasks 11–13 (2026-10-27): global search (`Catalog.search_galls/2`, `Taxa.search/2`; Inducer names find Galls only at species rank and below), home/about/sitemap/redirects (`Plugs.LegacyEntityRedirect` for 301s; `non_gall_redirects` table; `legacy_taxon_ids` kind `:genus_placeholder`; the gall-lookalikes Article created by the data migration only if missing), API v2 (shapes kept; empty gall `places` = everywhere; higher-taxon IDs are new IDs; `gall_id` now emitted, `pubyear` a string).
- Task 14: e2e browse / integration tests on `Catalog`/`Taxa`; new-schema `:prod_data` invariants; `write_operations_test` kept (old-admin writes still live); `Makefile` `PROD_DATA_DB=` copies a converted database into `gallformers_test`; old read functions with no callers deleted. No old-domain callers remain outside the old admin; `Galls.Identification.filter_galls` stays for `id_parity` until cutover.
- **e2e browser suite fixed (2026-10-27):** it had broken since #593's lock refresh let npm `playwright` float to 1.62.0, which `playwright_ex` 0.5 / `phoenix_test_playwright` 0.13 couldn't parse. Upgraded `phoenix_test_playwright` 0.13 → 0.19, `playwright_ex` 0.5 → 0.15, `phoenix_test` 0.10 → 0.13.1 (lock change limited to these three) and npm `playwright` to `^1.64.1` (0.19's minimum). Two test fixes: the e2e Playwright timeout is 10 s (a Gall page on production data loads many remote images and map tiles past the 2 s default); `E2ECase.visit/2` now waits for the LiveView to connect, since a `phx-click` sent before the join is dropped (the section-delete test clicked too early). `make e2e PROD_DATA_DB=gallformers_taxogall`: 41 + 1 tests, 0 failures.

### History (paused 2026-10-26)

**Done, uncommitted on `taxogall`, `mix precommit` green (2,639 tests) as of the end of Task 9:** Tasks 1–9 and decisions 3–6.
- Task 1: `make test-db` / CI convert the seeds with the real migration (`--curated test/support/fixtures/catalog_migration`).
- Tasks 2–7: Gall, Host, Source, family / genus / section / intermediate pages and both browse trees read `Catalog` / `Taxa`.
- Tasks 8–9: `gall_index` table (refreshed by Oban via `Facts.Events` → `Catalog.FactListener`, and `TaxonListener`; rebuilt at the end of the catalog migration), `Catalog.identify*`, `Taxa.search_plants/2`, `Taxa.search_genera_and_sections/3`, `priv/catalog_migration/legacy_trait_ids.csv` (102 rows, generated from production's old vocabulary), `mix gallformers.catalog.id_parity`.
- Also fixed: tests counting audit rows count only their own transaction's (`DataCase.test_audit_changes/0`); never run `make test-db` while tests run.

**Rehearsal on `gallformers_taxogall` (2026-10-26, strict):** every reconciliation line balances; `gall_index` 3,976 = 3,976. ID parity: 347 filter sets, no unexpected differences — introduced 114, hosts_whole_range 48 (both decided), outside_hosts_range 9 (no-inclusions rule, `3272`), not_in_catalog 5 (excluded scale insects), placeholder_waiver 12 (open question below); 5 skipped (old family 442 has no taxon; old form "non-gall").

**Done 2026-10-27, `mix precommit` green (2,668 tests):** decision 7 (74 taxonomy descriptions → common names; 91 placeholder-genus descriptions skipped), decision 8 (genus Host range = union of its subtree's ranges, in `PotentialRange`; `TaxonListener` refreshes `gall_index` for Galls on genus Hosts above a moved taxon), Task 10 (ID tool page and filter guide on `Catalog.identify*` / `Taxa` typeaheads; bookmark tests for old Trait IDs, old `fa`, unknown IDs, v1 names). Kept on purpose: `Galls.Identification` (used by `mix gallformers.catalog.id_parity` until cutover) and `FilterFields` (admin filter-terms screens). Task 10's agent stopped on the account's weekly usage limit just after the page was written; I finished it (formatter + one credo fix) — review its diff once more on resume.
Rehearsal 2026-10-27: strict run clean, every line balances. Parity: 347 filter sets, 0 unexpected; introduced 113, hosts_whole_range 49, outside_hosts_range 9, not_in_catalog 5, placeholder_waiver 0.
Doubtful carried-over common names, for Jeff (not blocking): "Creeper" (Parthenocissus), "Plane" (Platanus), combined names ("Plums, Cherries, and Allies", "Rowans and Mountain Ash", "Aspens and White Poplars", "necklace or bigleaf poplars"), and "Bramble, cinquefoil, and rose inquiline gall wasps" (tribe Diastrophini).

**Remaining then:** Tasks 11–14 — done 2026-10-27 (see Status above).

