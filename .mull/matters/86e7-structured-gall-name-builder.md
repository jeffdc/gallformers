---
status: planned
created: 2026-09-14
updated: 2026-10-27
epic: taxonomy
relates: [803b, a856]
---

# Structured gall name builder

Give every Gall a unique, human-readable name derived from its data (`8567` rule 9), with a curator override when needed. Part of taxogall: `50ff` step 9's leftover (not in `803b`'s plan), built alongside step 10 (`a856`). Design agreed with Jeff on 2026-10-27.

## State today (2026-10-27)

`galls.name` is derived by the migration as the Inducer's accepted name plus the generation qualifier; `galls.name_override` holds today's name wherever it differs; `Gall.display_name/1` is the override or the name. On the converted production copy 2,653 of 3,976 Galls use the derived name and 1,323 need an override — mostly undescribed Galls ("Belonocnema q-brandegeei-midrib-gall", "Unknown (Cynipidae) q-havardii-cup-gall") whose pattern the derivation doesn't cover, plus host-scoped and form names. The several gall forms of one species (*N. saltatorius* (australis / texanus / decrescens / saltatorius) (agamic)) all derive the same name today and survive only through their overrides.

## Design

### 1. Name parts stored on each Gall (Jeff: approach A)
Names must be unique; we generate them, with a curatorial override if required. Qualifiers are **stored on each Gall**, never computed "as needed" against other Galls (which would rename Galls whenever another Gall appears). A Gall's name parts:
- **Inducer** — its current Inducer Fact (taxon).
- **Generation** — `generation_value_id` (exists); qualifier text from the generation group vocabulary, e.g. "(agamic)", "(sexgen)".
- **Host qualifier** (optional) — a Host taxon, rendered "(on Quercus douglasii)", "(on Ulmus)".
- **Form label** (optional) — free text, rendered "(australis)", "(bud)", "(detachable bud)", "(leaf snap)".
- **Descriptor** (optional; undescribed Galls) — e.g. `q-havardii-cup-gall`. It seeds the Gallformers code when the Gall is created; after that name and code are independent.

**Base:** the Inducer's accepted name for a species-rank (or below) Inducer; "Genus descriptor" for an undescribed Gall whose Inducer is a genus (or section); **"Unknown (Family) descriptor"** when the Inducer is above genus, using the Inducer's family (Jeff: keep today's form — reproduces every current undescribed name and doesn't change when the Inducer moves between ranks above genus).

**Seasonal qualifiers read "(spring generation)", "(summer generation)", "(autumn generation)"** (Jeff, 2026-10-27, option A): the generation vocabulary's `name_qualifier` for the seasonal values says "… generation", as today's names do, removing 18 of the ~22 seasonal overrides; "(summer and autumn generations)" keeps its override.

**Qualifier order: form, then generation, then Host** — matching today's names ("Neuroterus saltatorius (australis) (agamic)", "Neuroterus quercicola (pacificus) (sexgen) (on Quercus douglasii)"); this revises rule 9's listing order (generation, Host, form).

### 2. Uniqueness and overrides
The displayed name (override, else derived) is **unique, case-folded**; a collision is rejected wherever it comes from (batch, edit, rename proposal). An override is for the odd case only.

