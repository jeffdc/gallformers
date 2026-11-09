---
status: raw
created: 2026-11-07
updated: 2026-11-09
epic: admin
relates: [6611]
---

# Import dry run at scale: recompute only the Galls a decision touches

Split out of `c8c3` item 9 (Jeff, 2026-11-07; to address 2026-11-08).

`Import.preview_package/2` (the dry run behind the review's reading of a Source) takes 0.25–1 s for 49 Galls (Nastasi & Davis 2022, package 97). A Source of ~570 Galls (Gagné 1989) may take 10 s or more, and it is recomputed after every decision. Recompute only the Galls a decision touches.


## Measured (2026-11-08, on a copy of `gallformers_taxogall`)

| Package | Dry run before | Dry run after the slot fix | A decision (re-resolve) |
|---|---|---|---|
| 118, 21 Galls, gall batch writes ~200 Facts | 1.8 s | 0.7 s | 0.34 s (resolve) |
| 116, 39 Galls, gall batch held | 1.2 s | 0.9 s | 0.65 s |

- **Slot fix (uncommitted):** `Facts.with_slot_siblings/1` used `id IN … OR slot IN (subquery)`, a full scan of `facts` on every Fact written (2.5 ms × 362 per dry run). Reading the slots first and passing them as a list lets both conditions use their index. It also speeds up approval.
- **Still linear:** the dry run costs ~3.5 ms per Fact written (~25 small queries per Fact: attributions, evidence, names, Carbonite transaction rows, locks). A decision costs ~16 ms per Gall to re-resolve the package (taxon name, common name and ancestry lookups per name). For ~570 Galls (Gagné 1989) that's roughly a 15–20 s dry run in the background and a ~9 s wait on every decision.
- **Two routes:** (A) batch the per-Fact and per-name queries in the Fact writer and the resolver. This is general, also speeds up approval, maybe 3–5×. (B) Re-resolve and re-preview only the Galls a decision touches. This is riskier: a taxon or Trait-term decision touches many Galls, and a partial recompute must match a full one. Recommended: A first, measured on a large test package (the five v6 Sources combined), then decide whether B is needed. Waiting on Jeff.


## Status (2026-11-09)

- The slot fix is committed (`14c19024`).
- Jeff chose route A (2026-11-08): batch the per-Fact and per-name queries in the Fact writer and the resolver.
- Not started beyond profiling. The next step is to build a large test package from the five v6 Sources, then profile one dry run and one decision on it. Count queries per table with a telemetry handler on the Repo's query events, and use `:tprof` for time (it needs `Mix.ensure_application!(:tools)` first). After that, batch the largest classes. From the 2026-11-08 counts, those are Carbonite transaction inserts (~534 per dry run), locks, per-Fact attribution and evidence inserts, Source lookups (~163) and `trait_term_mappings` lookups.
- `gallformers_c90c` on 127.0.0.1:54317 is a fully migrated copy of `gallformers_taxogall` to profile against. Drop it when this is done.
