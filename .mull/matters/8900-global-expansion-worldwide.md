---
status: active
created: 2026-02-23
updated: 2026-02-23
epic: geo-expansion
docs: [docs/plans/2026-02-23-global-expansion-design.md, docs/plans/2026-02-23-continent-scoping-design.md]
relates: [1db6, b99b]
needs: [b99b]
---

# Global expansion (worldwide)

Expand from Western Hemisphere to worldwide coverage. Infrastructure-first — ship global map/places/continent selector, data populates organically. Target: Romania conference summer 2026.

## Status (2026-02-23)

Stream 1 (place data pipeline) complete on maps-rework branch:
- 8 continents, 249 countries, 4290 subdivisions in DB
- Global PMTiles (4880 features, 370MB)
- All tests passing (1079 tests, 0 failures)
- Supersedes Western Hemisphere expansion (1db6)

Remaining streams:
- Stream 2: Continent scoping UI (sticky selector, scope ID tool + Search)
- Stream 3: Data sourcing (WCVP reconciliation for global hosts)
- Stream 4: Branding/messaging updates
