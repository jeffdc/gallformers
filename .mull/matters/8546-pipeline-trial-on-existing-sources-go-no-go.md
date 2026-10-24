---
status: raw
created: 2026-10-06
updated: 2026-10-23
epic: taxonomy
relates: [8567, 20e5]
needs: [294c]
---

# Pipeline trial on existing Sources (go/no-go)

# Pipeline trial on existing Sources (go/no-go)

Does LLM output reach an error rate no worse than a human transcriber, so the pipeline can feed Gallformers? Tested on existing Sources whose content the database already holds. On hold after five Sources (2026-10-15); next steps are being planned.

## Method

- Each Source runs through the six phases with the producer in `services/import-producer/` (Opus 5.5 on the subscription; reviews by Opus and Sonnet). Packages are in `services/import-producer/output/trial/` (gitignored).
- **Human check:** Jeff judges 40 random statements per Source (all of them for a small Source) against the scanned page, blind to the reviews, plus a few name matches. About 10–15 minutes per Source.
- **Dry run:** an approximate importer (`scripts/dryrun.py`) resolves names and Galls against the dev database and compares with the entries already linked to the Source.

## Results

| Source | Kind | Statements checked | Right | Cost (new flow) |
|---|---|---|---|---|
| Ashmead 1897 (98) | 19th-century BHL scan | 40 | 40 | ~$10 (projected) |
| Osten Sacken 1862 (21) | old scan, correction paper | 40 | 38 (2 wrong) | ~$7.50 (projected) |
| Floate 2010 (502) | born-digital paper, aphids | 40 | 38 (2 unsure) | $7.68 |
| Nastasi & Davis 2022 (680) | field guide, 53 pp | 40 | 40 | $9.95 |
| influentialpoints *Aphis rubifolii* (729) | web page | 17 | 17 | $2.72 |

**Pooled: 173 of 177 right; 1.1% wrong (exact 95% 0.1–4.0%), 2.3% counting unsure as wrong.** All four misses come from vocabulary definitions (season, 3) or one off-hand remark; none is a misreading of the page.

| Criterion | Target | Result |
|---|---|---|
| Hard gates (validation, no wrong denials, no wrong Inducer/Gall identity) | pass | met |
| Precision | ≥ 95% right, ≤ 2% wrong | met |
| Planted errors caught by phase 5 | ≥ 8 of 10 | 15/15 (Opus), 14/15 (Sonnet) |
| Fix rounds | ≤ 2 | 1 (phase 6) |
| Name resolution and recall of DB entries | ≥ 85% / ≥ 90% | modern Sources 100%; old Sources need the importer rules (now in the dry run) and historical plant names (`d585`) |
| Cost and time | median ≤ $5, ≤ 15 min | not met: $7.70–10 and ~20 min per paper; accepted for now |

## Findings that shaped the contract

- Old scans read well enough once phase 1 picks the better of the scan's own text and fresh OCR, outside Docling.
- The two reviewer models catch different errors; together they caught every planted error.
- Fix-and-re-review loops don't converge; phase 6 (producer agrees or disputes, humans decide disputes at intake) does.
- Most remaining errors are vocabulary definitions, fixable once for every Source.
- Undescribed galls and 19th-century names need importer rules; ambiguous matches need an admin queue.

## Not yet tested

A long scanned catalogue (Gagné 2008, ~$20) and a key (Felt 1917, 352 pp, may exceed one batch).

Check pages (private): Ashmead https://claude.ai/artifact/Ns3bRDFP95sUKkT3NUzW1x · 1862 https://claude.ai/artifact/2ZtVyD8m1cjqoq9kXLCn1z · Floate https://claude.ai/artifact/LQ1sAQ6GFvC6csYnhCiiad · field guide https://claude.ai/artifact/LVcz9oNbpmdys2oMgrGq4h · web page https://claude.ai/artifact/CcjPZXZBZV58LsFNs9K81F
