# Undescribed Gall Data Inconsistency - February 9, 2026

## Summary

18 galls have the undescribed naming pattern (real genus with dashed descriptive name like `Andricus-stem-gall`) but `undescribed` is not set to `true` in `gall_traits`. This means they won't be correctly handled by features that key off the `undescribed` flag.

**Root cause**: No validation enforcing that undescribed naming patterns match the `undescribed` flag.

**Resolution**: Fixed in production. Future enforcement via the taxonomy reclassification feature's enforced-floor invariant.

## Discovery

Found during brainstorming for the taxonomy reclassification feature. Two additional cases were found and fixed earlier:

- Species 1115 (`Unknown-cynipidae dentatae`) — `Unknown` genus but `undescribed=false`
- Species 3117 (`Unknown-cecid c-americana-folded-leaf`) — same issue

## Affected Species

19 species IDs: 1520, 5218, 5873, 1525, 3241, 5881, 5898, 5939, 5170, 3242, 5919, 4614, 5846, 5824, 5897, 5232, 5910, 5446, 5201

**Exception**: Species 4614 is a legitimately described species, NOT undescribed. It should be excluded from the fix.

All others have real genera (not `Unknown`) with dashed descriptive names — the naming convention used for undescribed species — but `gall_traits.undescribed` was `false`.

## Fix

All 18 affected species were fixed in production on February 9, 2026.
## Related Finding: Described Galls With No Sources

While investigating the undescribed flag issue, we also found 85 described galls (`undescribed=false`) that have no sources attached via `species_source`. This is a data quality concern — described species should generally have at least one source citation.

Note: The local DB snapshot predates the undescribed fix above, so a few of these (5919, 5824) appear here but are actually undescribed and were fixed in production later the same day.

| ID | Name |
|----|------|
| 681 | Aceria annonae |
| 4404 | Aceria artemisiae |
| 5669 | Aceria davidmansoni |
| 5561 | Aciurina trilitura |
| 4269 | Acraspis pezomachoides (sexgen) |
| 1373 | Albugo ipomoeae-panduratae |
| 1520 | Ampelovirus hackberry-island-chlorosis |
| 3436 | Amphicerus bicaudatus |
| 774 | Apiosporina morbosa |
| 2351 | Arnoldiola atra |
| 1832 | Asphondylia siccae |
| 967 | Calamomyia phragmites |
| 5678 | Ceruraphis viburnicola |
| 1999 | Chilophaga tripsaci |
| 5078 | Chionaspis nyssae |
| 3140 | Coleosporium montanum |
| 3139 | Coleosporium solidaginis |
| 3242 | Cristulariella quercus-concentric-spot |
| 1247 | Cronartium quercuum (telial) |
| 4270 | Cynips erutor |
| 4271 | Cynips expletor |
| 1969 | Cystiphora taraxaci |
| 1972 | Dasineura alopecuri |
| 1784 | Dasineura anemone |
| 624 | Dasineura crataegibedeguar |
| 5919 | Dasineura l-benzoin-leaf-roll-dasineura |
| 2372 | Dryocosmus kuriphilus |
| 1810 | Ecdytolopha insiticiana |
| 1354 | Epitrimerus marginemtorquens |
| 3248 | Eriophyes cerasicrumena (on-p-americana) |
| 4493 | Erysiphe platani |
| 3963 | Eurosta comma |
| 773 | Eurosta solidaginis |
| 5047 | Exobasidium decolorans |
| 5109 | Floracarus perrepae |
| 3975 | Gnorimoschema crypticum |
| 5846 | Gnorimoschema s-latissimifolia-spindle-gall |
| 1507 | Gymnosporangium clavipes |
| 6002 | Gymnosporangium floriforme |
| 3477 | Gymnotelium blasdaleanum |
| 5564 | Hemitrioza sonchi |
| 2036 | Iatrophobia brasiliensis |
| 2081 | Japanagromyza lonchocarpi |
| 2074 | Jersonithrips galligenus |
| 1384 | Josephiella microcarpae |
| 2078 | Labania minuta |
| 1307 | Leuronota maculata |
| 5824 | Lonicerae l-interrupta-bud-gall-similar-to-L-lonicera |
| 3157 | Melampsora epitea |
| 4523 | Melanopsichium pennsylvanicum |
| 1849 | Mompha stellella |
| 3602 | Neolasioptera portulacae |
| 4272 | Neuroterus anthracinus (sexgen) |
| 1600 | Norvellina chenopodii |
| 3356 | Ophiodothella vaccinii |
| 4293 | Phylloplecta tripunctata |
| 1814 | Pileolaria brevipes |
| 1740 | Pineus pinifoliae |
| 2834 | Podosphaera physocarpi |
| 3480 | Prospodium transformans |
| 1803 | Pseudomicrostroma juglandis |
| 1610 | Puccinia asperior |
| 3346 | Puccinia mariae-wilsoniae |
| 3726 | Puccinia spegazzinii |
| 2257 | Pucciniastrum pyrolae |
| 2350 | Pulvinaria cockerelli |
| 2324 | Ravenelia arizonica |
| 2325 | Ravenelia holwayii |
| 4736 | Rhinusa pilosa |
| 1808 | Rhytisma andromedae |
| 5132 | Rhytisma arbuti |
| 1531 | Rhytisma prini |
| 4287 | Saperda fayi |
| 1383 | Smicronyx sculpticollis |
| 4953 | Sorosphaerula veronicae |
| 5008 | Synchytrium hydrocotyles |
| 1851 | Takamatsuella circinata |
| 1613 | Taphrina deformans |
| 4245 | Taphrina padi |
| 3263 | Testicularia cyperi |
| 1820 | Torymus druparum |
| 2076 | Trichochermes magna |
| 3158 | Trioza aylmeriae |
| 4163 | Walshia amorphella |
| 4173 | Zapatella nievesaldreyi (agamic) |

## Prevention

The taxonomy reclassification feature (see `docs/plans/`) will include an enforced-floor invariant that ensures naming patterns and the `undescribed` flag stay in sync. This will prevent future drift between the two.
