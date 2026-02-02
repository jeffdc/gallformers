# V2 Schema Refactor - Implementation Plan

> **For Claude:** DO NOT USE THIS DOCUMENT. If for some reason you find yourself working on or from this doc STOP and let the user know. This is solely for historical reference at this point.

**Goal:** Refactor the Elixir/Phoenix application code to work with the V2 database schema that eliminates technical debt and simplifies the data model.

**Architecture:** This is a data-layer refactor. We'll update Ecto schemas first, then context modules, then LiveViews/controllers. The database has already been migrated via SQL script (migrate_v1_to_v2.sql). We're updating ~15 schemas, ~8 context modules, and associated tests.

**Tech Stack:** Phoenix 1.8, Ecto, SQLite, LiveView

**Prerequisites:**
- ✅ V2 schema design complete (docs/plans/2026-02-01-v2-schema-design.md)
- ✅ Migration script written (priv/repo/migrate_v1_to_v2.sql)
- ✅ Test database migrated (priv/test.sqlite)
- ⏭️ Code needs updating to match new schema

**Migration Strategy:**
1. Update schemas to match new DB structure
2. Update context modules (queries, business logic)
3. Update LiveViews and controllers
4. Update tests
5. Test against migrated database

---

## Phase 1: Core Schema Updates (Gall Architecture)

This phase handles the biggest structural change: `species` + `gallspecies` + `gall` → `species` + `gall_traits`.

### Task 1.1: Create GallTraits Schema (New)

**Files:**
- Create: `lib/gallformers/species/gall_traits.ex`
- Reference: Design doc Section 2.2

**Step 1: Write the GallTraits schema**

Create the new schema matching the V2 structure:

```elixir
defmodule Gallformers.Species.GallTraits do
  @moduledoc """
  Ecto schema for the gall_traits table (1:1 extension of species).

  This table stores gall-specific attributes for species with taxoncode='gall'.
  Uses Class Table Inheritance pattern: species_id is both PK and FK.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour Gallformers.SchemaFields

  @required_fields [:species_id]
  @optional_fields [:color_id, :walls_id, :cells_id, :detachable, :undescribed]

  @type t :: %__MODULE__{
          species_id: integer(),
          color_id: integer() | nil,
          walls_id: integer() | nil,
          cells_id: integer() | nil,
          detachable: String.t() | nil,
          undescribed: boolean()
        }

  @primary_key {:species_id, :integer, autogenerate: false}
  @derive {Phoenix.Param, key: :species_id}

  schema "gall_traits" do
    # Single-value trait FKs
    belongs_to :color, Gallformers.FilterFields.Color, define_field: false
    belongs_to :walls, Gallformers.FilterFields.Walls, define_field: false
    belongs_to :cells, Gallformers.FilterFields.Cells, define_field: false

    # Gall-specific columns
    field :detachable, :string
    field :undescribed, :boolean, default: false

    # 1:1 relationship to species
    belongs_to :species, Gallformers.Species.Species,
      foreign_key: :species_id,
      references: :id,
      define_field: false

    # Multi-value traits (junction tables)
    many_to_many :shapes, Gallformers.FilterFields.Shape,
      join_through: "gall_shape",
      join_keys: [species_id: :species_id, shape_id: :id]

    many_to_many :textures, Gallformers.FilterFields.Texture,
      join_through: "gall_texture",
      join_keys: [species_id: :species_id, texture_id: :id]

    many_to_many :alignments, Gallformers.FilterFields.Alignment,
      join_through: "gall_alignment",
      join_keys: [species_id: :species_id, alignment_id: :id]

    many_to_many :plant_parts, Gallformers.FilterFields.PlantPart,
      join_through: "gall_plant_part",
      join_keys: [species_id: :species_id, plant_part_id: :id]

    many_to_many :forms, Gallformers.FilterFields.Form,
      join_through: "gall_form",
      join_keys: [species_id: :species_id, form_id: :id]

    many_to_many :seasons, Gallformers.FilterFields.Season,
      join_through: "gall_season",
      join_keys: [species_id: :species_id, season_id: :id]
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @impl Gallformers.SchemaFields
  def required_associations, do: []

  @doc """
  Creates a changeset for gall traits.

  Valid detachable values: "unknown", "integral", "detachable", "both"
  """
  def changeset(gall_traits, attrs) do
    gall_traits
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:detachable, ~w(unknown integral detachable both),
      message: "must be one of: unknown, integral, detachable, both"
    )
    |> foreign_key_constraint(:species_id)
    |> foreign_key_constraint(:color_id)
    |> foreign_key_constraint(:walls_id)
    |> foreign_key_constraint(:cells_id)
  end
end
```

