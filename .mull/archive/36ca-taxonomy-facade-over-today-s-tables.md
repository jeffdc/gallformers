---
status: dropped
created: 2026-10-06
updated: 2026-10-24
epic: taxonomy
relates: [8567]
---

# Taxonomy facade over today's tables

# Taxonomy facade over today's tables

Part of the owned-taxonomy plan (`8567`). **Goal:** make `Gallformers.Taxonomy` a black box over today's tables, so the gall split and the taxonomy rebuild (phase 2) change what's behind it, not its callers. **No behavior change.**

## Decisions (Jeff)

- **Ships to main** as an ordinary PR (branch from main, e.g. `taxonomy-facade`; then merge main into `taxogall`), keeping the long-lived branch from drifting on ~20 shared files. (2026-10-05)
- **The taxon identity layer is not part of this;** it is built with the gall split. Inducer taxa only exist once galls split and agamic/sexgen pairs merge, and nothing reads taxon IDs before then. (2026-10-05)
- **The rule-6 listener is built here,** with one real use. (2026-10-05)
- **Timing floats** (2026-10-06): nothing in the schema, converter, or trial work (`294c`, `b119`, `8546`) depends on it. Do it after the pipeline trial, or earlier as filler while waiting on Adam's trial batches — in any case before Sources–Facts. If the trial says no-go, no effort was spent on structure for a plan that changes.

## Findings that shape it (2026-10-05)

- Callers mostly use the context's ~60 public functions already. Leaks: the 14 internal-module references (experiment 1 in `8567`), raw `species_taxonomy` joins in `galls.ex`, `plants.ex` (3), `galls/identification.ex` (3), `search.ex`, and 4 raw `taxonomy` queries in `sitemap_controller.ex`.
- **15 recursive CTEs walk the same tree** (genus → family, family → descendants) across `taxonomy/tree.ex` (7), `taxonomy/search.ex` (2), `taxonomy/species_link.ex` (2), `galls.ex`, `plants.ex` (2). One published read model replaces them.
- Taxonomy reads gall data: `list_associated_genera`, `list_gall_families_for_host`, `list_gall_families_for_host_genus` join `gallhost`; `reclassification.ex:107` calls `Galls.force_undescribed_if_placeholder` inside its transaction. Its 11 references into `Species` are species-as-taxa and stay until the gall split.
- The `Species` and `Alias` schemas' `many_to_many :taxonomies` associations are unused; drop them.

## Verification approach

Before any change, capture golden outputs from the unchanged code against the experiment DB (`gallformers_taxogall`, `make experiment-db`): `Galls.get_galls_tree/1`, `get_undescribed_tree/1`, `Plants.get_hosts_tree/1`, the sitemap XML, `Search.search_taxonomy/1` for a sample of queries, and ID-tool results for a sample of genus/family/place filter combinations. Save them in `docs/plans/` (local) via a small script run with `MIX_ENV=dev PGDATABASE=gallformers_taxogall mix run`. Diff after every task; any difference is a bug.

## Implementation plan

### Task 1: Ancestry read model

- **Create:** a migration in `priv/repo/migrations/` defining two plain (non-materialized) Postgres views; `lib/gallformers/taxonomy/ancestry.ex` and `lib/gallformers/taxonomy/placement.ex` (read-only Ecto schemas over them); `test/gallformers/taxonomy/read_model_test.exs`.
- **`taxonomy_ancestry`** — one row per (node, ancestor-or-self): `taxonomy_id, ancestor_id, ancestor_type, ancestor_rank, depth` (0 = self).
- **`species_placement`** — one row per (species, node it sits under): `species_id, taxonomy_id, type, depth`, derived from `species_taxonomy` plus ancestry; distinct on (species, node), since a plant linked to both a section and its genus reaches the genus twice.
- The views are the **published shape**: at the gall split they are redefined over the new taxa tables and consumers don't change. Plain views suffice at this size (1,615 nodes, ~7k links); check with `EXPLAIN ANALYZE` on the experiment DB, and materialize only if a hot page measurably slows.
- **Tests:** a genus directly under a family; a genus under intermediates (subfamily → tribe); a section under a genus; a placeholder genus; a plant linked to genus and section (no duplicate rows); a gall linked to a genus; the self row at depth 0.

### Task 2: Taxonomy internals use the read model

- **Modify:** `taxonomy/tree.ex`, `taxonomy/search.ex`, `taxonomy/species_link.ex` — replace the recursive CTEs with joins on the views ("everything under family X" becomes `ancestor_id = X`).
- Existing tests (`test/gallformers/taxonomy_test.exs`, `taxonomy/tree_test.exs`, `taxonomy/species_link_test.exs`) must pass unchanged; golden outputs unchanged.

### Task 3: Route outside raw queries through the facade

