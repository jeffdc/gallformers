---
status: planned
created: 2026-10-24
updated: 2026-10-24
epic: taxonomy
relates: [50ff, 8567]
---

# Taxogall back-end schema

The new back-end's schema for taxogall phase 1, agreed with Jeff on 2026-10-24, section by section. It is built whole on `taxogall` and replaces the old back-end in place (`8567` *Build approach*). Punchlist steps 5–8 in `50ff` build it. Rules and reasons live in `8567`; this matter holds the shape.

## 1. Contexts and today's tables

Each context has explicit `boundary` exports from the start. **Names (Jeff, 2026-10-24):** the new contexts get permanent names that don't collide with today's, because old and new code sit side by side on the branch until the public pages are re-pointed (`mix precommit` must pass on every commit); old modules are deleted then. `Sources` is extended in place.

| Context | Owns |
|---|---|
| `Sources` (extended) | Sources, their documents and stored text, Gallformers notes |
| `Facts` (shared building block) | Facts, attributions, evidence, standings |
| `Taxa` | taxa, names, rank, placement, taxonomic-act Facts, ancestry read model, "taxon changed" event |
| `Catalog` | Galls, Fact kinds about them, Trait vocabularies, generation groups, the Relationship-type list |
| `Import` | packages, batches, admin queue, disputes, replay log |
| `Audit` | who changed what (`ede2`) |

Read models (ID tool, search, pages, API) are published by `Catalog` and `Taxa`; nothing reads another context's tables.

| Fate | Tables |
|---|---|
| Unchanged | `users`, `place`, `place_hierarchy`, `wcvp_names`, `wcvp_distributions`, `articles`, `glossary`, `content_images`, `abundance`, `site_settings`, analytics |
| Kept, re-keyed | `host_range` (plant taxon → place; plants keep IDs, so no values change), `host_traits` (WCVP/POWO IDs on plant taxa), `image` (typed Gall-or-taxon reference; paths unchanged), `keys` (couplets re-targeted) |
| Extended in place | `source` (keeps IDs and `/source/:id`) |
| Replaced (read by the data migration, dropped after release) | `species`, `gall_traits`, `alias`, `alias_species`, `taxonomy`, `taxonomy_alias`, `species_taxonomy`, `gallhost`, `species_source`, `gall_range`, the nine `gall_*` Trait joins, the nine Trait vocabulary tables |

**IDs:** one shared sequence for Galls and all taxa, continuing today's species sequence (`8567` rule 4).

## 2. Sources–Facts (`Sources` and `Facts`)