**Step 2: Commit**

```bash
git add lib/gallformers/species/gall_traits.ex
git commit -m "Add GallTraits schema for V2 gall architecture"
```

---

### Task 1.2: Update Species Schema for GallTraits

**Files:**
- Modify: `lib/gallformers/species/species.ex`
- Remove association: `gall_species`

**Step 1: Update Species schema associations**

Replace the `gall_species` association with `gall_traits`:

```elixir
# In lib/gallformers/species/species.ex

# REMOVE this line:
has_many :gall_species, Gallformers.Species.GallSpecies

# ADD this line (around line 36):
has_one :gall_traits, Gallformers.Species.GallTraits,
  foreign_key: :species_id

# Update timestamps (add after line 26):
timestamps(type: :utc_datetime)
```

**Step 2: Update changeset to include timestamps**

```elixir
# In changeset/2, update cast to include timestamps
def changeset(species, attrs) do
  species
  |> cast(attrs, [:name, :taxoncode, :datacomplete, :abundance_id])
  |> validate_required(@required_fields)
  |> validate_length(:name, min: 1, max: 500)
  |> validate_inclusion(:taxoncode, taxoncodes())
  |> unique_constraint(:name)
end

# Add this helper after changeset/2:
@doc """
Creates a changeset for a gall species, including gall_traits.
"""
def gall_changeset(species, attrs) do
  species
  |> changeset(attrs)
  |> cast_assoc(:gall_traits, with: &Gallformers.Species.GallTraits.changeset/2)
end
```

**Step 3: Commit**

```bash
git add lib/gallformers/species/species.ex
git commit -m "Update Species schema to use gall_traits instead of gall_species"
```

---

### Task 1.3: Rename FilterFields.Location to FilterFields.PlantPart

**Files:**
- Rename: `lib/gallformers/filter_fields/location.ex` → `lib/gallformers/filter_fields/plant_part.ex`
- Modify: `lib/gallformers/filter_fields.ex` (context module)

**Step 1: Rename and update Location schema**

```bash
git mv lib/gallformers/filter_fields/location.ex lib/gallformers/filter_fields/plant_part.ex
```

Update the content:

```elixir
defmodule Gallformers.FilterFields.PlantPart do
  @moduledoc """
  Ecto schema for the plant_part table.

  Represents where on the plant a gall forms (leaf, stem, bud, etc.).
  Previously called "location" but renamed to avoid confusion with geographic places.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          part: String.t() | nil,
          description: String.t() | nil
        }

  schema "plant_part" do
    field :part, :string
    field :description, :string
  end

  @doc """
  Creates a changeset for a plant part.
  """
  def changeset(plant_part, attrs) do
    plant_part
    |> cast(attrs, [:part, :description])
    |> validate_required([:part])
    |> unique_constraint(:part)
  end
end
```

**Step 2: Update FilterFields context module**

```elixir
# In lib/gallformers/filter_fields.ex

# REPLACE:
alias Gallformers.FilterFields.Location

# WITH:
alias Gallformers.FilterFields.PlantPart

# REPLACE all list_locations/0 with list_plant_parts/0
# REPLACE all function references to Location with PlantPart
```

**Step 3: Commit**

```bash
git add lib/gallformers/filter_fields/plant_part.ex lib/gallformers/filter_fields.ex
git commit -m "Rename Location to PlantPart to avoid confusion with Places"
```

---

### Task 1.4: Update Hosts Schema

**Files:**
- Modify: `lib/gallformers/hosts/host.ex`

**Step 1: Rename table to gallhost**

```elixir
# In lib/gallformers/hosts/host.ex

# UPDATE schema declaration (around line 23):
schema "gallhost" do
  # ... rest unchanged

# ADD timestamps (after foreign keys):
timestamps(type: :utc_datetime)
```

**Step 2: Update changeset**

No changes needed to changeset logic, just ensure timestamps are handled.

**Step 3: Commit**

```bash
git add lib/gallformers/hosts/host.ex
git commit -m "Update Host schema to use 'gallhost' table and add timestamps"
```

---

### Task 1.5: Update Places Schema for Range Split

**Files:**
- Modify: `lib/gallformers/species/species.ex`
- Modify: `lib/gallformers/places/place.ex` (if it references speciesplace)

**Step 1: Update Species schema to split speciesplace**

