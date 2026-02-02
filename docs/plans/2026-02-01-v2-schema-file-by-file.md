# V2 Schema Refactor - File-by-File Migration Plan

**Goal:** Systematically migrate every source file from V1 to V2 schema, working from data layer → business logic → UI layer. Eery file must be reviewed.

**Strategy:** Go through every file one-by-one with the context of what changed in our heads, checking for any impact. Start at the lowest level (schemas) and work outward to the UI. 

---

## Migration Status

**Review Approach:**
- **We will review EVERY file systematically**, starting from Layer 1
- For each file, we'll check together:
  - What changes were made (if any)
  - Whether additional changes are needed
  - Whether anything was missed
  - Whether the changes are correct
- Even if a file was "already updated", we review it to verify and catch edge cases
- Keep track of what files we have reviewed. Since we are having to restart this after a context collapse of previous session, first enumerate all of the files that we have to still check, keep them in a list, and update each file's status as we complete it. At the end of each batch, update this document with the list of files completed.
- We have completed Layer 1 and Layer 2 at this point, so focus on the later Layers.
---

## What Changed in V2 (Keep This Context)

### Schema Structure Changes
1. **Gall architecture:** `species → gallspecies → gall` becomes `species → gall_traits` (1:1)
2. **Detachable type:** Integer (0-3) → String ("unknown", "integral", "detachable", "both")
3. **Multi-value traits:** All junction tables renamed to snake_case with `gall_` prefix (including `gall_color`, `gall_walls`, `gall_cells`)
4. **Location:** Renamed to `plant_part` (table + field name)
5. **Range split:** `speciesplace` → `host_range` + `gall_range_exclusion`
6. **Junction tables:** All renamed to snake_case (`aliasspecies` → `alias_species`)
7. **Timestamps:** Added to core tables (species, taxonomy, source, gallhost, alias)
8. **Placeholders:** `taxonomy.is_placeholder` for "Unknown" genera
9. **Deleted tables:** `gallspecies`, `gall`, `taxontype`, `detachable` (lookup), old camelCase junction tables

### Pattern Changes to Look For
```elixir
# OLD PATTERNS → NEW PATTERNS

# 1. GallSpecies association
has_many :gall_species, GallSpecies          → has_one :gall_traits, GallTraits
join: gs in GallSpecies                      → join: gt in assoc(s, :gall_traits)

# 2. Gall association (via GallSpecies)
join: g in assoc(gs, :gall)                  → (removed - traits on gall_traits directly)

# 3. Detachable
field :detachable, :integer                  → field :detachable, :string
g.detachable == 1                            → gt.detachable == "integral"

# 4. Multi-value traits (renamed tables - ALL are many-to-many)
join_through: "gallcolor"                    → join_through: "gall_color"
join_through: "gallwalls"                    → join_through: "gall_walls"
join_through: "gallcells"                    → join_through: "gall_cells"
join_through: "gallshape"                    → join_through: "gall_shape"
join_through: "galllocation"                 → join_through: "gall_plant_part"

# 5. Location → PlantPart
:locations                                   → :plant_parts
Location                                     → PlantPart
location: "leaf"                             → part: "leaf"

# 6. Range (speciesplace split)
many_to_many :places, Place,                 → many_to_many :host_ranges, Place,
  join_through: "speciesplace"                   join_through: "host_range"
                                             + many_to_many :gall_range_exclusions, Place,
                                                 join_through: "gall_range_exclusion"

# 7. Other junction tables
join_through: "aliasspecies"                 → join_through: "alias_species"
join_through: "speciessource"                → join_through: "species_source"
join_through: "speciestaxonomy"              → join_through: "species_taxonomy"

# 8. Foreign key field names (Host table)
gall_species_id                              → (stays same - still references species table)
```

---

## Layer 1: Data Layer (Schemas) - 18 Files

**Context:** Changes were made to these files during Phase 1 & 2:
- Deleted obsolete schemas (GallSpecies, Gall, TaxonType)
- Created GallTraits schema (1:1 with Species)
- Updated Species schema (gall_traits association, range split, timestamps)
- Renamed Location → PlantPart
- Updated all junction table references to snake_case
- Added timestamps to core tables
- Added placeholder support to Taxonomy

**Review Goal:** Go through each schema file below to verify changes are correct, complete, and nothing was missed.

Work through each schema file systematically, checking for old patterns.

### 1.1 Species Schemas (6 files)

#### File: `lib/gallformers/species/gall_species.ex`
**Action:** DELETE (table no longer exists)
**Reason:** Replaced by 1:1 gall_traits relationship
**Check:** Remove all imports/aliases of this module

---

#### File: `lib/gallformers/species/gall.ex`
**Action:** DELETE (table no longer exists)
**Reason:** Replaced by gall_traits
**Check:** Remove all imports/aliases of this module

