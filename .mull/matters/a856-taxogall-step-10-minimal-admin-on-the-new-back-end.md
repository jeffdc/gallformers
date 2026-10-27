---
status: raw
created: 2026-10-27
updated: 2026-10-27
epic: taxonomy
relates: [50ff, b5bd, 8567, e381, 20e5, 86e7, 803b]
---

# Taxogall step 10: minimal admin on the new back-end

# Taxogall step 10: minimal admin on the new back-end

`50ff` step 10 (`b5bd` M3, `8567` rule 12): replace the old-domain admin with as few screens as possible on the new back-end — taxonomy admin, images, a Gallformers note editor per Gall, and only what else proves unavoidable — and retire the old Gall / Host / gall–host / range / Source screens. Most data edits arrive as import batches.

## Approach (Jeff, 2026-10-27)

**Disable first, delete per screen.** The old screens hold logic and use cases that must partly carry forward, so they are disabled (not deleted) behind one switch, their use cases are inventoried below, and each screen's code is deleted only when its replacement lands (with the old domain code it is the last caller of).

**Disable now, not at cutover:** on `taxogall` the old admin already damages data the new back-end reads (inventory 2026-10-27):
- `Ranges.update_host_places/2` deletes and re-inserts `host_range` rows without `taxon_id`; the new pages read by `taxon_id`, so each Host save drops that plant's range from them.
- `Images.finalize_upload/4` writes only `species_id` (the changeset doesn't cast `gall_id` / `taxon_id`), so new uploads are invisible to the new pages.
- Gall / Host create, rename and delete write only the old tables; nothing in the old admin calls `Catalog`, `Taxa` or `Import`.

**The switch:** a config flag (off in dev and prod on this branch, on in test so the old admin tests keep running until their screens are deleted) checked by a plug on the HTTP request AND an `on_mount` hook (live navigation and connected sockets skip plugs); the gated routes move into their own `live_session`. Gated: `galls`, `gallhost`, `gall-range`, `hosts`, `host-range`, `taxonomy`, `section`, `sources`, `species-sources`, `images`, `image-audit`, `filter-terms`. A disabled screen shows "being rebuilt". Links to them are hidden: admin top nav (`Layouts.admin/1`), dashboard quick actions / taxonomy / filter-terms / stat cards (`action_card` already supports `disabled`), and the admin edit links on public pages (gall, host, source pages, image components). Not gated: dashboard, profile, glossary, articles, keys, users, ops, jobs, LiveDashboard.

## Inventory of the old screens (2026-10-27)

Use cases, logic worth carrying forward, and where each goes. File references are to `taxogall` at the time of writing.

### Gall admin (`/admin/galls`, `/new`, `/:id`, `/undescribed`)
- **Use cases:** list/search/delete; create by name; edit genus/family, Hosts, Traits, abundance, aliases, `datacomplete`, `undescribed`, `gallformers_code`; rename/reclassify; guided undescribed-gall naming (genus or "Unknown (Family)" + host initial-epithet + description slug).
- **Carry forward:** `gallformers_code` uniqueness (live check + DB constraint) and seeding from the epithet; undescribed lock (forced under an Unknown genus); `datacomplete` lock (no sources or undescribed → false, server-enforced); undescribed name rules (must start with genus or "Unknown (Family)", not taken); delete removes S3 images first; old name kept as an alias on rename; name-collision rollback.
- **Goes to:** Hosts, Traits, aliases, new Galls → **import pipeline** (`ApplyGall`, `GallMatcher` name undescribed Galls). Inducer rename/reclassify → **taxonomy admin** (Gall names are derived; renames reviewed, `86e7`). Editorial fields (`gallformers_code`, `abundance_id`, `datacomplete`, `default_source_id`, `name_override`) → **a small Gall editorial screen** — no write path exists yet (`Catalog` has `create_gall/2` only). Gall delete → open (no Catalog delete). Guided undescribed flow → likely obsolete (import names them).

### Gall–Host mapping and gall range (`/admin/gallhost`, `/admin/gall-range`)
- **Use cases:** add/remove Hosts; curate the stored gall range on a map; refresh from Hosts with a diff; confirm range; bulk range review.
- **Goes to:** Hosts → **import**. Stored range, confirmation and review → **obsolete** (the potential range is computed; differences are `exclude` / `only` range Facts). A curator's range exclusion is a Gallformers statement → via a Gallformers batch, or a small screen if batches prove too heavy (open).

### Host admin (`/admin/hosts`, `/new`, `/:id`, `/admin/host-range`)
- **Use cases:** create a plant from a typed name or from POWO/WCVP (name, family, native/introduced distribution); edit family/section, abundance, aliases; edit the range on a map (native → introduced → removed); refresh from WCVP with a diff; genus placeholders; rename/reclassify; bulk range review and WCVP sync/match/ignore.
- **Carry forward:** duplicate warnings (name, alias, WCVP id); WCVP authoritative for family; WCVP data staged and written only on save (`compute_powo_diff`, `apply_powo_selections`); "ignored" WCVP status kept (`upsert_host_traits`); every non-genus host needs a range entry.
- **Goes to:** plants, synonyms, common names, section membership → **taxonomy admin** (`Taxa.create_taxon` / `Import.record_plant_added`, `Taxa.add_synonym`, `add_common_name`, `Taxa.place`). Genus placeholders → obsolete (genus Hosts). **Host range editing and WCVP sync → needs a write path by `taxon_id` and a decision** (open): WCVP mix tasks exist; whether curators edit ranges by hand after release is open (`50ff` step 14: "fix wrong Host ranges on the Host").

### Taxonomy admin (`/admin/taxonomy`, `/new`, `/:id`)
- **Use cases:** list/filter/search; create/edit family, genus, section, intermediate rank; pick parent; create an intermediate by re-parenting children; bulk-move genera; cascade delete with impact preview and typed-name confirmation.
- **Carry forward:** name + parent uniqueness; parent required by rank; no self-parent; type change blocked when members exist; genus rename cascades to member names with old names kept, collision rolls back (now: reviewed Gall renames, `86e7`); create-intermediate atomic with ≥ 1 child; deletion impact preview + typed confirmation; section with members can't be deleted.
- **Goes to:** **new taxonomy admin** on `Taxa` (writes via `Import.record_taxonomy_edit/2` — place, rename, add_common_name, create_taxon — audited and in the replay log; `Taxa.add_synonym/4` / `Import.record_synonym_added`). Missing: taxon delete and merge (phase 2 for merges).

### Section admin (`/admin/section`, `/:id`)
- **Use cases:** set a section's member plant species. **Carry forward:** all members share one genus. **Goes to:** taxonomy admin (`Taxa.place`).

### Source admin (`/admin/sources`, `/new`, `/:id`)
- **Use cases:** list/search/delete; create/edit title, author, pubyear, link, license, citation, `datacomplete`.
- **Carry forward:** `Source.changeset` rules (required fields, 4-digit year, URL checks, unique title); canonical link for read-only licenses; typed-title delete confirmation.
- **Goes to:** mostly **import** (`SourceStep`, `match_source`, `create_imported_source`). New-model fields (`kind`, `authors`, `authored`, `doi`, `url`, `isbn`, `license_value`, `retracted_by`) and `Sources.update_source_details/2`, `retract_source/3` exist with no UI — a **small source details / retract editor** may be unavoidable (open). Delete is dangerous now (Facts and legacy citations reference Sources).

### Species–Source mapping (`/admin/species-sources/add`, `/find`)
- **Use cases:** attach a Source to species with description, external link, use-as-default; search and edit mappings.
- **Carry forward:** one default per Gall; external link must be a URL.
- **Goes to:** Gallformers ID Notes → **note editor** (`Sources.store_note/5`, versioned, audited; read with `list_gall_notes/1`). Other citations → read-only legacy citations; new attributions arrive as Facts via **import**. `useasdefault` → `Gall.default_source_id`, which needs a write path (with the Gall editorial screen).

### Images (`/admin/images`, `/admin/image-audit`)
- **Use cases:** pick a species; drag-drop multi-upload to S3 (presigned PUT); reorder; edit metadata (creator, attribution, license + link, source link, caption, linked Source); copy metadata to many; delete; import photos from an iNat observation; audit S3 orphans and unattributed images.
- **Carry forward:** presigned upload and path generation; size variants generated asynchronously; `sort_order` append and reorder; attribution rules (CC0 needs no creator, others do; a licensed Source counts as attribution); picking a Source fills license/link/creator; canonical link for read-only licenses; copy metadata; delete S3 variants first; iNat import (license mapping, creator "login - name", observation link, 1 s pacing).
- **Goes to:** **new images screen** on the typed reference (`gall_id` / `taxon_id`; `list_images_for_gall/1`, `list_images_for_taxon/1` exist; `create_image` / `update_image` must cast the typed refs; check constraint `image_one_typed_ref`). Image audit → open (works by `species_id`; already disabled on the dashboard).

### Filter terms (`/admin/filter-terms`, superadmin)
- **Goes to:** **obsolete** — the Trait vocabulary loads from `priv/import/vocab/traits.json`; old IDs translate through `legacy_trait_ids.csv`.

## Gaps the new back-end must fill (no write path today)
1. Gall editorial fields: `gallformers_code`, `abundance_id`, `datacomplete`, `default_source_id`, `name_override`.
2. `host_range` by `taxon_id` (writes, WCVP sync).
3. The import admin queue has no web UI (`Import.decide_queue_item/3` and friends) — batch review, approve/deny, retractions (`e381`; `9449` §5).
4. Image create/update with typed references.
5. Taxon delete.

## Open questions
- Is a small Gall editorial screen enough for gap 1, and does it also edit `default_source_id` (the lead Source)?
- Host ranges after release: hand editing by curators, WCVP sync only, or both? (`50ff` step 14.)
- Source details / retraction editor: needed, or import-only?
- Gall delete: needed? (No Catalog delete; Facts and attributions reference Galls.)
- Range exclusions by curators: Gallformers batches, or a small screen?
- Image audit: rebuild on typed references, or drop?
- The import queue / batch review screens (`e381`): part of step 10 or their own step?

## Next
1. Build the switch (disable the old screens and hide their links).
2. Answer the open questions; then design and plan the replacement screens (taxonomy admin, images, note editor, Gall editorial, import queue).