```elixir
# In lib/gallformers/species/species.ex

# REPLACE:
many_to_many :places, Gallformers.Places.Place,
  join_through: "speciesplace",
  join_keys: [species_id: :id, place_id: :id]

# WITH:
# Host range (where host plants exist)
many_to_many :host_ranges, Gallformers.Places.Place,
  join_through: "host_range",
  join_keys: [species_id: :id, place_id: :id]

# Gall range exclusions (places excluded from gall's range)
many_to_many :gall_range_exclusions, Gallformers.Places.Place,
  join_through: "gall_range_exclusion",
  join_keys: [species_id: :id, place_id: :id]
```

**Step 2: Add helper methods for semantic access**

```elixir
# Add these helpers after the schema definition:

@doc """
Returns the appropriate range association based on taxoncode.
For plants: host_ranges
For galls: gall_range_exclusions (places to EXCLUDE)
"""
def range_association(%__MODULE__{taxoncode: "plant"}), do: :host_ranges
def range_association(%__MODULE__{taxoncode: "gall"}), do: :gall_range_exclusions
def range_association(_), do: nil
```

**Step 3: Commit**

```bash
git add lib/gallformers/species/species.ex
git commit -m "Split speciesplace into host_range and gall_range_exclusion"
```

---

### Task 1.6: Update Taxonomy Schema for Placeholders

**Files:**
- Modify: `lib/gallformers/taxonomy/taxonomy.ex`

**Step 1: Add is_placeholder field**

```elixir
# In lib/gallformers/taxonomy/taxonomy.ex schema block:

schema "taxonomy" do
  field :name, :string
  field :type, :string
  field :description, :string
  field :is_placeholder, :boolean, default: false  # ADD THIS

  belongs_to :parent, Gallformers.Taxonomy.Taxonomy, foreign_key: :parent_id

  # ... rest unchanged

  timestamps(type: :utc_datetime)  # ADD THIS
end
```

**Step 2: Update changeset**

```elixir
@optional_fields [:description, :parent_id, :is_placeholder]

def changeset(taxonomy, attrs) do
  taxonomy
  |> cast(attrs, @required_fields ++ @optional_fields)
  |> validate_required(@required_fields)
  |> validate_inclusion(:type, types())
  |> unique_constraint([:name, :parent_id],
    name: :idx_taxonomy_name_parent,
    message: "already exists for this parent"
  )
  |> foreign_key_constraint(:parent_id)
end
```

**Step 3: Add helper for generating placeholder names**

```elixir
@doc """
Generates a display name for a placeholder "Unknown" taxonomy entry.

Examples:
  - Unknown family → "Unknown"
  - Unknown genus in Cynipidae → "Unknown (Cynipidae)"
"""
def display_name(%__MODULE__{is_placeholder: true, parent: %{name: parent_name}}) do
  "Unknown (#{parent_name})"
end
def display_name(%__MODULE__{is_placeholder: true}) do
  "Unknown"
end
def display_name(%__MODULE__{name: name}) do
  name
end
```

**Step 4: Commit**

```bash
git add lib/gallformers/taxonomy/taxonomy.ex
git commit -m "Add is_placeholder field to Taxonomy for Unknown genera"
```

---

### Task 1.7: Update Alias Schema for Junction Table Rename

**Files:**
- Modify: `lib/gallformers/species/alias.ex`
- Modify: `lib/gallformers/taxonomy/taxonomy.ex`

**Step 1: Update Species aliases association**

```elixir
# In lib/gallformers/species/species.ex

# UPDATE:
many_to_many :aliases, Gallformers.Species.Alias,
  join_through: "alias_species",  # Changed from "aliasspecies"
  join_keys: [species_id: :id, alias_id: :id]
```

**Step 2: Update Taxonomy aliases association**

```elixir
# In lib/gallformers/taxonomy/taxonomy.ex

# UPDATE (if exists):
many_to_many :aliases, Gallformers.Species.Alias,
  join_through: "taxonomy_alias",  # Changed from "taxonomyalias"
  join_keys: [taxonomy_id: :id, alias_id: :id]
```

**Step 3: Add timestamps to Alias schema**

```elixir
# In lib/gallformers/species/alias.ex

schema "alias" do
  field :name, :string
  field :description, :string
  field :type, :string

  timestamps(type: :utc_datetime)  # ADD THIS
end
```

**Step 4: Commit**

```bash
git add lib/gallformers/species/alias.ex lib/gallformers/taxonomy/taxonomy.ex lib/gallformers/species/species.ex
git commit -m "Rename junction tables to snake_case and add timestamps to Alias"
```

---

### Task 1.8: Update Image Schema (Remove default column)

**Files:**
- Modify: `lib/gallformers/species/image.ex`

**Step 1: Remove default field**

