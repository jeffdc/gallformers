---
status: planned
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

## Decisions (Jeff, 2026-10-27)
1. **The review queue and batch screens are step 10's core** (not a separate step): without them no batch can be approved and the backscan (step 11) can't start.
2. **One Gall editorial page** covers gap 1 — Gallformers code, abundance, `datacomplete`, the lead Source (`default_source_id`), name parts and override (`86e7`) — and is where **Gall images** are administered.
3. **No Gall delete;** mistakes and duplicates wait for the merge workflow (`3e8c`, after release).
4. **Host range editing carries over from today unchanged** ("a complex bit of work and no need to redo it"): the map editor (native → introduced → removed, country drill-down) and "refresh from WCVP" with the staged diff review, moved onto the taxon page and written by `taxon_id`, audited; the bulk WCVP range review page comes along (superadmin).
5. **A small Source editor:** edit details, retract (notice + date) and un-retract (re-computing the standings of the Facts the Source supports); no delete.
6. **Range exclusions by curators** on the Gall editorial page: a map of the potential range (today's gall-range map and drill-down reused), click to exclude or restore, a short statement; saved as a Gallformers batch fragment applied through the normal import path (rule 12's "small form that emits a schema fragment") — audited, replayable, attributed.
7. **Image audit deferred** to after release (the image component warns about an unattributed image where it's edited; orphan cleanup can be a one-off task later).
8. **Taxon delete** only for a taxon nothing refers to (no children, Facts, Galls, Host ranges).

## Design (agreed 2026-10-27)
1. **Review queue and batches:** packages and batches by status; a batch's statements with their delta class (confirms / new / denies or replaces) and its unmapped entries; approve / deny. The queue by kind with each kind's decision: ambiguous match, unresolved name / Host, undescribed-Gall candidate, dispute, same-date conflict, taxonomy disagreement, generation outside its group, Gall rename proposal. Built on the existing `Import` functions; every decision audited and in the replay log.
2. **Taxonomy admin** on `Taxa`: search and browse the tree; create, rename (→ Gall rename proposals, `86e7`), move; synonyms and common names; section membership (same-genus rule); add plants from POWO/WCVP (today's duplicate warnings); a plant's `datacomplete` and abundance; the Host range editor carried over; the taxon's images; delete an unreferenced taxon only. Writes through `Import.record_taxonomy_edit/2` / `record_synonym_added` / `record_plant_added` so they reach the replay log.
3. **Gall page** (reached from the public Gall page): the editorial fields with today's locks and uniqueness; name parts and override; images; **the Gallformers note editor** (each save a new dated version, then processed like any Source, `20e5`); range exclusions as above; no delete.
4. **Source editor:** details, retract / un-retract; no delete.
5. **Images:** one image component on the Gall page and the taxon page — upload (presigned S3), order, attribution and license rules, copy metadata, delete, iNat photo import — on the typed `gall_id` / `taxon_id` reference (`create_image` / `update_image` cast them; fixes today's species-only uploads).
6. **Wiring:** admin nav Queue, Galls, Taxonomy, Sources; the dashboard and the public pages' admin links point at the new screens; each old screen and the old domain code behind it are deleted when its replacement lands.

## Next
1. ~~Build the switch~~ — done (69f116b5).
2. Write the implementation plan for the design above; build.


## Implementation Plan

**Goal:** the minimal admin on the new back-end — review queue and batches, Gall page (editorial fields, name parts, images, note editor, range exclusions), taxonomy admin (with today's Host range editor carried over), Source editor — then delete each old screen and the old domain code behind it.

**Architecture:** back-end gaps are closed first in their owning contexts (`Import`, `Catalog`, `Taxa`, `Ranges`, `Images`, `Sources`), each audited and — where an edit must survive cutover — written to the replay log. Screens are LiveViews in a new admin `live_session` that resolves the signed-in user to an `Audit.Actor` on mount. Old screens are deleted as their replacements land; the legacy switch (69f116b5) goes when nothing is left behind it.

**Tech stack:** Phoenix LiveView, existing components (`core_components`, `form_components`, `ui_components`, `data_display_components` incl. `range_map`, admin `form_components`, `Admin.FormHelpers`), JS hooks (`RangeMap`, `ImageUpload`, `SortableImages`, `Typeahead`, `IndeterminateCheckbox`), Ecto, Oban, Carbonite, the private S3 bucket.

**Standing rules:** TDD; reuse existing components (CLAUDE.md — no new UI patterns without asking); `mix precommit` green and `MIX_ENV=dev mix dialyzer` 0 errors; audit-count assertions via `DataCase.test_audit_changes/0`; never `make test-db` while tests run; parallel agents never rebuild the test DB or edit seeds and keep shared-file edits small.

**Inventory of gaps (API map, 2026-10-27):** Import has no package list / global queue / pagination / deny and no in-memory package entry point; Taxa has no delete, no editorial-flag update, no synonym/common-name removal, no WCVP id; Catalog has no Gall editorial update and no public range-adjustment list; `Images` changesets don't cast `gall_id`/`taxon_id`; `Ranges` and `host_traits` are keyed by `species_id` (and `host_range`'s PK includes it); Source writes aren't audited and there's no un-retract; no web helper builds an `Audit.Actor` (`Actor.user/2` needs the local integer user id → `Accounts.get_user_by_auth0_id/1`).

### Task 1: Admin foundation
**Files:** create `lib/gallformers_web/live/admin_actor.ex` (or in `Live.UserAuth`), modify `lib/gallformers_web/router.ex`; test `test/gallformers_web/live/admin_actor_test.exs`.
**Behavior:** an `on_mount(:require_admin_actor, …)` hook: requires an admin (`Accounts.admin?/1`), resolves the session user to a local user and assigns `:current_user` and `:actor` (`Audit.Actor.user(id, name)`); a missing local user halts to `/admin` with a flash. A new `live_session :admin` in the `[:browser, :admin]` scope for the new screens (the role sessions from 1b9b2a0e stay). **Testing:** admin gets an actor; non-admin halted; live navigation into the session runs the hook.

### Task 2: Import back-end for review
**Files:** modify `lib/gallformers/import.ex` (+ `import/queue.ex` as needed); test `test/gallformers/import/review_test.exs`.
**Behavior:** `list_packages(opts)` (status filter, newest first, paginated `%{entries, total}`); `list_open_queue_items(opts)` across packages (by kind, with package and batch, paginated) including `gall_rename` items; `deny_package(actor, package, reason)` and `deny_batch(actor, batch, reason)` (audited, replay-logged, refused once applied); `submit_gallformers_fragment(actor, files)` — writes the files to the private bucket under a fresh key, registers, validates and resolves, and approves when nothing blocks (Gallformers batches skip review per `review_required?/1`), returning the package; each fragment gets a unique `batch_id`. Pre-approval delta preview stays out of scope (deltas exist after apply; the screen shows resolutions, unmapped and queue items before, deltas after). **Testing:** list filters and paging; deny refused after apply; a Gallformers range-exclusion fragment applies end to end and its Fact is attributed to the Gallformers Source with the statement and date; a blocked fragment stays awaiting review.

### Task 3: Review queue screens
**Files:** create `lib/gallformers_web/live/admin/queue_live/index.ex`, `package.ex`, and an item-decision component; router; tests under `test/gallformers_web/live/admin/queue_live/`.
**Behavior:** `/admin/queue` — open items by kind (counts, filters) and packages by status; `/admin/queue/packages/:id` — batches (type, mode, status), statements with resolution / candidates / delta, unmapped entries, the package's items, approve (surfacing `{:open_items}` / `{:blocked}`) and deny. Each item kind gets its decision controls per `Queue.validate_decision` (pick candidate, new, skip, keep, acknowledge with note, accept/reject rename); decisions call `Import.decide_queue_item/3` with the actor. Gall rename proposals show from → to and collision. Depends on Tasks 1–2. **Testing:** each kind's decision round-trips; approve blocked by an open item shows why; deny; rename accept/reject.

### Task 4: Catalog editorial back-end
**Files:** modify `lib/gallformers/catalog.ex`, `lib/gallformers/catalog/gall.ex`; test `test/gallformers/catalog/gall_editorial_test.exs`.
**Behavior:** `Catalog.update_gall_editorial(actor, gall, attrs)` — `gallformers_code` (unique, excluding self; blank → nil), `abundance_id`, `datacomplete` (locked false when the Gall is undescribed or has no Sources — legacy citations, notes or current attributions; enforced server-side), `default_source_id` (must be one of the Gall's Sources); audited; refreshes `gall_index` if a shown field changes. `Catalog.list_range_adjustments(gall_id)` (current exclude/only with place codes and attributions). `Catalog.gall_sources(gall_id)` if needed for the lead-Source picker. **Testing:** each lock and uniqueness; lead Source must be the Gall's; audit.

### Task 5: Images on typed references
**Files:** modify `lib/gallformers/images.ex`, `images/image.ex`, `storage/images.ex` (owner-based path, same `gall/{id}/…` layout thanks to the shared ID sequence), `lib/gallformers_web/live/admin/inat_import_component.ex` (owner instead of `species_id`); tests `test/gallformers/images_test.exs`, `inat_import_component_test.exs`.
**Behavior:** an owner `{:gall, id} | {:taxon, id}`: `finalize_upload/4`, `create_image/1`, `reorder_images`, sort order and listing by owner; changesets cast `gall_id`/`taxon_id` and require exactly one (the `image_one_typed_ref` check); `species_id` no longer required for new rows. **Testing:** upload for a Gall and for a taxon; sort order per owner; changeset rejects zero or two owners; iNat import by owner.

### Task 6: Image component
**Files:** create `lib/gallformers_web/live/admin/images_component.ex` (LiveComponent ported from `Admin.ImagesLive`); test `test/gallformers_web/live/admin/images_component_test.exs`.
**Behavior:** for an owner: grid/table, presigned multi-upload (`ImageUpload` hook), reorder (`SortableImages`), edit metadata with attribution and license rules (`Images.Attribution`, `Licenses`; picking a Source fills license/link/creator; canonical link for read-only licenses), copy metadata, delete, iNat import; an unattributed image shows a warning. Depends on Task 5. **Testing:** upload completion creates owned rows; reorder; edit validation; copy; delete; unattributed warning.

### Task 7: Gall page
**Files:** create `lib/gallformers_web/live/admin/gall_live/` (`index.ex` search, `edit.ex`), router (replace the legacy `/admin/galls*` routes), delete the old Gall admin LiveViews (`gall_live/form.ex`, `index.ex`, `undescribed.ex`) and their tests, plus old domain code with no callers left; tests `test/gallformers_web/live/admin/gall_live/`.
**Behavior:** `/admin/galls` search (`Catalog.search_galls/2`); `/admin/galls/:id` sections: editorial fields (Task 4, locks shown), name parts and override (`Catalog.update_name_parts/3`, shows the derived name), images (Task 6), the Gallformers note editor (`Sources.store_note/5`; shows versions), range exclusions (`range_map` of the potential range with exclusions, drill-down reused from the old gall-range screen; a statement field; save → `Import.submit_gallformers_fragment/2` with exclude/deny facts). Public Gall page admin link points here. Depends on Tasks 1, 2, 4, 6. **Testing:** each section saves with the actor and audit; locks; collision messages; note versioning; a range exclusion lands as a Gallformers Fact and shows on the public range map.

### Task 8: Taxa and Host range back-end
**Files:** migrations (host_range keyed by `(taxon_id, place_id)` with `species_id` nullable; WCVP link on taxa — `taxon_wcvp` or `host_traits.taxon_id`), modify `lib/gallformers/taxa.ex`, `lib/gallformers/ranges.ex`, `ranges/host_range.ex`, `lib/gallformers/plants.ex` (WCVP sync by taxon) or a new `Taxa`/`Ranges` module for it, `lib/gallformers/import.ex` (new replay ops); tests under `test/gallformers/taxa/` and `test/gallformers/ranges_test.exs`.
**Behavior:** `Taxa.update_editorial(actor, taxon, %{datacomplete, abundance_id})`; remove synonym / common name; `Taxa.referenced?/1` + `delete_taxon` (refused when anything refers to it — children, Relationship and act Facts, Galls' Host qualifier, Host ranges, images, generation groups, attribution names); section same-genus rule in `Taxa.place/3` for plant species in a section; `Ranges.get_places_for_taxon_with_precision/1`, `Ranges.update_taxon_places(actor, taxon_id, entries)` (audited; refreshes `gall_index` for Galls whose Hosts include the taxon or its genus); WCVP link and sync by taxon (match, ignore, sync, confirm); all of these as `record_taxonomy_edit/2` ops (or siblings) so they reach the replay log. **Testing:** each op audited and replay-logged; delete refused with the reason; same-genus rule; range write by taxon refreshes affected Galls' index rows; WCVP sync writes by taxon.

### Task 9: Taxonomy admin screens
**Files:** create `lib/gallformers_web/live/admin/taxonomy_live/` (new `index.ex`, `edit.ex`, `new.ex`) and port `host_range_live.ex` (bulk WCVP review, superadmin) onto taxa; keep and adapt `CountryDrillDown`, `PowoDiffReview`, the `range_map` editor flow from `host_live/form.ex` (`apply_powo_selections` moves into the new screen or a shared module); router (replace legacy taxonomy, hosts, section, host-range routes); delete the old Host, Taxonomy and Section admin LiveViews and tests and old domain code with no callers; tests under `test/gallformers_web/live/admin/taxonomy_live/`.
**Behavior:** search and browse the tree; create a taxon (rank, parent) or add a plant from WCVP (duplicate warnings via `Taxa.resolve_name/2` / `search/2`, WCVP pre-fill of name, family, distribution); edit: rename (→ rename proposals), move, synonyms and common names (add/remove), section membership, plant flags, **the Host range editor working as today** (tri-state map, country drill-down, refresh from WCVP with the staged diff, saved on Save), images (Task 6), delete when unreferenced. Public Host and rank pages' admin links point here. Depends on Tasks 1, 6, 8. **Testing:** port the old Host-form range tests to taxa; create/rename/move/delete; WCVP add; section rule; bulk review on taxa.

### Task 10: Source editor
**Files:** modify `lib/gallformers/sources.ex` (audited `update_source_details(actor, …)`, `retract_source(actor, …)` and new `unretract_source(actor, …)`, each running `Facts.recompute_for_source/2` and recorded in the replay log), create `lib/gallformers_web/live/admin/source_live/` (new index and edit), router (replace legacy sources and species-sources routes), delete the old Source and Species–Source admin LiveViews and tests and old code with no callers; tests.
**Behavior:** list/search Sources; edit details with today's validation (title, authors, date, DOI/URL, license with canonical link, citation); retract (pick the notice Source, date) and un-retract; no delete. Public Source page admin link points here. Depends on Task 1. **Testing:** details edit audited; retract and un-retract recompute standings; validation.

### Task 11: Wiring and the last deletions
**Files:** `lib/gallformers_web/components/layouts.ex` (nav: Queue, Galls, Taxonomy, Sources), `live/admin/dashboard_live.ex` (cards for the new screens; drop legacy cards), public pages' admin links, router (delete the remaining legacy routes: gallhost, gall-range, images, image-audit, filter-terms), delete their LiveViews / components (`GallHostLive`, `GallRangeLive`, `ImagesLive`, `ImageAuditLive`, `FilterTermsLive`, `RangeDrillDown`, `PlaceDrillDown` if unused, `ReclassifyLive` etc.) and the old domain code with no callers left (`Galls`, `Plants`, `Species`, `Taxonomy`, `FilterFields`, old `Ranges`/`Images`/`Sources` functions — `Galls.Identification` stays for `id_parity` until cutover); remove the legacy switch (`LegacyAdmin`, its plug, pipeline, sessions, config, tests) once nothing is gated; update `CLAUDE.md`'s taxogall note. **Testing:** nav and dashboard; every old admin URL 404s or redirects sensibly; `mix xref` shows no caller of deleted modules; e2e admin tests rewritten or removed with their screens (`make e2e PROD_DATA_DB=gallformers_taxogall` green).

**Order:** 1 → (2, 4, 5 in parallel) → (3, 8, 10 in parallel) → 6 → (7, 9 in parallel) → 11. Rehearse on `gallformers_taxogall` after Task 8 (new migrations) and at the end.


## Status (2026-10-27)

**All 11 tasks built, uncommitted on `taxogall`.** `mix precommit` green (2,450 tests — down from 2,829 as the old screens' and old domain code's tests went with them), `MIX_ENV=dev mix dialyzer` 0 errors, `make e2e PROD_DATA_DB=gallformers_taxogall` 23 tests 0 failures (the Makefile's `e2e` target is now one pass over `test/e2e`; the deleted reclassify / taxonomy-admin / host-admin e2e files were dropped). Rehearsal on `gallformers_taxogall` (strict) clean after the step 10 migrations: host_range keyed by taxon (1,083,689 rows), 2,741 WCVP links on taxa (`taxon_wcvp`).

**Built:** admin `live_session :admin` resolving the curator to an audited actor; review queue (`/admin/queue`, `/admin/queue/packages/:id`: decide every kind, approve, deny, resolve again); Gall page (`/admin/galls`, `/admin/galls/:id`: editorial fields with locks, name parts + override, images, Gallformers note versions, range exclusions submitted as a Gallformers fragment); taxonomy admin (`/admin/taxonomy`, `/new` incl. add from WCVP, `/:id`: rename → rename proposals, move, synonyms/common names, section members, plant flags, **the Host range editor carried over unchanged**, WCVP link, images, delete when unreferenced; `/admin/host-range` bulk WCVP review); Source editor (`/admin/sources`, `/:id`: details, retract, un-retract); one image component for Galls and taxa (refuses to save an image without attribution — Jeff, 2026-10-27: prevent save); nav Queue / Galls / Taxonomy / Sources; 301 redirects from old admin URLs; `docs/domain/admin-onboarding.md` rewritten. Every edit that must survive cutover goes to the replay log.

**Deleted:** all old-domain admin screens, the legacy switch, the image audit (deferred, Decision 7), and the old domain modules `Galls` (except `Galls.Identification`, kept for `id_parity`, now reading old tables by name, and `Galls.Summary`), `Plants`, `Species`, `Taxonomy`, `FilterFields`, the species-keyed `Ranges` / `Images` / `Sources` functions.

**Deviations and notes:** `host_range` and `source` aren't Carbonite-tracked (a range save / Source edit runs in an audit transaction naming the actor, and its replay-log entry holds the change; tracking `source` is a follow-up); pre-approval delta preview isn't available (deltas exist after apply); Source `link` no longer required (imported Sources may lack one); the public Gall page shows a Fact-only lead Source first.

**Follow-ups:** stale docs describing deleted modules — `CODING_STANDARDS.md` ("Taxonomy Naming API", "Schema Associations"), `docs/architecture/*` (range-system, elixir-architecture, core-architecture-rules, C4); track `source` in Carbonite; image audit after release; the content-image upload hook fix (`ContentImageUpload` sent its events to the page, not its component — also a production bug; fix on a branch off main).

