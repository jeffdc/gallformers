---
status: done
created: 2026-03-10
updated: 2026-03-10
epic: geo-expansion
relates: [383e]
blocks: [600a]
needs: [0df8]
---

# Extract shared PlaceDrillDown component from CountryDrillDown

Extract CountryDrillDown (host tri-state) and RangeDrillDown (gall binary) into a single shared PlaceDrillDown LiveComponent with two modes. Layer 2 (0df8) adds tests asserting correct tri-state behavior on CountryDrillDown — those tests protect the extraction. Do this when gall-side migration (layer 3) needs it.