```elixir
# In lib/gallformers/species/image.ex

schema "image" do
  # REMOVE this field:
  # field :default, :boolean, default: false

  # Keep these:
  field :path, :string
  field :source_id, :integer
  field :attribution, :string
  field :license, :string
  field :licenselink, :string
  field :sort_order, :integer

  belongs_to :species, Gallformers.Species.Species
  belongs_to :source, Gallformers.Sources.Source
end
```

**Step 2: Update changeset to remove default**

```elixir
def changeset(image, attrs) do
  image
  |> cast(attrs, [:path, :source_id, :attribution, :license, :licenselink, :sort_order])
  |> validate_required([:path, :sort_order])
  # Remove any validation on :default
end
```

**Step 3: Add helper for determining default image**

```elixir
@doc """
Returns true if this is the default image (sort_order = 1).
"""
def default?(%__MODULE__{sort_order: 1}), do: true
def default?(_), do: false
```

**Step 4: Commit**

```bash
git add lib/gallformers/species/image.ex
git commit -m "Remove default field from Image (use sort_order instead)"
```

---

### Task 1.9: Update Source Schema (Add timestamps)

**Files:**
- Modify: `lib/gallformers/sources/source.ex`

**Step 1: Add timestamps**

```elixir
# In lib/gallformers/sources/source.ex

schema "source" do
  field :title, :string
  field :author, :string
  field :pubyear, :string
  field :link, :string
  field :citation, :string
  field :license, :string
  field :datacomplete, :boolean, default: false
  field :licenselink, :string

  timestamps(type: :utc_datetime)  # ADD THIS
end
```

**Step 2: Commit**

```bash
git add lib/gallformers/sources/source.ex
git commit -m "Add timestamps to Source schema"
```

---

### Task 1.10: Delete Obsolete Schemas

**Files:**
- Delete: `lib/gallformers/species/gall_species.ex`
- Delete: `lib/gallformers/species/gall.ex`
- Delete: `lib/gallformers/species/taxon_type.ex`

**Step 1: Remove files**

```bash
git rm lib/gallformers/species/gall_species.ex
git rm lib/gallformers/species/gall.ex
git rm lib/gallformers/species/taxon_type.ex
```

**Step 2: Commit**

```bash
git commit -m "Remove obsolete schemas: GallSpecies, Gall, TaxonType"
```

---

## Phase 2: Context Module Updates

Now update the business logic layer to work with the new schemas.

### Task 2.1: Update Species Context for GallTraits

**Files:**
- Modify: `lib/gallformers/species.ex`

**Step 1: Update preload paths**

Find all places that preload gall data and update:

```elixir
# REPLACE patterns like:
Repo.preload(species, [gall_species: [gall: [:colors, :shapes, ...]]])

# WITH:
Repo.preload(species, [gall_traits: [:color, :walls, :cells, :shapes, :textures, ...]])
```

**Step 2: Update gall queries**

```elixir
# REPLACE joins like:
|> join(:inner, [s], gs in assoc(s, :gall_species))
|> join(:inner, [s, gs], g in assoc(gs, :gall))

# WITH:
|> join(:inner, [s], gt in assoc(s, :gall_traits))
```

**Step 3: Update gall creation logic**

```elixir
# REPLACE:
def create_gall(species_id, attrs) do
  %GallSpecies{species_id: species_id}
  |> GallSpecies.changeset(%{gall_id: gall_id})
  |> Repo.insert()
end

# WITH:
def create_gall_traits(species_id, attrs) do
  %GallTraits{species_id: species_id}
  |> GallTraits.changeset(attrs)
  |> Repo.insert()
end
```

**Step 4: Update detachable handling**

```elixir
# REPLACE integer detachable with string:
# 0 → "unknown"
# 1 → "integral"
# 2 → "detachable"
# 3 → "both"

def detachable_to_string(0), do: "unknown"
def detachable_to_string(1), do: "integral"
def detachable_to_string(2), do: "detachable"
def detachable_to_string(3), do: "both"
def detachable_to_string(_), do: "unknown"

def detachable_to_integer("unknown"), do: 0
def detachable_to_integer("integral"), do: 1
def detachable_to_integer("detachable"), do: 2
def detachable_to_integer("both"), do: 3
def detachable_to_integer(_), do: 0
```

**Step 5: Commit**

```bash
git add lib/gallformers/species.ex
git commit -m "Update Species context for GallTraits architecture"
```

---

### Task 2.2: Update Hosts Context

**Files:**
- Modify: `lib/gallformers/hosts.ex`

**Step 1: Update table references**

Search for "host" table name and ensure all queries use "gallhost":

```elixir
# Should already be handled by schema change, but verify queries
# No explicit FROM "host" should exist
```

**Step 2: Update any raw SQL**

```elixir
# If any fragments reference "host" table, update to "gallhost"
```

