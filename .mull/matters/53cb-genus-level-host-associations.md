---
status: planned
created: 2026-03-03
updated: 2026-05-15
epic: cynipid
relates: [67c9]
---

# Genus-level host associations

## Problem

When literature identifies a host plant only to genus level, admins create placeholder species like "[Genus] spp." There's no enforcement of this convention, no way for the system to know these are placeholders, and no guardrails around genus-level vs species-level associations.

## Spec

### Semantics

A genus-level placeholder host means "this gall is known to occur on additional unidentified members of this genus." It is an additive assertion, not a temporary state of knowledge. It can coexist with species-level host associations for the same genus on the same gall.

### Rules

1. A host species can be flagged as a genus-level placeholder (a column, not parsed from the name)
2. Naming is system-enforced: "[Genus] spp" — no freeform variants
3. One placeholder per genus maximum
4. Both genus-level and species-level host associations for the same genus on the same gall are allowed — they represent different claims ("known on S. otites" + "known on at least one other unidentified Senecio")
5. These constraints are per-genus, per-gall — other genera on the same gall are unaffected

### Range

- Genus-level placeholder hosts have no WCVP range data and contribute nothing to the auto-computed host union
- Gall range defaults to the union of hosts' ranges, but can be fully independent after that. Host union is a starting point/tool, not the authority.
- ID and Search serve fundamentally different needs — ID is a precision tool, Search is inclusive discovery

### ID screen behavior

The ID screen has two levels of host filtering with different matching and range rules:

- **Species filter** (specific species, e.g. "Senecio otites"): precision tool. Only species-level host matches. Genus-level placeholders do NOT surface. Galls with no range are excluded (current INNER JOIN behavior, unchanged).
- **Genus/Section filter** (e.g. "Senecio"): exploration tool. Shows all galls with any host in that genus, whether species-level or genus-level.
- **With region filter active**: genus-placeholder-only matches are still allowed through as exploratory exceptions, even when they lack gall range support through the normal path.
- **Search page**: galls with no range appear in all regions (current behavior, unchanged).

Implementation direction: when genus filter is active and region filter is set, use LEFT JOIN on gall_range so NULL range rows can pass through. Species filter keeps the current INNER JOIN.

### User-facing display

- Genus-level placeholder hosts are visually distinguished wherever they appear (search, gall detail, host detail) to communicate "host known to genus only"
- On the ID screen, show an indicator only when the genus-placeholder path is why a result survived the region filter
- Do NOT use a blanket "Range Unknown" badge. The indicator should explain the match mechanism, not imply that the gall globally lacks range data.
- Preferred wording direction: something like "Genus-level host match" or "Matched genus host; range unverified"

### Data cleanup

- Audit existing placeholder records, standardize naming to the enforced "[Genus] spp" convention, and set the placeholder flag

## Decisions

- **No family-level host associations.** The Genus/Section filter and the family browse feature (67c9) cover that need through filtering, not data entry.
- **No admin nudge to remove genus placeholder.** Having N species cataloged in a genus says nothing about whether unidentified hosts remain. The placeholder is a positive assertion, not a gap.
- **Gall range defaults from host union but can be fully independent.** Broader than this matter, but now aligned with 600a.
- **Genus placeholders can coexist with species-level hosts from the same genus.** "Senecio spp" alongside "Senecio otites" remains meaningful and should be allowed.
- **Genus/section ID mode is broader than species ID mode.** It may surface genus-placeholder-only matches that do not satisfy the region filter in the normal way, as long as those results are clearly marked as exploratory exceptions.
- **Do not use a generic "Range Unknown" badge for these cases.** Use a targeted indicator only when the genus-placeholder path is the reason the result appears.

## What's NOT in scope

- New data model / junction table for genus-level associations — the current species-as-placeholder approach works
- Range inheritance for genus-level placeholders — they contribute nothing to range
- Family-level placeholder hosts

## Dependency

This matter depends on 600a for alignment around the host-union-is-advisory model. 600a now treats host union as a starting point/tool rather than a ceiling, which removes the earlier conceptual conflict.

## Remaining implementation work

