---
status: raw
created: 2026-08-12
updated: 2026-08-14
epic: taxonomy
relates: [8ba0]
blocks: [1832, 3e8c, 0a58]
needs: [d108, e2cb]
---

# Multi-species gall model

## Status

Draft design for owner review. The design sections were developed collaboratively, but the matter is **not approved or planned** until Jeff reads and approves this document in full.

## TL;DR — Product impact

Gallformers will treat the gall a person observes as the primary record, separate from the organisms associated with it.

- One gall can show several confirmed, probable, or possible inducers when they produce an indistinguishable structure. One inducer can also link to several distinguishable galls.
- Gall pages gain an **Associated organisms** section covering inducers, non-modifying and gall-modifying inquilines, parasitoids, hyperparasitoids, predators, cecidophages, and successors. Each association shows its role, confidence, and relevant host when known.
- The gall remains the result users identify and the stable page they visit. Searching by an attached organism’s accepted name, synonym, or common name finds the gall without presenting that organism name as the gall’s identity.
- Every gall keeps one unique, human-readable label. Most labels default to the primary inducer’s name; admins use a guided builder to add structured distinctions such as generation, host, plant part, season, or form instead of encoding those facts in arbitrary parenthetical text.
- Related content becomes biologically meaningful: users can browse other galls from the same inducer, compare explicit lookalikes, and follow links between original galls and forms modified by gall-modifying inquilines.
- Attached taxa can link to their exact iNaturalist taxon, avoiding ambiguous name-based searches and supporting later iNaturalist features.
- Existing gall URLs, IDs, images, hosts, morphology, ranges, sources, Gallformers Codes, and other gall data remain intact. The initial release does not automatically merge existing records; curators handle scientifically justified merges in a separate workflow.
- Clearly labeled lookalikes may assist identification, but they remain excluded from gall totals. This change does not turn Gallformers into a general organism encyclopedia or a complete trophic-interaction database.

## Product premise

Gallformers is organized around the user’s question, “What am I looking at?” The ID tool is the primary public interface. Gallformers catalogs identifiable gall structures, not species or complete inducer biology.

A gall is a consistent restructuring of plant tissue caused by an inducer. It may be cryptic and require dissection, microscopy, or comparison with unaffected tissue. Inclusion depends on the induced structure, not outward visibility or inducer taxonomy. Mere presence of an organism or fruiting body is insufficient.

A gall record reflects distinctions supported by the structure and user-applicable ecological context. Recognizably different galls produced by one species are separate records. If several taxa produce galls that cannot be distinguished with available evidence, they are possible causes of one gall record; the product must not imply unsupported species-level identification. A recognizable gall remains core even with no formally named or fully resolved inducer.

Known non-galls remain outside the core database but may appear as clearly labeled ancillary lookalikes when they prevent predictable misidentification. Broader plant maladies and complete inducer biology remain outside current scope.

## Research baseline

The current schema conflates a biological taxon and a gall structure:

- `species.taxoncode='gall'` is treated as both inducer species and public gall entry.
- `gall_traits` is a strict 1:1 extension keyed by `species_id`; every morphology junction also uses that ID.
- Hosts, images, sources/excerpts, aliases, taxonomy, abundance, curated range, completeness, undescribed status, and Gallformers Code all attach to the same species ID.
- Public `/gall/:id` and API gall IDs are species IDs.
- “Related Galls” is inferred by genus+epithet name-prefix matching rather than stored biology.
- No model exists for role-bearing gall-community associations.

Local production snapshot current through 2026-08-03:

- 3,954 gall rows, all with gall traits;
- 8,524 host links;
- 7,400 gall images;
- 7,992 source links;
- 2,487 aliases;
- 227,451 curated gall-range rows;
- 932 gall labels with trailing parentheticals.

Parentheticals represent different concepts, not one generic qualifier:

