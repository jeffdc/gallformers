---
status: raw
created: 2026-10-24
updated: 2026-10-27
epic: taxonomy
relates: [8567, 9449, 3272, 803b, a856]
---

# Taxogall: program overview and punchlist

The top-level matter for **taxogall**: what we are building, which matters hold the parts, and the ordered punchlist to production. Detail lives in the linked matters; this one holds the picture and the order.

## The picture

Gallformers today treats everything as a species: a gall, its inducer and its host are all `species` rows, and data hangs off them with Sources linked per page. Taxogall replaces that with:

- **A gall system:** Galls are catalog entries (two generations are two Galls). What we know about them — Hosts and other Relationships, Traits, range adjustments, recorded occurrences, common names, descriptions — are **Facts**, each attributed to Sources that confirm or deny it. The newest Source wins; Gallformers is a Source too.
- **An owned taxonomy:** taxa referenced by stable IDs; phase 1 builds new taxonomy storage filled from today's data, phase 2 adds sourced names, authorship and acts.
- **A new back-end, built whole on `taxogall`**, replacing the old one in place (no facade, nothing run side by side). The domain core is new; infrastructure (auth, Oban, storage and images, plant ranges, places and maps, search, deploy) is reused. Public pages are re-pointed in place; most of today's admin is replaced by batches and a few new screens (`8567` *Build approach*).
- **Every write is a batch:** producers (an LLM pipeline, curator notes, forms) deliver JSON packages against a validated contract; humans approve batches. **The pipeline is the migration** for everything that lives in Sources: every existing Source is backscanned, and the site is released after the backscan.

Domain language: `docs/domain/domain-model.md`. Design and rules: `8567`. Migration plan (M0–M8): `b5bd`. Import contract: `294c` and `priv/import/`, with decisions in `docs/import/producer-guide-background.md`.

## Matters

**Core**

| Matter | Role |
|---|---|
| `8567` | Software design and rules (architecture, Sources–Facts, generation groups, phases) |
| `9449` | Back-end schema: contexts, tables, standing mechanics, import and replay, migration mapping, acceptance tests |
| `b5bd` | Migration plan: decisions, data migration, application surface, backscan, rehearsal, cutover, after release |
| `294c` | Import contract and validator (built; remaining items below) |
| `8546` | Pipeline trial: go (done, archived) |
| `e381` | Gallformers-side importer, admin queue, intake |
| `d585` | Host names resolved before the gall batch |
| `20e5` | Gallformers ID Notes: Facts vs commentary; conversion |
| `803b` | Step 9: public pages and API on the new back-end (design, inventory) |
| `86e7` | Gall name builder (derived names with generation / Host / form qualifiers) |
| `ede2` | Audit trail (shared building block; to rewrite for the new tables) |
| `f465` | Preview environment with production-like data (backscan staging, rehearsal timing) |

**After release** (wait for the new model): `1832` organism taxon pages, `3e8c` gall merges, `e1d2` iNat taxon IDs, `439a` phenology (fed by recorded occurrences), `7cde` completeness scoring, `4389` notifications, `29dc` interoperability, `1374` DNA barcodes, `8ba0` iNat integration, `eb47` GallOnt vocabulary, `67c9` host-family filter, `74de` API v2, `32a5` mobile ID tool, `3272` gall records outside the Hosts' ranges become Host-range proposals. Phase 2 work (no matters; superseded designs dropped 2026-10-24): authorship for curated taxa (plant authorship from WCVP), arbitrary-depth infrageneric ranks, taxon merges and splits with history, plant synonymy from POWO.

## Punchlist (in order)

1. **Housekeeping** — done 2026-10-24:
   - ~~Close superseded and done matters~~ (2026-10-24: dropped `0a58`, `2cb2`, `5c56`, `f49a`, `bf97`, `9005`, `d108`, `e2cb`, `91cf`, `53cb`, `eff3`; done `4dcd`, `8546`).
   - `b5bd`: fix stale references — M1 "`8567` step 2" → step 4; "`e381` v2" → `294c` format v3; M4 `7fda`/`db6f` → `services/import-producer/`; drop the `9737`/`2a27` mentions in M3.
   - `e381`: remove the stale "Retire the old source-ingestion system" item (done as `47ae`).
   - `86e7`: replace the `1121` pointer; align it with `8567` rules 6, 9 and 12 (derived names, no label-builder UI).
   - Metadata: unlink `ede2 needs ec68` (audit must not wait on roles).
   - `8567`: point its *Work ordering* at this punchlist.
2. ~~Record the `8546` go/no-go~~ — go (2026-10-24).
3. **Finish the contract (`294c`):** vocabulary generator (mix task); schema-description wording pass; golden regression set of the five trial packages; generation groups into `traits.json`, the guide and the `generation` enum once the groups settle.
4. ~~Taxonomy facade (`36ca`)~~ — dropped 2026-10-24 (`8567` *Build approach*).

