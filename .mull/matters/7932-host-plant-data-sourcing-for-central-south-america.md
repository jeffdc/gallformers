---
status: refined
effort: 5 days
created: 2026-02-13
updated: 2026-02-25
epic: geo-expansion
docs: ['']
relates: [e617]
blocks: [1db6]
---

# Host plant data sourcing for Central/South America

## Research phase (2 days)
Identify data sources for Central and South American host plants. Evaluate coverage, data quality, and format compatibility.

## Data import phase (1 day)
Pull in data from sources identified in research phase. Map to existing taxonomy, resolve naming conflicts.

## Importer tooling (2 days)
Existing USDA importer (services/usda_plants/) will need to be updated or rewritten for new data sources. Name parsing is particularly tricky — botanical names from Latin American sources have varied formatting conventions, subspecies/variety notation, and author citation styles that make reliable parsing difficult.

## Data Source Research (2026-02-19)

### Tier 1: Bulk-downloadable, hemisphere-wide

**WCVP (World Checklist of Vascular Plants)** — Kew Royal Botanic Gardens
- Free CSV download from Kew SFTP: wcvp_names.csv + wcvp_distributions.csv
- ~340k accepted vascular plant species with family/genus/species, author citations
- Per-country distributions using TDWG Level 3 codes (maps to places table)
- CC-BY, updated weekly
- **Likely the single best starting point** — one download, clean taxonomy + geographic distribution for entire hemisphere

**GBIF (Global Biodiversity Information Facility)**
- REST API + async bulk downloads (DwC-A or CSV)
- Occurrence records not curated checklists — introduced/cultivated plants mixed in
- Strong for Brazil, Mexico, Colombia, Costa Rica, Argentina
- Free account required, CC-BY/CC0

### Tier 2: Regional depth

- **Flora e Funga do Brasil** — state-level + biome distributions, ~35k species. florabr R package or GBIF DwC-A. Essential since Brazil = ~70% of Neotropical gall research.
- **Tropicos** (Missouri Botanical Garden) — 1.4M names, especially strong for Neotropics. REST API with free key. Backbone for Flora Mesoamericana, Ecuador/Bolivia catalogs.
- **Colombia catalog** — 30k+ species, DwC-A download via SiB Colombia IPT.
- **Cono Sur catalog** — Argentina, Chile, Paraguay, Uruguay. ~19k species. R package available.
- **Mexico: eFloraMEX + CONABIO/SNIB** — eFloraMEX still under construction; Villasenor 2016 checklist (23,314 native vascular plant species) is the most cited comprehensive inventory. Practical route is Tropicos + GBIF.
- **Caribbean: Flora of the West Indies (Smithsonian)** — ~10,470 indigenous taxa, 71% endemic. Web-only, no API.

### Tier 3: Gall-specific (high value per record, labor-intensive)

- **Gagné & Jaschhof World Catalog of Cecidomyiidae** — definitive gall midge catalog organized by host plant family, global. PDF only. Already referenced as source/287.
- **Brazilian gall inventory literature** — SciELO papers, meta-analysis covers 51 studies/151 sites. Scattered across papers.

### Key URLs
- WCVP download: http://sftp.kew.org/pub/data-repositories/WCVP/
- WCVP portal: https://powo.science.kew.org
- GBIF: https://www.gbif.org
- Tropicos API: http://services.tropicos.org
- Flora do Brasil: https://floradobrasil.jbrj.gov.br
- Colombia IPT: https://ipt.biodiversidad.co/sib/resource?r=catalogo_plantas_liquenes
- Cono Sur: http://conosur.floraargentina.edu.ar
- Caribbean: https://naturalhistory2.si.edu/botany/westindies/
- World Flora Online: https://www.worldfloraonline.org
- Catalogue of Life: https://www.catalogueoflife.org

### Strategy
WCVP is highest-value single action: one download, one import pipeline, authoritative taxonomy, hemisphere-wide. TDWG-to-places mapping is straightforward. Gets host plant list; gall-host associations are separate problem in the literature.

## Current State & USDA Importer

- Initial plant import from USDA dataset done in 2021 during site bootstrap
- Many additions and edits since then — current DB is diverged from original import
- Importer is a Rust app at services/usda_plants
- Most complex part: name parsing (parser-combinator in plant.rs with messy botanical name rules)
- USDA data included range data for US and Canada alongside species names
- **Goal for W. Hemisphere expansion**: audit existing DB against new data sources before importing