- reproductive generation: 621 `(agamic)` and 255 `(sexgen)` token occurrences;
- seasonal generation: 22 records across 11 taxa;
- host/lifecycle phase: 17 records across 11 base taxa;
- morphology/location: 12 records across 6 base taxa;
- rust stages: aecial and telial;
- genuine infraspecific or nomenclatural labels such as `pacificus`, `australis`, `decrescens`, `texanus`, and `pv nerii`;
- behavior/association or legacy disambiguation such as `altering Diplolepis gall`, `perforans`, `q-bicolor`, and `deforming-pisiformis`.

Representative cases:

- `/gall/1173` and `/gall/838`: one inducer species, distinguishable sexual and agamic gall forms.
- `/gall/6613` and `/gall/6612`: one mite species, separate inflorescence and leaf galls.
- `/gall/2960`: rust/host-specific gall labeling rather than a second biological species.

## Chosen architecture

Use an **independent gall aggregate**. A gall is a first-class identification record; biological taxa are separate entities attached through role-bearing associations.

Rejected alternatives:

1. A generic `identification_records` aggregate would make lookalikes semantically neat but generalizes toward a plant-anomaly platform before that scope is approved.
2. A parent gall-concept/child gall-form hierarchy creates a new identity level and recurring ambiguity over hosts, sources, ranges, images, and associations. Shared inducers and explicit gall relationships solve the demonstrated grouping needs without inheritance.

## Core gall aggregate

Create a first-class `galls` table and preserve every current gall ID exactly.

Gall-owned data:

- one persisted, case-insensitively unique gall `label`;
- a structured label recipe and exceptional-override audit metadata;
- `record_class`: `gall | lookalike`;
- data-complete state;
- occurrence abundance;
- detachability;
- reproductive generation;
- Gallformers Code;
- range review/confirmation state;
- morphology junctions: color, walls, cells, shape, texture, alignment, plant part, form, and season;
- gall hosts;
- curated gall range;
- gall images;
- gall sources and per-link excerpts;
- timestamps.

The gall aggregate is the transaction boundary for gall-owned editing. Lookalikes may carry descriptive fields required by the ID tool, but `record_class` must exclude them from core gall counts and prevent presentation as galls.

### Images and sources

Gall images move to `gall_id`. Plant/taxon images remain species-owned. Ownership must be unambiguous: an image has exactly one owner.

Legacy source links and excerpts become gall-level source associations. Do not copy them to deduplicated inducer taxa. General taxon-source links and source-backed organism assertions are deferred. Taxonomic names, synonyms, and authorship continue through their dedicated data/workflows.

### Species and taxonomy after separation

`species` becomes taxon-only. Remove `taxoncode` after cutover rather than replacing `gall` with another role label: being an inducer, associate, or host is expressed by relationships/traits, not a species type. Host eligibility is derived from plant lineage plus host traits. Any organism taxon, plant or non-plant, may participate in a role-bearing association. Host links separately identify the plant bearing the gall.

Accepted names, nomenclatural authorship, scientific synonyms, common names, provisional status, and taxonomic placement are taxon-owned.

Matter [d108](./d108-generic-nested-infrageneric-taxonomy.md) remains responsible for canonical placement and generic infrageneric taxonomy. It retains separate `species` and higher `taxonomy` node tables. This matter must not duplicate or absorb that work. Until a future unified taxon tree exists, a gall association targets exactly one of:

- a `species` record; or
- a higher-rank `taxonomy` node.

Use explicit constrained foreign keys and an association-target domain abstraction so a later unified taxon migration does not change gall semantics. Database constraints enforce exactly one target.


### iNaturalist taxon identifiers

Taxa at any supported rank may have a nullable iNaturalist taxon mapping. Store it as a taxon-owned external identifier, never on the gall or gall–taxon association. Because internal targets currently span `species` and `taxonomy`, use one constrained `taxon_external_identifiers` mapping with:

