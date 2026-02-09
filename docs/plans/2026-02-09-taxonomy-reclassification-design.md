# Taxonomy Reclassification Design

## Problem

There is no way to change a species' taxonomy (genus/family) after creation. This blocks
several real workflows:

- A gall was created under `Unknown (Unknown)` and later identified as a midge — needs to
  move to `Unknown (Cecidomyiidae)`
- An undescribed gall gets formally described — needs to move from `Unknown (Cecidomyiidae)`
  to a real genus like `Asteromyia`
- A species was misclassified and needs to move to a different genus entirely

Additionally, the gall creation flow has gaps around Unknown genus handling and inline
taxonomy creation. And the `undescribed` flag on `gall_traits` has no enforced relationship
with taxonomy state, leading to data inconsistencies (21 found during investigation).

## Design

Three changes, described below:

1. Reclassify modal (post-creation taxonomy editing)
2. Improved gall creation taxonomy flow
3. Enforced undescribed invariant

---

## 1. Reclassify Modal

A dedicated "Reclassify" button on both the gall and host edit forms. Opens a modal for
reassigning a species' taxonomy.

### UI

The modal shows:

**Current taxonomy** (read-only, top of modal):
> Family: Unknown | Genus: Unknown (Unknown)

**New taxonomy** with two fields:

- **Genus** — typeahead searching all genera. Selecting a genus auto-populates the family
  (every genus has a parent family).
- **Family** — auto-populated and read-only when a real genus is selected. Becomes a dropdown
  when the user selects "Unknown" as genus, so they can specify which family's Unknown genus
  to use.

### Flows

**Move to a real genus:**
Pick genus "Asteromyia" in typeahead -> family auto-fills "Cecidomyiidae" -> confirm.

**Move to a different family (genus still unknown):**
Pick "Unknown" in genus field -> family dropdown appears -> pick "Cecidomyiidae" -> system
links to `Unknown (Cecidomyiidae)` -> confirm.

**Move to fully unknown:**
Pick "Unknown" in genus field -> pick "Unknown" in family dropdown -> links to
`Unknown (Unknown)` -> confirm.

### Scope

- Available on both gall and host edit forms (built as a reusable component)
- **Hosts do not use Unknown genera or families.** The "Unknown -> pick family" flow
  only appears for galls. For hosts the genus typeahead is the only option, and there
  is no undescribed flag to manage.

### Backend

New function in `Taxonomy` context:

```elixir
@doc """
Reassign a species to a different genus. Deletes the existing genus link
in species_taxonomy and creates a new one. For galls with Unknown genus,
enforces undescribed=true on gall_traits.
"""
@spec reassign_species_taxonomy(integer(), integer()) :: :ok | {:error, term()}
def reassign_species_taxonomy(species_id, new_genus_id)
```

Wrapped in a transaction. The function handles:
- Deleting the old `species_taxonomy` row for type "genus"
- Inserting the new one
- If the species is a gall and the new genus is an Unknown placeholder, setting
  `undescribed=true` on `gall_traits`

### Component

A reusable `reclassify_modal` in `form_components.ex`:
- Accepts current taxonomy as assigns
- Contains genus typeahead + conditional family dropdown
- Emits a `"reclassify"` event with the selected `genus_id`
- Each form's LiveView handles the event by calling `reassign_species_taxonomy/2`

---

## 2. Gall Creation Taxonomy Flow

When creating a new gall, after the admin enters the species name, the system extracts the
first word as the genus and runs through this decision tree:

### Case 1: Genus exists in taxonomy

Auto-populate family. Done. (Already works today.)

### Case 2: Genus is "Unknown"

Show a family picker dropdown:
- All gall families listed
- "Unknown" as an option (for fully unknown)
- Selecting a family links to `Unknown (Family)`, creating the Unknown genus placeholder
  if needed (via existing `find_or_create_unknown_genus/1`)
- Selecting "Unknown" links to `Unknown (Unknown)`

### Case 3: Genus doesn't exist (new real genus)

Show:
- **Family typeahead** — search existing families
- **"Create new family" option** — if the family doesn't exist either, admin can type a
  new family name. The system creates the family, auto-creates its `Unknown` genus
  placeholder, then creates the new genus under it.

### Guard rail

Admins can never manually create anything named "Unknown". The system owns all Unknown
entries. If someone types "Unknown" as a genus name, the flow routes to Case 2 (family
picker), not Case 3 (new genus creation).

---

## 3. Enforced Undescribed Invariant

The `undescribed` boolean on `gall_traits` must respect taxonomy state.

### Rule 1: Unknown Genus Floor

- **Unknown genus -> `undescribed` is locked true.** The UI disables the checkbox and
  shows a brief explanation ("Undescribed is required for species with unknown genus").
- **Reclassify from real genus -> Unknown:** forces undescribed to true, locks checkbox.
- **Creation:** if the selected genus is any `Unknown (*)` flavor, `undescribed` is
  auto-set true and locked.

### Rule 2: Described Galls Require Sources

- **Real genus + `undescribed=false` -> must have at least one source.** A formally
  described species must have a citation.
- **Real genus + no sources -> `undescribed` toggle is locked true.** The UI disables
  the checkbox and shows: "A source is required to mark a species as described."
- **Reclassify from Unknown -> real genus:** the checkbox stays locked at true until
  the admin attaches a source. Only then can they toggle undescribed to false.
- **Real genus + has sources -> admin controls `undescribed`.** Can be either true or
  false. True is valid for species placed in a genus but not yet formally described
  (e.g., "Contarinia h-virginiana-circular-leaf-blister").

### Scope: Galls Only

These invariants apply **only to galls**. Hosts (plants) do not have an `undescribed`
flag, and Unknown genera/families are not used with hosts.

### Enforcement layers

**Unknown genus floor** — enforced at the **context level**. The `Galls` context
validates on save: if the species is linked to an Unknown genus, `undescribed` must
be true. This prevents bypass via direct DB operations or future API endpoints.

**Source requirement** — enforced as a **UI warning** for now. The toggle is locked
in the UI, but no context-level validation blocks saves. Many existing galls will
fail this check and the fixes are non-trivial (finding the correct source for each).
This can be promoted to a context-level validation later once the backlog is cleared.

---

## Data Cleanup

Investigation found 21 data inconsistencies:

- **2 Unknown-genus galls with undescribed=false** (species 1115, 3117) — already fixed
  in production by Jeff
- **19 real-genus galls with undescribed naming pattern but undescribed=false** — tracked
  in bead `gallformers-nvve` with fix query

Additionally, the new source requirement will flag more galls:

- **Described galls with no sources** — any gall with `undescribed=false` and zero
  entries in `species_source` should be flipped to `undescribed=true`. This is a bulk
  update that can run before the UI enforcement ships, preventing the new lock from
  surprising admins with galls they can't edit without first attaching sources.

These inconsistencies motivated the enforced invariants above.

---

## Implementation Notes

- The reclassify modal reuses the existing genus typeahead component pattern
- `reassign_species_taxonomy/2` is a simple junction table swap — low risk
- The undescribed invariant adds a validation check, not a migration
- Creation flow changes are refinements to existing `resolve_taxonomy_for_gall/2` logic
- No database schema changes required