---

#### File: `lib/gallformers/species/taxon_type.ex`
**Action:** DELETE (table no longer exists)
**Reason:** Replaced with CHECK constraint on species.taxoncode
**Check:** Remove all imports/aliases of this module

---

#### File: `lib/gallformers/species/gall_traits.ex`
**Action:** VERIFY (already created in prep)
**What to check:**
- [ ] Table name: `gall_traits`
- [ ] Primary key: `species_id` (PK + FK pattern)
- [ ] Single-value FKs: `color_id`, `walls_id`, `cells_id`
- [ ] Field: `detachable` as STRING with CHECK constraint
- [ ] Field: `undescribed` as BOOLEAN
- [ ] Multi-value associations use snake_case: `gall_shape`, `gall_texture`, etc.
- [ ] PlantPart association (not Location)

**Changeset validation:**
```elixir
validate_inclusion(:detachable, ~w(unknown integral detachable both))
```

---

#### File: `lib/gallformers/species/species.ex`
**Action:** MAJOR UPDATE
**Changes needed:**

1. **Remove association:**
   ```elixir
   # DELETE
   has_many :gall_species, Gallformers.Species.GallSpecies
   ```

2. **Add association:**
   ```elixir
   # ADD
   has_one :gall_traits, Gallformers.Species.GallTraits, foreign_key: :species_id
   ```

3. **Add timestamps:**
   ```elixir
   # ADD after field definitions
   timestamps(type: :utc_datetime)
   ```

4. **Update range associations:**
   ```elixir
   # REPLACE
   many_to_many :places, Gallformers.Places.Place,
     join_through: "speciesplace",
     join_keys: [species_id: :id, place_id: :id]

   # WITH
   many_to_many :host_ranges, Gallformers.Places.Place,
     join_through: "host_range",
     join_keys: [species_id: :id, place_id: :id]

   many_to_many :gall_range_exclusions, Gallformers.Places.Place,
     join_through: "gall_range_exclusion",
     join_keys: [species_id: :id, place_id: :id]
   ```

5. **Update junction table names:**
   ```elixir
   # UPDATE these join_through values:
   "aliasspecies"       → "alias_species"
   "speciestaxonomy"    → "species_taxonomy"
   ```

6. **Add helper methods:**
   ```elixir
   @doc "Returns the appropriate range association based on taxoncode"
   def range_association(%__MODULE__{taxoncode: "plant"}), do: :host_ranges
   def range_association(%__MODULE__{taxoncode: "gall"}), do: :gall_range_exclusions
   def range_association(_), do: nil

   @doc "Creates a changeset for a gall species with gall_traits"
   def gall_changeset(species, attrs) do
     species
     |> changeset(attrs)
     |> cast_assoc(:gall_traits, with: &Gallformers.Species.GallTraits.changeset/2)
   end
   ```

---

#### File: `lib/gallformers/species/image.ex`
**Action:** UPDATE
**Changes needed:**

1. **Remove field:**
   ```elixir
   # DELETE
   field :default, :boolean, default: false
   ```

2. **Update changeset:**
   ```elixir
   # REMOVE :default from cast/validate_required
   ```

3. **Add helper:**
   ```elixir
   @doc "Returns true if this is the default image (sort_order = 1)"
   def default?(%__MODULE__{sort_order: 1}), do: true
   def default?(_), do: false
   ```

---

#### File: `lib/gallformers/species/alias.ex`
**Action:** UPDATE
**Changes needed:**

1. **Add timestamps:**
   ```elixir
   # ADD after fields
   timestamps(type: :utc_datetime)
   ```

2. **Check junction table references** (updated in Species schema above)

---

#### File: `lib/gallformers/species/species_source.ex`
**Action:** UPDATE
**Changes needed:**

1. **Update table name:**
   ```elixir
   # UPDATE
   schema "species_source" do  # Changed from "speciessource"
   ```

2. **Verify composite PK still works:**
   ```elixir
   @primary_key false
   schema "species_source" do
     belongs_to :species, Species, primary_key: true
     belongs_to :source, Source, primary_key: true
   end
   ```

---

#### File: `lib/gallformers/species/abundance.ex`
**Action:** CHECK ONLY
**What to check:**
- [ ] No gall-specific logic
- [ ] No references to old tables
**Expected:** No changes needed

---

### 1.2 Taxonomy Schemas (1 file)

#### File: `lib/gallformers/taxonomy/taxonomy.ex`
**Action:** UPDATE
**Changes needed:**

1. **Add field:**
   ```elixir
   field :is_placeholder, :boolean, default: false
   ```

2. **Add timestamps:**
   ```elixir
   timestamps(type: :utc_datetime)
   ```

