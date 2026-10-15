---
status: done
created: 2026-10-07
updated: 2026-10-15
epic: taxonomy
relates: [8546, e381, 294c]
---

# Import producer POC (Docling + headless Claude Code)

# Import producer POC (Docling + headless Claude Code)

Proof of concept for the producer side of the import contract (`priv/import/`, format v3, `e381`): turn a gall-related Source (PDF) into a package — `document.json` (phase 0), `taxonomy.json` (phase 1, if any acts), `gall.json` (phase 2) — that passes `uv run priv/import/validate.py <package-dir>`. Feeds the go/no-go trial `8546`, including its phase-0 format check (Docling on born-digital and scanned Sources).

## Goals (Jeff, 2026-10-07)

1. Phase 0: PDF → DoclingDocument; judge whether it is good enough for born-digital and scanned PDFs.
2. Phases 1–2: an LLM reads the document and produces batches following the guide exactly; every batch validates.
3. Run on 2–3 Sources Jeff provides; report what worked, what failed, rough cost per Source, and where the contract seems wrong or unclear.

Rules: **don't change the schema, vocab or guide — report problems instead.** Ask before every run that spends model usage.

## Decisions (2026-10-07)

- **Fresh build, not source-ingestion.** `e381`: the old Python POC does not carry forward. New uv project at `services/import-producer/`; outputs in gitignored `output/`.
- **Model: Claude Opus 5.5 on Jeff's Claude subscription**, via headless Claude Code (`claude -p --model claude-opus-5-5`), effort `high` to start; tune after judging output. Unset `ANTHROPIC_API_KEY` for the child process so it bills the subscription, not the API (verify on first run). `--safe-mode` so user CLAUDE.md, hooks, skills, memory don't leak into the producer.
- **Runner: a driver script** (`uv run produce <pdf> -o output/<name>`) runs phase 0, then one `claude -p` per phase; phases runnable individually (phase 0 is free). Writes `run.json`: per-phase tokens, API-equivalent cost (`total_cost_usd`), turns, duration, validation results.
- **Phase 0:** Docling converts PDF → `document.json`. Born-digital vs scanned decided by embedded subset fonts + full-page-image fraction (text extraction alone is not a signal); scans get full-page OCR (compare ocrmac vs tesseract). `--ocr auto|force|off` override. A `quality` report (items per label, chars per page, empty pages, tables, furniture, coverage vs text layer, OCR noise) plus manual inspection decides "good enough".
- **What the LLM reads:** a deterministic `document.txt` rendered from `document.json`, one line per item (`#/texts/42 p12 [paragraph] …`), furniture marked. Refs are the real Docling refs, so evidence anchors stay the document's. (Interpretation of the guide's "phases read the document": read its items, not raw bbox-heavy JSON.)
- **Producer agent inputs:** `PRODUCER_GUIDE.md`, `schema/*`, `vocab/*.schema.json`, `examples/*`, read in place (never copied — the contract stays the single source of truth); `document.txt` / `document.json`; `taxonomy.json` in phase 2. **Not** `docs/domain/domain-model.md` — tests whether the guide stands alone; gaps become contract findings.
- **Agent tools:** Read; Write/Edit in the package dir; Bash restricted to `validate.py`, `lookup-place` (search `vocab/places.json`, too large for the prompt), and `check`. Loop: write → validate → check → fix until clean.
- **Deterministic envelope values** (`batch_id`, `produced_at`, `producer` incl. `model` and `instructions_version` = prompt hash, `vocabulary_version`, document sha256) are supplied by the driver in the prompt.
- **`check`** — local, diagnostic subset of layer 2: quote found in its item (whitespace/hyphenation normalized), `whole_item` items exist, refs declared, qualifier targets/types (§5.3), ≤1 inducer per Gall, `new` Galls have Facts. Not a contract change.
- Phase 1 writes no `taxonomy.json` when the Source states no acts and says why in `notes.md`.
- **Testing:** TDD (pytest) for deterministic parts (scan detection, rendering, place lookup, checks). LLM phases tested only by authorized runs.
- **Known risk:** long catalogues may produce a `gall.json` larger than one response's output. No chunking up front; report it if hit.

