---
status: refined
created: 2026-03-03
updated: 2026-05-03
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