3. **Update changeset:**
   ```elixir
   @optional_fields [:description, :parent_id, :is_placeholder]

   def changeset(taxonomy, attrs) do
     # ... existing
     |> unique_constraint([:name, :parent_id],
       name: :idx_taxonomy_name_parent,
       message: "already exists for this parent"
     )
   end
   ```

4. **Add helper:**
   ```elixir
   @doc "Generates display name for placeholders"
   def display_name(%__MODULE__{is_placeholder: true, parent: %{name: parent_name}}) do
     "Unknown (#{parent_name})"
   end
   def display_name(%__MODULE__{is_placeholder: true}), do: "Unknown"
   def display_name(%__MODULE__{name: name}), do: name
   ```

5. **Update junction table:**
   ```elixir
   # IF exists:
   many_to_many :aliases, Alias,
     join_through: "taxonomy_alias"  # Changed from "taxonomyalias"
   ```

---

### 1.3 Host Schemas (1 file)

#### File: `lib/gallformers/hosts/host.ex`
**Action:** UPDATE
**Changes needed:**

1. **Update table name:**
   ```elixir
   schema "gallhost" do  # Changed from "host"
   ```

2. **Add timestamps:**
   ```elixir
   timestamps(type: :utc_datetime)
   ```

3. **Verify FK field names** (should still be gall_species_id, host_species_id - they point to species table)

---

### 1.4 Source Schemas (1 file)

#### File: `lib/gallformers/sources/source.ex`
**Action:** UPDATE
**Changes needed:**

1. **Add timestamps:**
   ```elixir
   timestamps(type: :utc_datetime)
   ```

---

### 1.5 FilterFields Schemas (10 files)

#### File: `lib/gallformers/filter_fields/plant_part.ex`
**Action:** VERIFY (should already exist)
**What to check:**
- [ ] Table name: `plant_part`
- [ ] Field name: `part` (not `location`)
- [ ] Proper changeset validation

---

#### Files: `lib/gallformers/filter_fields/{alignment,cells,color,form,season,shape,texture,walls}.ex`
**Action:** CHECK ONLY
**What to check:**
- [ ] No references to gall schema
- [ ] Table names correct (used in junction tables elsewhere)
**Expected:** No changes needed

---

### 1.6 Places Schema (1 file)

