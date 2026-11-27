> **The old model.** This describes the data model production (`main`) runs until the cutover: everything is a species. On `taxogall` the code runs on the new back-end, described by the [domain doc](domain-model.md) and [the architecture docs](../architecture/README.md); this doc stays only for work on the catalog migration, which reads the old tables, and is deleted after release.

## Key Domain Concepts

### Species
The standard scientific concept of a species. 

Each species has:
- **Taxonomy**: family, genus, species name
- **Abundance**: how common it is
- **Range**: geographic distribution
- **Aliases**: alternative names
- **Sources**: references to scientific literature

Both a Gall and a Host are Species.

### Galls
A gall is an abnormal plant growth induced by another organism. Each gall entry includes:
- **Morphology**: shape, color, texture, alignment, walls, cells
- **Location**: where on the host plant (leaf, stem, bud, etc.)
- **Seasonality**: when the gall appears
- **Detachability**: whether it falls off the plant
- **Hosts**: which plants it affects

They are:
- Insects (wasps, midges, aphids, flies, etc.)
- Mites
- Other organisms (fungi, bacteria, nematodes)

### Hosts
Plants that galls form on, with:
- **Taxonomy**: family, genus, species
- **Common names**
- **Geographic range**
- **Associated galls**

### Taxonomy
Standard biological classification:
- Kingdom -> Phylum -> Class -> Order -> Family -> Genus -> Species
- The database tracks only partial taxonomic levels and relationships: 
  - Family
  - Genus
  - Section (optional)
  - Species
