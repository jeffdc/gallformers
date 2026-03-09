---
status: done
created: 2026-03-06
updated: 2026-03-09
epic: geo-expansion
relates: [b9e5, be9d]
---

# TDWG L3 mapping precision improvement

Our `tdwg_to_places.json` maps 361 TDWG L3 botanical regions to gallformers place codes. Currently only 123 (34%) are mapped at "exact" (state/province) precision. The other 237 use "country" precision — dumping all subdivisions of a country in, losing the geographic granularity that TDWG L3 actually provides.

## Current state

- US/Canada: 43% exact — good
- Russia/Central Asia: 56% exact — good
- Europe: 30% exact — mixed
- South America: 6-14% exact — nearly unmapped at state level
- Southeast Asia: 15% exact — sparse
- Africa: 24-42% exact — mostly country-level

## What needs to happen

Map each TDWG L3 code to the specific gallformers place codes (states/provinces) it covers, instead of dumping entire countries. The TDWG L3 system is already granular (e.g., Brazil split into ~7 regions, Argentina into botanical subregions). We just need to do the mapping work.

## Priority

Regions with the most host plants first. South America is a known gap (matter 7932). Southeast Asia and Africa follow.

## Notes

- This is mapping/data work, not code work
- The existing `Wcvp.Tdwg` module and `build_db` task don't need code changes — just better data in the JSON file
- Improving these mappings automatically improves range data quality for all hosts synced from WCVP
