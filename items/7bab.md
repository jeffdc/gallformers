---
plan: taxogall
title: 'Fact inspector is too slow to use: opening it on a Trait or other Fact takes 3-4 s, and so does changing the selected Fact'
stage: captured
kind: bug
category: performance
source: Jeff, 2026-11-09, trying the taxogall build
from: 74ac
created: "2026-11-09T20:55:40Z"
updated: "2026-11-12T02:23:22Z"
---

Jeff: 'not workable as is.' Not investigated or reproduced; no cause assumed.

What selecting a Fact does, for whoever investigates (from the inspector's build; checked in the code as of a0434bcf, not profiled):
- The Gall page (`GallformersWeb.GallLive`) loads all of a Gall's Facts once, on the first render too, as `gall_facts` (`Import.gall_facts/1`, `Gallformers.Import.GallFacts.for_gall/1`: each Fact with Gallformers' newest statement, the other Sources' statements newest first, its standing, and `past` for the Facts no longer current).
- Selecting a `fact_ref` patches the URL to `?fact=<key>` (`GallformersWeb.FactKey`; `push_patch`), so every selection, and every change of the selected Fact, goes through `handle_params`, which finds the Fact in `gall_facts` and loads its history: `Import.fact_history/1` (`Gallformers.Import.FactHistory`), read from the audit trail (Carbonite transactions and changes on the Fact's standing and its attributions, with each transaction's actor and the package's Source). It runs for readers and in Edit mode alike. In Edit mode `handle_params` also reloads the tray marks on every patch (`Curation.others_pending/2`, `Curation.pending_for/2`).
- In Edit mode the inspector is wrapped by `GallLive.FactActions` (a LiveComponent) with the tray state.

From the Fact inspector design and build (matter 87a1, tasks 2 and 5 and 'A Fact's history in the inspector'); Jeff, 2026-11-09, trying the taxogall build.
