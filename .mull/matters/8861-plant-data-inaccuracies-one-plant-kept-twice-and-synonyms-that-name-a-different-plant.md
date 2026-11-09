---
status: raw
created: 2026-11-09
updated: 2026-11-09
epic: taxonomy
relates: [b5bd, 50ff]
---

# Plant data inaccuracies: one plant kept twice, and synonyms that name a different plant

This matter describes a problem only. It proposes no fix.

## The problem

The v1 plant data has plants whose names don't line up with the plants they mean. There are two kinds.

1. **One plant kept twice.** The same plant exists as two `species` rows, with Galls hosted on each. Usually one row's name is also an alias or synonym on the other row.
2. **A synonym that names a different plant.** One plant has a name as an alias or synonym, while another plant holds the same name as its own accepted name. According to WCVP, they are two different plants: the synonym is a misapplied name, or a homonym whose author has been lost.

In the old system, each row was its own species, so the two rows sat side by side without conflict. The catalog migration turns aliases into synonyms of the new taxa (`aliases.csv`, rule 4), and the resolver then picks one plant for a given name. It picks the accepted name and gives no sign that it did. So:

- With a plant kept twice, a Source naming either plant links to only one of the two rows. The Galls hosted on the other row go unmatched. The name lookup also hides that the plant exists twice.
- With a misapplied name, a Source that uses the name in its accepted sense resolves to the right plant. A Source that uses it in the misapplied sense resolves to the wrong one. The synonym also stays attached to a plant it doesn't belong to.

Jeff believes at least some of the duplicates came from ingesting the Nastassi guide book. That hasn't been checked.

## What has been addressed

These two pairs were each one plant kept twice. WCVP holds each pair as one plant.

- *Silphium asteriscus* var. *dentatum* (species 4863) is the same plant as *Silphium dentatum* Elliott (4878). WCVP accepts *S. dentatum*.
- *Horkelia congesta* Douglas ex Hook. (5190) is the same plant as *Potentilla congesta* (4870). WCVP accepts *P. congesta*.

How they were addressed:

- **The cutover, as a curated decision.** The new file `priv/catalog_migration/plant_merges.csv` (columns `species_id, into_species_id, note`) holds one row per pair: 4863 into 4878, and 5190 into 4870. The catalog migration reads the file in step 11c (`Gallformers.CatalogMigration.PlantMerges`). It merges each pair with the editorial plant merge (`Gallformers.Import.Merge`, applied unlogged) once Facts, names, notes and images are written. The merge does the following:
  - The absorbed plant's names become synonyms of the plant kept.
  - Its Host Facts, notes and images move to the plant kept.
  - Its ID redirects to the plant kept.
  - It is then deleted.
- **Rehearsed.** A full rebuild on a copy of `gallformers_taxogall` merged both pairs, with nothing pending and no duplicate keys. Precommit passes. **This work is not yet committed.**
- **Jeff's local review DB.** The same two merges were also made on `gallformers_taxogall`, where its replay log recorded them. That log doesn't reach the cutover; only the curated file and preview's replay log do (`b5bd`, M6).

## Others found, not addressed

How these were found: after a rebuild, by looking for a plant name that is accepted on one taxon and is also a synonym with no sensu on another, then checking each name against WCVP. The number in parentheses is how many Galls each plant hosts.

**One plant kept twice (WCVP says one plant):**

- *Cupressus nootkatensis* 2160 (0 Galls) and *Callitropsis nootkatensis* 1271 (1).
- *Cupressus pigmaea* 2236 (1) and *Hesperocyparis pygmaea* 1268 (2). "pigmaea" is a misspelling, and WCVP doesn't hold it.
- *Fallopia japonica* 4728 (1) and *Reynoutria japonica* 1529 (1).
- *Grindelia robusta* 3384 (1) and *G. hirsutula* 3181 (5).
- *Alnus viridis* 36 (2) and *A. alnobetula* 5308 (1). WCVP treats *A. viridis* as *A. alnobetula* subsp. *alnobetula*, so this is a species against a subspecies.
- *Populus trichocarpa* 4539 (12) and *P. tristis* 249 (12). WCVP sinks *P. trichocarpa* into *P. tristis*. That is unexpected and needs checking against other authorities.

**A synonym that names a different plant (WCVP says two plants):**

- *Quercus dumosa* 797 (64): its name is also a synonym on *Q. cornelius-mulleri* 800 (18).
- *Quercus texana* 1055 (3): its name is also a synonym on *Q. buckleyi* 351 (40).
- *Berberis dictyota* 6985 (1): its name is also a synonym on *B. aquifolium* 697 (1).
- *Solidago stricta* 3696 (0): its name is also a synonym on *S. virgata* 4648 (0).
- *Ulmus pumila* 2733 (2): the alias "Ulmus pumila Walter" is on *U. alata* 495 (4). It is a homonym: *U. pumila* Walter is an old name for winged elm, not Siberian elm. Normalizing the name drops the author, which is the only thing that tells the two apart.
- *Aristolochia durior* 1775 (0): its name is also a synonym on *Bignonia capreolata* 5135 (0). WCVP's *A. durior* Hill is a *Bignonia* name, while the plant meant here is probably Dutchman's pipe (*Aristolochia macrophylla*).
- *Quercus parvula* 338 (5): the alias "Quercus parvula (shrevei)" is on *Q. parvula* var. *shrevei* 2701 (4). Normalizing the name drops the part in parentheses, so the alias ends up naming the species instead of the variety.

The *Ulmus* and *Quercus parvula* cases show a second source of error. Normalizing alias text throws away an author or a qualifier, so a name that was distinct becomes the same as another plant's name.

## What is not known

- **Coverage.** The scan found only the pattern described above, where a name is accepted on one plant and is a synonym on another. It would miss:
  - the same plant under two names where neither name appears on the other row;
  - an infraspecific row duplicating its species where no alias links the two;
  - a misspelling with no alias at all.
- **How many more.** Nobody has estimated how many plants are affected beyond those listed.
- **Where they came from.** For most of the listed cases, it isn't known whether they came from the Nastassi guide ingestion or from earlier data entry.
- **Which name each Source meant.** For the misapplied names, it isn't known which sense the Sources that cite them were using. *Quercus dumosa*, at 64 Galls, matters most.

