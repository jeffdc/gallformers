---
status: raw
created: 2026-10-02
updated: 2026-10-24
epic: taxonomy
relates: [8567]
---

# Taxonomy migration

How to move today's data and application onto the domain model ([`docs/domain/domain-model.md`](../../docs/domain/domain-model.md)) and the owned-taxonomy design in matter `8567`. This matter tracks the migration details.

## Migration plan (draft, 2026-10-05)

From starting the replacement system to running it in production. Covers **phase 1** (a new back-end built whole on `taxogall`, replacing the old one in place: the gall system on new taxonomy storage, released after the backscan; `8567` *Build approach*); phase 2 (the taxonomy system) gets its own shorter plan later — see M8. Design lives in `8567`, the ordered punchlist in `50ff`, the import contract in `294c`.

### M0. Strategy decisions (settle first)

- **Cutover style — agreed:** **one cutover in a maintenance window**, rehearsed many times on production copies — not a long-running dual-write. Scale is small (~10⁶ rows) and the maintenance-mode runbook exists (`runbooks/planned-maintenance.md`).
- **Where the backscan runs — probably:** run it against a **staging copy** on the new system; record curator approvals there; at cutover, **replay the approved batches** into production after the data migration. Batches are portable files, so replay is deterministic. (The backscan of ~927 Sources takes weeks and can't happen inside a maintenance window.) **Replay must cover more than batch files** (2026-10-24): curators also decide things on staging outside the batches — which Gall an ambiguous match maps to, synonyms or plants added in the Host-name step (`d585`), dispute rulings, taxonomy-admin edits. Each must be captured and replayed, and import must be idempotent under Oban retries (`e381`).
- **Changes on the live site meanwhile — agreed:** the data migration always runs from the latest production copy; a short **edit freeze** before cutover; new or changed Sources since the backscan get a final small backscan pass.
- **Legacy Facts the backscan doesn't confirm — undecided:** investigate once the backscan produces the list; options include a legacy-data Source with curator review, or attribution to Gallformers. Mechanism (2026-10-24, `9449` §6): the migration attributes every legacy Fact to one undated "Gallformers legacy data" Source, so the site works before the backscan and any real Source outranks it; this decides the mechanism, not the release-time disposition. Whichever is chosen must not manufacture a Source's support, and its date decides whether these Facts outrank the literature under the recency rule (`8567` Sources–Facts point 7).
- **Today's stored gall ranges — decided:** leave ranges as alone as possible (`8567` rule 10). The potential range is computed from the Hosts; only **differences** from it are stored, as inclusion/exclusion Facts. Migration compares each Gall's stored range with its host union: regions in both are dropped (redundant); regions removed from the union become **exclusion** Facts attributed to Gallformers (today's curator removals); regions outside the union become **inclusion** Facts (attribution per the legacy-Facts decision). **Reopened (2026-10-24): a difference is not always a curator removal.** A curator could copy a host union into a stored range, and the copy keeps no record of where it came from; Hosts added and WCVP re-imports since then widen the union. The resulting drift would become exclusions and wrongly narrow ID-tool results. Classify differences before writing Facts (the range timestamps may help), and include drift cases in the M5 parity check.
- **Rollback — agreed:** a full pre-cutover backup, a rehearsed restore, and a time limit after which we fix forward instead of rolling back.
- **How migrations run in production — known:** schema migrations run automatically at boot (`Ecto.Migrator` in the supervision tree when `RUN_MIGRATIONS=true`, set by `docker-entrypoint.sh`; `lib/gallformers/application.ex`). **The data migration must not be a boot-time Ecto migration:** it is long-running, and boot would stall under Fly health checks and `HealthWatchdog`, risking restarts mid-migration. Run it as a separate, explicit step in the maintenance window (e.g. a release task on a one-off machine).

### M1. Foundations (build on `taxogall`; order per `8567`)

- **First, de-risk the pipeline (reordered 2026-10-06) — done:** import schema and validator (`294c`, built), the one-off pipeline-vs-database diff (`b119`, done), pipeline trial on existing Sources (`8546`, go on 2026-10-24) — steps 1–3 of the M2 approach.
- ~~Taxonomy facade over today's tables (`36ca`)~~ — dropped 2026-10-24 (`8567` *Build approach*). What it would have provided is built new: the ancestry read model, explicit `boundary` exports from the start, and the taxon-changed listener.
- New taxonomy storage, built with the gall split: taxa, rank, placement, names and synonyms; stable taxon IDs for plants (their species IDs), higher taxa and Inducers (new IDs above today's highest species ID), plus the crosswalk. Filled by the skeleton migration (M2).
- Sources–Facts layer and audit, acceptance tests first (`8567` step 4). Sources gain kind, authorship date (from `pubyear` for existing ones), and retraction status.
- Gall system: Galls split from species; Traits, Relationships (15 types), qualifiers, aliases, and range as Facts; synchronous taxonomy-change listener.
- Import: the contract (`294c`, format v3 in `priv/import/`), importer (bucket + Oban), curator upload wrapper (`e381`).
- Prerequisite UI the backscan needs — minimal, per `8567` rule 12: **batch review with approve/deny**, unresolved-reference handling, retraction entry. Gallformers statements arrive as batches too (curator notes → LLM → batch), so no statement editor.
- Audit (`ede2`): who changed what — needed before curators edit the new system.
- Test infrastructure: rewrite `priv/repo/test_seeds.sql` for the new model; adapt the prod-data test targets (`make test-prod-data*`).

### M2. Data migration scripts (repeatable, run against copies until cutover)

**Approach (Jeff, 2026-10-06).** Today there are no Facts — data hangs off species rows, with Sources linked per page (`species_source`). **The pipeline is the migration for everything that lives in Sources;** only what can't come out of a Source migrates directly. Assuming a pipeline that turns an arbitrary Source into valid JSON:

1. Run some high-value existing Sources through the pipeline → JSON.
2. A one-off tool (`b119`) compares that JSON with the data stored today for the same species (where the species is on both sides; the pipeline may produce more).
3. Iterate pipeline and diff until satisfied the pipeline produces accurate data (`8546`).
4. Run **all** current Sources through the pipeline → JSON. (Gallformers ID Notes excepted, 2026-10-24: they migrate verbatim and are processed after release, `20e5`.)
5. Bulk-import the JSON into the new system.
6. One-off sanity check, old database vs new: they should be similar, the new much better. Needs human judgement. (Possibly the same tool as step 2.)
7. Not good enough → back to step 1, tweak the pipeline.
8. Good enough → release.

**What migrates directly** — what doesn't come out of Sources; certain so far:
- **Gall entries as skeletons:** ID, name, Gallformers Code, URL, images, editorial data — so `/gall/:id`, Codes, and images survive, and batches can reference Galls by ID.
- **Skeletal taxonomy, taken as accurate as currently defined** — old names in Sources resolve through synonymy (aliases). During imports the tree changes only to add taxa a Source presents as new; every other taxonomic act is recorded as a Fact and flagged where it disagrees with the tree (decided 2026-10-24, `9449` §3). It **includes Inducer species**, which today exist only inside gall names (suffix mapping, agamic/sexgen merging).
- **Hosts:** plants with their POWO ranges and genus placeholders.
- **Range exceptions** (curator removals): Gallformers data — curatorial, with other Sources possible later.
- **Sources as records** (bibliographic data; the page deep links in `species_source.externallink` unless the pipeline reproduces them).
- Keys and other non-Fact data.

What else migrates is open until step 6 shows what the pipeline doesn't reproduce; each class gets a decision then (M0). The items below predate this approach: those describing Facts (Traits, Hosts as Facts, Relationships, aliases, Source 58, gall ranges beyond exceptions) are now produced by the pipeline and need re-review.

- Refresh the data inventory on a fresh production copy.
- Gall split: every gall row becomes a Gall entry keeping its ID, Gallformers Code, URL, and image paths.
- Inducer taxa from gall rows: ~2,440 described names, merging the 76 agamic/sexgen pairs; undescribed Galls link at genus/section (625) or at the family named in a placeholder genus (927); "Unknown (Unknown)" gets no Inducer.
- Plants: carried over as taxa (POWO-imported in phase 2); genus placeholders become genus-level Hosts, keeping their range data.
- Taxonomy crosswalk for the legacy `/taxonomy/:id` redirect.
- Traits → Facts, including generation from the name-suffix mapping (~900 mechanical, 47 curated — see *Name-suffix categorization*).
- Hosts → *host of* Facts; existing community data → Relationship Facts.
- Aliases: gall "scientific" aliases → taxon synonymy; gall common names → gall alias Facts. **Sort by meaning, not by field** (2026-10-24): the "scientific" ones are only mostly synonyms. Former undescribed-gall labels and informal codes are not synonyms, and in taxon synonymy they would feed import name resolution and cause silent wrong matches.
- Galls named after an associate, not an Inducer (e.g. 1148 *Synergus lignicola*, named after an inquiline; the suffix list catches only 2419): audit rows named after inquiline genera for a missing *modified form of*.
- Sources: existing records → Sources with kind, authorship date, license; record-level citations (`species_source`) → attributions on the legacy-data Source or the cited Source, per the M0 decision.
- Source 58 ("Gallformers ID Notes", 1,323 Galls) → **each Gall's note, verbatim** (2026-10-24, `20e5`): shown as "Notes on ID and Taxonomy", Gallformers' own document for that Gall; audit author unknown for legacy text. Facts are extracted from the notes after release through the normal pipeline, not at migration.
- Gall ranges: diff each stored range against the Gall's host union (as of the migration); keep only the differences as inclusion/exclusion Facts. Expect the 232k rows to shrink to a small fraction — measure on the next inventory refresh.
- Non-galls: hand-review all 120; don't migrate; record their IDs for redirects.
- Images: attach to Gall entries (paths unchanged); parse the 5,365 iNat image URLs for observation IDs.
- Keys: re-target each of the 4 keys' couplets to Galls or taxa.
- Editorial carry-over: abundance, data-complete flags, name overrides, photo order. Also decide (2026-10-24): the default Source shown on a gall page (`species_source.useasdefault`), range-confirmed (44 galls), and `undescribed` (derivable from the Inducer link?).
- Optional: iNat taxon IDs as external references (see *iNat correspondence*).

### M3. Application surface

- Public pages: Gall, Host, genus / family / section / intermediate ranks, Source, place, browse — edited in place to read the new read models, reusing today's components.
- ID tool: use the potential range with inclusion/exclusion Facts applied — effectively today's behavior; verify results don't change on a sample of real queries.
- Global search and its name index (taxonomy read model).
- Name builder (`86e7`): derived names with generation / Host / form qualifiers, overrides, uniqueness.
- API v1/v2: traffic is trivial; minimal effort (keep it working or version it simply).
- Admin — as few screens as possible (`8567` rule 12): taxonomy admin and reclassification, the batch review/retraction screens, and only what else proves unavoidable (e.g. images). Retire Gall/Host/gall–host/range/Source forms in favor of batches wherever possible.
- Redirects: `/taxonomy/:id` via the crosswalk; the 120 non-gall URLs to a new **gall-lookalikes Article** (write it). **ID-tool bookmarks** (`id_live.ex`): `fa` holds an old `taxonomy` ID (higher taxa get new IDs, and old family IDs overlap plant IDs, so an old link could quietly resolve to a plant); `co`, `sh`, `fo`, `se` and the like hold trait-vocabulary IDs; `ng` shows non-galls, which aren't migrated; the v1 parameter mapping must keep working.
- Public database snapshot (`db-snapshot.yml` publishes every table not on its exclusion list): exclude the new private tables — stored Source text, import packages, disputes, the admin queue.
- Derived outputs: sitemap.

### M4. Pipeline and backscan

- The producer (`services/import-producer/`) produces `294c` packages; Gallformers validates and imports them (`e381`).
- Trial batches end to end on staging: a few Sources of different kinds (paper, website, research data), including a correction and a retraction. (The go/no-go trial on existing Sources, `8546`, comes much earlier — before the build.)
- Full backscan of every existing Source on staging; curators approve or deny batches; resolve unresolved references; track coverage (Facts confirmed, Facts with no Source support).
- Disposition of legacy Facts the backscan didn't confirm (per M0).

### M5. Rehearsal (repeat until boring)

- Run the full migration plus batch replay on a fresh production copy (`make experiment-db`), then on the **Fly preview** environment for production-like timing.
- Verification suite:
  - counts reconcile (Galls, Hosts, Sources, images, Codes);
  - every old `/gall/:id`, `/host/:id`, Gallformers Code, and image path still resolves;
  - `/taxonomy/:id` and non-gall redirects work; old ID-tool bookmark URLs resolve to the same filters;
  - keys resolve;
  - ID tool and search parity on a sample of real queries (expected difference: the potential range now includes Hosts' introduced range, so Galls without a stored range gain introduced regions — decided 2026-10-25);
  - API responses compatible;
  - spot-check a set of well-known Galls by hand.
- Time the migration to size the maintenance window.
- Rehearse rollback: restore the pre-cutover backup and confirm the old release runs against it.

### M6. Cutover

1. Announce the window; start the edit freeze.
2. Final small backscan pass for Sources added or changed since the backscan; approve.
3. On preview, export the replay log to the private bucket: `bin/gallformers eval "Gallformers.Release.export_replay_log()"`; keep the key it prints. No preview decisions after this.
4. Full production backup to S3; verify it restores.
5. Enable maintenance mode (`runbooks/planned-maintenance.md`).
6. Deploy the release; schema migrations run automatically at boot.
7. Run the data migration as a separate step (not at boot): `Gallformers.Release.migrate_catalog()`, strict — it stops, writing nothing, on any pending curated decision or duplicate taxon key. Then replay preview's log: `Gallformers.Release.replay_log("<key from step 3>")`; it stops naming the first entry it cannot replay, and can be re-run after a fix.
8. Run the verification suite against production.
9. Smoke-test as a curator and as a visitor; lift maintenance mode.
10. Watch errors, Oban queues, and traffic; apply the rollback criteria from M0.

### M7. After release

- Drop the old tables (the `species`-centric model) once stable. Legacy code is removed on `taxogall` as each piece is replaced, so little should remain by now.
- Replace `docs/domain/general.md` and `admin-domain-reference.md`; update `CLAUDE.md`, admin onboarding, and runbooks that assume the old tables (e.g. `restore-deleted-gall.md`).
- Close or reconcile related matters (`86e7`, `1832`, `3e8c`; the after-release list in `50ff`). `2cb2`, `e2cb`, `d108`, `53cb`, `0a58` and `5c56` were dropped on 2026-10-24 as superseded by `8567`.

### M8. Phase 2 (later, own plan)

- Rebuild the taxonomy system behind the same taxon IDs: sourced names, authorship, placement, taxonomic acts with history; POWO import for plants.
- Learn from iNat's taxonomy curation and query practice first (`8567` open question).
- Migration: today's taxa into the new taxonomy system; curated vs POWO-imported origins; no Gall changes.

### Estimate (2026-10-05)

Anchored on Jeff's actual velocity, not bottom-up task counts: the early-2026 rewrite (new stack, SQLite → Postgres, DigitalOcean → Fly, new maps, world coverage, every admin screen) took ~8 focused weeks with AI agents. This effort is smaller in surface (same stack and host, pipeline-first admin with few screens, trivial API traffic) but changes the model rather than porting it — and that design work is mostly done. Single-threaded: Jeff plus one agent.

| | Focused weeks |
|---|---|
| Phase 1 build — new taxonomy storage, Sources–Facts, gall split, importer, minimal screens, pages, ID tool, search, migration scripts | ~4–7 |
| Rehearsal and cutover | ~1 |
| Pipeline trust + backscan review (largely Jeff's time; can overlap the build) | ~2–4 |
| **Phase 1 to production** | **~6–11** |
| Phase 2 (taxonomy system), later | ~3–5 |

**The schedule risk is not the code:** it's the pipeline reaching trusted output (release waits on the backscan), Jeff's review time, and migration decisions — none of which agents accelerate.

## Migration notes

- **Order: build the pipeline, migrate, backscan, then release.** Legacy data is migrated as-is so the new system runs, the backscan attributes it, and only then is it released.
- **IDs.** Today galls and plants share the `species` ID sequence; higher taxa have a separate `taxonomy` ID sequence. After the split:
  - Galls keep their species IDs, so `/gall/:id` and the API's `/galls/:id` stay valid.
  - Plant taxa keep their species IDs, so `/host/:id` stays valid.
  - Inducer taxa get new IDs: one inducer can merge several old rows (e.g. its agamic and sexgen galls), and the gall keeps the old number.
  - Higher taxa get new IDs; 1,562 of their 1,615 old IDs collide with species IDs. Only the legacy `/taxonomy/:id` redirect needs a crosswalk — genus and family pages are addressed by name.
  - Each system owns its own IDs; cross-system references are typed. New taxa draw from the taxonomy system's sequence, starting above today's highest species ID (7,143 in the 2026-09-30 production copy) so they don't clash with the plant IDs it keeps.
- **Genus placeholder plants** ("*Quercus* spp.") become genus-level host links, and **their range data keeps contributing to the potential range exactly as today.** The code check that said placeholders have no range data was wrong: 86 of the 159 placeholders own 89,328 host-range rows (e.g. *Bidens* spp. 4,100, *Hibiscus* spp. 4,018), and today's host-union fallback includes them. Dropping them would narrow ID results.
- **Placeholder genera** ("Unknown (Cynipidae)", 102 of them) are not migrated. Galls linked to them get an inducer link at the family named in the placeholder, or no inducer link for "Unknown (Unknown)".
- **Name suffixes need a curated mapping, not a parser.** Parentheses in gall names carry generation terms (agamic, sexgen, spring/summer generation), rust spore stages (aecial, telial), and host-scoped forms ("on betula", "(q-bicolor)", even "(agamic) (q-bicolor)").
- **Aliases.** "Scientific" aliases on gall rows are mostly inducer synonyms and move to the taxon side. Common names on galls become gall facts; none has a Source today.
- **Non-galls are reviewed by hand, then not migrated.** All 120 `form = non-gall` records get a manual review. They don't enter the new model; their old URLs redirect to a new Article about gall lookalikes.
- **Today's stored gall range** is reduced to its differences from the host union (inclusion/exclusion Facts; see M0). Only 44 of 3,509 galls with a stored range are marked confirmed; most stored ranges are probably copies of host unions. Observational data (Research Grade iNat overlay) is a separate, future layer.
- **The ID tool keeps today's effective behavior:** potential range with curator exclusions applied (today: "stored range, else host union," where stored ranges mostly encode those exclusions). Verify with a parity check.
- **Images from iNat** (5,365 of 7,663 gall images) store the observation URL; parsing it recovers observation IDs and gives a head start on observation links.
- **Keys** (4) have couplets pointing at species IDs; each target needs a semantic review (gall or taxon).
- **Plants become POWO-imported taxa** (phase 2), keeping their WCVP/POWO IDs; curators can adjust them editorially. Host distributions stay outside Facts.

## iNat correspondence (research 2026-10-02)

Researched when the plan was to mirror iNat; under the owned-taxonomy direction this is optional correspondence, not taxonomy.

Read-only research: 156 unauthenticated requests to the iNat API, plus iNat's source code on GitHub. Raw data (samples, per-name results, API responses, inventory queries, curation list): `docs/plans/2026-10-02-taxonomy-migration-research/` (local, gitignored).

**Name-matching test** (random sample from the production copy):

| | Exact match, active | Synonym (auto-resolves) | Not in iNat |
|---|---|---|---|
| Plants (60) | 58 (97%) | 1 | 1 (*Salix groenlandica*) |
| Inducers (64) | 55 (86%) | 1 | 8 |

- **Projection:** ~2,500 plants match automatically (~80 to curate); ~2,100 inducers match automatically (~300–350 to curate). The inducer sample is small; treat its rate as ±10 points.
- **Missing inducers are genuinely absent from iNat**, not misspelled — mostly little-known cynipids (e.g. *Andricus santafe*, *Neuroterus fusifex*, *Diplolepis tuberculosa*). They simply have no iNat correspondence.
- **Matching method:** `GET /v1/taxa?q=<name>&is_active=any`, then exact name match, filter by kingdom, keep only active taxa, prefer species rank. Same-name inactive duplicates are common; a few names collide across ranks (e.g. *Ulmus minor* complex vs species).
- **Synonyms resolve automatically:** an inactive taxon points to its successor via `current_synonymous_taxon_ids` (e.g. *Hieracium flagellare* → *Pilosella flagellaris*).
- **No POWO route for plants.** iNat follows POWO for vascular plants but exposes no POWO/WCVP IDs (v1 has no such field; framework endpoints error or are blocked). Match on the POWO-accepted name instead.
- **Infraspecific names:** iNat has no pathovar rank; *Pseudomonas savastanoi* (pv. *nerii*) matches only at species. Phytoplasmas lack the "Candidatus" prefix.

**Caching:** our ~5,000 taxa plus ancestors (likely <10,000) fit in ~25–50 batched calls (`/v1/taxa?id=…`, up to at least 115 IDs per call; `per_page` max 500). Every record carries `ancestor_ids`. iNat also publishes a monthly taxonomy export (`inaturalist-taxonomy.dwca.zip`, ~81 MB): active taxa only, no synonyms, no authorship — usable for an initial seed or cross-check.

## Name-suffix categorization (2026-10-02)

Parentheses in gall names (excluding the "Unknown (Family)" placeholder prefix) hold 46 distinct tokens across 948 occurrences. They encode four dimensions the new model separates: **generation, host, form, and name history**. Some names stack three, e.g. *Neuroterus quercicola* (pacificus) (sexgen) (on Quercus douglasii).

| Category | Tokens | Count | Target in the new model |
|---|---|---|---|
| Cynipid generation | agamic, sexgen | 877 | Generation trait. Mechanical mapping. |
| Seasonal generation | spring / summer / autumn / "summer and autumn" generation(s) | 22 | Generation, seasonal group (`8567`, *Generation groups*). "Summer and autumn generations" induce one Gall: multivoltine, so one generation value, not two. |
| Rust spore stage | telial, aecial | 4 | Generation, rust-stage group (`8567`). Each stage is on a different host. |
| Host-scoped | "on Betula", "on Malus", "on Quercus lobata", "q-bicolor", … | 20 | Host relationships plus a host qualifier in the name. Two different situations; see below. |
| Plant part / form | bud, leaf snap, capitulum, inflorescence, detachable bud, integral stem, leaf, midrib gall, deforming-pisiformis | 13 | Separate entries for one species (boundary case 4): plant-part/form trait plus a form qualifier in the name. |
| Historical / infraspecific name | pacificus, texanus, australis, cerinus, decrescens, rydbergiana, saltatorius, perforans | 10 | Gall alias (former name). Some may be cryptic species; curator review. |
| Pathovar | pv nerii | 1 | Part of the taxon name (an infraspecific rank in Gallformers' taxonomy). |
| Relationship | altering Diplolepis gall | 1 | *Modified form of* relationship. |

**Findings**

- **~900 of the 948 tokens map mechanically** (cynipid and seasonal generation terms). **47 gall names need a curator**; they're listed below.
- **"On X" covers two biological situations.** Host-alternating life cycles (aphids: *Hamamelistes*, *Hormaphis*, *Eriosoma*, *Prociphilus*; heteroecious rusts: *Gymnosporangium*) are different life-cycle phases on alternate hosts, so they belong in the generation trait under a group-specific vocabulary. The same phase on different hosts (eriophyids, *Contarinia*, *Neuroterus* sexgen on *Q. douglasii* vs *Q. lobata*) is a separate entry distinguished by host. **Decided (Jeff, 2026-10-23): host-alternating phases are generations,** in group-specific vocabularies (`8567`, *Generation groups*). The aphid entries map to fundatrix (primary host) and exules (secondary host).
- **The name builder needs qualifiers** (requirement for `86e7`). Names are unique, and one inducer + generation can have several entries, so a derived name adds a generation, then a host, then a form qualifier as needed.

**Curation list** (production copy, 2026-10-02). Handling is a proposal; each row needs a curator decision.

| ID | Gall name | Category | Proposed handling |
|---|---|---|---|
| 3396 | Cynips mellea (rydbergiana) (agamic) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 2128 | Neuroterus quercicola (pacificus) (agamic) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 3167 | Neuroterus quercicola (pacificus) (sexgen) (on Quercus douglasii) | Historical / infraspecific name, Host-scoped | parenthetical name → gall alias (former name); curator checks for a cryptic species; same phase, different host → separate entry; host relationship + host qualifier in name |
| 1996 | Neuroterus quercicola (pacificus) (sexgen) (on Quercus lobata) | Historical / infraspecific name, Host-scoped | parenthetical name → gall alias (former name); curator checks for a cryptic species; same phase, different host → separate entry; host relationship + host qualifier in name |
| 1720 | Neuroterus saltatorius (agamic) (saltatorius) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 1076 | Neuroterus saltatorius (australis) (agamic) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 2450 | Neuroterus saltatorius (decrescens) (agamic) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 1109 | Neuroterus saltatorius (texanus) (agamic) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 3168 | Neuroterus vesicula (cerinus) (sexgen) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 2915 | Phylloxera caryaesepta (perforans) | Historical / infraspecific name | parenthetical name → gall alias (former name); curator checks for a cryptic species |
| 6860 | Colomerus tricaseri (on Empogona kirkii) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 6862 | Colomerus tricaseri (on Sericanthe andongensis) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 2338 | Contarinia partheniicola (on Ambrosia) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 5512 | Contarinia partheniicola (on Parthenium incanum) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 3248 | Eriophyes cerasicrumena (on Prunus americana) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 633 | Eriophyes cerasicrumena (on Prunus serotina) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 2688 | Eriosoma lanigerum (on Malus) | Host-scoped | life-cycle phase on an alternate host → generation; host relationship |
| 4089 | Eriosoma lanigerum (on Ulmus) | Host-scoped | life-cycle phase on an alternate host → generation; host relationship |
| 5578 | Gymnosporangium nidus-avis (on Juniper) | Host-scoped | life-cycle phase on an alternate host → generation; host relationship |
| 2960 | Gymnosporangium sabinae (on Pyrus) | Host-scoped | life-cycle phase on an alternate host → generation; host relationship |
| 2255 | Hamamelistes spinosus (on Betula) | Host-scoped | life-cycle phase on an alternate host → generation; host relationship |
| 1005 | Hamamelistes spinosus (on Hamamelis) | Host-scoped | life-cycle phase on an alternate host → generation; host relationship |
| 3981 | Hormaphis cornu (on Betula) | Host-scoped | life-cycle phase on an alternate host → generation; host relationship |
| 3979 | Hormaphis cornu (on Hamamelis) | Host-scoped | life-cycle phase on an alternate host → generation; host relationship |
| 1340 | Neuroterus quercusbatatus (agamic) (q-bicolor) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 1339 | Neuroterus quercusbatatus (sexgen) (on Quercus bicolor) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 5095 | Phytoplasma pruni (on Trillium) | Host-scoped | same phase, different host → separate entry; host relationship + host qualifier in name |
| 4092 | Prociphilus caryae (on Amelanchier) | Host-scoped | life-cycle phase on an alternate host → generation; host relationship |
| 5120 | Pseudomonas savastanoi (pv nerii) | Pathovar | pathovar is part of the taxon name → infraspecific taxon in Gallformers' taxonomy |
| 6613 | Acalitus pundamariae (inflorescence) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 6612 | Acalitus pundamariae (leaf) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 4931 | Andricus notholithocarpi (midrib gall) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2841 | Asphondylia pseudorosa (bud) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2887 | Asphondylia pseudorosa (capitulum) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2886 | Asphondylia pseudorosa (leaf snap) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2892 | Asphondylia rosulata (bud) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2891 | Asphondylia rosulata (leaf snap) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2889 | Asphondylia solidaginis (bud) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2888 | Asphondylia solidaginis (leaf snap) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 3235 | Tanaostigmodes howardii (detachable bud) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2047 | Tanaostigmodes howardii (integral stem) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 1519 | Unknown (Cynipidae) q-alba-(deforming-pisiformis) | Plant part / form | separate entry for one species → plant-part/form trait + form qualifier in name |
| 2419 | Periclistus pirata (altering Diplolepis gall) | Relationship | inquiline-modified gall → *modified form of* relationship to the Diplolepis gall |
| 1247 | Cronartium quercuum (telial) | Rust spore stage | rust life-cycle stage → generation |
| 6002 | Gymnosporangium floriforme (aecial) | Rust spore stage | rust life-cycle stage → generation |
| 6460 | Gymnosporangium floriforme (telial) | Rust spore stage | rust life-cycle stage → generation |
| 778 | Gymnosporangium juniperi-virginianae (telial) | Rust spore stage | rust life-cycle stage → generation |

## Data inventory (2026-10-02)

Read-only queries against a production copy restored into local `gallformers_dev` (species last updated 2026-09-30).

| Area | Count |
|---|---|
| Gall rows | 4,094 (1,552 undescribed; 1,551 with a Gallformers Code) |
| Distinct described inducer names | ~2,440 |
| Names with both an agamic and a sexgen row | 76 (619 agamic and 253 sexgen rows overall) |
| Undescribed galls by genus link | 927 to placeholder genera; 625 to a real genus |
| Plants | 2,575 real + 159 genus placeholders; 2,554 with WCVP/POWO IDs; 171 WCVP "no_match" |
| Higher taxa | 1,615 rows (263 families, 1,230 genera, 12 sections, 7 intermediate ranks) + 103 placeholders |
| Stored iNat taxon IDs | None |
| Host links | 8,734 (228 to placeholders; 78 galls have only placeholder hosts; 1 gall has none) |
| Aliases | Scientific: 2,229 on galls, 588 on plants. Common: 287 on galls, 835 on plants |
| Sources | 927; 8,195 record-level links (8,189 to galls), 8,074 with narrative; Source 58 on 1,323 galls |
| Gall range | 232,390 rows for 3,509 galls; 44 confirmed |
| Host range | 1,081,537 rows for 2,625 plants; 89,328 of them on 86 placeholders |
| Images | 7,663 on galls (5,365 from iNat); 17 on plants |
| Non-gall records | 120 |
| Keys | 4 |