## Docs used to build

Docling official docs (docling-project.github.io) + the installed package source for exact API; Claude Code CLI/headless docs (verify `--safe-mode`, `--tools`/`--allowedTools` Bash patterns, `--output-format json` fields, prompt-file passing, API-key vs subscription precedence).

## Phase-0 test corpus

Existing PDFs in `services/source-ingestion/output/*/source.pdf` (born-digital e.g. `nicholls`, `gagne-2008-hickories`; scans e.g. `ashmead-1896`, `kinsey-1929`, `felt-1917-key`) for free Docling runs before the trial Sources arrive.

**Report for Jeff and Adam (2026-10-07):** [Import producer POC: findings](https://claude.ai/code/artifact/161000a1-0ec6-473b-8e1c-5c739d6b4f45) — what worked, what didn't, what has no solution yet, results, phase 0, extraction quality, all contract findings by theme.

## Built (2026-10-07)

`services/import-producer/` (uv, Docling 2.135, Python 3.13; 47 tests, ruff clean). Commands (`uv run produce …`): `convert` (phase 0 → `document.json`, `document.txt`, `phase0.json` with quality report), `render`, `phase --phase 1|2 [--effort] [--dry-run]` (headless `claude -p`, writes `phaseN.prompt.md`, `phaseN.stream.jsonl`, appends `run.json`), `check`, `lookup-place`. Prompt template: `prompts/producer.md`; contract files inlined from `priv/import/` at run time; envelope values fixed by the driver. Child env strips `CLAUDE*`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`; no `apiKeyHelper` configured.

## Results

### Phase 0 (Docling), 2026-10-07

| PDF | Kind | Path | Coverage vs text layer | Notes |
|---|---|---|---|---|
| wise-2007 | born-digital | text layer | — | 49 s first run (model download) |
| nicholls | born-digital | text layer | 0.96 | 14 s; prose clean; **Table 1 (4×234 species-pairing grid) mangled**, rows merged |
| melika-1997 | scan w/ OCR layer | existing layer | 0.95 | 5 s; clean, columns correct |
| ashmead-1896 | BHL scan | existing layer | 0.97 | 10 s; good structure; the scan's own OCR errors (antenne, punetate) |
| costa-rica | image-only (slide deck) | tesseract full-page | 0.81 | tables of hosts came out well |

- **Decision: scans that already carry an OCR text layer use that layer** (with Docling's layout model); only image-only PDFs are re-OCR'd (tesseract). On melika-1997, macOS Vision OCR (`ocrmac`) **interleaved the two columns line by line** in both full-page and layout-region modes — fatal for quotes. Tesseract kept columns apart but was ~10× noisier than the existing layer (0.91% vs 0.09% suspicious tokens). Reverses the design's "re-OCR scans" assumption.
- Running headers/footers come through as `furniture` and carry printed page numbers → usable for `evidence.page`.
- Sex symbols (♀♂) are mangled by every OCR path; irrelevant to gall data.
- Judgement so far: DoclingDocument is good enough for prose in both born-digital and OCR-layer scans; complex multi-row tables are the weak spot.

### Phases 1–2

Smoke test: `apiKeySource: none` (subscription), allowed Bash ran, `ls /` denied, writes inside the package allowed; $0.03.

| Source | Phase | Result | Turns | Time | Cost (API-equiv.) |
|---|---|---|---|---|---|
| wise-2007 | 1 | correctly no taxonomy.json | 5 | 39 s | $0.58 |
| wise-2007 | 2 | gall.json valid + check clean, first try | 5 | 101 s | $0.74 |
| melika-1997 | 1 | 33 taxa, 40 acts (4 sp. nov., 21 synonymies); valid + clean | 5 | 171 s | $1.05 |
| melika-1997 | 2 | 14 Galls (3 new), 126 Facts (2 deny), 18 unmapped; valid + clean | 42 | 466 s | $2.43 |
| nicholls | 1 | 107 taxa, 98 acts (80 synonymy incl. 2 deny; 2 comb. nov., 2 comb. rev.); valid + clean | 7 | 469 s | $3.08 |
| nicholls | 2 | 51 Galls, 328 Facts, 31 unmapped; valid + clean | 16 | 843 s | $4.86 |

**Per Source (API-equivalent `total_cost_usd`, billed to the subscription):** wise-2007 $1.31 / 2.5 min; melika-1997 $3.48 / 10.5 min (≈$1 of it the page-number detour, since fixed); nicholls $7.94 / 22 min. Total incl. smoke test ≈ $12.76. Cost is dominated by re-reading the cached prompt each turn (contract ≈ 18k tokens + document), so turns matter more than output.

**nicholls vs database (Source 559, 27 entries):** all 26 two-generation entries match, with all 13 `alternate_generation_of` pairings; DB *Acraspis gemula (sexgen)* ↔ producer's *Philonix pallipes* sexual Gall (a synonym the Source discusses). Taxonomy: the melika-1997 synonymy of *N. floccosus* is reversed as a `synonymy` act with stance **deny** ("Melika & Abrahamson (1997) erroneously synonymized N. floccosus with N. quercusverrucarum") — the recency rule can resolve it. Recombinations composed per §4. Producer added 25 Galls the Source only mentions (comparisons, Kinsey's "complexes") — not wrong per the guide, but review load. Range: 10 includes (CA-AB on introduced bur oak; DE on introduced Q. rubra) and 2 excludes, reasoned. No Gall marked `new` — deliberately deferred (finding 22).

### Overall judgement

- **Worked:** every batch (5) passed `validate.py` and the local `check` (every quote found in its item) on the run's own loop; acts and Facts composed as the guide intends, including deny stances; agreement with the database is high where the DB holds the Source; producer notes are the most valuable output — specific contract questions with quotes.
- **Weak:** Docling on complex/rotated tables (wise appendix, nicholls Table 1); scans' OCR layers interleave columns in places and mangle ligatures (names won't resolve); consistency between runs on judgement rules the guide doesn't state (reported vs adopted acts, placements from passing remarks, mentioned-only Galls); read-only Bash leakage.
- **Not verified:** no layer-2 dry run (name/Gall resolution) exists yet; Facts were spot-checked, not audited one by one.

**melika-1997 vs database (Source 78, 11 entries):** the 9 entries for the 8 treated species match (incl. both N. quercusbatatus generations, linked by `alternate_generation_of`). DB's *N. floccosus (agamic)* appears here under *N. quercusverrucarum* — this 1997 Source synonymized floccosus; nicholls 2022 revived it (comb. rev.), so the DB has re-assigned this Source's data. That is exactly the re-resolution `name_as_written` is for. DB's *N. pallidus (sexgen)* ≈ producer's *N. pallidus* Gall (no generation given in the passage). Producer added 4 Galls the Source only mentions (N. dubius, N. exiguus, N. quercusirregularis var. albipleurae, N. chrysolepis). Denials are both explicit ("The leaf petioles are never involved in gall formation"; a host record reassigned to another species).

**Why 42 turns:** ~29 single-item Edits adding printed page numbers after its script to compute them was denied. Each turn re-reads ~90k cached tokens, so roughly $1 of the $2.43. **Fix (producer, 2026-10-07):** `document.txt` now shows the printed page per item (`p12=571`, inferred `p13=~572`), derived from numbers in running heads (one offset supported by ≥2 pages; contradicting pages left blank). Matches the agents' own mappings on melika, wise, nicholls (offset 0), ashmead. Prompt says to use it and not compute pages.

**Lockdown gap:** outside the three allowed commands, `ls && cat …` and an inline `python3 -c` (reading document.json) *ran* — Claude Code auto-approves commands it classifies read-only (and the user rule `Bash(cat *)` still applies under `--safe-mode`). Writes outside the package (`/tmp`) and a heredoc script were denied. Read-only leakage can't be blocked while the agent has Bash; full lockdown would mean exposing validate/check/lookup as an MCP tool and removing Bash.

Prompt `producer.md@45cb89a47198` onward adds a "clarifications" block (swelling candidates with DB definitions; inflorescence/raceme → flower; taxa above family → unmapped) — Jeff, 2026-10-07.

**Phase-0 revision (from melika-1997 phase 1):** the scan's own text layer is *not* clean everywhere — columns interleave in texts/97–98 and 103, and the "fl" ligature is OCR'd as "Jl", "$0", "~7" (*Cynips flocossa* → "Cynips Jlocossa"). Still better than re-OCR here, but scans need a per-Source judgement.

**wise-2007 vs database (Source 184):** *Lasioptera solani* stem gall matches (inducer, host, plant part, quoted description). *Anthonomus nigrinus* is linked in the DB, but the Source never calls its bud damage a gall; the producer left it out — a DB-vs-Source disagreement of the kind `8546` wants reviewed. It also declined to invent Galls for *Neolasioptera* sp. and *Prodiplosis longifila* (leaf rolls), and flagged them for a reviewer.

### Free follow-ups (2026-10-07)

Scripts: `scripts/dryrun.py` (approximate layer-2 resolution + Fact diff against `gallformers_dev`, writes `<pkg>/dryrun.json`), `scripts/audit_sample.py` (seeded sample for a manual support audit).

**Resolution (approximate importer: exact names, scientific aliases, normalization for case/"var."/subgenus/hybrid sign, genus abbreviations expanded from genera in the batch or document):**

| | wise | melika | nicholls |
|---|---|---|---|
| Galls resolved to one entry | 1/1 | 13/14 | 49/51 |
| DB entries for the Source found | 1/2 | 10/11 | 27/27 |
| Gall-batch names resolved | 2/2 | 23/25 | 67/80 |
| Taxonomy-batch names resolved | — | 27/33 | 95/107 |

- Unresolved names are: parasitoids/inquilines (Gallformers has no taxa for them at all — *Sycophila*, *Eurytoma*, *Ormyrus*, *Ceroptres*); hybrids and plants missing from the DB (*Q. ⨯ bebbiana*); Kinsey-era combinations and varieties with no alias in the DB; OCR-damaged names ("Jlocossa"); spelling/gender variants (*spinosus/spinosa*, *engelmannii/engelmanni*).
- Abbreviations ("Q. alba", 40 in nicholls) resolve only with document context — the batch alone never writes *Quercus* in full.
- Fuzzy matching is unsafe: "Atrusca carolina" → *Atrusca capronae*; "Callirhytis balanaspis" → *C. balanopsis* (a different entry).
- DB ambiguity: alias "Biorhiza fulvicollis" points at two species.
- **Silent merge risk:** *Acraspis bandero/hirtior/ulterior* — valid species per the Source (and its taxonomy batch) — are aliases of *A. quercushirta* in the DB, so resolving against today's DB folds their Galls into *A. quercushirta (agamic)*. Resolution must apply the pending taxonomy batch first (§7.10).

**Fact diff vs DB (resolved Galls):** hosts in both 106, batch-only 12, DB-only 127 (DB-only expected — other Sources). Of the 12 batch-only hosts, 7 are stated by the Source (DB gaps) and 5 come from a Kinsey "complex" host list the producer itself flagged as doubtful. Traits: 154 agree, 40 batch-only, 536 DB-only. Descriptions differ in scope, not accuracy: the DB's per-Source "description" is often the whole species account (synonymy, varieties); the contract's is gall-only quotes.

**Support audit (48 random statements, seed 20261007):** 39 clearly supported; 4 true but with weak evidence (figure captions); 4 supported but dependent on unsettled rules (placement from a passing remark; misspelling as synonym; include from an introduced host; season from adult emergence); 1 overreach (a host denial where the Source only reassigned one record); 0 plainly wrong.

**Phase 0, more Sources:** gagne-2008 (147-page scan): 21 s, 98% coverage, OCR damage inside names ("Cqryomyia", "Caryomyiaflaticrnstum"). nastasi-davis (field guide): 94%, excellent per-field structure (Host / Gall location / Description / Range); image credits come through as body text. Website (influentialpoints, Source 729): Docling's URL fetch hung >10 min; converting the saved HTML took 0.1 s but navigation/layout tables become body text and the species text is duplicated (layout-table cell + word fragments).

### Contract findings (from producer notes + review)

1. **No way to record "phase 1 ran and found no acts."** `validate.py` rejects a package with only a document; a taxonomy batch with empty `acts` is allowed only for retractions (§7.11). "Ran, found nothing" is indistinguishable from "never ran".
2. **Classification shown to organize a list is not a placement act** — §4 should say so; checklist appendices would otherwise yield dozens of spurious placements.
3. **Ranks stop at family**, so parasitoids identified only to superfamily/order ("proctotrupoid wasps") can't be declared; went to `unmapped` with slot `rank`. Common in gall literature. **Jeff (2026-10-07): the contract is wrong here — taxonomy above family is wanted; only lumps/splits above family are unsupported.** §4 "Nothing above family" and `vocab/ranks.schema.json` need changing (for `294c`).
4. **Vocabulary lacks definitions and synonyms** (surfaced as "no plain swelling form", "no inflorescence plant part"). **Jeff (2026-10-07):** "swelling" is a synonym whose candidates are tapered swelling, stem club, abrupt swelling; inflorescence and raceme are parts of the flower (`plant_part: flower`). The DB `form` table has a definition per value (tapered = gradual; abrupt = emerges directly from unaffected tissue; stem club = enlarged growing tip of a woody plant); `vocab/traits.schema.json` carries only bare enums, so the producer can't know scope or synonyms. **Proposed fix:** vocab files carry each value's definition and synonyms (vocab generator task).
5. **§5.2 "reared from":** unclear whether context ("gall midges" + "reared from these galls") is enough for `inducer_of` over `emerged_from`.
6. **Common-name-only Hosts:** unclear whether `name_as_written` may use the scientific name given elsewhere in the Source for a plant a passage names only by common name.
7. **Status changes are not expressible** (variety → species, stat. rev. when the Source doesn't use those words): only implied by a `name` act at the new rank.
8. **Synonymy can't distinguish "new synonymy" (this Source's act) from synonyms it merely repeats**, nor available names from chresonyms/misspellings ("Neuroterus batata Basset: Ashmead 1885a"). May matter for priority between Sources.
9. **`name_as_written` vs OCR errors:** the document says "Cynips Jlocossa" (printed "flocossa"). Verbatim keeps the quote verifiable but the name won't resolve. Which wins?
10. **The guide's `revision` example invites spurious placements:** it states a placement from a passing remark ("Andricus, the largest genus of the tribe Cynipini"); the melika producer followed it (Neuroterus → Cynipidae from the title; Tetrastichinae → Eulophidae from a parenthetical). Conflicts with finding 2.
11. **A name split across two items** (heading line break, interleaved columns) can't be one quote; producer used two evidence entries. Fine, but the guide could say so.
12. **Host-dependent Traits** ("smooth and large when on Q. alba … pubescence denser … on Q. stellata") can't be scoped to a Host.
13. **"Only" restrictions** ("on Q. breviloba (in Texas only)") can't be stated: range adjustments are include/exclude relative to Host ranges the producer is told not to know.
14. **Doubted records** ("Q. macrocarpa … but this must be confirmed"): stance is only confirm/deny.
15. **Secondhand statements** (Source citing Kinsey 1923) count at the citing Source's date; no way to mark them. Matters for the recency rule.
16. **`new` for a known Gall whose Inducer is newly described** (N. weldi: gall reported by Weld 1959, wasp named 1997) isn't covered; Gallformers likely holds it as an undescribed Gall this Source now names.
17. **Trait semantics unclear:** `detachable` for galls that drop only after emergence or with the organ; `season` (visible vs develops vs emerges); `shape: numerous`/`cluster` describe counts/grouping, not shape.
18. **More vocabulary gaps:** plain "leaf" (no side; 8 unmapped in nicholls alone); ovoid/oval/oblong/rounded (shape; 10 in nicholls); woody vs soft (texture); perpendicular (alignment); undefined `pip`/`hat` ("seed-like", "mushroomlike"?); `hidden cell` chosen from its name alone. Swelling definitions are stem-centric (midrib swellings don't fit).
19. **Nomenclatural status not expressible:** nomen dubium, unavailable names, misspellings/chresonyms (only `synonymy` exists).
20. **`new.status` values:** guide lists sp./gen./comb./stat. nov.; are comb. rev., stat. rev. allowed? Nowhere to mark syn. nov. (overlaps 8).
21. **Reported vs adopted acts:** "Synonymized by Beutenmueller (1907)" in the Source's synonym list vs "Melika & Abrahamson (2002) synonymized …" in a comment. Runs drew the line differently (overlaps 10). Needs a rule.
22. **`new` for a newly described generation** of a known species ("This is the first sexual generation to be described for Phylloteras"): fits §5.1 literally, but may duplicate an entry Gallformers already holds. **Needs Jeff's decision**; producer left all unset.
23. **Range includes vs introduced hosts:** do Gallformers' Host ranges include introduced populations? Decides whether "on introduced bur oak in Alberta" is an include.
24. **Species-level statements vs generation-level Gall entries:** distribution and "earlier records" are about the species; Facts attach to one generation's Gall. Apply to both?
25. **Hedged statements** ("putative", "may", "must be confirmed"): no certainty level beyond confirm/deny (with 14).


## v3 tightening (2026-10-08)

After the producer POC trial (`ca20`), v3 was tightened without a version bump (draft, no consumers): any Linnaean rank (no synonymy/split above family); taxonomy batch always written (empty = no acts); `status_as_written` on acts; `name_reading` for OCR-damaged names; `formerly_undescribed` Galls; range adjustment `only`; evidence `cites`; hedged statements → `unmapped`; newly described generations are `new`; Host ranges include introduced populations; `vocab/traits.json` with definitions and synonyms; `validate.py` checks quotes and references against the package's document. Decisions and the build list: `294c`.


## melika-1997 re-run on the tightened contract (2026-10-08)

Package `output/melika-1997-v2` (same `document.json`, re-rendered with printed pages; first run kept in `output/melika-1997` for comparison). Prompt `producer.md@1ada6c9f387e`. POC `check.py` deleted (superseded by `validate.py`).

| Phase | First run | Re-run |
|---|---|---|
| 1 | 33 taxa, 40 acts; 5 turns, 171 s, $1.05 | 30 taxa, 30 acts; 5 turns, 141 s, $1.09 |
| 2 | 14 Galls, 126 Facts; 42 turns, 466 s, $2.43 | 14 Galls, 132 Facts; **6 turns**, 398 s, **$2.10** |

What the tightening changed:
- **Placements:** 11 → 4 (only the new species in *Neuroterus*). Neuroterus → Cynipidae (title) and Tetrastichinae → Eulophidae (parenthetical) are gone; redescribed species no longer get name/placement acts just for being used.
- **`status_as_written`:** the 4 "New synonymy." acts are marked; the 17 repeated synonyms are not. One misuse: the variety → species change got "in our opinion, is a distinct species" (a quote, not status words).
- **`name_reading`:** "Cynips Jlocossa" → "Cynips flocossa", "Neuroterus Jlocossus" → "Neuroterus flocossus"; both now resolve. Taxonomy-name resolution 27/33 → 27/30 (82% → 90%); remaining misses are "Cynips q. irregularis" (abbreviation inside the epithet) and *noxiosus/noxiosa* — importer normalization.
- **`formerly_undescribed`** on the *N. weldi* Gall, with Host *Q. chapmanii*.
- **`cites`** on 20 evidence entries; printed `page` on 148 of 170 (from `document.txt`, no hand work — the cause of the first run's 42 turns).
- **Reassigned record** (Q. geminata) no longer a deny. Denials: "petioles are never involved" (plant_part) and "not woody … easily cut like cheese" (texture `stiff`, via the woody → stiff mapping).
- **Hedges** to `unmapped`: Viereck's "must be confirmed" record; "probably those Weld …".
- Declined, with reasons: "rounded" (a low leaf thickening, not a 3-D shape); "in Texas only" (ambiguous: the variety's range or its Host record; and the variety may be folded into the species); both detachable cases cite the guide's open question.

New contract questions from the re-run:
1. **Hedged identity vs `formerly_undescribed`:** "the galls induced by N. weldi are probably those Weld described" — a flag, not a Fact; should a hedge set it?
2. **Explicit negatives with no taxon:** "No inquilines were reared from these galls" — `inquiline_of` needs a subject.
3. **Facts about infraspecific taxa the Source doesn't treat** (N. quercusirregularis var. albipleurae on Q. breviloba): if Gallformers folds the variety into the species, its Facts (and an `only`) would land on the species' Gall.
4. **Trait denials:** used for plant_part and texture; the guide discusses deny only for Relationships. (`e381` v3 decision 9 says only an explicit denial withdraws a multi-valued Trait — so yes, but the guide should say it.)
5. **Vocabulary:** no form for an integral leaf thickening protruding on both sides (common in *Neuroterus*; `leaf blister` is a cup opening below); `cylindrical`'s definition assumes an erect gall.


## Old BHL scans: the upside-down OCR problem (2026-10-11)

**Root cause.** Docling's tesseract step (`tesseract_ocr_cli_model.py`) runs tesseract orientation detection (OSD, `--psm 0`) on every page and rotates whenever it reports a non-zero angle — no confidence threshold, no option to disable it. The PDFs and renderers are fine (BHL page images are upright). OSD is unreliable on 19th-century typefaces:

| Scan | Pages falsely flagged 180° | OSD confidence |
|---|---|---|
| 1862 "Additions and corrections" (Source 21) | 5 of 21 | mostly 1–8 |
| Ashmead 1896 (Source 98) | 5 of 26 | mostly 1–8 |
| Melika 1997 (Source 78) | 0 of 14 | 20–30 |

Every flagged page checked was upright (incl. the highest-confidence one, 13.57).

**Does fresh OCR beat BHL's text layer?** Tesseract per page, upright, OSD off (`--psm 3 -l eng`), vs the existing layer:

| Scan | Dictionary words (layer → fresh) | Suspicious tokens | Expected words found | Non-space chars |
|---|---|---|---|---|
| 1862 | 77.6% → 80.7% | 0.67% → 0.27% | 8/12 → 9/12 | 38,969 → 38,681 |
| 1896 | 81.9% → 82.1% | 0.12% → 0.18% | 7/9 → 8/9 | 54,608 → 54,609 |

- 1862: fresh OCR is moderately better (noise halved; destroyed words like "([i/nqndse" come back as "Cynipide"; 37 vs 25 name hits). 1896: a tie. BHL layer quality varies by item.
- Both paths mangle the æ ligature (CYNIPIDÆ → "CYNIPID^" / "CYNIPIDZ"; antennæ → "antenne"). `name_reading` covers names; an `eng+lat` tesseract model is untested.
- **Metric bug:** the phase 1 "coverage vs text layer" ratio counts whitespace. BHL layers are ~37% whitespace (fresh OCR ~18%), so the 1862 "75% coverage" was whitespace, not lost text. Compare non-whitespace characters.

**Implications.** No blanket re-OCR rule: per Source, the better text should win. Any re-OCR path must bypass Docling's OSD (OCR outside Docling — e.g. OCRmyPDF or our own tesseract call — then Docling with OCR off), and the OSD-without-threshold behavior is worth reporting upstream to Docling.



## Phase 1 for scans: best text per scan (2026-10-11)

**Built** (`services/import-producer`, 54 tests, ruff clean):
- Coverage now compares non-whitespace characters (`quality.nonspace`).
- `producer/ocr.py`: OCR happens **outside Docling**. For every scan (`--ocr auto`), OCRmyPDF `--force-ocr` (tesseract `eng`, no page rotation) makes a fresh text layer; both texts are measured (non-space chars, dictionary-word rate on lower-case 4+ letter words, suspicious-token rate). Fresh wins only if it keeps ≥95% of the layer's characters **and** reads ≥1 point better on dictionary words; a PDF without a usable layer always gets fresh. `--ocr force` = always fresh, `--ocr off` = never. Docling then reads the chosen PDF with its OCR off. Decision and both measurements go in `convert.json` (`ocr`), along with the Docling `backend`.
- `ocrmac` dependency and the `--engine` / `--ocr-mode` options removed.

**Two more Docling problems found and fixed on the way:**
1. **OCRmyPDF `--redo-ocr` is wrong for some BHL scans.** Ashmead 1896 draws its old OCR as ordinary (render mode 0) text hidden under the page image, not as invisible text. Redo mode keeps text it thinks is visible and blanks those words out of the image before OCR (OCRmyPDF `_pipeline.py`: "Mask visible text, but not invisible text"), so it kept the old text and OCR'd letter fragments ("w..wched" for "attached"; text doubled). `--force-ocr` OCRs the whole rendered page. Regression test reproduces it.
2. **Docling's default PDF backend (docling-parse) smears layered (MRC) scan pages.** Felt 1917 pages are a low-res JPEG2000 background plus a masked high-res foreground; docling-parse rendered only a muddy background, the layout model found no regions, and all 12,536 lines became separate items with running heads in the body. **Scans now use Docling's pypdfium2 backend** (renders them correctly); born-digital PDFs keep the default.

**Results (free, `output/phase1-v2/`):**

| Scan | Text kept | Dictionary words layer / fresh | Non-space chars layer / fresh | Coverage | Items |
|---|---|---|---|---|---|
| 1862 Additions (21) | **fresh** | 85.4% / 88.8% | 38,969 / 38,694 | 99.2% | 214 |
| Ashmead 1896 (98) | layer | 90.6% / 90.5% | 54,608 / 54,630 | 97.8% | 394 |
| Gagné 2008 (123) | layer | 80.6% / 80.3% | 446,128 / 451,747 | 98.1% | 1,760 |
| Felt 1917 (7) | layer | 79.2% / 76.2% | 362,171 / 378,563 | 99.5% | 7,613 |

(Dictionary rates are higher than the earlier table because plurals now count via the singular.)

- No page is upside down: the 1862 fresh text reads 83–93% on every text page (page 1 is BHL's cover sheet).
- Felt now has 528 running heads, 392 section headers, 282 pictures, 22 tables; the near-empty pages 246–310 are photo plates and their blank backs.
- OCR adds ~6 s (21 pages) to ~60 s (352 pages) per scan.

**Known noise:** with the pypdfium2 backend, Gagné 2008 gets 224 items that are a lone "—", placed just above the page top (y ≈ −5). The text layer's real dashes all sit inside their paragraphs (pdfium also reads "Etymology. — The" correctly where docling-parse gave "Etymology.-The"), so nothing is lost; the phantom items only clutter `document.txt`. Possible cleanup: drop items whose box lies outside the page.

**Still open:** report the OSD-without-threshold behavior to Docling (outward-facing; not done). An `eng+lat` tesseract model is untested.


**Phantom items dropped (2026-10-12).** Phase 1 now deletes text items whose every box lies wholly outside their page (`convert.drop_off_page`, count in `convert.json` as `dropped_off_page_items`). The PDF's text layer has nothing off-page even unclipped, so these come from pdfium (dash glyphs reported with a box just above the page top). Gagné 2008: 228 dropped, all dashes; Felt 1917: 6 single characters; 1862 and 1896: none.

**What the OCR measures can and can't tell us.** There is no ground truth: nothing records what each page actually says. Dictionary-word rate, suspicious-token rate and character counts are reference-free proxies. The word list lacks scientific vocabulary and capitalized words are skipped, so they mostly measure the English prose, not the taxon names the batches depend on. They're good enough to pick the better of two texts when the gap is large; they can't say how accurate either text is. Proposed: a small hand-checked transcription set (a few pages per scan) for character/word error rates, plus a names lexicon from the database as a domain-specific proxy.



**Closed 2026-10-15.** The POC became the reference producer: how to set it up and run it, how phase 1 handles scans, the agents' lockdown and known limits are in `services/import-producer/README.md`; the trial results are in `8546`; the decisions are in `docs/import/producer-guide-background.md`. Still open from this work: report Docling's page-orientation bug upstream (Jeff: not now); test Tesseract with English + Latin (later).