**New back-end** (schema: `9449`; built whole on `taxogall`; old domain code removed as each piece replaces it; the new test seeds in `priv/repo/test_seeds.sql` grow with it). **Steps 5–8 built 2026-10-25** (all 17 tasks of `9449`'s plan; see its *Status*). **Step 8 done 2026-10-26:** rehearsed on a production copy, every curated decision made, strict run clean (`9449` *First rehearsal*). The prod-data test targets move to step 9.

5. **Sources–Facts and audit** (`8567` step 4, `ede2`): acceptance tests first (two Sources confirming one Host; a denial in both orders; a superseded placement; a retraction; re-import dropping a Fact; a qualifier denied while its Relationship stands; a Gallformers override citing Observations; placements from different Sources that would form a cycle or rank inversion).
6. **Taxonomy storage and gall system** (`8567` step 5): new taxonomy tables (taxa, rank, placement, names and synonyms, today's IDs) and crosswalk; ancestry read model; Galls separate from taxa; Traits, Relationships, qualifiers, aliases, range adjustments and recorded occurrences as Facts; generation groups schema; taxonomy-change listener; read models for ID tool, search, pages and API; `boundary` exports from the start.
7. **Importer (`e381`, `d585`):** bucket + Oban import; Host-name resolution step before the gall batch; admin queue; batch approve/deny; dispute intake; retraction entry; "no silent merges" test; storage release gate.
8. **Data migration scripts (`b5bd` M2):** refresh the inventory; gall skeletons, taxonomy skeleton and Inducer taxa (agamic/sexgen merge), Hosts and placeholders, range exceptions, Sources as records, keys, editorial carry-over; name-suffix mapping and the 47 curated names; hand-review the 120 non-galls; convert the ID Notes (`20e5`). Adapt the prod-data test targets.

**Front-end:**

9. **Public pages re-pointed in place (`b5bd` M3; design in `803b`):** Gall, Host, taxon ranks, Source, place, browse; ID tool parity (season filter wording to "forms and grows"); search; name builder (`86e7`); minimal API; redirects and the gall-lookalikes Article; sitemap. **Built and committed 2026-10-27 (67378c93; e2e fix 2b3dd12d), except the name builder (`86e7`, not in `803b`'s plan) — **built 2026-10-27, uncommitted: 18 overrides left of 1,323; see `86e7` Status**; see `803b` Status.** The e2e browser suite's Playwright breakage (pre-existing since #593) is fixed on `taxogall`: Elixir test libraries and npm Playwright upgraded together.
10. **New minimal admin (`b5bd` M3, `8567` rule 12; inventory and plan in `a856`):** taxonomy admin, images, a note editor for each Gall's Gallformers note (`20e5`), and only what else proves unavoidable; retire the old Gall/Host/gall–host/range/Source forms.

**Release:**

11. **Backscan (`b5bd` M4)** on the preview environment (`f465`): trial batches end to end, including the kinds the trial didn't test (a long scanned catalogue such as Gagné 2008; a key such as Felt 1917, which may exceed one batch), then every existing Source except the Gallformers ID Notes (they migrate verbatim; `20e5`); curators approve; track coverage; legacy Facts the backscan doesn't confirm stay, marked unconfirmed (M0, decided 2026-10-27).
12. **Rehearsal (`b5bd` M5)** until boring, including timing on the preview environment (`f465`) and a rollback rehearsal.
13. **Cutover (`b5bd` M6).**
14. **After release (`b5bd` M7):** drop the old tables; replace `docs/domain/general.md` and `admin-domain-reference.md`; update `CLAUDE.md`, onboarding and runbooks; reconcile the after-release matters above. **Process the Gallformers notes** through the normal pipeline (`20e5`): note → `document.json` → Gallformers batch quoting it; needs the contract change in `294c` and the legacy-notes date decided. **Fix wrong Host ranges on the Host** (curator, editorial): stored gall ranges become no Facts (`b5bd` M0, option A), so cases where a curator widened a gall's range instead of its Host's now surface as Galls missing from regions — fix the Host.
15. **Phase 2 (`b5bd` M8):** the taxonomy system, its own plan.

## Open decisions


- Scope of the curated taxonomy; Traits that vary by Host (`8567`).

Decided 2026-10-27 (Jeff): legacy Facts the backscan doesn't confirm are marked unconfirmed (`b5bd` M0); undated Gallformers statements carry the cutover date, while the legacy-data Source stays undated (`8567` Sources–Facts point 7); generation groups settled (`8567`); gall renames from taxon renames are reviewed (B), to protect Gallformers codes and the iNat link (`8567`, `86e7`). Deferred: coordinates on recorded occurrences (`294c`).