**Step 3: Commit**

```bash
git add lib/gallformers/hosts.ex
git commit -m "Update Hosts context for gallhost table rename"
```

---

### Task 2.3: Update Places Context for Range Split

**Files:**
- Modify: `lib/gallformers/places.ex` (if it handles speciesplace logic)

**Step 1: Update range queries**

```elixir
# REPLACE:
def get_species_places(species_id) do
  from sp in "speciesplace",
    where: sp.species_id == ^species_id
end

# WITH:
def get_host_ranges(species_id) do
  from hr in "host_range",
    where: hr.species_id == ^species_id
end

def get_gall_range_exclusions(species_id) do
  from gre in "gall_range_exclusion",
    where: gre.species_id == ^species_id
end
```

**Step 2: Add semantic wrapper**

```elixir
@doc """
Gets the range for a species based on its taxoncode.
For plants: returns places where the host exists
For galls: returns places EXCLUDED from the gall's range
"""
def get_species_range(%Species{taxoncode: "plant", id: id}) do
  get_host_ranges(id)
end
def get_species_range(%Species{taxoncode: "gall", id: id}) do
  get_gall_range_exclusions(id)
end
```

**Step 3: Commit**

```bash
git add lib/gallformers/places.ex
git commit -m "Update Places context for host_range/gall_range_exclusion split"
```

---

### Task 2.4: Update Taxonomy Context for Placeholders

**Files:**
- Modify: `lib/gallformers/taxonomy.ex`

**Step 1: Add query helpers**

```elixir
@doc """
Lists all non-placeholder taxonomies.
"""
def list_taxonomies do
  from(t in Taxonomy, where: t.is_placeholder == false)
  |> Repo.all()
end

@doc """
Gets the "Unknown" placeholder for a given parent.
Returns nil if not found.
"""
def get_unknown_placeholder(parent_id) do
  from(t in Taxonomy,
    where: t.is_placeholder == true and t.parent_id == ^parent_id
  )
  |> Repo.one()
end

@doc """
Gets or creates an "Unknown" placeholder genus for a family.
"""
def get_or_create_unknown_genus(family_id) do
  case get_unknown_placeholder(family_id) do
    nil ->
      %Taxonomy{}
      |> Taxonomy.changeset(%{
        name: "Unknown",
        type: "genus",
        parent_id: family_id,
        is_placeholder: true
      })
      |> Repo.insert()

    taxonomy ->
      {:ok, taxonomy}
  end
end
```

**Step 2: Update display logic**

```elixir
@doc """
Returns the display name for a taxonomy, handling placeholders.
"""
def display_name(taxonomy) do
  Taxonomy.display_name(Repo.preload(taxonomy, :parent))
end
```

**Step 3: Commit**

```bash
git add lib/gallformers/taxonomy.ex
git commit -m "Add placeholder support to Taxonomy context"
```

---

### Task 2.5: Update FilterFields Context for PlantPart

**Files:**
- Modify: `lib/gallformers/filter_fields.ex`

**Step 1: Rename all location references to plant_part**

```elixir
# REPLACE:
def list_locations do
  Repo.all(Location)
end

# WITH:
def list_plant_parts do
  Repo.all(PlantPart)
end

# Similarly update:
# - get_location/1 → get_plant_part/1
# - create_location/1 → create_plant_part/1
# - update_location/2 → update_plant_part/2
# - delete_location/1 → delete_plant_part/1
```

**Step 2: Commit**

```bash
git add lib/gallformers/filter_fields.ex
git commit -m "Rename location functions to plant_part in FilterFields context"
```

---

## Phase 3: Update Queries and Business Logic

### Task 3.1: Update ID Tool for New Structure

**Files:**
- Modify: `lib/gallformers/id_tool.ex`

**Step 1: Update gall trait queries**

```elixir
# Find queries building filter WHERE clauses
# REPLACE joins to gall table with joins to gall_traits

# BEFORE:
|> join(:inner, [s], gs in assoc(s, :gall_species))
|> join(:inner, [s, gs], g in assoc(gs, :gall))
|> join(:left, [s, gs, g], gc in assoc(g, :colors))

# AFTER:
|> join(:inner, [s], gt in assoc(s, :gall_traits))
|> join(:left, [s, gt], c in assoc(gt, :color))
```

**Step 2: Update detachable filter**

```elixir
# REPLACE integer comparison:
|> where([..., g], g.detachable == ^detachable_int)

# WITH string comparison:
|> where([..., gt], gt.detachable == ^detachable_string)
```

**Step 3: Update location references**

