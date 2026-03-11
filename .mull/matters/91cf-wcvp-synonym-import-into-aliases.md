---
status: raw
created: 2026-03-10
updated: 2026-03-11
epic: admin
relates: [be9d, e79e]
---

# WCVP synonym import into aliases

## Problem

Hosts in gallformers have limited alias coverage. WCVP contains thousands of taxonomic synonyms that would improve search, matching, and discoverability.

## Design

### Schema Changes

Two changes to the `alias` table:

1. **Add `source` column** — `"wcvp"` or nil for manually added
2. **Expand type CHECK constraint** — add `synonym`, `misapplied`, `illegitimate`, `invalid`, `orthographic`, `artificial_hybrid`

Existing types (`common`, `scientific`, `former_undescribed`) unchanged. Manually-added scientific aliases stay `scientific`. WCVP imports get the specific type matching their `taxon_status`.

### WCVP Status → Alias Type Mapping

| WCVP taxon_status   | Alias type         |
|----------------------|--------------------|
| Synonym              | synonym            |
| Misapplied           | misapplied         |
| Illegitimate         | illegitimate       |
| Invalid              | invalid            |
| Orthographic         | orthographic       |
| Artificial Hybrid    | artificial_hybrid  |

Skip: Unplaced, Local Biotype, Accepted.

### New WCVP Lookup

`Wcvp.Lookup.get_synonyms/1` — given an accepted `plant_name_id`, returns all names where `accepted_plant_name_id` matches and `taxon_status` is in the target list. Returns `[%{taxon_name, taxon_status, plant_name_id}]`.

### Integration Point

In the existing WCVP sync flow, when `host_traits.wcvp_id` is set:

1. Call `Wcvp.Lookup.get_synonyms(wcvp_id)`
2. For each synonym, check if an alias with that exact name already exists for the species (case-insensitive)
3. If not, create alias with the mapped type, `source: "wcvp"`
4. Link to species via `alias_species`

### Deduplication

Skip if an alias with the same name (case-insensitive) already exists for that species regardless of type. Don't touch manually-added aliases.

### Display

UI can show types meaningfully: "Synonym", "Misapplied name", "Orthographic variant", etc. FTS index already includes all aliases regardless of type — search works automatically.

### Not In Scope

- Batch import for all existing hosts (future work)
- Common name import from external sources (separate matter)
- UI changes beyond displaying the new types (aliases already show on host pages)

### Synonym Detection During WCVP Sync

When `match_by_name` resolves a synonym (i.e., the host's current name in gallformers is a WCVP synonym, not the accepted name), we should detect this and alert the admin. The current flow silently links to the accepted WCVP record and syncs range data, but the admin should be informed so they can choose to:

1. **Reclassify** the host to the accepted WCVP name
2. **Add the old name as an alias** (synonym type)

This is related to the `resolve_synonyms: true` path added in `match_by_name/2` and used by both `sync_host_from_wcvp` (bulk) and `refresh_from_wcvp` (individual host form). The detection point is wherever the synonym fallback fires — surface it in the UI rather than silently proceeding.