- `source` gains: kind (`publication | website | database | unpublished | research_data | gallformers`), authors as written, authored date with precision (year / month / day) plus `as_written`, identifiers (DOI, URL, ISBN), license value plus `as_written`, retraction (`retracted_by` notice Source, date). Gallformers is one Source row (today's Source 58, ID kept).
- `source_documents`: one per stored document — a Source's `document.json`, or one version of a Gall's Gallformers note (`gall_id`, version date). Private S3 key, sha256.
- `document_items`: ref (`#/texts/42`), text, printed page. Quotes are checked and located against these. Never in the public snapshot.
- `facts`: `id`, `kind`, `standing` (`current | withdrawn | superseded | retracted | unsupported`), `slot`. Typed details live in tables owned by `Catalog` or `Taxa`, keyed by `fact_id`, unique on the kind's natural key. `slot` groups Facts that compete for one value (a Gall's detachable; a taxon's placement or accepted name); multi-valued kinds have none.
- `attributions`: `fact_id`, `source_id`, stance (`confirm | deny`), `stated_on` (the Source's authored date; for Gallformers, the statement's date; nullable for undated legacy), `value_as_written` (for controlled values), `batch_id`, statement text (Gallformers), and for occurrences `when_as_written` / `stage_as_written`. One per (Fact, Source); a newer Gallformers statement replaces Gallformers' attribution (audit keeps the old).
- `attribution_evidence`: one per quote — item, quote, stored span (computed by Gallformers), page, URL, `whole_item`, `cites`.
- `attribution_names`: each taxon named — `name_as_written`, `name_reading` (re-resolution after splits).
- `attribution_observations`: provider, ID, URL.

**Standing**, recomputed synchronously in the same transaction for the Facts touched:
1. Ignore attributions from retracted Sources; none left → `retracted`; no attributions at all → `unsupported` (hidden, audit keeps it).
2. The newest `stated_on` decides: confirm → `current`, deny → `withdrawn`.
3. Partial dates compare at the coarser precision ("1897" vs "1897-05" is a tie). A tie with opposite stances goes to the admin queue; the Fact keeps its standing until decided.
4. In a slot, the newest current Fact wins; the others are `superseded`.

Where a null `stated_on` sorts is the parked date decision (`8567` Sources–Facts point 7); the schema works either way.

## 3. Taxonomy storage (`Taxa`, phase 1)

- `taxa`: `id`, `rank` (contract rank list), `parent_id`, `origin` (`curated | powo`), `kingdom` (Plantae for plants; set for others when known — used for "a Host is a plant").
- `taxon_names`: `taxon_id`, `name`, `status` (`accepted | synonym`), `sensu`, `authorship` (null until phase 2). One accepted name per taxon; names not globally unique (homonyms across kingdoms). Normalized-name index for import resolution.
- `taxon_common_names`: today's plant common names; taxonomy batches' `common_name` acts.
- `legacy_taxon_ids`: crosswalk from old `taxonomy` IDs and old gall-row Inducer names (`/taxonomy/:id` redirects, `fa=` bookmarks, migration).
- `taxon_ancestry`: closure table (ancestor, descendant, depth), rebuilt for a subtree on placement change. Read model for ID tool, search, "all Galls under X", generation groups.
- Tree validator on every parent change: no cycles; a child ranks below its parent.
- Taxonomic-act Facts, one detail table per kind (`placement_facts`, `name_facts`, `synonymy_facts`, `split_facts`, `common_name_facts`), keyed by `fact_id`; placement and accepted name use slots. Recorded in phase 1; phase 2 lets them drive the tree.
- **Phase 1 tree is editorial:** the migrated skeleton plus curator edits (audited, no Facts). Phase 2 makes placement and names sourced Facts using the slot mechanics.
- **Approved taxonomy batches in phase 1** (Jeff, 2026-10-24): every act is recorded as a Fact with its attribution (phase 2's data, captured now). The tree changes automatically only to add taxa the Source presents as new (sp. nov. etc.), since their Galls need them. Any act that disagrees with the tree — a synonymy, another placement, a name the tree holds as a synonym but the Source treats as valid — is flagged for a curator to apply editorially or leave. Gall names never resolve through a disagreement silently.

## 4. Gall system (`Catalog`)

- `galls`: `id` (keeps species ID), `gallformers_code`, `generation_value_id` (identifies the Gall; not a Fact), derived `name` plus `name_override`, editorial carry-over (abundance, `datacomplete`, and whatever is decided for default Source and range-confirmed).

| Fact table | Columns | Natural key |
|---|---|---|
| `relationship_facts` | `type` (fixed list of 15), subject (taxon or Gall), object (taxon or Gall), `gall_context_id` | type + subject + object + context; check constraints per type's endpoint kinds |
| `qualifier_facts` | `of_fact_id` (a Relationship), `qualifier`, `value` | of + qualifier + value |
| `trait_facts` | `gall_id`, `trait_value_id` | Gall + value; `detachable` in a slot |
| `range_facts` | `gall_id`, `adjustment` (`include | exclude | only`), `place_id` | Gall + adjustment + place |
| `occurrence_facts` | `gall_id`, `place_id` | Gall + place (when / stage on the attribution) |
| `alias_facts` | `gall_id`, `name` | Gall + name |
| `description_facts` | `gall_id` | one per Gall; each Source's attribution carries its quotes |

- Vocabularies: `trait_values` (trait, value, definition), `trait_term_mappings`, `generation_groups`, `generation_values` (value, definition, name-qualifier text), `generation_group_taxa`. Relationship types: a code-level list (direction, inverse label, endpoint kinds) with a check constraint, changed only by migration.
- Read models (async): potential range = host ranges of current `host_of` plants (a genus Host carries its former placeholder's range rows), with `only` / `exclude` / `include` applied; **an empty result means every region**. Current Inducer, Hosts, Traits for the ID tool and pages. Flags: alternate-generation mismatches; a generation outside its Inducer's groups.
- A batch's `unmapped` entries stay in `Import`, not Facts.

## 5. Import (`Import`)

- `import_packages`: private S3 prefix, resolved Source (or new), status (`received → validated → resolving → awaiting review → approved | denied`), format and vocabulary versions, submitter.
- `import_batches`: `package_id`, `batch_type`, `mode`, producer `batch_id` (**unique** — idempotency), status, `applied_at`.
- `batch_statements`: each taxon, Gall, act and Fact in a batch — its resolution (taxon / Gall / existing Fact, `ambiguous`, `unresolved`, `new`) and delta class (confirms existing, new, denies or replaces).
- `batch_unmapped`.
- `queue_items`: ambiguous match (proposal + reason), undescribed-Gall candidate, unresolved name or Host (`d585`), phase 6 dispute, same-date conflict, taxonomy disagreement, generation outside its group — each with proposal, decision, who, when.
- **Applying a batch** (one transaction, Oban job unique per package): taxonomy batch first, and the gall batch waits for it and for every Host name to resolve; resolve names and Galls, uncertain ones to the queue; find or create Facts by natural key and **diff** attributions against the Source's existing ones (add new, update changed, leave unchanged untouched, remove gone — a Fact left unsupported becomes `unsupported`); recompute standings; emit taxonomy events; audit. Re-applying an applied `batch_id` is a no-op.
- **`replay_log`**: an ordered record, by stable keys (`batch_id` and statement refs, taxon names, legacy IDs — never database IDs), of everything that changes data during the backscan on preview: batches applied, queue decisions, synonyms and plants added in the Host-name step, taxonomy-admin edits. Replayed in order after the cutover data migration; the M5 rehearsals exercise it.
- Retractions set `retracted_by`. Gallformers batches use Source 58, `mode: add`.

## 6. Migration, legacy data, audit, tests

| From | To |
|---|---|
| `species` (gall) | `galls`, same ID; Code, abundance, `datacomplete`; generation from the name-suffix mapping (47 curated); `name_override` where today's name isn't the derived one |
| `species` (plant) | `taxa`, same ID, `origin: powo`, Plantae, accepted name; `host_traits`, `host_range` unchanged |
| Genus placeholders | no taxon; `host_range` rows move to the genus taxon; `gallhost` links become genus-level `host_of` |
| `taxonomy` + `species_taxonomy` | `taxa` (new IDs) with `parent_id`; `legacy_taxon_ids` |
| Inducer names in gall names | `taxa` (agamic/sexgen merged); placeholder genera → family-level links; "Unknown (Unknown)" → no Inducer |
| `species_source`, Source 58 | each Gall's note as a `source_documents` row, verbatim (`20e5`) |
| `species_source`, other Sources | `legacy_citations` (Gall, Source, narrative, `useasdefault`, external link), shown as today until the backscan; not Facts |
| `image` | typed Gall-or-taxon reference, paths unchanged |
| `gall_range` | range Facts, after drift is told apart from curator removals (`b5bd` M0, reopened) |
| Aliases | sorted by meaning (curated, `b5bd` M2) |
| `keys` | couplets re-targeted |

- **Legacy Facts** (proposed mechanism): one "Gallformers legacy data" Source (kind `database`, no date) attributes every legacy Fact at migration; the backscan adds real Sources alongside. Release-time disposition is `b5bd` M0's open decision; undated, any real Source outranks it.
- **Audit (`ede2`, rewritten):** Carbonite triggers on the new tables (`facts`, `attributions`, detail tables, `galls`, `taxa`, `taxon_names`, queue, replay log), declared in the migration that creates each; the audit schema stays out of the public snapshot.
- **Tests:** a new `priv/repo/test_seeds.sql` grows with the new tables. Step 5 opens with these acceptance tests, written first: two Sources confirm one Host; a denial before and after a confirmation, same result; a superseded placement; a retraction cancels a Source's stances; a re-import drops one Fact and leaves unchanged ones untouched; a qualifier denied while its Relationship stands; a Gallformers override citing Observations; a same-date conflict goes to the queue; placements forming a cycle or rank inversion are rejected; a Gall with no range data appears in every region; replaying the log on a fresh copy gives the same result.


## Implementation Plan

**Goal:** Build the new back-end's domain core (punchlist `50ff` steps 5–8): Sources–Facts with audit, taxonomy storage, the gall catalog, the importer with replay, and the data migration that fills them from today's tables.

**Architecture:** New contexts (`Facts`, `Taxa`, `Catalog`, `Import`, `Audit`) with explicit `boundary` exports, plus `Sources` extended in place. They live beside today's code on `taxogall`; nothing reads the old tables except the data migration. Public pages are re-pointed later (step 9), and the old modules and tables go then. Every task keeps `mix precommit` green.

**Tech stack:** Elixir/Phoenix, Ecto + PostgreSQL, Oban, Carbonite (audit), boundary, ExAws S3 (private bucket `gallformers-private`, already in `infra/s3.tf`), an Elixir JSON Schema 2020-12 validator (chosen in Task 11).

**Conventions for every task:** migrations under `priv/repo/migrations/` (timestamped); each new table's Carbonite trigger is declared in the migration that creates it (Task 1); schemas under `lib/gallformers/<context>/`; tests mirror under `test/gallformers/<context>/`; baseline rows the tests need go into `priv/repo/test_seeds.sql`; acceptance tests from §6 are written first, in the task that makes them possible, and named as in §6.

### Task 1: Audit foundation and the shared ID sequence

**Files:**
- Modify: `mix.exs` (add `carbonite`; confirm the release against Ecto and PostgreSQL versions)
- Create: `priv/repo/migrations/*_install_carbonite.exs`, `priv/repo/migrations/*_create_entity_id_sequence.exs`
- Create: `lib/gallformers/audit.ex` (boundary), `lib/gallformers/audit/context.ex`
- Modify: `test/support/data_case.ex` (explicit audit metadata for tests)
- Test: `test/gallformers/audit/audit_test.exs`

**Behavior:** Carbonite in its own schema. `Audit.transaction(actor, operation, fun)` inserts transaction metadata inside the checked-out transaction before the first write, then runs `fun`; `Audit.multi/3` does the same for `Ecto.Multi`. An audited write without metadata is rejected; no default actor. A `Audit.track_table/2` migration helper (with `store_changed_from: true`) is what later tasks call when they create tables. The sequence `entity_id_seq` is created for Galls and taxa; its start is set by the data migration (Task 14) to above every existing species ID.

**Testing:** write with metadata is captured (insert, update with changed-from values, delete); write without metadata fails; rollback leaves no audit rows; two sandboxed processes never share metadata.

**Notes:** Scope is capture for the new tables only. The history UI, actor plumbing for LiveView and Oban, and the public-snapshot exclusion follow `ede2`; the snapshot exclusion is Task 17.

### Task 2: Sources extended

**Files:**
- Create: `priv/repo/migrations/*_extend_source.exs`
- Modify: `lib/gallformers/sources/source.ex`, `lib/gallformers/sources.ex` (explicit exports for the new functions)
- Test: `test/gallformers/sources/source_test.exs`

**Behavior:** `source` gains `kind` (`publication | website | database | unpublished | research_data | gallformers`), `authors` (array, as written), `authored_date`, `authored_precision` (`year | month | day`), `authored_as_written`, `doi`, `url`, `isbn`, `license_value`, `license_as_written`, `retracted_by_id`, `retracted_on`. Existing columns stay (old code still reads them). Source 58 becomes kind `gallformers`.

**Testing:** a Source with a year-only date round-trips its precision; an unknown kind is rejected; retracting sets both fields and points at an existing Source.

### Task 3: Documents and quote location

**Files:**
- Create: `priv/repo/migrations/*_create_source_documents.exs`
- Create: `lib/gallformers/sources/source_document.ex`, `document_item.ex`, `docling.ex` (reads a DoclingDocument), `quote_locator.ex`
- Create: `lib/gallformers/storage/private.ex` (private bucket get/put)
- Test: `test/gallformers/sources/docling_test.exs`, `quote_locator_test.exs`

**Behavior:** Storing a `document.json` creates a `source_documents` row (S3 key, sha256, kind `docling | note`, `gall_id` and version date for notes) and one `document_items` row per text, table and picture item (ref, text, printed page). Table text is rows of cells joined with " | ", a spanning cell once — the same reading `priv/import/validate.py` uses. `QuoteLocator.locate(item_text, quote)` returns the character span, matching after NFKC normalisation, soft-hyphen removal, whitespace collapsing, and line-break dehyphenation, as `validate.py` does.

**Testing:** port the validator's document cases from `priv/import/tests/test_document_checks.py` (quote across a hyphenated line break and extra whitespace; table row quote; spanning cell; missing item; whole item with no text) and assert spans.

### Task 4: Facts core and standing

**Files:**
- Create: `priv/repo/migrations/*_create_facts.exs` (`facts`, `attributions`, `attribution_evidence`, `attribution_names`, `attribution_observations`)
- Create: `lib/gallformers/facts.ex` (boundary), `facts/fact.ex`, `attribution.ex`, `evidence.ex`, `attribution_name.ex`, `attribution_observation.ex`, `standing.ex`
- Test: `test/gallformers/facts/standing_test.exs`, `test/gallformers/facts/facts_test.exs`

**Behavior:** As §2. `Facts.Standing` is pure: given a Fact's attributions (with each Source's retraction state) and, for a slot, its competing Facts, it returns standings plus any conflicts. Partial dates compare at the coarser precision; a tie with opposite stances is a conflict, and the Fact keeps its previous standing. Null `stated_on` sorts oldest (the parked decision; one function to change). `Facts.attribute/2` upserts an attribution (one per Fact and Source; a newer Gallformers statement replaces Gallformers' attribution), writes evidence, names and observations, and recomputes standings for the Facts touched in the same transaction, returning conflicts to the caller. `Facts` never depends on `Catalog`, `Taxa` or `Import`; detail tables reference `facts.id`.

**Testing:** pure standing cases — newest confirm wins; newest deny withdraws; retracted-only support is retracted; no support is unsupported; year vs month tie is a conflict; slot supersession; null date loses to any dated attribution. DB cases — one attribution per Fact and Source; a replaced Gallformers attribution keeps the old one in audit.

### Task 5: Taxa storage, ancestry and tree validation

**Files:**
- Create: `priv/repo/migrations/*_create_taxa.exs` (`taxa`, `taxon_names`, `taxon_common_names`, `legacy_taxon_ids`, `taxon_ancestry`)
- Create: `lib/gallformers/taxa.ex` (boundary), `taxa/taxon.ex`, `taxon_name.ex`, `common_name.ex`, `legacy_id.ex`, `ancestry.ex`, `tree.ex`, `name_normalizer.ex`
- Test: `test/gallformers/taxa/tree_test.exs`, `ancestry_test.exs`, `name_resolution_test.exs`

**Behavior:** As §3. `taxa.id` defaults to `entity_id_seq`. `Taxa.place/2` changes a parent through the tree validator and rebuilds the subtree's closure rows. `Taxa.resolve_name(name, opts)` matches accepted names and synonyms through the normalized index (case, "var.", subgenus, hybrid sign), filtered by rank and kingdom when given; it returns `{:ok, taxon} | {:ambiguous, [taxon]} | :none`. Names are not globally unique.

**Testing:** acceptance test *placements forming a cycle or rank inversion are rejected*; ancestry answers "descendants of genus X" and "ancestors of species Y" after a move; homonyms in two kingdoms resolve separately with a kingdom filter and ambiguously without one.

### Task 6: Taxon change events

**Files:**
- Create: `lib/gallformers/taxa/events.ex`; Modify: `lib/gallformers/application.ex` (listener registration)
- Test: `test/gallformers/taxa/events_test.exs`

**Behavior:** `8567` rule 6: Taxa defines a "taxon changed" behaviour (rename, move, merge, split) and calls registered listeners inside its own transaction; a listener's error fails the change. Registration is application wiring, so Taxa never references Catalog.

**Testing:** a listener is called within the transaction; a listener error rolls the taxonomy change back; no listeners registered is fine.

### Task 7: Taxonomic-act Facts

**Files:**
- Create: `priv/repo/migrations/*_create_taxon_act_facts.exs` (`placement_facts`, `name_facts`, `synonymy_facts`, `split_facts`, `common_name_facts`)
- Create: `lib/gallformers/taxa/act_facts/*.ex`
- Test: `test/gallformers/taxa/act_facts_test.exs`

**Behavior:** The contract's five act kinds as Fact details with natural keys; placement and accepted name use slots. In phase 1 these are recorded only; they never move the editorial tree.

**Testing:** acceptance test *a placement is superseded* (two Sources place one taxon under different parents; the newer is current, the older superseded; the tree is unchanged).

### Task 8: Catalog vocabularies

**Files:**
- Create: `priv/repo/migrations/*_create_catalog_vocab.exs` (`trait_values`, `trait_term_mappings`, `generation_groups`, `generation_values`, `generation_group_taxa`)
- Create: `lib/gallformers/catalog.ex` (boundary), `catalog/vocab/*.ex`, `catalog/relationship_types.ex`
- Create: `lib/mix/tasks/gallformers/catalog/load_vocab.ex` (loads `priv/import/vocab/traits.json` and `relationships.schema.json`)
- Test: `test/gallformers/catalog/vocab_test.exs`

**Behavior:** Trait values with definitions and term mappings load from `traits.json`, today's source of truth. The vocabulary generator (later) reverses the direction. Generation groups start as the provisional list (agamic, sexual, spring, summer, autumn) plus the aphid values from `8567`; taxa mappings stay empty until the groups settle. `Catalog.RelationshipTypes` holds the 15 types with direction, inverse label and endpoint kinds, matching `relationships.schema.json`.

**Testing:** loading is idempotent; every value in `traits.schema.json` is present; relationship types match the contract's three endpoint groups.

### Task 9: Galls and gall Fact kinds

**Files:**
- Create: `priv/repo/migrations/*_create_galls.exs`, `*_create_gall_facts.exs` (the seven tables in §4)
- Create: `lib/gallformers/catalog/gall.ex`, `catalog/facts/*.ex`, `catalog/assert.ex` (find or create a Fact by natural key, then `Facts.attribute/2`)
- Test: `test/gallformers/catalog/assert_test.exs`, `test/gallformers/catalog/acceptance_test.exs`

**Behavior:** As §4. `galls.id` defaults to `entity_id_seq`; migrated Galls insert their species IDs. Check constraints enforce each relationship type's endpoint kinds; `host_of` subjects must be Plantae (validated through Taxa). `detachable` uses a slot. An occurrence's `when` and `stage` go on the attribution.

**Testing:** acceptance tests *two Sources confirm one Host*; *a denial before and after a confirmation gives the same result*; *a retraction cancels a Source's stances*; *a qualifier is denied while its Relationship stands*; *a Gallformers override cites Observations*; *a same-date conflict is reported* (the queue item itself is Task 13). Plus: a Host that isn't a plant is rejected; two Sources recording one place make one occurrence Fact with two dated attributions.

### Task 10: Catalog read models

**Files:**
- Create: `lib/gallformers/catalog/read_models/potential_range.ex`, `gall_summary.ex`, `flags.ex`; Oban worker `catalog/read_models/refresh_worker.ex`
- Test: `test/gallformers/catalog/read_models_test.exs`

**Behavior:** Potential range = host ranges of the current `host_of` plants (a genus Host contributes its own range rows), then `only`, `exclude`, `include`; **empty means every region**. `GallSummary` gives current Inducer, Hosts and Traits per Gall. `Flags` reports alternate-generation mismatches and generations outside the Inducer's groups. Refreshed asynchronously on Fact and taxon changes.

**Testing:** acceptance test *a Gall with no range data appears in every region*; `exclude` removes a region; `only` keeps one; a withdrawn Host stops contributing; flag cases for both mismatch kinds.

### Task 11: Import intake and validation

**Files:**
- Create: `priv/repo/migrations/*_create_import.exs` (`import_packages`, `import_batches`, `batch_statements`, `batch_unmapped`, `queue_items`, `replay_log`)
- Create: `lib/gallformers/import.ex` (boundary), `import/package.ex`, `batch.ex`, `batch_statement.ex`, `queue_item.ex`, `replay_entry.ex`, `import/validator.ex`
- Test: `test/gallformers/import/validator_test.exs`

**Behavior:** A package in the private bucket (`import/<package_id>/`) is registered and validated: schemas from `priv/import/schema/` and `priv/import/vocab/`, plus the package checks `validate.py` makes (document sha256, quotes in items via Task 3, references, ids, qualifier targets, one Inducer per Gall, new Galls have Facts, one description per Gall, no synonymy or split above family). Producer `batch_id` is unique.

**Testing:** every example package in `priv/import/examples/` validates; mutated copies fail with the same errors `validate.py` reports for them (reuse the cases in `priv/import/tests/`).

**Notes:** Choose the JSON Schema library first: it must handle draft 2020-12, `unevaluatedProperties`, `if/then` and relative `$ref` across the schema and vocab files (evaluate JSV). If none does, run `validate.py` from the import job instead, and add Python to the runtime image. Decide before writing code.

### Task 12: Resolution and the Host-name step

**Files:**
- Create: `lib/gallformers/import/resolver.ex`, `import/gall_matcher.ex`
- Test: `test/gallformers/import/resolver_test.exs`, `gall_matcher_test.exs`

**Behavior:** Every taxon resolves through `Taxa.resolve_name/2` (using `name_reading` when `name_as_written` fails; abbreviations expanded from genera the document names; 19th-century "C. q. spongifica" tried as the fused epithet), or becomes an `unresolved` or `ambiguous` statement. No fuzzy matching. Unresolved Host names stop the gall batch and become queue items (`d585`). Galls match by `identified_by` (Inducer, generation, Host, plant part); undescribed Galls match by genus, Host and descriptive words, with one candidate proposed or several offered. Nothing ambiguous is applied.

**Testing:** abbreviation expansion; fused-epithet match; `name_reading` fallback; a name the tree holds as a synonym while the batch treats it as valid is flagged, not resolved (no silent merge); an unresolved Host blocks the gall batch; undescribed-Gall candidates proposed.

### Task 13: Applying batches and the admin queue

**Files:**
- Create: `lib/gallformers/import/apply_taxonomy.ex`, `apply_gall.ex`, `queue.ex`, `worker.ex` (Oban, unique per package)
- Test: `test/gallformers/import/apply_test.exs`, `queue_test.exs`

**Behavior:** As §5. Taxonomy batch: record every act (Task 7), create taxa the Source presents as new, flag disagreements. Gall batch: find or create Facts, diff attributions against the Source's existing ones (add, update, leave unchanged untouched, remove), recompute standings, enqueue conflicts, emit events, audit — one transaction per batch. Re-applying an applied `batch_id` is a no-op. Phase 6 disputes from `review.json` become queue items. Queue decisions are recorded with who and when.

**Testing:** acceptance test *a re-import drops one Fact and leaves unchanged ones untouched* (assert no audit rows for unchanged attributions); re-applying a batch changes nothing; a taxonomy batch adding a new species makes its gall batch resolve; a disagreeing synonymy is flagged and the tree is unchanged; a same-date conflict lands in the queue.

### Task 14: Replay log

**Files:**
- Create: `lib/gallformers/import/replay.ex`
- Test: `test/gallformers/import/replay_test.exs`

**Behavior:** Every data-changing step during the backscan appends to `replay_log` in order, referenced by stable keys (`batch_id` plus statement refs, taxon names, legacy IDs): batch applied, queue decision, synonym or plant added in the Host-name step, taxonomy-admin edit. `Replay.run/1` replays the log in order against a database the data migration has just filled.

**Testing:** acceptance test *replaying the log on a fresh copy gives the same result*: apply batches and decisions on one sandboxed dataset, rebuild from the same seed, replay, and compare Facts, attributions, standings and taxa by stable keys (not IDs).

### Task 15: Data migration — skeleton

**Files:**
- Create: `lib/gallformers/catalog_migration.ex`, `catalog_migration/taxa.ex`, `catalog_migration/galls.ex`
- Create: `lib/mix/tasks/gallformers/catalog/migrate.ex`; Modify: `lib/gallformers/release.ex` (`migrate_catalog/0`, the production entry point; never run at boot)
- Create: `priv/catalog_migration/name_suffixes.csv` (the mapping and the 47 curated cases from `b5bd`)
- Test: `test/gallformers/catalog_migration/skeleton_test.exs`

**Behavior:** Rebuilds the new tables from the old ones, repeatably (truncate new, refill), from a production copy. Plants → `taxa` (same IDs, `powo`, Plantae, accepted name); `taxonomy` + `species_taxonomy` → `taxa` with new IDs, parents and `legacy_taxon_ids`; Inducer taxa from gall names (agamic/sexgen merged; placeholder genera to family; "Unknown (Unknown)" none); gall rows → `galls` (same IDs, Code, abundance, `datacomplete`, generation, `name_override`); genus placeholders → no taxon, their range rows moved to the genus. Sets `entity_id_seq` above every ID used. Prints a count reconciliation.

**Testing:** on a small fixture of old-model rows: counts reconcile; an agamic/sexgen pair yields one Inducer and two Galls; a placeholder's range rows land on its genus; the crosswalk maps an old family ID; running twice gives the same result.

**Notes:** Run locally only with `MIX_ENV` set explicitly and against a copy — never `mix run` without it.

### Task 16: Data migration — legacy Facts, citations, notes, images

**Files:**
- Create: `lib/gallformers/catalog_migration/legacy_facts.ex`, `citations.ex`, `notes.ex`, `images.ex`
- Create: `priv/repo/migrations/*_create_legacy_citations.exs`, `*_add_typed_image_refs.exs` (nullable `gall_id` / `taxon_id` beside `species_id`, which old code still uses)
- Test: `test/gallformers/catalog_migration/legacy_test.exs`

**Behavior:** One "Gallformers legacy data" Source (kind `database`, no date) attributes every legacy Fact: Inducer, Hosts (genus Hosts from placeholders), Traits, existing community Relationships. Non-58 `species_source` rows → `legacy_citations`. Source 58 text → one note `source_documents` per Gall, verbatim. Images get their typed reference.

**Testing:** a migrated Gall has its Inducer, Hosts and Traits current, each attributed to the legacy Source with null `stated_on`; a real Source's later denial withdraws a legacy Host; notes keep their text exactly; image paths are unchanged.

### Task 17: Data migration — curated inputs, ranges, private-table exclusions

**Files:**
- Create: `lib/gallformers/catalog_migration/ranges.ex`, `aliases.ex`, `keys.ex`, `reports.ex`
- Create: `priv/catalog_migration/aliases.csv`, `range_decisions.csv`, `non_galls.csv`, `keys.csv` (curated inputs, filled from the reports)
- Modify: `.github/workflows/db-snapshot.yml` (exclude `source_documents`, `document_items`, the `Import` tables and the audit schema)
- Test: `test/gallformers/catalog_migration/curated_test.exs`

**Behavior:** Reports first, Facts after decisions: a range report classifies each Gall's stored range against its host union (redundant, likely curator removal, likely drift since a copy, outside the union) for review into `range_decisions.csv`, which then produces range Facts; an alias report lists gall "scientific" aliases for sorting into synonyms, former labels and codes (`aliases.csv`); the 120 non-galls are listed and excluded (`non_galls.csv`); key couplets are re-targeted from `keys.csv`. Missing curated decisions fail the run with a list, never a guess.

**Testing:** range classification cases (copy then widened union is drift, not exclusion); an alias marked "former label" never enters `taxon_names`; a missing decision stops the run naming the rows; the snapshot workflow's exclusion list contains every private table.

**Notes:** The reports need a fresh production copy (`b5bd` M2 inventory refresh). The curation itself is Jeff's time, not code.
