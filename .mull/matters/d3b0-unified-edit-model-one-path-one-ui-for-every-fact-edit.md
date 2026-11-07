---
status: raw
created: 2026-11-07
updated: 2026-11-07
epic: taxogall
---

# Unified edit model: one path, one UI for every Fact edit

# Unified edit model: one path, one UI for every Fact edit

## The model (Jeff, 2026-11-07)

Terms:
- **Source**: anywhere Facts are derived from.
- **Gallformers Source** (needs a better name): Gallformers' own statements of Fact, usually backed by an Observation. Append-only: each change dated when made (and by whom). Structure still open (below); Jeff punted on it too long.
- **Gallformers ID Notes**: editorial prose, nothing to do with Facts. Not yet split from the Gallformers Source (20e5).
- **Gallformers legacy data**: everything from the old site, before any Source is ingested. Undated.

Rules:
1. **Any Source may state any Fact.** The literature is the usual authority; Gallformers may state any Fact, taxonomic included, as an exception. (Resolves the swing between "Gallformers is the authority" and "only the literature": the middle.)
2. **New Facts come in exactly two ways:** ingest a Source to approval, or edit/add a Fact on a Fact-bearing entity.
3. **An edit is the ingestion of a Gallformers statement** resolving to the same changes, through the exact same code path as a Source ingestion.
4. **Sources never reference each other formally.** A curator may write "Weld (1959)" in a statement's text; it stays text. Source–Source relationships are latent, via shared Facts only.
5. **Galls and Gallformers' non-plant taxonomy are Fact-bearing, with the same mechanics** front and back. Host↔Gall is a Gall Fact; plant records are editorial.
6. **All edits that can be inline are inline on the main pages,** with one shared set of UI components, mechanics, validators and code, so a bug in editing is fixed once.
7. **Correcting an ingestion mistake:** the corrected Fact overrides the incorrect one with the original Source's authority; the change is audited (who, why, when).
8. **Delete** is only for data added by mistake: a true exception outside the rules.
9. **Split and lump are taxonomic acts, so Facts:** they happen under the authority of the Source whose statement decides them.

## Decided (Jeff, 2026-11-07)

- **Review edits are under the Source's authority.** Edits during review correct import errors or map what the original couldn't be read for; every review action states Facts *from the Source*, not from Gallformers or the curator (who is in the audit). So review decisions that change the non-plant tree become that Source's statements.
- **Corrections are the same act as review**, lower ceremony: under the original Source's authority. No second code path that creates Facts.
- **ID notes are 100% editorial.**
- **One edit framework** first, then rebuild the editors onto it (open point 4: agreed).
- **Gallformers Source dating:** an undated base (the old site's data, so the literature outranks it and the backscan can correct it, as f923 chose) plus dated **changes** (a curator's edits; timestamped, since several happen a day), which outrank older statements. Audit records who. The name is "change".
- **Old ID notes** are processed into changes carrying the notes' own dates.
- **Not acceptable:** a Source record per change (thousands of tiny Sources would swamp search and Source views without condensing code); one Source with several statements per Fact (wide change); replace-only with history only in the audit. Structure still being explored (below).

## Open (to settle in this order, proposed)

1. Structure of the Gallformers Source: append-only, dated per change, curator recorded; separate from ID notes. Explore the solution space (per-change-set Sources was only one idea).
2. Corrections (rule 7): a third act outside ingestion (audited, replayed), or a corrected re-ingestion of that Source?
3. Review decisions that change the non-plant tree (`SynonymDecisions` split / synonym_of) must become statements: under whose authority (the reviewed Source's, accepted)?
4. One edit framework, then rebuild the editors onto it.

## Audit of the current code (2026-11-07)

- **Ingestion path used only by the Gall page's tray Fact items** (Hosts, Traits, common names, range exclusions, observation intake: `Curation` → `Import.submit_gallformers_fragment`). Direct Fact writes elsewhere: taxonomy edits (`Import.TaxonomyStatements` via `BasisPicker`), Source corrections (`Import.SourceCorrections`), merge and rename aliases (`Catalog.Records.add_former_label`, `Catalog.GallRenames`), split answers (`Catalog.repoint_inducer`), vocabulary term moves (`Catalog.move_term_attributions`), term placements outside apply.
- **Model violations:** `attributions.cites_as_written` / `cited_source_id` (stored, never read; remove). `BasisPicker` writes a curator's statement in a paper's name at the paper's date, while the tray credits a "Source" edit to Gallformers at today's date (two models of one act). One Gallformers Source row (Source 58, also holding ID notes); a new Gallformers statement replaces the earlier on the same Fact (wiping a note-derived statement's quote); contradicts "each statement is its own dated entry". `SynonymDecisions.carry_out` changes the non-plant tree with no statement (drift vs `Taxa.Sync`).
- **Replay gaps (cutover risk):** Gall editorial tray edits (`Catalog.update_gall_editorial`, `update_name_parts`) and ID note saves (`Sources.store_note`) are audited but not replay-logged.
- **UI duplication:** five editor shapes (`GallLive.Editor`, `HostLive.Editor`, `SpeciesLive.Editor`, `RangeEdit`/`RangeEditor`, `TaxonomyLive.Edit`); two Fact-row UIs (`CurationComponents.fact_row`/`fact_chip` vs `FactsComponents.facts_view`/`fact_menu`/`fact_editor`; the Gall page shows both); six plant searches (Gall page can't add a genus/section Host; review and corrections can); taxon/parent, Gall and Source searches each several times with different filters; four rename dialogs; six "why/evidence" inputs; three observation-link parsers; four Fact-key encodings; two place pickers; duplicated tray marks and Source short labels; `Curation.Review` re-implements the import preview rules; validation repeated (`Curation.Spec` vs `Import.Validator`/Resolver; code/name checks three times).
- **Bug:** name/authorship comparison differs by path (`TaxonChanges.name` raw strings vs `NameNormalizer.normalize_authorship` in `TaxonomyQueue`): a curator's "(Weld 1959)" vs "(Weld, 1959)" makes a new name statement.
- **Gaps:** no UI anywhere for a Gall's Inducer, generation, descriptions, creating a Gall, range "only"; rank pages have no Edit mode; plant lineage, common names, WCVP link and completeness/abundance flags only in the taxonomy admin; species page photos and delete only in the admin.

