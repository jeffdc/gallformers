# Taxonomy Lineage Domain Type — Design

**Date**: 2026-02-11
**Status**: Proposal
**Scope**: `Gallformers.Taxonomy.Lineage`, `Family`, `Genus`, `Section` domain types

## Problem

The codebase constructs, deconstructs, and passes around plain maps representing the
"Family → Genus → Section (optional)" taxonomy hierarchy in at least 6 different shapes
across 12+ locations. This is a classic unmodeled domain type (CLAUDE.md Principle #6).

### Current map shapes

| Shape | Keys | Where Used |
|-------|------|------------|
| Core FSG | `genus, genus_id, section, section_id, family, family_id` | Tree, SpeciesLink, Forms |
| With descriptions | Above + `genus_description, family_description, section_description` | `get_taxonomy_for_species` |
| New genus | Core + `genus_is_new: true`, IDs nil | Form init for new species |
| Disambiguation | `genus, requires_disambiguation, possible_families: [...]` | Multi-family genus lookup |
| Resolution wrapper | `taxonomy, genus_is_new, family_id, section_id, possible_families` | Bridge between lookup and form |
| Batch minimal | `genus, family` (names only) | Bulk query optimization |
| Reclassify adapter | `%{id: id, name: name}` | Reshaping for ReclassifyLive |

### Construction sites (duplicated logic)

1. `Tree.build_taxonomy_from_genus/1` — 2-way pattern match on parent (nil/family), returns flat map
2. `SpeciesLink.build_taxonomy_map/2` — Same 2-way match, different data path, same map shape
3. `SpeciesLink.lookup_taxonomy_for_new_species/1` — 3-way: new genus / single match / ambiguous
4. `SpeciesLink.resolve_taxonomy_for_species/2` — Wraps lookup result in normalized container
5. `SpeciesLink.get_taxonomy_for_species/1` — Query with section join, returns map with descriptions
6. `ReclassifyHelpers.apply_family_disambiguation/2` — Reconstructs map from disambiguation modal

### Consumption patterns

- Forms: `taxonomy && taxonomy.family_id` (nil-guard boilerplate everywhere)
- Components: `if @taxonomy, do: @taxonomy.genus, else: ""`
- Business logic: `Galls.compute_undescribed_lock(taxonomy, species_id)` — two args always passed together
- Adapters: `ReclassifyHelpers.reclassify_family/1` reshapes `%{family_id:, family:}` into `%{id:, name:}`

### Root cause

The relational DB schema (one `taxonomy` table with `type` column and `parent_id`) is leaking
into the domain layer. Family, Genus, and Section are real domain objects, not pairs of
`name + id` fields on a flat map.

## Proposed Design

### Domain types

Four new structs, each in its own module under `lib/gallformers/taxonomy/`:

#### `Gallformers.Taxonomy.Family`

```elixir
defmodule Gallformers.Taxonomy.Family do
  @moduledoc "A taxonomic family (e.g., Cynipidae, Fagaceae)."

  defstruct [:id, :name, :description]

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          description: String.t() | nil
        }
end
```

#### `Gallformers.Taxonomy.Genus`

```elixir
defmodule Gallformers.Taxonomy.Genus do
  @moduledoc "A taxonomic genus (e.g., Andricus, Quercus)."

  defstruct [:id, :name, :description]

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          description: String.t() | nil
        }
end
```

#### `Gallformers.Taxonomy.Section`

```elixir
defmodule Gallformers.Taxonomy.Section do
  @moduledoc "A taxonomic section, an optional subdivision within a genus."

  defstruct [:id, :name, :description]

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t(),
          description: String.t() | nil
        }
end
```

#### `Gallformers.Taxonomy.Lineage`

```elixir
defmodule Gallformers.Taxonomy.Lineage do
  @moduledoc """
  The taxonomic placement of a species: Family → Genus → Section (optional).

  This is the "address" of a species in the taxonomy tree. Unlike the Taxonomy
  Ecto schema (which models a single tree node), a Lineage models the *path*
  from family down to genus, composed of proper domain types.

  Includes species_id and species_name because a lineage is always for a
  specific species (or a species being created). These fields are nil during
  creation before the species is persisted.

  Companion to TaxonName: TaxonName parses species name strings (bootstrapping).
  Lineage models where the species sits in the tree (structured data with IDs).
  """

  alias Gallformers.Taxonomy.{Family, Genus, Section, TaxonName}

  defstruct [:species_id, :species_name, :family, :genus, :section]

  @type t :: %__MODULE__{
          species_id: integer() | nil,
          species_name: String.t() | nil,
          family: Family.t() | nil,
          genus: Genus.t(),
          section: Section.t() | nil
        }
end
```

### Constructor functions

All constructors live in the `Lineage` module. No DB access — they take
already-loaded data and return structs.

```elixir
@doc "Build a Lineage from a Taxonomy genus record and its preloaded parent."
@spec from_genus(Taxonomy.t()) :: t()
def from_genus(genus)

@doc "Build a Lineage for a new genus that doesn't exist in the DB yet."
@spec new_genus(String.t()) :: t()
def new_genus(genus_name)

@doc """
Build a Lineage from the result maps returned by SpeciesLink queries.
Used by get_taxonomy_for_species and similar query functions to convert
their raw query results into a Lineage.
"""
@spec from_query_result(map(), map() | nil) :: t()
def from_query_result(genus_result, section_result \\ nil)
```

`from_genus/1` replaces both `Tree.build_taxonomy_from_genus/1` and
`SpeciesLink.build_taxonomy_map/2` — the duplicated construction logic.

`new_genus/1` replaces the `%{genus: name, genus_id: nil, genus_is_new: true, ...}` maps.

`from_query_result/2` is the bridge from the raw Ecto query maps (which select
specific columns) into the domain type.

### Behavior functions

```elixir
@doc "Is the genus resolved (has a DB id)? False for new genera during creation."
@spec resolved?(t()) :: boolean()
def resolved?(%__MODULE__{genus: %Genus{id: nil}}), do: false
def resolved?(%__MODULE__{}), do: true

@doc "Is the genus a placeholder 'Unknown (Family)' name?"
@spec placeholder_genus?(t()) :: boolean()
def placeholder_genus?(%__MODULE__{genus: %Genus{name: name}}),
  do: TaxonName.unknown_genus?(name)

@doc "Does this lineage include a section?"
@spec has_section?(t()) :: boolean()
def has_section?(%__MODULE__{section: nil}), do: false
def has_section?(%__MODULE__{}), do: true

@doc "Parse the species_name into a TaxonName struct. Bridge to TaxonName for callers that need epithet/qualifier."
@spec parsed_name(t()) :: TaxonName.t() | nil
def parsed_name(%__MODULE__{species_name: nil}), do: nil
def parsed_name(%__MODULE__{species_name: name}), do: TaxonName.parse(name)
```

### What gets deleted

- `ReclassifyHelpers.reclassify_family/1` — replaced by `lineage.family` (it's already a `%Family{}`)
- `ReclassifyHelpers.reclassify_genus/1` — replaced by `lineage.genus`
- `ReclassifyHelpers.apply_family_disambiguation/2` — constructs a `%Lineage{}` directly
- `Tree.build_taxonomy_from_genus/1` — replaced by `Lineage.from_genus/1`
- `SpeciesLink.build_taxonomy_map/2` — replaced by `Lineage.from_genus/1`
- The duplicated 2-way pattern match on parent type

### Disambiguation — not a Lineage variant

The disambiguation state (`requires_disambiguation: true, possible_families: [...]`)
is a *lookup result*, not a lineage. It means "I tried to find your lineage and
found multiple candidates."

Replace the current variant-map approach with tagged return tuples:

```elixir
@type lookup_result ::
  {:ok, Lineage.t()}
  | {:new_genus, Lineage.t()}
  | {:ambiguous, String.t(), [family_candidate()]}

@type family_candidate :: %{
  genus_id: integer(),
  section: Section.t() | nil,
  family: Family.t()
}
```

Callers pattern-match on the tag instead of checking magic map keys like
`Map.get(taxonomy, :requires_disambiguation)`.

## File layout

```
lib/gallformers/taxonomy/
├── family.ex            # %Family{} struct
├── genus.ex             # %Genus{} struct
├── section.ex           # %Section{} struct
├── lineage.ex           # %Lineage{} struct + constructors + behavior
├── taxon_name.ex        # Unchanged — bootstrapping string parser
├── taxonomy.ex          # Unchanged — Ecto schema (DB row)
├── tree.ex              # Updated — returns Lineage, delegates construction
├── species_link.ex      # Updated — returns Lineage, delegates construction
└── reclassification.ex  # Updated — works with Lineage
```

## Migration strategy

### Phase 1 — Introduce types, update constructors

1. Create `Family`, `Genus`, `Section`, `Lineage` modules.
2. Add constructors: `from_genus/1`, `new_genus/1`, `from_query_result/2`.
3. Change `Tree.build_taxonomy_from_genus/1` to call `Lineage.from_genus/1`.
4. Change `SpeciesLink.build_taxonomy_map/2` to call `Lineage.from_genus/1`.
5. Change `SpeciesLink.get_taxonomy_for_species/1` to return `%Lineage{}`.

**Breaking change**: `taxonomy.family_id` becomes `taxonomy.family.id`. The
compiler catches every missed site because `%Lineage{}` has no `family_id` field.

### Phase 2 — Update consumers

6. Update both admin forms (`gall_live/form.ex`, `host_live/form.ex`):
   - `taxonomy.family_id` → `taxonomy.family && taxonomy.family.id` (or use Lineage helpers)
   - `taxonomy.genus_id` → `taxonomy.genus.id`
   - `taxonomy.section_id` → `taxonomy.section && taxonomy.section.id`
7. Update `taxonomy_genus_family_row` component to expect `%Lineage{}`.
8. Update `genus_disambiguation_modal` component.
9. Replace `reclassify_family(@taxonomy)` with `@taxonomy.family` and
   `reclassify_genus(@taxonomy)` with `@taxonomy.genus`.
10. Update `Galls.compute_undescribed_lock/2` to take a single `%Lineage{}`.
11. Delete `ReclassifyHelpers.reclassify_family/1` and `reclassify_genus/1`.

### Phase 3 — Type the lookup/resolution flow

12. Change `lookup_taxonomy_for_new_species/1` to return tagged tuples.
13. Update `resolve_taxonomy_for_species/2` to match on tags.
14. Update both form modules for the new return shapes.
15. Delete or simplify `ReclassifyHelpers` if fully subsumed.

Each phase is independently committable and testable.

## Trade-offs

### Gets simpler

- **One constructor** instead of two duplicated pattern matches
- **Real types** instead of flat maps — `lineage.family` is a `%Family{}` you can pass directly
- **Adapter elimination** — `ReclassifyHelpers.reclassify_family/1` and `reclassify_genus/1` disappear
- **Parameter reduction** — `compute_undescribed_lock(taxonomy, species_id)` becomes `compute_undescribed_lock(lineage)`
- **Self-documenting** — `%Lineage{}` is greppable, has typespecs, shows up in dialyzer
- **Compiler-enforced migration** — flat field access like `taxonomy.family_id` fails on a struct, so the compiler finds every site that needs updating

### Gets more complex

- Four new modules (but three are 5-line structs)
- `taxonomy.family_id` → `taxonomy.family.id` is more keystrokes for nil cases
- Phase 1 is not a silent drop-in — requires updating access patterns in the same commit

### Risks

- `description` fields are only populated by `get_taxonomy_for_species`. Other constructors
  leave them nil. Callers must not assume they're always present (typespec makes this explicit).
- Batch query (`get_taxonomy_for_species_batch`) returns only names. Could return a Lineage
  with nil IDs, or stay as a lightweight map. Forcing it into Lineage may be over-modeling
  for a performance-optimized path.

## Relationship to TaxonName

| Concern | Type | What it models |
|---------|------|---------------|
| Parsing a species name string | `TaxonName` | genus, epithet, qualifier, unknown? |
| Where a species sits in the tree | `Lineage` | family → genus → section path with IDs |

They are peers, not nested. `TaxonName` is used **before** a Lineage exists — it extracts
the genus name from a raw string so the lookup can find the Lineage. Once you have a Lineage,
`Lineage.parsed_name/1` bridges back to TaxonName for callers that need the epithet/qualifier.

The connection point is the genus name: `TaxonName.parse(name).genus` extracts it from the
string, and `lineage.genus.name` holds the same value from the tree.

## Relationship to future Species domain type

Lineage is deliberately **neutral** on the Species type question. Whether the future Species
domain type is one struct, two structs (Gall/Plant), or a protocol, both/all will hold a
`%Lineage{}`. The lineage shape is the same regardless of what kind of species sits at the end.

See `docs/plans/2026-02-11-species-domain-type-notes.md` for initial thinking on the Species
type design.

## Example usage

### Loading an existing species for editing

```elixir
# In a form's mount
lineage = Taxonomy.get_taxonomy_for_species(species_id)

socket
|> assign(:taxonomy, lineage)
|> assign(:selected_family_id, lineage && lineage.family && lineage.family.id)
```

### Creating a new species

```elixir
case Taxonomy.lookup_taxonomy_for_new_species(name) do
  {:ok, %Lineage{} = lineage} ->
    socket |> assign(:taxonomy, lineage)

  {:new_genus, %Lineage{} = lineage} ->
    socket |> assign(:taxonomy, lineage)

  {:ambiguous, genus_name, possible_families} ->
    socket
    |> assign(:taxonomy, Lineage.new_genus(genus_name))
    |> assign(:possible_families, possible_families)
    |> assign(:show_genus_disambiguation, true)

  nil ->
    socket
end
```

### Passing to ReclassifyLive

```elixir
# Before: adapter functions
current_family={reclassify_family(@taxonomy)}
current_genus={reclassify_genus(@taxonomy)}

# After: direct access
current_family={@taxonomy && @taxonomy.family}
current_genus={@taxonomy && @taxonomy.genus}
```

### Undescribed lock check

```elixir
# Before: two args
Galls.compute_undescribed_lock(taxonomy, species_id)

# After: one arg
Galls.compute_undescribed_lock(lineage)
```

## Manual Test Plan

This section covers how to verify the Lineage refactor didn't break any user-facing
behavior. All tests are performed in the admin UI at `http://localhost:4000`.

### 1. Edit an existing gall

1. Navigate to any gall's admin edit page (e.g. `/admin/gall/1`).
2. The **Genus** and **Family** fields in the taxonomy row should display text names
   (e.g. "Andricus", "Cynipidae"), not blank, `nil`, or something like `%Genus{...}`.
3. Make a trivial edit (e.g. toggle a trait checkbox) and save.
4. Confirm the save succeeds with a green flash message and the genus/family still
   display correctly after reload.

### 2. Edit an existing host that has a section

1. Navigate to an existing host that belongs to a genus with sections. Oaks (Quercus)
   are a good choice — find one via `/admin/host` search.
2. Verify the **Genus**, **Family**, and **Section** fields all display text names.
3. The section dropdown should be populated with available sections for that genus.
4. Change the section selection, save, and confirm the new section persists on reload.

### 3. Create a new gall with a known genus

1. Go to `/admin/gall` and click **New Gall**.
2. In the name field, type a species name using an existing genus
   (e.g. "Andricus testspecies").
3. The taxonomy row should auto-fill with the correct genus and family. No
   disambiguation modal should appear.
4. You do not need to complete the save — just verify the auto-fill works.

### 4. Create a new gall with an ambiguous genus

An "ambiguous genus" is one that exists in multiple families. Currently the only
example in the database is **Phoradendron**, which exists in 2 families.

1. Go to `/admin/gall` → **New Gall**.
2. Type "Phoradendron testspecies" in the name field.
3. A **genus disambiguation modal** should appear listing the possible families.
4. Each family option should display a readable family name (not a struct or ID).
   If any option has a section, the section name should display below the family name.
5. Click one of the family options.
6. The modal should close, and the taxonomy row should now show the selected family
   and genus.

### 5. Create a new gall with a brand-new genus

1. Go to `/admin/gall` → **New Gall**.
2. Type a species name with a genus that does not exist in the database
   (e.g. "Xyzzygenus testspecies").
3. The form should load without errors. The genus field should show the new genus name.
   The family field should be empty (since the genus is unknown).
4. You do not need to complete the save.

### 6. Create a new host — same genus-lookup paths

Repeat tests 3–5 above but using `/admin/host` → **New Host** instead. The behavior
should be identical: known genus auto-fills, ambiguous genus shows disambiguation,
new genus shows empty family.

For hosts, also verify that after genus disambiguation resolves, the **section
dropdown** populates if the selected genus has sections.

### 7. Reclassify a gall

1. Open an existing gall for editing.
2. Click the **Reclassify** button to open the reclassify modal.
3. The modal should display the current family and genus names (not blank or struct
   representations).
4. Select a different genus and/or family and complete the reclassification.
5. After the modal closes, verify:
   - A green flash message confirms the update.
   - The taxonomy row shows the new genus and family.
   - Reloading the page still shows the updated taxonomy.

### 8. Reclassify a host

1. Open an existing host for editing.
2. Click **Reclassify** and verify the same behavior as test 7.
3. Additionally, after reclassification completes, verify the **section dropdown**
   repopulates correctly for the new genus (it should show sections for the new genus,
   or be empty if the new genus has no sections).

### 9. Undescribed gall lock behavior

1. Find or create a gall that has `undescribed` set to true (these are galls with
   names like "Unknown (Cynipidae) q-alba-hideous-wart").
2. Open it for editing.
3. Certain fields should be locked/disabled based on the undescribed status. Verify
   that the lock indicator and field disabling still function (fields that were locked
   before this change should still be locked).
4. If the gall has a known genus/family, those should still display correctly.

### 10. Public gall detail page

1. Navigate to a gall's public page (e.g. `/gall/4153` or pick any gall from the
   main search).
2. The taxonomy line should display **Family** and **Genus** as clickable links with
   correct names (e.g. "Eriophyidae", "Acalitus").
3. Click the **Family** link — it should navigate to `/family/{id}`, not `/family/`
   or an error page.
4. Go back and click the **Genus** link — it should navigate to `/genus/{id}`.
5. If the family or genus has a description, it should appear in parentheses after
   the name (e.g. "Eriophyidae (Mite)"). If the description is blank, no empty
   parentheses should appear.
6. Try a few different galls to cover variety — one with a description, one without.

### 11. Public host detail page

1. Navigate to a host's public page (e.g. `/host/123` or search for a host plant).
2. The taxonomy line should display **Family**, **Genus**, and optionally **Section**
   as clickable links with correct names.
3. Click each link (Family, Genus, and Section if present) — each should navigate to
   the correct page (`/family/{id}`, `/genus/{id}`, `/section/{id}`).
4. Descriptions in parentheses should appear only when non-empty.
5. Test with a host that **has a section** (e.g. an oak — Quercus species often have
   sections) and one that **does not** have a section. The section separator and label
   should only appear when a section exists.

### 12. Public family, genus, and section pages

1. After clicking through the links in tests 10 and 11, verify the family, genus, and
   section landing pages load without errors.
2. These pages list species belonging to that taxon — confirm the page renders a
   species list (or an appropriate empty state).

### What to look for across all tests

- **No struct leaks**: You should never see `%Gallformers.Taxonomy.Family{...}` or
  similar in any text field or label. All displayed values should be plain strings.
- **No blank names**: If a gall or host has a genus and family, those names should
  always render. A blank field where a name should appear indicates a `.name` accessor
  was missed.
- **No crashes**: Check the server console for any `KeyError`, `UndefinedFunctionError`,
  or `BadStructError` — these would indicate code still trying to access the old flat
  map keys like `taxonomy.family_id` or `taxonomy.genus`.