- **Modify:**
  - `galls.ex` (`fetch_gall_tree_data`) and `plants.ex` (`fetch_host_tree_data`, the host-list family join ~line 872) — join `species_placement` instead of walking `taxonomy`.
  - `galls/identification.ex` — genus filter (~249), family filter (~257, drops `Tree.genus_ids_for_family`), placeholder-in-genus path (~422) — join `species_placement`.
  - `plants.ex` `get_genus_placeholder` (~361) and `update_species_section_link` (~714) — use `Taxonomy` API functions (add `unlink_species_from_taxonomy/2` beside `link_species_to_taxonomy/2`).
  - `search.ex` `search_taxonomy` (~426) — move the query into `Taxonomy.Search` and delegate; `search.ex` stops referencing the `Taxonomy` schema.
  - `sitemap_controller.ex` — use `Taxonomy.list_taxonomies_by_type/1` (or a lean `list_names_by_type/1` if the struct load is wasteful).
  - Drop the unused `:taxonomies` associations from `species/species.ex` and `species/alias.ex`.
- **Tests:** the existing gall/host tree, ID-tool (`test/gallformers/galls_identification_test.exs`, `test/gallformers_web/live/id_live_test.exs`), search and sitemap tests pass; golden outputs unchanged.

### Task 4: Move gall-data queries out of Taxonomy

- **Move** `list_associated_genera/2`, `list_gall_families_for_host/1`, `list_gall_families_for_host_genus/1` from `taxonomy/tree.ex` into `Galls` (they read `gallhost`), re-expressed over `species_placement`; update their callers (genus and host pages). Remove the delegates from `taxonomy.ex`.
- `count_families_for_taxoncode/1` and `count_genera_for_taxoncode/1` filter on `species.taxoncode` (species-as-taxa); they stay in Taxonomy until the gall split.
- **Tests:** move the corresponding tests with the functions; golden outputs unchanged.

### Task 5: Taxon-changed listener (`8567` rule 6)

- **Create:** `lib/gallformers/taxonomy/change_listener.ex` (behaviour: `handle_taxon_change(change) :: :ok | {:error, reason}`); `lib/gallformers/taxonomy/change.ex` (event struct; first kind `:species_reassigned` with `species_id`, `from_genus_id`, `to_genus_id`, `to_placeholder?`); `lib/gallformers/galls/taxonomy_listener.ex`.
- **Modify:** `taxonomy/reclassification.ex` — replace the direct `Galls` call with `notify/1`, which calls each listener in order **inside the transaction** and rolls back on the first `{:error, _}`. Listeners come from config (`config :gallformers, Gallformers.Taxonomy, change_listeners: [Gallformers.Galls.TaxonomyListener]` in `config/config.exs`), read at runtime so tests can substitute; Taxonomy's code never names Galls. `Galls.force_undescribed_if_placeholder/2` becomes the listener's body (made private to Galls).
- The event fires at the same point as today's call (genus reassignment in Reclassification only), so behavior is identical. Renames, moves, merges and splits join later as more change kinds.
- **Tests:** reassigning a species into a placeholder genus marks its gall undescribed (existing `reclassification_test.exs` case keeps passing); a test listener returning `{:error, :collision}` makes the reassignment fail and leaves genus and name unchanged; no listeners configured → reassignment works.
- Remove `Gallformers.Galls` from Taxonomy's `dirty_xrefs`.

### Task 6: Explicit exports

- **Modify:** `lib/gallformers/taxonomy.ex` — `exports:` becomes the public types: `Taxonomy` (schema struct), `Lineage`, `Family`, `Genus`, `Intermediate`, `Section`, `Ancestry`, `Placement`, `ChangeListener`, `Change`. `TreeBuilder` is reached through a `Taxonomy.build_tree/3` delegate (it is pure display shaping).
- Web: replace `Taxonomy.Tree.get_children_for_parents/1` and `Tree.name_parent_exists?/3` in `admin/taxonomy_live/form.ex` with context functions (add `name_parent_exists?/3` to `taxonomy.ex`); `reclassify_helpers.ex` and `genus_live.ex` use the now-exported `Lineage`/`Genus`. Remove the four `Gallformers.Taxonomy.*` entries from `GallformersWeb`'s `dirty_xrefs` (`lib/gallformers_web.ex:40–43`).
- `galls.ex:765` spec and `identification.ex`'s `Tree` alias go through public names.
- **Done when:** `MIX_ENV=dev mix compile --force --warnings-as-errors` is clean with `exports:` explicit; Taxonomy's `dirty_xrefs` lists only `Species` modules (the gall split removes them); `mix precommit` passes; golden outputs unchanged on the experiment DB.

**Size:** a few focused days. Tests insert `%Gallformers.Taxonomy.Taxonomy{}` directly in many places; that's fine (tests aren't boundary-checked) and needs no change.

**Not yet reviewed in depth** with Jeff (the 2026-10-06 review reordered the plan first). Re-check line references against main before starting; the code may have moved.


## Dropped (Jeff, 2026-10-24)

Not needed: the new back-end is built whole on `taxogall` and replaces the old one in place (`8567` *Build approach*). A facade over today's tables only pays off if old and new run side by side, and the plan has them meet only at cutover; it would refactor code the cutover deletes. What it would have provided (an ancestry read model, explicit `boundary` exports, the taxon-changed listener) is built new in `50ff` step 6. The coupling inventory in `8567` still shows what the rewrite replaces.
