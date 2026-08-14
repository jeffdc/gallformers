---
status: raw
created: 2026-08-12
updated: 2026-08-12
epic: admin
relates: [5c56]
needs: [2cb2]
---

# Gall merge workflow

Design and implement curator-driven merging of first-class gall records after matter `2cb2`. Requirements include choosing a surviving gall ID, preserving old `/gall/:id` paths through permanent redirects/history, and explicitly reconciling gall label, record classification, morphology traits, hosts, images, sources/excerpts, curated range, Gallformers Code, occurrence abundance, data completeness, and taxon-role-confidence associations. Reuse transaction, preview, audit, and conflict-resolution lessons from species merge/split matter `5c56`, but keep gall-structure merging distinct from taxonomic synonymization.
