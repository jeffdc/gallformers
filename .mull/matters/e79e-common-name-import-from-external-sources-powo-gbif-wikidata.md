---
status: raw
created: 2026-03-10
updated: 2026-03-10
epic: admin
relates: [91cf]
---

# Common name import from external sources (POWO/GBIF/Wikidata)

## Idea

Import common/vernacular names for host plants from external sources to improve search and discoverability. WCVP does not include common names — need a different source.

## Candidate Sources

- **POWO** (Plants of the World Online) — same Kew team as WCVP, hosts already have `powo_id` in `host_traits`
- **GBIF** — vernacular names via species API, global coverage
- **Wikidata** — structured common names in multiple languages

## Relationship

Serves the same ends as 91cf (WCVP synonym import) — both improve alias coverage for hosts. The `source` column added in 91cf would be reused here (e.g., `source: "powo"`, `source: "gbif"`).

## Status

Needs research into which source has the best coverage and API access. Not yet scoped.