```elixir
# REPLACE:
|> join(:left, [...], gl in assoc(..., :locations))

# WITH:
|> join(:left, [...], gpp in assoc(..., :plant_parts))
```

**Step 4: Commit**

```bash
git add lib/gallformers/id_tool.ex
git commit -m "Update ID tool queries for GallTraits architecture"
```

---

### Task 3.2: Update Explore Context

**Files:**
- Modify: `lib/gallformers/explore.ex`

**Step 1: Update gall detail queries**

Similar to ID tool - replace gall_species/gall joins with gall_traits.

**Step 2: Commit**

```bash
git add lib/gallformers/explore.ex
git commit -m "Update Explore queries for GallTraits architecture"
```

---

### Task 3.3: Update Search Queries

**Files:**
- Modify: `lib/gallformers/search.ex`

**Step 1: Update gall searches**

Replace gall table references with gall_traits.

**Step 2: Commit**

```bash
git add lib/gallformers/search.ex
git commit -m "Update Search queries for GallTraits architecture"
```

---

## Phase 4: LiveView and Controller Updates

### Task 4.1: Update Admin Gall Form

**Files:**
- Modify: `lib/gallformers_web/live/admin/gall_live/form.ex` (or equivalent)

**Step 1: Update form structure**

```elixir
# Change form to work with Species + GallTraits together
# Use Species.gall_changeset/2 which handles the association

def mount(_params, _session, socket) do
  changeset =
    %Species{taxoncode: "gall", gall_traits: %GallTraits{}}
    |> Species.gall_changeset(%{})

  {:ok, assign(socket, changeset: changeset)}
end
```

**Step 2: Update form fields**

```heex
<!-- Replace detachable dropdown with string values -->
<.input
  field={@form[:gall_traits][:detachable]}
  type="select"
  options={[
    {"Unknown", "unknown"},
    {"Integral", "integral"},
    {"Detachable", "detachable"},
    {"Both", "both"}
  ]}
/>

<!-- Replace color multi-select with single-select -->
<.input
  field={@form[:gall_traits][:color_id]}
  type="select"
  options={@colors}
/>
```

**Step 3: Update save logic**

```elixir
def handle_event("save", %{"species" => params}, socket) do
  case Species.create_gall(params) do
    {:ok, species} ->
      {:noreply, push_navigate(socket, to: ~p"/admin/species/#{species}")}
    {:error, changeset} ->
      {:noreply, assign(socket, changeset: changeset)}
  end
end
```

**Step 4: Commit**

```bash
git add lib/gallformers_web/live/admin/gall_live/form.ex
git commit -m "Update admin gall form for GallTraits structure"
```

---

### Task 4.2: Update Gall Detail Page

**Files:**
- Modify: `lib/gallformers_web/live/gall_live/show.ex` (or equivalent)

**Step 1: Update data loading**

```elixir
def mount(%{"id" => id}, _session, socket) do
  species =
    Species.get_species!(id)
    |> Repo.preload([
      gall_traits: [
        :color, :walls, :cells,
        :shapes, :textures, :alignments, :plant_parts, :forms, :seasons
      ],
      :images,
      :taxonomies,
      host_relations: [:host_species]
    ])

  {:ok, assign(socket, species: species)}
end
```

**Step 2: Update template**

```heex
<!-- Access gall traits -->
<%= if @species.gall_traits do %>
  <div>
    <p>Detachable: <%= @species.gall_traits.detachable %></p>

    <%= if @species.gall_traits.color do %>
      <p>Color: <%= @species.gall_traits.color.color %></p>
    <% end %>

    <!-- Multi-value traits -->
    <%= for shape <- @species.gall_traits.shapes do %>
      <span class="badge"><%= shape.shape %></span>
    <% end %>
  </div>
<% end %>
```

**Step 3: Commit**

```bash
git add lib/gallformers_web/live/gall_live/show.ex
git commit -m "Update gall detail page for GallTraits structure"
```

---

### Task 4.3: Update Host Detail Page

**Files:**
- Modify: `lib/gallformers_web/live/host_live/show.ex` (or equivalent)

**Step 1: Update range display**

```heex
<!-- Use semantic range helpers -->
<%= if @species.taxoncode == "plant" do %>
  <h3>Found in:</h3>
  <%= for place <- @species.host_ranges do %>
    <span><%= place.name %></span>
  <% end %>
<% end %>
```

**Step 2: Commit**

```bash
git add lib/gallformers_web/live/host_live/show.ex
git commit -m "Update host page to use host_ranges"
```

---

## Phase 5: Test Updates

### Task 5.1: Update Schema Tests

**Files:**
- Modify: `test/gallformers/species_test.exs`
- Create: `test/gallformers/species/gall_traits_test.exs`