- exactly one typed internal taxon target;
- code-defined provider `inaturalist` initially;
- numeric external taxon ID;
- uniqueness on `(provider, external_id)` across both internal target tables;
- at most one identifier per provider and internal taxon;
- timestamps/editor attribution.

Admin entry accepts a numeric ID or `https://www.inaturalist.org/taxa/:id` URL, resolves it through the iNaturalist API, and requires review of returned name/rank before saving. Provisional taxa may remain unmapped. Gall pages and API organism entries expose the mapped ID and canonical iNaturalist taxon URL when present; name-based iNaturalist links prefer the stable taxon ID. The identifier remains attached through accepted-name changes, preventing name search from being mistaken for taxon identity. Observation/range/phenology and taxonomic-change features remain follow-up work in [8ba0](./8ba0-inaturalist-integration.md).

## Gall identity and record boundaries

A gall record is a curated identification concept, not a universal tuple or a purely visual class.

Default rule:

- Merge visually identical forms into one gall when available evidence cannot distinguish them.
- Split records only when morphology or user-applicable ecological context—host, tissue, season, generation/life stage, geography, or comparable evidence—supports a distinct identification.

Neither morphology alone nor host alone is a universal database key. Several indistinguishable taxa may be possible inducers of one gall; one inducer may attach to several distinguishable gall records.

The foundational migration preserves one gall record per current row and performs no scientific consolidation. Gall merging is follow-up matter [3e8c](./3e8c-gall-merge-workflow.md).

## Gall labels and organism names

A gall has exactly one nonblank label (maximum 500 characters), unique after trimming and case folding. Gall ID remains stable identity, but duplicate labels are rejected because two indistinguishable records should be one gall and two distinguishable records need a user-visible discriminator. The existing database already enforces unique species-backed gall names and the production snapshot has zero case-folded duplicates, so uniqueness preserves current behavior rather than creating a migration conflict.

### Structured Gall Label Builder

All gall creation and renaming uses a Gall Label Builder; the ordinary editor does not expose an unrestricted label field. The builder stores the rendered label and a structured recipe describing its source components.

Two base modes are supported:

1. **Taxon-based:** use the accepted name of the primary named species or the display label of a provisional species concept. The base excludes nomenclatural authorship.
2. **Descriptive:** when no suitable species-level primary exists, adapt the current undescribed-gall workflow: select a known genus or family, select a linked host, and enter a short normalized descriptive phrase. This produces a gall label and Gallformers Code without fabricating a taxonomic species name.

Editors add only the discriminators necessary to distinguish the record. Each discriminator references structured gall data rather than copying it into a free-form field. Initial builder components are:

- reproductive generation;
- seasonal generation when that dimension is structured;
- one or more linked hosts;
- plant part;
- season;
- gall form;
- lifecycle/rust stage when that dimension is structured.

Components render through code-defined templates, including `(agamic)`, `(sexgen)`, `(on Pyrus)`, and other reviewed conventions. The builder validates that referenced hosts and trait values are already attached to the gall, presents a live preview, and checks case-insensitive uniqueness before save. A collision blocks save and directs the editor either to the existing record or to add a supported discriminator.

A genuinely unmodeled distinction uses an exceptional editorial qualifier, not a general label textbox. It requires a rationale, is visibly marked in admin as unstructured, and enters a review queue so recurring concepts can become structured fields or builder components. This escape hatch handles novel biology without making free-form parentheticals the default data model.

The recipe is persisted. Changing a primary taxon or structured value used by the recipe requires label regeneration in the same reviewed operation; taxon rename/reclassification previews all affected gall labels and blocks on uniqueness conflicts. Probable or possible primary inducers may supply a taxon-based label, but confidence remains visibly displayed and the label is not evidence of confirmation.

Migration preserves every current full label. Known naming patterns are converted to structured recipes. Labels that cannot be parsed without biological judgment become audited legacy-exception recipes and enter the same review queue; migration never rewrites them heuristically.

