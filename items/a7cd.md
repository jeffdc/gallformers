---
plan: taxogall
phase: d51b
title: Make the 7 one-word plant 'species' their genus in the catalog migration
stage: committed
docs:
  - .mull/matters/b5bd-taxonomy-migration.md
created: "2026-11-09T20:38:18Z"
updated: "2026-11-12T02:23:22Z"
---

**The problem.** Seven old-site plants are one-word "species" sitting under a genus of the same name. Each is linked to a WCVP record of rank Genus. The catalog migration turns every plant `species` row that isn't a genus placeholder into a species-rank taxon. These seven therefore become bogus species named like their genus, instead of standing for the genus. They were found in the dev cutover rehearsal (2026-11-07).

| Old species ID | Name | WCVP ID (rank, status) | Galls hosted (old `gallhost`) |
|---|---|---|---|
| 6135 | Justicia | 2330441 (Genus, Accepted) | 1 |
| 6246 | Myrceugenia | 130862 (Genus, Accepted) | 2 |
| 6509 | Bersama | 2675087 (Genus, Accepted) | 1 |
| 6517 | Tiliacora | 2516993 (Genus, Accepted) | 1 |
| 6521 | Neoboutonia | 133639 (Genus, Accepted) | 1 |
| 6527 | Malacantha | 118003 (Genus, Accepted) | 1 |
| 7019 | Echinops | 3134378 (Genus, Accepted) | 1 |

IDs, WCVP links and counts were read on 2026-11-11 from `gallformers_taxogall` and the local `wcvp` database. All seven rows have `genus_placeholder = false` and `taxoncode = 'plant'`. After conversion each is a `species`-rank taxon with the same ID, under a genus taxon of the same name.

**How to find them** (the query from `b5bd`): accepted plant names at species rank or below that contain no space, or that equal their parent's name; then check each linked `wcvp_id`'s `taxon_rank`. On a converted copy:

```sql
select t.id, t.rank, n.name, pn.name as parent, w.wcvp_id
from taxa t
join taxon_names n on n.taxon_id = t.id and n.status = 'accepted'
left join taxon_names pn on pn.taxon_id = t.parent_id and pn.status = 'accepted'
left join taxon_wcvp w on w.taxon_id = t.id
where t.kingdom = 'Plantae' and t.rank in ('species', 'subspecies', 'variety', 'form')
  and (position(' ' in n.name) = 0 or n.name = pn.name)
order by n.name;
```

Then check each `wcvp_id` against `wcvp_names.plant_name_id` → `taxon_rank` in the `wcvp` database. On `gallformers_taxogall` (2026-11-11) it returns these seven plus *Stephanomeria* (88146). Stephanomeria is not v1 data and is item 1525's.

**The fix (from `b5bd`):** "Mark the old rows `genus_placeholder` (or add curated decisions) so the migration makes them the genus, not a species."
- **A genus placeholder** ("*Quercus* spp.") becomes no taxon (`Gallformers.CatalogMigration.Taxa`, "Genus placeholder plants"). It stands for its genus taxon, with a `:genus_placeholder` crosswalk entry in `legacy_taxon_ids` (its species ID → the genus), so its old `/host/:id` redirects to the genus page. Its `host_range` rows are re-keyed to the genus, and Galls hosted on it get the genus as their Host. That is the outcome wanted here.
  - Placeholders lose the plant editorial flags (`datacomplete`, `abundance_id`; the migration reports them as "on genus placeholders (no taxon)").
  - What happens to the row's WCVP link is not covered in the matters. Check it.
- **Where the fix lives.** The cutover runs from the latest production copy, and only the curated files in `priv/catalog_migration/` and preview's replay log reach it. So a fix on a local database, or on preview's converted data, doesn't carry. Two routes:
  1. set `genus_placeholder` on the seven rows in production's v1 data before the cutover copy;
  2. a curated decision the migration reads.

  As of a0434bcf, no curated input marks a row as a genus placeholder. `plant_merges.csv` can't express it either: `Gallformers.CatalogMigration.PlantMerges` requires both sides to be plant `species` rows, and the genus is no `species` row. Route 2 therefore means extending an input or adding one (`Gallformers.CatalogMigration.Curated` lists the inputs). If neither route is clearly right, ask Jeff which before building. Route 1 edits production.
- Test first: add an old-style seed row (a one-word plant under its same-named genus) in `priv/repo/test_seeds.sql`, plus any curated fixture in `test/support/fixtures/catalog_migration/`, and assert it migrates as the genus.

**Done when** a strict catalog migration on a fresh production copy turns none of the seven into a species: each old ID redirects to its genus, their Galls are hosted on the genus, and the query above returns none of them.

From matter b5bd, 'Dev cutover rehearsal', data to settle: Justicia, Myrceugenia, Bersama, Tiliacora, Neoboutonia, Malacantha, Echinops (genus_placeholder or curated decisions). Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.
