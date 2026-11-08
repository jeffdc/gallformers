---
status: raw
created: 2026-11-07
updated: 2026-11-07
epic: admin
relates: [c8c3, 6611]
---

# Import dry run at scale: recompute only the Galls a decision touches

Split out of `c8c3` item 9 (Jeff, 2026-11-07; to address 2026-11-08).

`Import.preview_package/2` (the dry run behind the review's reading of a Source) takes 0.25–1 s for 49 Galls (Nastasi & Davis 2022, package 97). A Source of ~570 Galls (Gagné 1989) may take 10 s or more, and it is recomputed after every decision. Recompute only the Galls a decision touches.