A gall label has no taxonomic aliases or nomenclatural authorship.

### Taxon naming

All associated-taxon identity remains taxon-owned and viewable from the gall page:

- accepted scientific name;
- authorship citation;
- scientific synonyms;
- organism common names;
- provisional unpublished species label and status.

The gall page displays names for all attached taxa, organized by role and confidence. A gall does not accumulate those names as its own aliases. Existing aliases require migration by meaning:

- scientific aliases move to the deduplicated inducer taxon; when a legacy gall-source link references that alias, preserve the alias reference as metadata on the new gall-source link as long as the alias belongs to a taxon attached to that gall; this does not create a general taxon-source association;
- common aliases move to the deduplicated inducer taxon by default; the exception manifest must identify records that are gall-structure labels rather than organism common names;
- former undescribed/gall-tracking labels become audit-only gall-label history unless the exception manifest establishes that they are genuine taxon names. Historical gall labels are not current gall names, public aliases, or search terms.

Matter [e2cb](./e2cb-taxonomic-name-authorship.md) owns taxonomic authorship. Its name-level ownership remains intact. Gall labels have no authorship.

Standalone public pages for non-plant organism taxa are deferred to matter [1832](./1832-public-organism-taxon-pages.md).

## Organism associations

A `gall_taxon_association` represents a curated conclusion that a target taxon participates in this gall community.

Fields/relations:

- exactly one target: species or higher taxonomy node;
- relationship confidence: `confirmed | probable | possible`;
- optional editorial note;
- one or more controlled ecological roles;
- optional primary-inducer state;
- zero or more host scopes referencing this gall’s own host associations;
- inserted/updated timestamps and the project’s existing editor attribution/audit metadata where those fields already exist.

### Confidence

Confidence describes the relationship, not taxonomic precision:

- `confirmed`: evidence establishes that the target taxon has the recorded role(s) in the gall;
- `probable`: best-supported determination but not conclusive;
- `possible`: plausible candidate that cannot currently be excluded or resolved further.

Taxonomic precision is expressed by the target rank. A confirmed family-level inducer and a possible named-species inducer are distinct valid assertions. Do not add a second taxonomic-confidence scale.

### Roles

Roles are a code-defined, versioned catalog with stable keys, definitions, labels, ordering, public grouping, and mutual-exclusion metadata. Editors cannot create arbitrary roles. One association may carry multiple roles because guild concepts overlap.

Initial catalog:

- `inducer`: causes the plant restructuring represented by the gall;
- `inquiline`: lives within a gall induced by another organism and feeds on gall tissue without substantially transforming the original gall; it is not asserted to kill the inducer;
- `gall_modifying_inquiline`: remains an inquiline relationship, but the organism causes a novel, diagnosable modification of the original inducer’s gall and may kill the inducer; it is grouped publicly under inquilines and is mutually exclusive with the non-modifying `inquiline` role;
- `parasitoid`: develops on or in another gall-community organism and ultimately kills it;
- `hyperparasitoid`: a parasitoid of a parasitoid; here it records gall-community presence, not a trophic target;
- `predator`: consumes organisms in the gall community;
- `cecidophage`: consumes gall plant tissue without being asserted as its primary inducer;
- `successor`: occupies the gall after the inducer has departed or died.

This is deliberately not a full ecological interaction ontology. Direct organism-to-organism trophic edges are deferred. Public copy must not imply a specific prey/host that the schema does not record.


