---
status: raw
created: 2026-02-13
updated: 2026-08-14
epic: idea-bucket
relates: [9005, 2cb2]
---

# iNaturalist integration

Photo import with proper attribution (high priority — helps admins significantly). Observation-informed range and abundance data. Taxonomic change tracking. Cross-links to iNat observations. Reduces admin burden while expanding coverage.

Maps architecture (4143) is being designed with iNat observation data in mind. MapLibre GL JS + PMTiles supports layering precomputed observation density data on top of the admin-boundary choropleth. Static generation, no real-time iNat queries. This also supports phenology map overlays when that work (439a) matures.