- Add placeholder flag and enforcement rules to the host data model
- Enforce naming and uniqueness rules for genus placeholders
- Update genus/species host matching behavior in ID
- Add the targeted ID-result indicator for genus-placeholder exception cases
- Visually distinguish genus-level placeholder hosts across the site
- Audit and normalize existing placeholder records

## Investigation notes (2026-05-15)

User-reported regression: galls hosted only on `[Genus] spp` placeholders are silently suppressed by the ID region filter even when the user picks the correct genus. Concrete repro: gall `Exobasidium a-spp-whole-shoot-discoloration` (species 4548), only host `Arctostaphylos spp` (species 4547, linked to taxonomy 709), invisible under continent scope. Without a region filter the gall surfaces normally — the genus query path itself is fine; the place filter (`Identification.apply_place_filter/3`) gates it out because the placeholder host has no `host_range` and the gall has no `gall_range`.

### Verified data state (dev DB)

- **152 placeholder-pattern records** today: 117 `[Genus] spp`, 35 `[Genus] sp`
- **All linked to a genus** in `species_taxonomy` (no orphans)
- **4 genera have 2 placeholders each** (sp + spp variants): Cardamine, Lonicera, Solidago, Symphoricarpos — needs dedup before the per-genus uniqueness constraint can be enforced
- **19 galls** are currently in the "only placeholder hosts, no gall_range" state and therefore invisible under any region filter

## Open design decisions

1. **Species typeahead must exclude placeholders.** The spec's "Species filter precision" rule is only coherent if placeholders never appear in the species typeahead. Make explicit: `Plants.search_hosts/2` filters out `genus_placeholder = true`. Same call applies wherever else species-only pickers exist (gall edit, host browser, range entry) — audit at implementation time.

2. **Naming-cleanup strategy for `[Genus] sp` records (35 records).** Renaming to `[Genus] spp` changes the canonical URL (`/host/Acer-sp` → `/host/Acer-spp`). Options:
   - (a) Rename + add slug redirect from old name
   - (b) Keep current names; only enforce `[Genus] spp` for new records
   - (c) Leave existing names; only set the flag, no renames
   Recommendation: (a) for long-term consistency; needs the redirect mechanic to exist.

3. **Dedup procedure for the 4 duplicate genera.** Migration needs to pick a survivor, rewrite `gallhost.host_species_id` to point at it, then delete the loser. Open: what to do with aliases, images, descriptions, and any other FK references on the loser. Likely a one-shot script with a manual review step.

4. **Section-level placeholders are out of scope.** Matter excludes family-level but is silent on sections (children of genera, per memory). State explicitly: no section-level placeholders; if needed later, separate matter.

5. **Admin UI flag interaction (currently unspecified):**
   - Checking the flag auto-fills the name from the selected genus
   - Validation blocks save when another placeholder exists for that genus
   - Un-flagging a placeholder requires renaming away from `[Genus] spp` (otherwise orphan name + cleared flag)
   - WCVP-driven workflows must skip placeholder records (no range backfill, no synonym ingest)

6. **Indicator wording — pick one, not "or".** Recommend `"Matched genus host; range unverified"`. `"Genus-level host match"` reads as a category label, not an explanation, and conflicts with the spec's "explain the match mechanism" directive.

7. **Gall detail page when ALL hosts are placeholders.** The "don't say Range Unknown" rule in the spec is scoped to the ID screen (where the badge could mislead about overall data quality). On the gall detail page itself, the gall genuinely has no inferred range, and silence is worse than a targeted note like *"Range unknown — only genus-level host data available."* Worth deciding explicitly.

## Implementation mechanics

- **The spec's "use LEFT JOIN on gall_range" direction is approximate, not literal.** The current `apply_place_filter/3` uses subquery membership (`s.id in subquery(galls_with_range_match) or s.id in subquery(galls_with_host_fallback)`), not joins. The fix is to add a third allowed path that activates when the genus filter is set: galls whose host is a `genus_placeholder` matching the requested genus. Pseudocode:
  ```
  galls_with_placeholder_in_genus = SELECT gh.gall_species_id
    FROM gallhost gh JOIN species hs ON hs.id = gh.host_species_id
    JOIN species_taxonomy st ON st.species_id = hs.id
    WHERE hs.genus_placeholder = true AND st.taxonomy_id = ^genus_id
  ```
  Then OR that into the place filter's gating clause, but only when `genus_id` was passed.

