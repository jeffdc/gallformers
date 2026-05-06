---
status: done
created: 2026-05-05
updated: 2026-05-05
epic: platform
---

# Audit changeset boundaries in write paths

Changeset-boundary audit across lib/gallformers/ focusing on write paths that read raw attrs or hand-assemble persisted data before the relevant Ecto changeset boundary.

What was audited
- Started from actual writes: Repo.insert/update/update_all paths in content_images, images, articles, sources, ingestions, taxonomy, plants, galls, accounts, and related submodules.
- Only kept findings where raw input or manual map shaping materially affects persisted data, write eligibility, workflow transitions, defaults, or field clearing before cast/validation.
- Ignored harmless orchestration and pure read-path normalization.

High-signal findings
1. Sources.create_species_source/1 and update_species_source/2
- Branch on raw attrs["useasdefault"] / attrs[:useasdefault] before SpeciesSource.changeset/2 to decide whether other defaults should be cleared.
- Parse species_id from raw attrs before cast/4, including String.to_integer/1 in helper code.
- Risk: default-clearing behavior can drift from what the changeset accepts; malformed species_id can fail outside changeset error handling.
- Relevant changeset: Gallformers.Species.SpeciesSource.changeset/2 already casts :useasdefault and :species_id.

2. Ingestions.record_duplicate_signals/2
- Filters raw attrs down to non-nil values before SourceIngestion.changeset/2.
- Risk: nullable duplicate-signal fields cannot be intentionally cleared back to nil, leaving stale persisted metadata.
- Relevant changeset: Gallformers.Ingestions.SourceIngestion.changeset/2 already casts these fields and normalizes nullable strings.

3. Taxonomy.Tree.update_taxonomy/2
- Reads raw name/type via local attr_value before Taxonomy.changeset/2 normalization/validation and uses those raw values to decide type-change rejection and genus-rename branching.
- Risk: business logic runs on untrimmed/unvalidated input; whitespace or other unnormalized values can trigger the wrong path.
- This overlaps with the docs/plans/2026-05-05-utils-tree-cleanup.md draft and confirms that Tree.update_taxonomy/2 should be refactored to create one changeset up front and use Ecto.Changeset.get_change/3 or get_field/2 for decision-making.

Manual write logic that should likely move into changesets
4. Ingestions.transition_source_ingestion_status/3
- Manually sets processing_stage and failed_at in context helpers before SourceIngestion.changeset/2.
- Better home: a specialized transition changeset or changeset helper that owns workflow-derived defaults/timestamps.

5. Plants.upsert_host_traits/2
- normalize_host_traits_attrs/2 manually preserves/clears wcvp_match_status based on wcvp_id and existing state before HostTraits.changeset/2.
- Risk: helper only checks atom keys, while cast/4 accepts strings too; write behavior can differ by key shape.

6. Galls.update_gall_properties/2
- enforce_unknown_genus_floor/2 rewrites undescribed from raw attrs before GallTraits.changeset/2.
- Better home: a gall-properties-specific changeset or helper using put_change/3 after cast.

Structured map fields that likely want embeds
7. Ingestions.SourceIngestionSpecies.review_payload
- Stable nested structure with species_review, host_reviews, trait_reviews, description_review is repeatedly assembled and traversed by hand.
- Good candidate for embedded schemas.

8. Ingestions.SourceIngestionSpecies.extraction_payload
- Stable nested structure with gall_species, host_species, hosts, traits, description_evidence, location, confidence is also repeatedly hand-built and read.
- Likely embed candidate, though slightly lower confidence than review_payload.

Useful overlap from the utils/tree cleanup scratch plan
- Tree has its own private attr_value implementation with different falsy semantics from Gallformers.Utils.attr_value/2. Even if current taxonomy attrs rarely carry false/0/"" for these fields, the duplicate helper is a footgun and should be removed in favor of a single implementation or, better, changeset accessors once the changeset is created.
- The scratch plan's recommendation to refactor Tree.update_taxonomy/2 around a single changeset is aligned with this audit and should be treated as part of the same cleanup.
- The broader Utils cleanup/rename is secondary. It is worth doing only after the write-boundary fixes are made, otherwise it risks mixing structural cleanup with correctness work.

Suggested implementation order
1. Fix Taxonomy.Tree.update_taxonomy/2 first: one changeset, no raw attr branching, delete Tree.attr_value/2.
2. Fix Sources species-source default handling by deriving decisions from the changeset or a validated subset rather than raw attrs.
3. Fix Ingestions.record_duplicate_signals/2 so nil clears can pass through intentionally.
4. Move workflow/default/timestamp logic from Ingestions.transition_source_ingestion_status/3 into a changeset boundary.
5. Move HostTraits and GallTraits write-time business rules into specialized changesets.
6. Revisit review_payload/extraction_payload embeds once the surrounding workflow settles.

Verification expectations when implementation starts
- Compile with mix compile --warnings-as-errors or run mix precommit; do not use plain mix compile.
- Add or update tests that exercise mixed string/atom key input, nil clearing, and taxonomy rename/type-change decisions using normalized input.