`gall_modifying_inquiline` is a role subtype, not an inducer or parasitoid reclassification. Gall [1148](https://www.gallformers.org/gall/1148) is the model case: *Synergus lignicola* is associated as a gall-modifying inquiline, while the record represents the woody modified outcome of an original inducer gall such as [914](https://www.gallformers.org/gall/914). Where the original gall is known, also add the directional `modified_form_of` gall relationship. Inducer death may be described in the association note; it does not change the inquiline role.

### Primary inducer

Editors may mark at most one association per gall as primary. Only an association containing the `inducer` role may be primary. A primary inducer may be confirmed, probable, or possible; confidence remains explicit. A gall may have no primary inducer.

Primary status drives smart-default naming and compact display only. It does not hide competing evidence or make other associations semantically subordinate.

### Host scope

An association may apply to zero or more existing gall hosts. No scope means it applies to the whole gall concept. The editor may only select hosts already linked to that gall.

Removing a host with scoped organism links is blocked until those scopes are removed or reassigned. Geography, tissue, season, and lifecycle applicability remain in the optional note for this version.

### Invariants

Database/domain validation must enforce:

- exactly one target type/ID;
- at least one valid role;
- explicit valid confidence;
- for a given gall and target taxon, allow either one unscoped association or multiple host-scoped associations with pairwise-disjoint host sets, never both; this permits confidence/roles to differ by host without contradictory overlapping assertions;
- at most one primary inducer per gall;
- primary implies the inducer role;
- scoped hosts belong to the same gall;
- no orphan roles/scopes on association deletion.

## Provisional and broader-rank inducers

A gall association may stop at any modeled rank when that is the best supported determination. Do not fabricate an unknown species merely to attach a genus or family.

When evidence supports a distinct species-level organism but no formal name exists, create a stable provisional unpublished species concept under the most precise known parent. It has an explicit provisional/unpublished status and an editorial display label, not a fabricated Latin binomial and not the gall’s Gallformers Code. One provisional species may attach to multiple galls when evidence supports one organism producing several forms. It can later receive a published name without changing gall identity.

Replace gall-level `undescribed` with a derived inducer-resolution presentation. Derive it deterministically from associations carrying the `inducer` role, independent of their confidence: `none` when there are no inducer associations; `multiple` when there is more than one; otherwise `named_species`, `provisional_species`, or `broader_rank` according to the single target. Confidence is displayed separately and is never folded into this state.

A gall structure itself is not taxonomically described or undescribed.

## Gallformers Code, abundance, and completeness

Gallformers Code belongs to the gall structure. It identifies what observers can recognize and remains stable through inducer reclassification, multiple candidates, or one inducer producing several gall forms. Preserve all existing values and iNaturalist links exactly. Remove documentation that defines it as an undescribed-species identifier.

Abundance describes gall occurrence for identification and moves to the gall. New inducer taxa do not inherit it.

`data_complete` remains one gall-level editorial flag meaning the identification record has expected gall-focused information. Inducer resolution is independent: an unnamed, broader-rank, or uncertain inducer does not automatically make a documented gall incomplete. The existing rule that a source-less gall cannot be complete remains. Remove the rule that an “undescribed” gall is necessarily incomplete. Section scoring remains matter [7cde](./7cde-data-completeness-scoring.md).

## Reproductive generation and other qualifiers

Structure reproductive generation on the gall record:

- `agamic`;
- `sexual`;
- null for unknown/not applicable.

Backfill terminal `(agamic)` and `(sexgen)` labels while preserving those labels initially. This supersedes the ownership assumption in matter [0a58](./0a58-generation-field-for-gall-traits.md); do not add generation to species-keyed `gall_traits` independently.

Seasonal generations, rust stages, host phases, morphology qualifiers, and infraspecific taxon labels are separate concepts. Do not force them into reproductive generation. They remain in labels/traits until separately designed.

## Hosts

Keep gall-host associations simple in this change. Move existing host links unchanged to `gall_id`. Do not add host certainty, geography, tissue, or lifecycle fields. Organism-association host scopes provide the required first contextual distinction.

## Gall-to-gall relationships

Replace name-prefix “Related Galls” with two mechanisms.

### Derived shared-inducer relationships

Show other galls sharing the same exact species-level inducer target, including provisional species concepts. Do not derive same-inducer relationships from a shared genus, family, or other broader-rank target. Display relevant confidence and reproductive generation. This covers most current agamic/sexual and one-species/multiple-form relationships without persisting redundant links.

### Explicit relationships

Support only:

- `lookalike`: symmetric; two records may be confused during identification;
- `modified_form_of`: directional from the modified gall record to the original inducer’s gall. The modifying organism remains a `gall_modifying_inquiline` association on the modified record; the gall-to-gall link identifies the original structure being transformed. The inverse public label is `has modified form`.

Use a constrained vocabulary, correct directionality/symmetry, duplicate prevention, and no generic untyped “related” relation. Do not add alternate-generation, lifecycle, or duplicate-candidate relations without a concrete need.

## Public experience

### Gall detail

Lead with gall label and identification data. Add **Associated organisms**, grouped:

1. primary inducer;
2. other inducers;
3. inquilines, separated into non-modifying and gall-modifying inquilines;
4. parasitoids and hyperparasitoids;
5. predators, cecidophages, and successors.

Each entry shows accepted taxon name, authorship when present/applicable, roles, confidence, applicable host when scoped, and note. Scientific synonyms and common names are available beneath each taxon without being presented as gall names. Format broader ranks honestly and according to rank.

Related sections:

- other galls from this inducer;
- lookalikes;
- modified form of / has modified form.

### Identification and search

The ID result’s primary identity is the gall label. Compact secondary text shows the primary inducer and confidence where useful. Multiple candidates render as possible/probable inducers rather than silently selecting a species.

Search matches gall labels and attached taxa’s accepted, scientific-synonym, and common names but returns gall records. When a synonym/name of an attached taxon caused the match, explain that relationship.

Lookalikes are visibly labeled as non-gall identification aids and excluded from core gall counts. Gall-family/genus browse pages and inducer-family ID filters traverse only associations carrying the `inducer` role. A gall appears under every exact or ancestral taxonomic node supported by its inducer targets, with confidence visible and counts deduplicated by gall ID; parasitoid, inquiline, and other associate taxonomy never determines gall browse placement.

## Admin experience

The gall editor manages gall-owned fields. Creation and rename operations use the structured Gall Label Builder. Structured fields are selected before label components, the preview updates immediately, and the rendered label is read-only outside the builder. Exceptional editorial qualifiers require rationale and the elevated override action described above.

A dedicated organism-association editor:

- searches taxa at species or higher rank;
- records and validates an iNaturalist taxon ID/URL on the target taxon when available;
- creates a provisional species concept when justified;
- selects one or more roles, including the two inquiline forms;
- requires explicit confidence;
- optionally marks an inducer primary;
- optionally scopes the association to existing gall hosts;
- previews the label-recipe effect before save.

Changing a primary inducer or any structured value referenced by the label recipe requires regeneration and uniqueness validation. Taxon names, authorship, synonyms, common names, iNaturalist mapping, and placement remain in taxonomy/species workflows.

## API v2 cutover

Keep `/api/v2/galls` routes and gall IDs but perform a clean semantic cutover. Do not preserve the legacy species-shaped response or compatibility shims.

Use `label`, not `name`, as the gall identity field. Return:

- `id`, `label`, `record_class`, `data_complete`, occurrence abundance, `gallformers_code`, and reproductive generation;
- morphology, hosts, range, images, and sources;
- organism associations with target ID/type/rank, accepted name, authorship, iNaturalist taxon ID/URL when mapped, roles, confidence, primary state, scoped host IDs, and note;
- derived `inducer_resolution` state;
- related records divided into shared-inducer galls, lookalikes, `modified_form_of`, and inverse modified-form results.

Remove gall-level `undescribed`, gall taxonomic aliases, and species-taxonomy claims. Document the response as a breaking semantic change despite stable paths and IDs.

## Migration

### Prerequisites and dependencies

- [2cb2](./2cb2-multi-species-gall-model.md) needs [d108](./d108-generic-nested-infrageneric-taxonomy.md) for canonical species placement and post-junction taxonomy shape.
- [2cb2](./2cb2-multi-species-gall-model.md) needs [e2cb](./e2cb-taxonomic-name-authorship.md) for exact-name authorship behavior.
- [0a58](./0a58-generation-field-for-gall-traits.md) depends on this matter’s gall ownership.
- Follow-ups [3e8c](./3e8c-gall-merge-workflow.md) (gall merge workflow) and [1832](./1832-public-organism-taxon-pages.md) (public organism taxon pages) depend on this foundation.
- [8ba0](./8ba0-inaturalist-integration.md) relates to this matter and builds future iNaturalist-backed features on its taxon external identifiers.

### Mapping approach

Use narrow deterministic transformation rules plus a checked-in, reviewed exception manifest.

Safe rules cover ordinary scientific names and explicitly approved gall-form suffixes. The manifest covers:

- true infraspecific names and pathovars;
- nested parentheticals;
- unknown placeholders;
- non-gall lookalikes;
- multiple or uncertain inducers;
- legacy behavioral/disambiguation labels;
- every transformation/deduplication that cannot be proven mechanically.

Preflight must account for every legacy gall ID exactly once and show preserved gall ID/label plus its new taxon outcome. Abort on unknown patterns, duplicate mappings, invalid target placement, or inconsistent ownership.

### Expand and backfill

1. Add gall-centered tables and temporary nullable/new ownership paths.
2. Preserve every legacy gall species ID as the new gall ID and its full current name as the initial unique label. Convert recognized patterns into structured label recipes; use audited legacy-exception recipes for the rest.
3. Create new species IDs for every inducer taxon from a sequence advanced beyond the pre-migration maximum species ID. No new taxon created by this migration reuses a legacy gall ID as its corresponding taxon ID; gall and taxon IDs remain typed by entity thereafter.
4. Deduplicate biological species where mapping is reliable. Remove gall-form qualifiers from taxon names; do not mechanically remove genuine taxonomic parentheticals.
5. Create a confirmed primary-inducer association from each legacy named-species assertion unless the manifest specifies a broader rank, provisional concept, multiple candidates, another confidence, or no inducer.
6. Move gall-owned data: morphology, reproductive generation, hosts, ranges, images, sources/excerpts, occurrence abundance, completeness, Gallformers Code, and review state.
7. Move taxon-owned data: canonical taxonomy placement, accepted names, authorship, scientific synonyms, and organism common names. Preserve legacy gall-source-to-alias metadata under the constraint described above.
8. Backfill lookalike classification from the current `non-gall` form, then remove `non-gall` as a morphology value.
9. Backfill reproductive generation from exact `(agamic)`/`(sexgen)` tokens in the gall-label qualifier segment, including reviewed multi-parenthetical labels. Family placeholders such as `Unknown (Cynipidae)` are taxonomy, not generation. Attach recognized label components to the structured recipe; retain every other qualifier in an audited legacy-exception recipe.
10. Replace related-name inference with shared-inducer derivation. Do not invent explicit lookalike/modified-form links from labels.

Do not consolidate gall records during this migration.

### Legacy confidence

Migrate the current named-inducer assertion as `confirmed` by default because that is the claim the existing product presents. The reviewed manifest identifies exceptions. Do not silently downgrade the entire database or require review of every ordinary record.

### Rollout

Use expand/validate/switch without long-lived dual writes:

1. Add and backfill the new schema while the legacy application continues reading old data.
2. Block or tightly gate gall/taxon admin writes during the final mapping and comparison window.
3. Resolve every preflight/backfill exception and run production-data invariant comparisons.
4. Deploy one atomic application/API read/write cutover.
5. Smoke-test production behavior.
6. Remove obsolete species-backed gall semantics and junctions only after verification.

Rollback before application cutover is schema-safe. After new-model writes begin, use a tested forward correction or restore procedure; do not pretend the new writes can be losslessly projected back into the conflated model.

### Migration invariants

Prove at minimum:

- all 3,954 legacy gall IDs become 3,954 same-ID gall records;
- every gall-owned record moves exactly once with matching counts and no orphan;
- every legacy gall has an explicit inducer outcome;
- every new accepted taxon name is valid and unique under canonical species-name rules and has coherent placement; every gall label is nonblank and case-insensitively unique;
- all source excerpts, image paths, Gallformers Codes, ranges, timestamps, and migrated label recipes remain intact;
- every populated iNaturalist external ID has one internal taxon target, is globally unique for the provider, and resolves to the reviewed iNaturalist taxon;
- association target, role, confidence, primary, and host-scope invariants hold;
- no unknown parenthetical category is silently transformed.

## Verification and acceptance

Behavioral tests must prove:

- one species taxon can induce several galls;
- one gall can have several inducers with different confidence;
- one association can carry overlapping roles, while non-modifying and gall-modifying inquiline subtypes remain mutually exclusive;
- associations target species or higher ranks;
- provisional species and broader-rank determinations render correctly;
- host-scoped associations cannot reference unrelated hosts;
- primary-inducer, structured label-recipe, exceptional-override, regeneration, and case-insensitive uniqueness invariants;
- derived inducer-resolution states replace gall-level undescribed;
- lookalikes appear in ID results but not core gall counts;
- shared-inducer relationships, symmetric lookalikes, and directional modified-form relationships;
- stable existing gall URLs and IDs;
- gall-centered API response, synonym-match explanation, and iNaturalist taxon ID/URL exposure;
- migration rules handle every parenthetical class, including non-terminal generation tokens and Unknown-family placeholders, without stripping true taxonomy.

Production-data verification compares ownership-table counts and checksums before and after backfill.

End-to-end smoke scenario:

1. open a preserved legacy `/gall/:id` URL;
2. edit gall morphology and rebuild a unique label from structured components;
3. attach confirmed and possible taxa at different ranks, save a reviewed iNaturalist taxon mapping, and assign overlapping roles including both inquiline forms;
4. mark a lower-confidence primary and verify honest display;
5. scope one association to a linked host and verify invalid scopes/removal are blocked;
6. verify ID result, gall detail, search-by-attached-synonym, and API output;
7. follow shared-inducer, lookalike, and directional modified-form relationships;
8. confirm a lookalike is labeled and excluded from gall totals.

Final repository verification requires `mix compile --warnings-as-errors`, focused/full tests appropriate to the affected contracts, `mix precommit`, and browser-driven public/admin/API scenarios.

## Explicitly deferred

- source-backed organism assertions and general taxon-source links;
- standalone public non-plant organism pages ([1832](./1832-public-organism-taxon-pages.md));
- gall merging, redirects, and field reconciliation ([3e8c](./3e8c-gall-merge-workflow.md));
- iNaturalist observation/range/phenology ingestion and taxonomic-change automation ([8ba0](./8ba0-inaturalist-integration.md));
- organism-to-organism trophic graphs;
- richer host certainty/context;
- geographic, tissue, season, or stage scoping of organism links;
- seasonal-generation, rust-stage, and general lifecycle ontologies;
- unified taxonomy beyond [d108](./d108-generic-nested-infrageneric-taxonomy.md);
- broader plant-malady coverage;
- generic gall-concept/form inheritance.

## Design references

- Gobbo et al. (2020), “From Inquilines to Gall Inducers,” illustrates that inducer and inquiline are ecological roles that may occur within closely related taxa: https://doi.org/10.1093/gbe/evaa204
- Luz and Mendonça (2019), “Guilds in Insect Galls: Who is Who,” motivates distinguishing overlapping guild dimensions including inquilines, cecidophages, successors, predators, and parasitoids: https://doi.org/10.1653/024.102.0133