**Step 1: Write GallTraits schema tests**

```elixir
defmodule Gallformers.Species.GallTraitsTest do
  use Gallformers.DataCase

  alias Gallformers.Species.{Species, GallTraits}

  describe "gall_traits changeset" do
    test "valid attributes" do
      species = insert(:species, taxoncode: "gall")

      attrs = %{
        species_id: species.id,
        detachable: "integral",
        undescribed: false
      }

      changeset = GallTraits.changeset(%GallTraits{}, attrs)
      assert changeset.valid?
    end

    test "requires species_id" do
      changeset = GallTraits.changeset(%GallTraits{}, %{})
      assert "can't be blank" in errors_on(changeset).species_id
    end

    test "validates detachable values" do
      species = insert(:species, taxoncode: "gall")

      attrs = %{species_id: species.id, detachable: "invalid"}
      changeset = GallTraits.changeset(%GallTraits{}, attrs)

      assert "must be one of: unknown, integral, detachable, both" in
        errors_on(changeset).detachable
    end
  end
end
```

**Step 2: Run tests**

```bash
mix test test/gallformers/species/gall_traits_test.exs
```

Expected: All new tests pass

**Step 3: Update Species tests**

```elixir
# In test/gallformers/species_test.exs

# Update fixtures to use gall_traits
def gall_fixture(attrs \\ %{}) do
  species = species_fixture(Map.merge(attrs, %{taxoncode: "gall"}))

  {:ok, traits} =
    %GallTraits{species_id: species.id}
    |> GallTraits.changeset(%{detachable: "integral"})
    |> Repo.insert()

  %{species | gall_traits: traits}
end
```

**Step 4: Run tests**

```bash
mix test test/gallformers/species_test.exs
```

**Step 5: Commit**

```bash
git add test/gallformers/species_test.exs test/gallformers/species/gall_traits_test.exs
git commit -m "Add tests for GallTraits schema"
```

---

### Task 5.2: Update Context Tests

**Files:**
- Modify: `test/gallformers/species_test.exs` (context tests)

**Step 1: Update gall creation tests**

```elixir
test "create_gall/1 creates gall with traits" do
  attrs = %{
    name: "Test Gall",
    taxoncode: "gall",
    gall_traits: %{
      detachable: "integral",
      undescribed: false
    }
  }

  assert {:ok, species} = Species.create_gall(attrs)
  assert species.gall_traits.detachable == "integral"
end
```

**Step 2: Run tests**

```bash
mix test test/gallformers/species_test.exs
```

**Step 3: Commit when passing**

```bash
git add test/gallformers/species_test.exs
git commit -m "Update Species context tests for GallTraits"
```

---

### Task 5.3: Update LiveView Tests

**Files:**
- Modify: `test/gallformers_web/live/admin/gall_live_test.exs`

**Step 1: Update test fixtures**

Use the new gall_fixture from Step 5.1.

**Step 2: Update form interaction tests**

```elixir
test "creates gall with traits", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/admin/galls/new")

  form_data = %{
    "species" => %{
      "name" => "New Gall",
      "taxoncode" => "gall",
      "gall_traits" => %{
        "detachable" => "integral",
        "undescribed" => "false"
      }
    }
  }

  view
  |> form("#gall-form", form_data)
  |> render_submit()

  assert_redirect(view, ~p"/admin/species/\#{species_id}")
end
```

**Step 3: Run tests**

```bash
mix test test/gallformers_web/live/admin/gall_live_test.exs
```

**Step 4: Commit when passing**

```bash
git add test/gallformers_web/live/admin/gall_live_test.exs
git commit -m "Update admin gall LiveView tests for GallTraits"
```

---

### Task 5.4: Update E2E Tests

**Files:**
- Modify: `test/e2e/admin/gall_admin_test.exs`

**Step 1: Update E2E gall creation**

```elixir
test "admin can create a gall", %{session: session} do
  session
  |> visit("/admin/galls/new")
  |> fill_in(Query.text_field("Name"), with: "Test Gall")
  |> select(Query.select("Detachable"), option: "Integral")
  |> click(Query.button("Save"))
  |> assert_has(Query.text("Test Gall"))
end
```

**Step 2: Run E2E tests**

```bash
make e2e-admin
```

**Step 3: Commit when passing**

```bash
git add test/e2e/admin/gall_admin_test.exs
git commit -m "Update E2E tests for gall creation with GallTraits"
```

---

## Phase 6: Data Migration & Cleanup

### Task 6.1: Update Test Seeds

**Files:**
- Modify: `priv/repo/test_seeds.sql`

**Step 1: Update seed data for new structure**

