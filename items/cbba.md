---
plan: taxogall
phase: 63c6
rank: 30
title: Read and write all 15 Relationship kinds through their one writer, with qualifiers, both directions
stage: committed
created: "2026-11-15T20:53:21Z"
updated: "2026-11-22T02:26:29Z"
---

Catalog.RelationshipTypes holds the 15 kinds with their endpoints (taxon to Gall, Gall to Gall, taxon to taxon in a Gall) and qualifiers (required for formation, lethality, parasitism mode). Make each readable and writable through One write path's Relationship writer: a Gall's community on its page, the reverse view on an organism's species page ('found in these Galls'), qualifiers shown and edited, hyperparasitism derived from chains of parasitoid of, never stored. The screens come from The UI; failing tests first.

Deletes: nothing. Calls: the Relationship writer and reader from One write path; Catalog.RelationshipTypes.