### 3. Renames are reviewed (Jeff, decision B, 2026-10-27)
- A taxonomy change that would alter a Gall's derived name — Inducer renamed or moved; an "Unknown (Family)" Gall's family changing; a Host-qualifier taxon renamed — creates a **rename proposal** in the import admin queue (`queue_items`, new kind) instead of renaming. The Gall keeps its current name until a curator accepts.
- **Accept:** the new derived name takes effect; the old name becomes a `former_label` alias Fact attributed to Gallformers; the **Gallformers code is untouched** (it ties existing iNat observations to the Gall; a code change is a separate, deliberate curator decision).
- **Reject:** the curator sets an override, so the name stays.
- A Gall with an override gets no proposal (its displayed name doesn't change).
- A **collision doesn't fail the taxonomy change** (amending `8567` rule 6 for names): the proposal is flagged as colliding and waits for the curator.
- Deliberate edits to name parts or the override (by a curator or a batch) apply directly — they are the review.

### 4. Migration
Fill the parts from what's known: generation (already set); Host qualifier from the host-scoped `name_suffixes.csv` rows ("(on Quercus douglasii)" → that plant taxon, "(on Ulmus)" → the genus); form label from the gall-form and plant-part rows; descriptor for undescribed Galls from their name (today base + code). Compute the derived name; keep an override only where it differs from today's name, so every current name survives. The report lists the remaining overrides (target: a small, reviewable set).

### 5. Where name edits come from
No name-builder screen (rule 12). Name parts and the override are set through the small Gall editorial screen (`a856` gap 1, which also covers the code, abundance, `datacomplete`, the lead Source) or a Gallformers batch. New Galls from imports get their parts from the batch (an undescribed Gall's descriptor from its proposed label).

## Notes
- A Gall's name carries no authorship and no taxonomic synonyms; a Gall's common names are alias Facts (`kind: common_name`).
- History: extracted from the dropped `2cb2` draft (a label-builder UI with recipes, primary inducers and confidence), which `8567` superseded.

## Implementation Plan

**Goal:** Gall names are generated from name parts stored on each Gall (Inducer, form label, generation, Host qualifier, descriptor), unique case-folded, with an override for the odd case; taxonomy-driven renames become curator-reviewed proposals; the migration fills the parts so today's names survive with as few overrides as possible.

**Architecture:** one pure-ish derivation module in `Catalog` (`Catalog.GallName`) used by every writer (migration, import, deliberate edits, rename proposals). The stored `galls.name` is the accepted derived name; `name_override` stays. Rename proposals ride the existing import admin queue (`queue_items`, new kind) and are decided with `Import.decide_queue_item/3`.

**Tech stack:** Ecto migrations (audited `galls` table via Carbonite), `Catalog` / `Taxa` / `Import` contexts, `CatalogMigration`, ExUnit.

**Standing rules:** TDD; `mix precommit` green; tests use the converted seeds (add old-style seed rows when needed, `make test-db`) and in-test fixtures; audit-count assertions use `DataCase.test_audit_changes/0`; never run `make test-db` while tests run.

### Task 1: Name parts and the derivation
**Files:** Create `priv/repo/migrations/<ts>_add_name_parts_to_galls.exs`, `lib/gallformers/catalog/gall_name.ex`; modify `lib/gallformers/catalog/gall.ex`, `lib/gallformers/catalog.ex` (delegates, Boundary export if needed); test `test/gallformers/catalog/gall_name_test.exs`.

**Behavior:**
- `galls` gains `host_qualifier_taxon_id` (nullable bigint, a taxon ID — no cross-context FK if the codebase avoids them between Catalog and Taxa; check `relationship_facts` for the convention), `form_label` (text), `descriptor` (text). Replace `galls_display_name_index` with a **case-folded** unique index on `lower(COALESCE(name_override, name))` (production has no case-folded duplicates; verify on `gallformers_taxogall` read-only before relying on it).
- `Catalog.GallName.derive(gall_parts)` → `{:ok, name}` | `{:error, reason}` where parts = Inducer taxon (current `inducer_of`), generation value, host qualifier taxon, form label, descriptor. Base: species-rank-or-below Inducer → its accepted name; genus/subgenus/section Inducer → "<Genus accepted name> <descriptor>"; Inducer above genus (or none, with a descriptor) → "Unknown (<family accepted name>) <descriptor>" (family = the Inducer's family-rank ancestor, or the Inducer itself if it is a family). Qualifiers appended in order **form, generation, Host**: "(<form_label>)", "(<generation name_qualifier>)", "(on <host qualifier accepted name>)". An undescribed Gall without a descriptor, or no Inducer and no descriptor → `{:error, :no_base}` (callers then need an override).
- `Catalog.derived_name(gall_id)` loads the parts and derives.

**Testing:** species + generation; species + form + generation (N. saltatorius (australis) (agamic)); species + form + generation + Host (N. quercicola (pacificus) (sexgen) (on Quercus douglasii)); genus + descriptor; tribe Inducer under Cynipidae + descriptor → "Unknown (Cynipidae) …"; family Inducer + descriptor; no Inducer + no descriptor → error; case-folded uniqueness rejects "andricus foo" when "Andricus foo" exists.

### Task 2: Deliberate name edits
**Files:** modify `lib/gallformers/catalog.ex` (+ a small module if large), `lib/gallformers/catalog/gall.ex` (changeset for parts/override); test `test/gallformers/catalog/gall_name_edit_test.exs`.

**Behavior:** `Catalog.update_name_parts(actor, gall, attrs)` sets any of `form_label`, `descriptor`, `host_qualifier_taxon_id`, `name_override` (nil clears it) and recomputes `name` from the parts in one audited transaction; a case-folded collision returns `{:error, changeset}` with a clear message; a derivation error with no override returns an error. It enqueues a `gall_index` refresh for the Gall (the index stores the name). These are the curator edits / Gallformers batch edits (applied directly — they are the review). The Gallformers code is never touched here.

**Testing:** setting a form label renames; clearing an override shows the derived name; a collision is rejected and nothing changes; audit records the change (own-transaction count); index row refreshed.

### Task 3: Migration fills the parts
**Files:** modify `lib/gallformers/catalog_migration/galls.ex` (and `name_suffixes.ex` if parsing lives there), `lib/gallformers/catalog_migration.ex` (report); test `test/gallformers/catalog_migration/` (skeleton/curated tests) + seeds as needed (`priv/repo/test_seeds.sql`, `test/support/fixtures/catalog_migration/name_suffixes.csv`).

**Behavior:** for each Gall, parse today's name: parentheticals that are generation tokens → generation (as today); "(on X)" → Host qualifier taxon (resolve X through `Taxa` among the Gall's Hosts / plants; unresolved → leave to the override); any other parenthetical → form label (multiple → joined in order? keep the first and let the override cover the rest — report them); undescribed Galls (Inducer above species) → descriptor = the text after the base ("Belonocnema q-…", "Unknown (Cynipidae) q-…"). Compute `Catalog.GallName.derive/1`; set `name` = derived (or today's name when derivation fails); set `name_override` only where the derived name ≠ today's name. Report: "Gall names derived" / "overrides kept" with the override list in the curation worksheets (`--reports`), reconcile Galls = derived + overridden.

**Testing:** seed cases reproduce exactly with no override: species+generation pair, gall forms (302 "Neuroterus seedatorius (australis) (agamic)"), undescribed genus-level (304), a host-scoped name (add a seed like "X y (on Notholithocarpus densiflorus)"); a name the parts can't reproduce keeps an override; report counts reconcile.

### Task 4: Rename proposals from taxonomy changes
**Files:** create `priv/repo/migrations/<ts>_add_gall_rename_queue_kind.exs` (extend the `queue_items.kind` check), modify `lib/gallformers/catalog/taxon_listener.ex`, `lib/gallformers/import.ex` / `lib/gallformers/import/queue.ex` (new kind + decide), the queue item schema's kind enum; test `test/gallformers/catalog/rename_proposals_test.exs`, `test/gallformers/import/queue_test.exs` (or the existing decide tests).

**Behavior:**
- On `:rename` / `:move` events, find the Galls whose derived name may change (current Inducer in the changed subtree; Host qualifier = the renamed taxon) without an override; derive the new name; where it differs from `galls.name`, create (or update — one open proposal per Gall) a queue item of kind `gall_rename` with `{gall_id, from, to, collision: boolean}` (collision = the new name, case-folded, is already another Gall's displayed name). The taxonomy change never fails because of a name.
- Decide: **accept** → set `name` to the proposal's `to` (re-derive at decision time; if it changed again, use the current derivation and say so), add the old displayed name as an alias Fact `kind: former_label` attributed to the Gallformers Source (dated at decision), refresh `gall_index`; a collision at accept time is refused. **reject** → set `name_override` to the current displayed name. The Gallformers code is never touched. Decisions are audited and recorded in the replay log like other queue decisions (check `Import.decide_queue_item/3` and the replay log kinds).

**Testing:** renaming an Inducer creates one proposal per affected Gall and leaves names unchanged; a Gall with an override gets none; moving a genus between families renames "Unknown (Family)" Galls only (proposals) and leaves genus-based undescribed names alone; accept applies the name + former_label alias + leaves the code; reject sets the override; a colliding proposal is flagged and can't be accepted until resolved; a second rename updates the open proposal instead of adding another.

### Task 5: Imported Galls use the derivation
**Files:** modify `lib/gallformers/import/apply_gall.ex`; test `test/gallformers/import/apply_test.exs`.

**Behavior:** a new Gall from a batch gets its parts — generation; Host qualifier when the batch's `identified_by.host` distinguishes it; for an undescribed Gall a descriptor generated in today's convention from its Host and the Source's wording: "<host genus initial>-<host epithet>-<slug of name_as_written>" (lowercase, hyphenated, trimmed to a sensible length) — and its name from `Catalog.GallName`; a collision gets " (2)", " (3)", … appended to the descriptor (undescribed) or as an override (described), as the provisional naming does today. The descriptor seeds the Gallformers code when the Gall has none. Replace the provisional naming code and its moduledoc note.

**Testing:** a described new Gall is named from its Inducer and generation; an undescribed one gets "<Genus> <h-epithet-slug>" and the same code; a colliding name is made unique; existing apply tests still pass.

**After the tasks:** rehearse on `gallformers_taxogall` (migrate, strict catalog migration, report the remaining overrides for Jeff), then `make test-db` and `mix precommit`. Contract follow-up (not in this plan): an optional proposed descriptor for undescribed Galls in `294c`.


## Status (2026-10-27)

**All five tasks built, uncommitted on `taxogall`.** `mix precommit` green (2,818 tests), `MIX_ENV=dev mix dialyzer` 0 errors.
- Tasks 1–3: `galls.host_qualifier_taxon_id` / `form_label` / `descriptor`; case-folded unique display-name index; `Catalog.GallName.derive/1`, `for_gall/1`, `Catalog.derived_name/1`, `Catalog.update_name_parts/3`; the migration reads today's names into parts and keeps an override only where the derived name differs (`gall_names` worksheet under `--reports`). Galls with no Inducer derive "Unknown (Unknown) descriptor".
- Task 4: rename proposals — Catalog finds affected Galls (`Catalog.GallRenames`), Import queues them (`Import.GallRenames`, a taxon listener registered after `Catalog.TaxonListener`; Catalog → Import would be a Boundary cycle). `queue_items.kind` gains `gall_rename` (no package; one open proposal per Gall). Accept re-derives, sets the name, adds the old name as a `former_label` alias stated by the Gallformers Source; reject sets the override; neither touches the code; decisions go to the replay log.
- Task 5: imported Galls named from their parts; undescribed descriptor "<h>-<epithet>-<slug of name_as_written>" (≤ 60 chars) seeds the code; collisions numbered.
- Seasonal qualifiers read "… generation" (decision above).

**Rehearsal on `gallformers_taxogall` (strict, clean):** 3,976 Galls = 3,958 derived + **18 overrides** (was 1,323): 11 aphid / rust life-cycle names that don't write their generation (Eriosoma, Hamamelistes, Hormaphis, Prociphilus, Gymnosporangium, the "summer and autumn" ones), 4 parentheticals that aren't name parts (authorship, pathovar, relationship, "(q-bicolor)"), 2 other differences, 1 unresolved Host qualifier ("(on Juniper)"). 22 form labels, 18 Host qualifiers, 1,546 descriptors.

**Follow-ups:** an imported Gall's `identified_by.plant_part` could become its form label (today such Galls get a " (2)" override); an optional proposed descriptor for undescribed Galls in the contract (`294c`); if a curator sets an override while a rename proposal is open, the proposal stays open (accept refused, reject works).