Ensure test_seeds.sql uses the V2 schema (gall_traits, plant_part, etc.).

**Step 2: Rebuild test database**

```bash
make test-db
```

Expected: Database rebuilds without errors

**Step 3: Run full test suite**

```bash
mix test
```

Expected: All tests pass

**Step 4: Commit**

```bash
git add priv/repo/test_seeds.sql
git commit -m "Update test seeds for V2 schema"
```

---

### Task 6.2: Update structure.sql

**Files:**
- Replace: `priv/repo/structure.sql` with `priv/repo/structure_target.sql`

**Step 1: Replace structure file**

```bash
cp priv/repo/structure_target.sql priv/repo/structure.sql
```

**Step 2: Commit**

```bash
git add priv/repo/structure.sql
git commit -m "Update structure.sql to V2 schema (final state)"
```

---

### Task 6.3: Run Full Verification

**Files:**
- None (verification step)

**Step 1: Rebuild test DB and run all tests**

```bash
make test-db
mix precommit
```

Expected: All checks pass

**Step 2: Run E2E tests**

```bash
make e2e
```

Expected: All E2E tests pass

**Step 3: Manual smoke test**

```bash
mix phx.server
```

Visit key pages:
- http://localhost:4000 (home)
- http://localhost:4000/id (ID tool)
- http://localhost:4000/admin/galls (admin galls)

Expected: No errors, pages load correctly

---

## Phase 7: Documentation

### Task 7.1: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update schema documentation**

Update the "Key Domain Concepts" section to reflect:
- GallTraits as 1:1 extension
- PlantPart vs Place distinction
- host_range vs gall_range_exclusion semantics

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Update CLAUDE.md for V2 schema architecture"
```

---

### Task 7.2: Write Migration Retrospective

**Files:**
- Create: `docs/retrospectives/2026-02-v2-schema-migration.md`

**Step 1: Document lessons learned**

```markdown
# V2 Schema Migration - Retrospective

**Date:** 2026-02-XX

## What Went Well
- SQL migration script approach worked smoothly
- Class Table Inheritance pattern for galls is much cleaner
- Test-driven approach caught issues early

## What Could Be Better
- [Fill in after completion]

## Metrics
- Lines of code changed: ~XXX files
- Tests updated: ~XXX tests
- Time taken: ~X days
```

**Step 2: Commit**

```bash
git add docs/retrospectives/2026-02-v2-schema-migration.md
git commit -m "Add V2 schema migration retrospective"
```

---

## Success Criteria Checklist

Before considering this complete, verify:

- [ ] All Ecto schemas updated to match V2 structure
- [ ] All context modules updated (queries, associations)
- [ ] All LiveViews and controllers updated
- [ ] All tests passing (unit, integration, E2E)
- [ ] Test database migrated and working
- [ ] `mix precommit` passes cleanly
- [ ] `make e2e` passes cleanly
- [ ] Manual smoke testing complete
- [ ] Documentation updated
- [ ] No references to deleted tables (gall, gallspecies, speciesplace, etc.)

---

## Notes for Implementer

**Key Architecture Changes:**
1. **Gall data**: Was 3 tables (species → gallspecies → gall), now 2 (species → gall_traits)
2. **Detachable**: Was integer (0-3), now string ("unknown", "integral", "detachable", "both")
3. **Single-value traits**: Were junction tables (gall_color), now FK columns (gall_traits.color_id)
4. **Location**: Renamed to plant_part to avoid confusion with geographic places
5. **Range**: speciesplace split into host_range (inclusions) and gall_range_exclusion (exclusions)

**Common Pitfalls:**
- Don't forget to update preload paths in queries
- detachable is now a string, not an integer
- Junction tables are now snake_case (gall_shape not gallshape)
- species_id in gall_traits is both PK and FK (1:1 relationship)
- Remember to add timestamps to all modified schemas

**Testing Strategy:**
- Test each schema in isolation first
- Then test context modules
- Then LiveViews
- Finally E2E tests
- Keep the test DB rebuilt frequently

**Commit Discipline:**
- Small, focused commits per task
- Tests passing before each commit
- Clear commit messages following conventions

---

## Estimated Timeline

- **Phase 1** (Schemas): 2-3 hours
- **Phase 2** (Contexts): 2-3 hours
- **Phase 3** (Queries): 1-2 hours
- **Phase 4** (LiveViews): 2-3 hours
- **Phase 5** (Tests): 3-4 hours
- **Phase 6** (Migration): 1 hour
- **Phase 7** (Docs): 1 hour

**Total: ~15-20 hours of focused work**

Split across multiple sessions with review checkpoints between phases.
