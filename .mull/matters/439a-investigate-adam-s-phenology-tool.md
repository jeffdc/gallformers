---
status: raw
created: 2026-02-14
updated: 2026-02-16
docs: [docs/plans/2026-02-16-cynipid-phenology-product-vision.md]
relates: [85c0]
---

# Investigate Adam's phenology tool

GitHub: https://github.com/Megachile/Phenology

Goals:
- Get it primed for use with Claude Code (CLAUDE.md, documentation, etc.)
- Understand what it does and how it works
- Evaluate the codebase quality and architecture
- Propose a path forward: fold into gallformers codebase vs. integrate at some level

## Product exploration (2026-02-16)

Phenology data is one dimension of a larger cynipid product vision for Gallformers. iNat observations serve as a foundational data layer feeding three dimensions: phenology timing, fine-grained range, and abundance signal. Combined with existing host associations and future adult anatomy data, this enables:

1. Enriched species profiles — location-aware, temporally-aware pages
2. Collection/field planning — when and where to find target species
3. Field trip optimization — what's active near me on a given date
4. Improved gall-first ID — phenology as a filter to narrow candidates
5. New organism-first ID pathway — adult anatomy (via keys) + phenology + host narrows to species without seeing a gall

Keys play a dual role: navigation for users AND structured anatomy data source. Building adult cynipid keys and building the anatomy dataset are the same effort.

Scope is cynipid-only for now. Patterns could extend to other groups later.

Design doc: docs/plans/2026-02-16-cynipid-phenology-product-vision.md