- **Detecting "this gall survived only via the placeholder path" requires a second-pass query** (mirroring the existing `Identification.attach_place_match/2` pattern). For each result, check whether the gall has any host with a `host_range` row matching the region — if not, the placeholder path is why it surfaced, and the badge should appear. Compute once per result set, attach as e.g. `:place_match => :genus_placeholder`.

## Cross-matter touchpoints

- **91cf (WCVP synonym import)** and **b9e5 (bulk WCVP range backfill)**: both must skip records with `genus_placeholder = true`. Note in their bodies at implementation time.
- **7fda (source ingestion pipeline)**: could be aware of genus-level host mentions in literature and auto-resolve to the placeholder species. Out of scope here but worth a forward reference.
- **5c56 (species merge/split)**: when a genus is renamed or merged, its placeholder must follow. Likely already covered by the species-merge primitives; verify at implementation.
- **67c9 (filter galls by host family)** is the existing `relates` link and remains the correct family-level browse story.

## Tests to add

- Placeholder-only gall surfaces under genus filter with continent scope active, with badge
- Same gall does NOT surface under species filter for any sibling species
- Placeholder is absent from species typeahead results
- Naming + uniqueness enforcement blocks bad admin input (both create and update paths)
- Host union for a gall with mixed placeholder + real hosts excludes the placeholder
- Un-flagging a placeholder is rejected unless the name is also changed


## Decisions from planning review (2026-05-15)

- **#2 resolved: rename the 35 `[Genus] sp` records to `[Genus] spp`.** Migration normalizes all placeholder names to the enforced convention; old slug must redirect to new slug. Verify a slug-redirect mechanic exists before implementation; if not, that's a small prerequisite task.


## Resolutions to open design questions (2026-05-15)

- **Q1 — Species typeahead exclusion:** Hide placeholders from the **public** species-level host typeahead only. Admin host edit list, admin gall edit host picker, and any other admin-facing pickers must still show placeholders so they can be created/edited. Direct-URL access to `/host/:id` continues to work (route is by ID, no slug). Audit all species-only pickers at implementation; tag each as "public hide" or "admin show."

- **Q3 — Dedup procedure:** Programmatic merge with `[Genus] spp` as canonical survivor for all 4 cases (Cardamine, Lonicera, Solidago, Symphoricarpos). Migration script:
  1. Pick the `spp` variant as survivor
  2. Rewrite `gallhost.host_species_id` from loser → survivor (skip if a duplicate gallhost row would result; just drop the loser's row in that case)
  3. Merge aliases unique to the loser onto survivor
  4. Move any other FK references (images, sources, etc.) onto survivor
  5. Delete the loser
  Produce as dry-run first; review; apply. No case-by-case manual review unless dry-run flags a conflict (e.g. divergent descriptions).

- **Q4 — Section-level placeholders:** Out of scope. Add to the "What's NOT in scope" list: placeholders are genus-level only; section-level placeholder hosts are not supported. Separate matter if needed later.

- **Q5(a) — Auto-fill name on flag check:** Yes. Checking `genus_placeholder` auto-populates `name = "[selected genus] spp"` and makes the name field read-only while flagged.

- **Q5(b) — Block duplicate save:** Yes. DB-level unique constraint + friendly form error pointing to the existing placeholder.

- **Q5(c) — Un-flagging:** Not allowed. Once a record is flagged a placeholder, it stays flagged. Genus-name changes are handled by the existing `Taxonomy.Reclassification.rename_for_genus_change/4` cascade via `TaxonName.replace_genus/3`, which correctly transforms `"Aster spp"` → `"Eurybia spp"` when the underlying genus is renamed. Verify test coverage at implementation; no new mechanic needed.

- **Q6 — ID screen indicator wording:** `"Matched genus host; range unverified"`.

- **Q7 — Gall detail page when all hosts are placeholders:** Show the explanatory note `"Range unknown — only genus-level host data available."` The "don't show Range Unknown" rule from the spec is scoped to the ID screen only.

### Slug-redirect prerequisite

Not needed. Public host pages route by ID (`/host/:id`, router.ex:201). Renaming `[Genus] sp` → `[Genus] spp` doesn't change URLs.

