---
status: raw
created: 2026-09-14
updated: 2026-09-14
epic: taxonomy
relates: [2cb2]
---

# Structured gall name builder

## Purpose and review status

Give every gall a human-readable name through a structured name builder. Jeff identifies this as an important product feature. This matter extracts the existing proposal from `2cb2`; it does not redesign it or approve its details. It remains Raw for review with Jeff and Adam.

The draft uses “label” for the gall's name to distinguish it from an organism's scientific name. Its references to primary inducers and confidence remain proposals; whether relationship certainty is needed in the first release is explicitly open for Adam in `1121`.

## Existing proposal — preserved for review

### Gall name and identity

A gall has exactly one nonblank label (maximum 500 characters), unique after trimming and case folding. Gall ID remains stable identity, but duplicate labels are rejected because two indistinguishable records should be one gall and two distinguishable records need a user-visible discriminator. The existing database already enforces unique species-backed gall names and the production snapshot has zero case-folded duplicates, so uniqueness preserves current behavior rather than creating a migration conflict.

### Structured Gall Name Builder

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

### Admin workflow and integration

The gall editor manages gall-owned fields. Creation and rename operations use the structured Gall Label Builder. Structured fields are selected before label components, the preview updates immediately, and the rendered label is read-only outside the builder. Exceptional editorial qualifiers require rationale and the elevated override action described above.

Changing a primary inducer or any structured value referenced by the label recipe requires regeneration and uniqueness validation. Taxon names, authorship, synonyms, common names, iNaturalist mapping, and placement remain in taxonomy/species workflows.

## Related work

- `2cb2`: gall/taxon separation, shared editing, and the overall migration. Builder behavior is owned here; model-wide integration and verification remain there.
- `1121`: the lean Taxonomy product guide and questions for Adam.
- `e2cb`: scientific-name authorship, distinct from gall naming.
- `0a58`: structured reproductive generation, one potential naming component.

Extraction does not decide implementation order or first-release scope. The earlier suggestion to defer the builder is not an agreed decision.