#### File: `lib/gallformers/places/place.ex`
**Action:** CHECK ONLY
**What to check:**
- [ ] No speciesplace references (that's in Species schema)
**Expected:** No changes needed

---

### 1.7 Other Schemas (Check for gall references)

#### Files to check:
- `lib/gallformers/accounts/user.ex` - CHECK ONLY
- `lib/gallformers/accounts/auth0_user.ex` - CHECK ONLY
- `lib/gallformers/analytics/page_view.ex` - CHECK ONLY
- `lib/gallformers/articles/article.ex` - CHECK ONLY
- `lib/gallformers/glossaries/glossary.ex` - CHECK ONLY

**Expected:** No changes needed (no gall-specific logic)

---

## Layer 2: Business Logic (Contexts) - 9 Files

**Context:** Changes were made to these files during Phase 2:
- Updated Species context (GallTraits queries, detachable conversion, preloads)
- Updated Hosts context (removed GallSpecies joins, updated gall_species_id usage)
- Updated Search context (GallTraits queries)
- Updated IDTool context (filter queries for new structure)
- Updated Explore context (gall queries)
- Updated Taxonomy context (placeholder helpers)
- Updated FilterFields context (Location → PlantPart)
- Updated Places context (range split)
- Updated GallSummary (detachable conversion)

**Review Goal:** Go through each context file below to verify changes are correct, complete, and nothing was missed.

Work through each context module systematically, checking queries and business logic.

### 2.1 Species Context

#### File: `lib/gallformers/species.ex`
**Action:** MAJOR UPDATE - This is the core context for galls
**Expected refs:** 44+ references to old patterns

**What to update:**

1. **Remove alias:**
   ```elixir
   # DELETE
   alias Gallformers.Species.{Gall, GallSpecies, ...}
   ```

2. **Add alias:**
   ```elixir
   # ADD
   alias Gallformers.Species.GallTraits
   ```

3. **Update all query joins:**
   ```elixir
   # FIND patterns like:
   |> join(:inner, [s], gs in assoc(s, :gall_species))
   |> join(:inner, [s, gs], g in assoc(gs, :gall))

   # REPLACE with:
   |> join(:inner, [s], gt in assoc(s, :gall_traits))
   ```

4. **Update all preload paths:**
   ```elixir
   # FIND patterns like:
   Repo.preload(species, [gall_species: [gall: [:colors, :shapes, ...]]])

   # REPLACE with:
   Repo.preload(species, [gall_traits: [:color, :walls, :cells, :shapes, :textures, ...]])
   ```

5. **Update detachable handling:**
   ```elixir
   # ADD conversion helpers
   def detachable_to_string(0), do: "unknown"
   def detachable_to_string(1), do: "integral"
   def detachable_to_string(2), do: "detachable"
   def detachable_to_string(3), do: "both"
   def detachable_to_string(nil), do: nil
   def detachable_to_string(s) when is_binary(s), do: s

   def detachable_to_int("unknown"), do: 0
   def detachable_to_int("integral"), do: 1
   def detachable_to_int("detachable"), do: 2
   def detachable_to_int("both"), do: 3
   def detachable_to_int(nil), do: nil
   def detachable_to_int(i) when is_integer(i), do: i
   ```

6. **Update functions that create/update galls:**
   - `create_gall/1` → use `Species.gall_changeset/2`
   - Any function building gall queries
   - Any function filtering by detachable

7. **Update multi-value trait queries:**
   ```elixir
   # Just rename the tables (snake_case) - applies to ALL traits
   |> join(:left, [...], gc in "gall_color", ...)     # was "gallcolor"
   |> join(:left, [...], gw in "gall_walls", ...)     # was "gallwalls"
   |> join(:left, [...], gce in "gall_cells", ...)    # was "gallcells"
   |> join(:left, [...], gs in "gall_shape", ...)     # was "gallshape"
   |> join(:left, [...], gpp in "gall_plant_part", ...)  # was "galllocation"
   ```

**Systematic approach:**
- Search for `GallSpecies` → replace all
- Search for `:gall_species` → replace all
- Search for `assoc(gs, :gall)` → remove (gall doesn't exist)
- Search for detachable integer comparisons → convert to string
- Search for old junction table names → rename to snake_case (gallcolor → gall_color, etc.)

---

#### File: `lib/gallformers/hosts.ex`
**Action:** MAJOR UPDATE
**Expected refs:** 45+ references to gall_species_id

**What to update:**

1. **Remove alias:**
   ```elixir
   # DELETE (if exists)
   alias Gallformers.Species.{Gall, GallSpecies}
   ```

2. **Update queries using gall_species_id:**
   ```elixir
   # NOTE: gall_species_id field name STAYS THE SAME
   # It's in the gallhost table and still references species.id
   # But we remove joins through GallSpecies table

   # BEFORE:
   |> join(:inner, [h], gs in GallSpecies, on: h.gall_species_id == gs.species_id)
   |> join(:inner, [h, gs], g in Gall, on: gs.gall_id == g.id)

   # AFTER (if we need gall traits):
   |> join(:inner, [h], s in Species, on: h.gall_species_id == s.id)
   |> join(:left, [h, s], gt in assoc(s, :gall_traits))
   ```

3. **Update preloads:**
   ```elixir
   # BEFORE:
   Repo.preload(host, [gall_species: [gall_species: [gall: [...]]]])

   # AFTER:
   Repo.preload(host, [gall_species: [gall_traits: [...]]])
   ```

4. **Search and update:**
   - All references to `gall_species` association path
   - All references to `:gall` nested in queries
   - Any detachable logic

---

#### File: `lib/gallformers/search.ex`
**Action:** MAJOR UPDATE
**Expected refs:** 6+ GallSpecies references

**What to update:**

1. **Remove alias:**
   ```elixir
   # DELETE
   alias Gallformers.Species.{Gall, GallSpecies}
   ```

2. **Add alias:**
   ```elixir
   # ADD
   alias Gallformers.Species.GallTraits
   ```

3. **Update gall search queries:**
   ```elixir
   # In search_galls/1, search_galls_paginated/3, etc.

   # BEFORE:
   from s in Species,
     join: gs in GallSpecies, on: s.id == gs.species_id,
     join: g in Gall, on: gs.gall_id == g.id

   # AFTER:
   from s in Species,
     join: gt in assoc(s, :gall_traits)
   ```

4. **Update trait filters in search** (if any)

---

#### File: `lib/gallformers/id_tool.ex`
**Action:** MAJOR UPDATE
**Expected refs:** 40+ references to old patterns

**What to update:**

1. **Remove alias:**
   ```elixir
   # DELETE
   alias Gallformers.Species.{Gall, GallSpecies}
   ```

2. **Add alias:**
   ```elixir
   alias Gallformers.Species.GallTraits
   ```

3. **Update base query:**
   ```elixir
   # BEFORE:
   from s in Species,
     join: gs in GallSpecies, on: s.id == gs.species_id,
     join: g in Gall, on: gs.gall_id == g.id

   # AFTER:
   from s in Species,
     join: gt in assoc(s, :gall_traits)
   ```

4. **Update detachable filter:**
   ```elixir
   # BEFORE:
   defp filter_by_detachable(query, detachable_int) do
     where(query, [..., g], g.detachable == ^detachable_int)
   end

   # AFTER:
   defp filter_by_detachable(query, detachable_string) do
     where(query, [..., gt], gt.detachable == ^detachable_string)
   end
   ```

5. **Update multi-value trait filters:**
   ```elixir
   # Just rename tables (snake_case) - applies to ALL traits including colors/walls/cells

   # BEFORE:
   |> join(:inner, [...], gc in "gallcolor", ...)
   |> join(:inner, [...], gs in "gallshape", ...)

   # AFTER:
   |> join(:inner, [...], gc in "gall_color", ...)
   |> join(:inner, [...], gs in "gall_shape", ...)
   ```

6. **Update location → plant_part:**
   ```elixir
   # BEFORE:
   |> join(:inner, [...], gl in "galllocation", ...)

   # AFTER:
   |> join(:inner, [...], gpp in "gall_plant_part", ...)
   ```

---

#### File: `lib/gallformers/explore.ex`
**Action:** UPDATE
**What to update:**

1. Check for GallSpecies/Gall references
2. Update any queries that join to gall data
3. Update preloads

---

#### File: `lib/gallformers/taxonomy.ex`
**Action:** UPDATE
**What to update:**

1. **Add placeholder helpers:**
   ```elixir
   def list_taxonomies do
     from(t in Taxonomy, where: t.is_placeholder == false)
     |> Repo.all()
   end

   def get_unknown_placeholder(parent_id) do
     from(t in Taxonomy,
       where: t.is_placeholder == true and t.parent_id == ^parent_id
     )
     |> Repo.one()
   end

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
       taxonomy -> {:ok, taxonomy}
     end
   end
   ```

2. **Add display helper:**
   ```elixir
   def display_name(taxonomy) do
     Taxonomy.display_name(Repo.preload(taxonomy, :parent))
   end
   ```

---

#### File: `lib/gallformers/filter_fields.ex`
**Action:** UPDATE
**What to update:**

1. **Rename Location → PlantPart:**
   ```elixir
   # REPLACE alias
   alias Gallformers.FilterFields.Location  →  alias Gallformers.FilterFields.PlantPart

   # RENAME all functions:
   list_locations/0        → list_plant_parts/0
   get_location/1          → get_plant_part/1
   create_location/1       → create_plant_part/1
   update_location/2       → update_plant_part/2
   delete_location/1       → delete_plant_part/1
   ```

2. **Update @filter_types** (if it exists):
   ```elixir
   @filter_types [:alignment, :cells, :color, :form, :plant_part, :season, :shape, :texture, :walls]
   ```

---

#### File: `lib/gallformers/places.ex`
**Action:** UPDATE
**What to update:**

1. **Update range queries:**
   ```elixir
   # ADD new functions

   def get_host_ranges(species_id) do
     from hr in "host_range",
       where: hr.species_id == ^species_id,
       select: hr.place_id
     |> Repo.all()
   end

   def get_gall_range_exclusions(species_id) do
     from gre in "gall_range_exclusion",
       where: gre.species_id == ^species_id,
       select: gre.place_id
     |> Repo.all()
   end

   def get_species_range(%Species{taxoncode: "plant"} = species) do
     get_host_ranges(species.id)
   end
   def get_species_range(%Species{taxoncode: "gall"} = species) do
     get_gall_range_exclusions(species.id)
   end
   ```

2. **Remove speciesplace references** (if any exist)

---

#### File: `lib/gallformers/gall_summary.ex`
**Action:** UPDATE
**What to update:**

1. **Update detachable conversion:**
   ```elixir
   # This file has conversion logic - update to handle both int and string

   # FIND:
   defp detachable_to_string(0), do: "unknown"
   defp detachable_to_string(1), do: "integral"
   defp detachable_to_string(2), do: "detachable"
   defp detachable_to_string(3), do: "both"

   # KEEP but ADD:
   defp detachable_to_string(s) when is_binary(s), do: s  # Already a string
   defp detachable_to_string(nil), do: nil
   ```

2. Check for GallSpecies references
3. Check for location → plant_part

---

#### File: `lib/gallformers/images.ex`
**Action:** CHECK
**What to check:**
- [ ] Any references to `image.default` field → use `sort_order == 1` instead

---

#### File: `lib/gallformers/sources.ex`
**Action:** CHECK ONLY
**Expected:** No gall-specific logic

---

## Layer 3: Web Layer (Controllers, LiveViews, Components) - 60+ Files

Work through each web file, checking for old schema references.

### 3.1 API Controllers (10 files)

#### File: `lib/gallformers_web/controllers/api/gall_controller.ex`
**Action:** UPDATE
**What to update:**
1. Remove GallSpecies/Gall aliases
2. Add GallTraits alias
3. Update queries and preloads
4. Update detachable serialization (int → string)

---

#### File: `lib/gallformers_web/controllers/api/species_controller.ex`
**Action:** UPDATE
**What to update:**
1. Update gall preloads
2. Update detachable handling

---

#### File: `lib/gallformers_web/controllers/api/host_controller.ex`
**Action:** UPDATE
**What to update:**
1. Update gall_species preload paths

---

#### File: `lib/gallformers_web/schemas/api_schemas.ex`
**Action:** UPDATE
**What to update:**

1. **Update Gall schema:**
   ```elixir
   # FIND:
   %Schema{
     type: :object,
     properties: %{
       detachable: %Schema{type: :integer, nullable: true}  # OLD
     }
   }

   # REPLACE with:
   %Schema{
     type: :object,
     properties: %{
       detachable: %Schema{
         type: :string,
         enum: ["unknown", "integral", "detachable", "both"],
         nullable: true
       }
     }
   }
   ```

2. Update any schema references to old tables

---

#### Files: Other API controllers
**Action:** CHECK ONLY
- `explore_controller.ex` - check for gall queries
- `filter_field_controller.ex` - check for location → plant_part
- `glossary_controller.ex` - no gall logic expected
- `place_controller.ex` - check for speciesplace
- `search_controller.ex` - check for gall search
- `source_controller.ex` - no gall logic expected
- `stats_controller.ex` - check for gall stats queries
- `taxonomy_controller.ex` - check for placeholder logic

---

### 3.2 Admin LiveViews (20+ files)

#### File: `lib/gallformers_web/live/admin/gall_live/form.ex`
**Action:** MAJOR UPDATE
**Expected refs:** 22+ references

**What to update:**

1. **Remove detachable integer options:**
   ```elixir
   # DELETE:
   @detachable_options [
     {"", 0},
     {"integral", 1},
     {"detachable", 2},
     {"both", 3}
   ]

   # REPLACE with:
   @detachable_options [
     {"Unknown", "unknown"},
     {"Integral", "integral"},
     {"Detachable", "detachable"},
     {"Both", "both"}
   ]
   ```

2. **Update form structure:**
   ```elixir
   # Use Species.gall_changeset/2 which handles gall_traits association
   def mount(_params, _session, socket) do
     changeset =
       %Species{taxoncode: "gall", gall_traits: %GallTraits{}}
       |> Species.gall_changeset(%{})

     {:ok, assign(socket, changeset: changeset)}
   end
   ```

3. **Update location → plant_part** in form fields

4. **Update save logic:**
   ```elixir
   # Use context function that handles gall_traits
   defp save_gall(socket, :new, params) do
     case Species.create_gall(params) do
       {:ok, species} -> # ...
     end
   end
   ```

---

#### File: `lib/gallformers_web/live/admin/gall_live/index.ex`
**Action:** UPDATE
**What to update:**
1. Update data loading (preload gall_traits)
2. Update table display (access via gall_traits)

---

#### File: `lib/gallformers_web/live/admin/host_live/form.ex`
**Action:** UPDATE
**What to update:**
1. Check for gall_species references in host form
2. Update any gall preloads

---

#### File: `lib/gallformers_web/live/admin/form_helpers.ex`
**Action:** CHECK
**What to check:**
- Generic form helpers - look for detachable, location, gall references

---

#### Files: Other admin LiveViews
**Action:** CHECK EACH
- `article_live/*.ex` - no gall logic expected
- `dashboard_live.ex` - check stats queries
- `filter_terms_live/*.ex` - check for location → plant_part
- `gall_host_live.ex` - UPDATE (gall references)
- `glossary_live/*.ex` - no gall logic expected
- `host_live/index.ex` - UPDATE (gall references)
- `image_audit_live.ex` - check for image.default
- `images_live.ex` - check for image.default
- `place_live/*.ex` - check for speciesplace
- `section_live/*.ex` - taxonomy - check placeholders
- `source_live/*.ex` - no gall logic expected
- `species_source_live/*.ex` - check junction table name
- `taxonomy_live/*.ex` - UPDATE (placeholder support)
- `users_live.ex` - no gall logic expected

---

### 3.3 Public LiveViews (15+ files)

#### File: `lib/gallformers_web/live/gall_live.ex`
**Action:** MAJOR UPDATE
**What to update:**

1. **Update data loading:**
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

2. **Update template access:**
   ```heex
   <%= if @species.gall_traits do %>
     <p>Detachable: <%= @species.gall_traits.detachable %></p>

     <%= if @species.gall_traits.color do %>
       <span><%= @species.gall_traits.color.color %></span>
     <% end %>

     <%= for shape <- @species.gall_traits.shapes do %>
       <span><%= shape.shape %></span>
     <% end %>
   <% end %>
   ```

---

#### File: `lib/gallformers_web/live/host_live.ex`
**Action:** UPDATE
**What to update:**
1. Update host data loading (gall_traits preloads)
2. Update range display (host_ranges)

---

#### File: `lib/gallformers_web/live/id_live.ex`
**Action:** UPDATE
**Expected refs:** 17+ references

**What to update:**

1. **Update URL param mapping:**
   ```elixir
   # CHECK if "lo" param still maps correctly
   # locations: "lo" → plant_parts: "pp" (maybe?)
   ```

2. **Update filter options:**
   ```elixir
   # Ensure detachable options are strings
   # Ensure location → plant_part
   ```

3. **Update filter event handlers:**
   - Handle detachable as string
   - Handle plant_part (not location)

---

#### File: `lib/gallformers_web/live/search_live.ex`
**Action:** UPDATE
**What to update:**
1. Update gall search results display

---

#### File: `lib/gallformers_web/live/explore_live.ex`
**Action:** UPDATE
**What to update:**
1. Update explore queries/display

---

#### Files: Other public LiveViews
**Action:** CHECK EACH
- `about_live.ex` - no gall logic expected
- `analytics_live.ex` - check stats
- `article_live.ex` - no gall logic expected
- `articles_live.ex` - no gall logic expected
- `family_live.ex` - taxonomy - check placeholders
- `filter_guide_live.ex` - UPDATE (location → plant_part)
- `genus_live.ex` - taxonomy - check placeholders
- `glossary_live.ex` - no gall logic expected
- `home_live.ex` - check for gall display
- `place_live.ex` - check for range queries
- `privacy_live.ex` - no gall logic expected
- `section_live.ex` - taxonomy - check placeholders
- `source_live.ex` - no gall logic expected
- `user_profile_live.ex` - no gall logic expected

---

### 3.4 Components (5 files)

#### File: `lib/gallformers_web/components/data_display_components.ex`
**Action:** UPDATE
**What to check:**
- Components that display gall data
- Components that show detachable values
- Components that show locations (→ plant_parts)
- Components that show ranges (speciesplace split)

---

#### File: `lib/gallformers_web/components/form_components.ex`
**Action:** CHECK
**What to check:**
- Generic form components
- Any gall-specific form components

---

#### Files: Other components
**Action:** CHECK EACH
- `core_components.ex` - generic, no gall logic expected
- `ui_components.ex` - generic, no gall logic expected
- `layouts.ex` - no gall logic expected
- `seo.ex` - no gall logic expected

---

## Layer 4: Tests - 50+ Files

Work through all test files systematically.

### 4.1 Schema Tests

#### File: `test/gallformers/species/gall_traits_test.exs`
**Action:** CREATE
**What to write:**
- Changeset validations
- detachable enum validation
- FK constraints
- Association tests

---

#### File: `test/gallformers/species_test.exs`
**Action:** UPDATE
**What to update:**
1. Remove GallSpecies/Gall fixtures
2. Add GallTraits fixtures
3. Update all test helper functions
4. Update detachable test values (int → string)

---

#### Files: Other schema tests
**Action:** UPDATE EACH
- Update fixtures to use V2 schema
- Update assertions to match new structure

---

### 4.2 Context Tests

#### File: `test/gallformers/species_context_test.exs`
**Action:** UPDATE
**What to update:**
1. Gall creation tests (use gall_traits)
2. Gall query tests
3. Detachable filtering tests

---

#### File: `test/gallformers/hosts_test.exs`
**Action:** UPDATE
**What to update:**
1. Host fixtures
2. Gall association tests

---

#### Files: Other context tests
- `id_tool_test.exs` - UPDATE (filter tests)
- `search_test.exs` - UPDATE (gall search)
- `taxonomy_test.exs` - UPDATE (placeholder tests)
- etc.

---

### 4.3 LiveView Tests

#### File: `test/gallformers_web/live/admin/gall_live_test.exs`
**Action:** MAJOR UPDATE
**What to update:**
1. Form interaction tests (detachable strings)
2. Creation tests (gall_traits structure)
3. Update tests (gall_traits)

---

#### Files: All other LiveView tests
**Action:** UPDATE EACH
- Check fixtures
- Check form interactions
- Check data display assertions

---

### 4.4 E2E Tests

#### File: `test/e2e/admin/gall_admin_test.exs`
**Action:** UPDATE
**What to update:**
1. Gall creation flow (string detachable)
2. Form field interactions

---

#### Files: Other E2E tests
**Action:** CHECK EACH
- Browse tests - check gall display
- Search tests - check gall results
- ID tool tests - check filters

---

## Layer 5: Support Files & Config

### 5.1 Test Support

#### File: `test/support/fixtures/*.ex`
**Action:** UPDATE ALL
**What to update:**
- All gall fixtures → use gall_traits
- All detachable → strings
- All location → plant_part
- All junction tables → snake_case

---

### 5.2 Database Files

#### File: `priv/repo/structure.sql`
**Action:** REPLACE
**What to do:**
```bash
cp priv/repo/structure_target.sql priv/repo/structure.sql
```

---

#### File: `priv/repo/test_seeds.sql`
**Action:** UPDATE
**What to update:**
1. Use V2 table names
2. Use V2 structure (gall_traits, etc.)
3. Detachable as strings
4. snake_case junction tables

---

## Execution Strategy

### Phase 1: Data Layer (START HERE - Day 1)
1. Review Layer 1 file-by-file (18 schema files)
2. For each file:
   - Read the current file state
   - Check against the plan's requirements
   - Verify changes are correct and complete
   - Make additional changes if needed
   - Run `mix compile --warnings-as-errors` after changes
3. Even if file was "already updated", review it to verify
4. Commit after each logical grouping

### Phase 2: Business Logic (Day 1-2)
1. Review Layer 2 file-by-file (9 context files)
2. Same review process as Phase 1
3. After each context file, compile and check for errors

### Phase 3: Web Layer (Day 2-3)
1. Work through Layer 3 file-by-file
2. Focus on getting the app to run: `mix phx.server`
3. Manual smoke tests on key pages

### Phase 4: Tests (Day 2-3)
1. Update test fixtures first
2. Work through test files by layer (schema → context → LiveView → E2E)
3. Get `mix test` passing (excluding E2E)
4. Get `make e2e` passing

### Phase 5: Verification (Day 3)
1. Full test suite: `mix precommit`
2. E2E tests: `make e2e`
3. Manual testing of all key flows
4. Performance check (query speeds)

---

## Tracking Progress

Use a checklist file to track completed files:

```bash
# Create tracking file
cat > /tmp/v2-migration-progress.txt << 'EOF'
# Layer 1: Data Layer
[ ] lib/gallformers/species/gall_species.ex (DELETE)
[ ] lib/gallformers/species/gall.ex (DELETE)
[ ] lib/gallformers/species/taxon_type.ex (DELETE)
[ ] lib/gallformers/species/gall_traits.ex (VERIFY)
[ ] lib/gallformers/species/species.ex (UPDATE)
... (rest of files)
EOF
```

Check off each file as you complete it.

---

## Success Criteria

Before considering this complete:

- [ ] All schema files updated or deleted
- [ ] All context modules updated
- [ ] All LiveViews/controllers updated
- [ ] All component files checked
- [ ] All tests updated
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix precommit` passes
- [ ] `make e2e` passes
- [ ] Manual smoke test passes
- [ ] No references to deleted tables/fields in codebase
- [ ] structure.sql reflects V2 schema

---

## Notes for Implementer

**Keep this context in your head:**
- Gall data moved from 3 tables to 2 (removed join table)
- Detachable is now a string, not an integer
- All trait junction tables (colors/walls/cells/shapes/textures/etc.) renamed to snake_case
- Location is now plant_part
- Range is split by taxoncode semantics

**Work systematically:**
- One file at a time
- Compile after each change
- Commit frequently
- Don't skip the "CHECK ONLY" files - you might find surprises

**Common mistakes to avoid:**
- Forgetting to update preload paths
- Missing nested association updates (gall_species.gall.colors → species.gall_traits.colors)
- Not updating both query and preload in same function
- Keeping old integer detachable logic

This is a **large refactor** - expect 4-5 days of focused work going file-by-file.

---

## How to Use This Plan

**Approach:**
1. **Start at Layer 1, File 1** (`lib/gallformers/species/gall_species.ex`)
2. **Work through EVERY file** in order, even if it was "already worked on"
3. **For each file:**
   - Read the current file state
   - Read the plan's requirements for that file
   - Verify changes are correct and complete
   - Make additional changes if needed
   - Note if anything was missed or incorrectly done
4. **Review together** - User and Claude go through each file systematically
5. **Move to next file** only after current file is verified

**Starting Command:**
```
Let's start the file-by-file review. Begin with Layer 1, Section 1.1,
File: lib/gallformers/species/gall_species.ex (marked as DELETE).
```

**Total Work:**
- Layer 1: 18 schema files
- Layer 2: 9 context files
- Layer 3: 60+ web files
- Layer 4: 50+ test files
- Layer 5: Support files

**Estimated total time:** 3-4 days going through every file systematically.
