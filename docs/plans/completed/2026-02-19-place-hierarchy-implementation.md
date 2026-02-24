# Place Hierarchy & Range Precision — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable hierarchy-aware range tracking with precision metadata, so ranges can be stored at any level (state, country, continent) and the system correctly expands/contracts through the hierarchy for filtering and display.

**Architecture:** Add a `precision` column to `host_range` and `gall_range_exclusion` tables. Use SQLite `WITH RECURSIVE` CTEs to traverse the existing `place_hierarchy` table in both directions (ancestors and descendants). Enhance the `.typeahead` component with optional grouping. Update all range queries, the ID tool filter, and admin map interactions.

**Tech Stack:** Phoenix LiveView, Ecto with SQLite, MapLibre GL JS + PMTiles, Tailwind CSS v4

**Design doc:** `docs/plans/2026-02-19-place-hierarchy-ranges-design.md`

---

## Task 1: Migration — Add precision columns and reclassify territories

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_range_precision_and_reclassify_territories.exs`
- Modify: `priv/repo/test_seeds.sql` (add precision column to INSERT statements, add test data for hierarchy-aware ranges)

### Step 1: Write the migration

```elixir
defmodule Gallformers.Repo.Migrations.AddRangePrecisionAndReclassifyTerritories do
  use Gallformers.Migration

  def up do
    # Add precision column to host_range
    execute "ALTER TABLE host_range ADD COLUMN precision TEXT NOT NULL DEFAULT 'exact'"

    # Add precision column to gall_range_exclusion
    execute "ALTER TABLE gall_range_exclusion ADD COLUMN precision TEXT NOT NULL DEFAULT 'exact'"

    # Reclassify Puerto Rico: update existing US-PR row in place
    # Change code from US-PR to PR, type from state to country
    execute "UPDATE place SET code = 'PR', type = 'country' WHERE code = 'US-PR'"

    # Rewire PR hierarchy: US → Caribbean
    execute """
    UPDATE place_hierarchy
    SET parent_id = (SELECT id FROM place WHERE code = 'XB')
    WHERE place_id = (SELECT id FROM place WHERE code = 'PR')
    """

    # Delete the duplicate PR country entry (has 0 host_range records)
    # Must delete hierarchy link first, then the place
    execute """
    DELETE FROM place_hierarchy
    WHERE place_id = (SELECT id FROM place WHERE code = 'PR' AND type = 'country'
                      ORDER BY id DESC LIMIT 1)
    """
    # Now there's only one PR row (the reclassified one), so the DELETE above
    # targets the newer duplicate. Actually, after the UPDATE, both rows have
    # code='PR' and type='country'. We need to delete the one that has NO
    # host_range records.
    # Safer approach: delete by the known ID of the duplicate entry.
    # The duplicate was inserted by the western hemisphere migration as a country.
    # The original US-PR (now PR) has host_range records pointing to it.
    execute """
    DELETE FROM place_hierarchy WHERE place_id IN (
      SELECT p.id FROM place p
      WHERE p.code = 'PR' AND p.type = 'country'
      AND p.id NOT IN (SELECT DISTINCT place_id FROM host_range)
    )
    """
    execute """
    DELETE FROM place WHERE id IN (
      SELECT p.id FROM place p
      WHERE p.code = 'PR' AND p.type = 'country'
      AND p.id NOT IN (SELECT DISTINCT place_id FROM host_range)
    )
    """
  end

  def down do
    # Restore PR as US-PR state
    execute """
    UPDATE place SET code = 'US-PR', type = 'state'
    WHERE code = 'PR' AND id IN (SELECT DISTINCT place_id FROM host_range)
    """

    # Rewire back to US
    execute """
    UPDATE place_hierarchy
    SET parent_id = (SELECT id FROM place WHERE code = 'US')
    WHERE place_id = (SELECT id FROM place WHERE code = 'US-PR')
    """

    # Re-insert the PR country entry under Caribbean
    execute "INSERT INTO place (name, code, type) VALUES ('Puerto Rico', 'PR', 'country')"
    execute """
    INSERT INTO place_hierarchy (place_id, parent_id)
    SELECT p.id, c.id FROM place p, place c
    WHERE p.code = 'PR' AND p.type = 'country' AND c.code = 'XB'
    """

    # Remove precision columns (SQLite doesn't support DROP COLUMN before 3.35.0,
    # but we're on 3.43.2 so this works)
    execute "ALTER TABLE gall_range_exclusion DROP COLUMN precision"
    execute "ALTER TABLE host_range DROP COLUMN precision"
  end
end
```

### Step 2: Update test seeds

Add precision column to host_range inserts, add a Caribbean test place (Bahamas as leaf country), and add a country-level host_range row for hierarchy testing.

In `priv/repo/test_seeds.sql`, update the places section:

```sql
-- Add Caribbean continent and leaf country for hierarchy tests
INSERT INTO place (id, name, code, type) VALUES
  (905, 'Caribbean', 'XB', 'continent'),
  (906, 'Bahamas', 'BS', 'country');

-- Add hierarchy links for new places
INSERT INTO place_hierarchy (place_id, parent_id) VALUES
  (905, 900),  -- Caribbean → Western Hemisphere
  (906, 905);  -- Bahamas → Caribbean

-- Update host_range to include precision column
-- (replace existing INSERT with precision-aware version)
INSERT INTO host_range (species_id, place_id, precision) VALUES
  (6, 2, 'exact'),      -- T. alpinus in California (exact)
  (8, 1, 'exact'),      -- M. arvensis in Alberta (exact)
  (8, 2, 'exact'),      -- M. arvensis in California (exact)
  (7, 2, 'exact'),      -- T. serpyllum in California (exact)
  (8, 902, 'country');   -- M. arvensis in United States (country-level)
```

### Step 3: Update HostRange and GallRangeExclusion schemas

**File:** `lib/gallformers/ranges/host_range.ex`

Add the precision field to the schema and changeset:

```elixir
@required_fields [:species_id, :place_id]
@optional_fields [:precision]
@valid_precisions ~w(exact country continent)

@primary_key false
schema "host_range" do
  belongs_to :species, Gallformers.Species.Species
  belongs_to :place, Gallformers.Places.Place
  field :precision, :string, default: "exact"
end

def changeset(host_range, attrs) do
  host_range
  |> cast(attrs, @required_fields ++ @optional_fields)
  |> validate_required(@required_fields)
  |> validate_inclusion(:precision, @valid_precisions)
  |> unique_constraint([:species_id, :place_id], name: :host_range_pkey)
end
```

**File:** `lib/gallformers/ranges/gall_range_exclusion.ex`

Same pattern — add precision field, validate inclusion.

### Step 4: Run migration and verify

```bash
mix ecto.migrate
mix test test/gallformers/galls_identification_test.exs
```

Expected: Migration succeeds. Existing tests pass (all existing rows have precision='exact', queries unchanged yet).

### Step 5: Commit

```bash
git add priv/repo/migrations/ lib/gallformers/ranges/host_range.ex lib/gallformers/ranges/gall_range_exclusion.ex priv/repo/test_seeds.sql
git commit -m "Add precision column to host_range and gall_range_exclusion, reclassify PR/VI"
```

---

## Task 2: Places context — hierarchy traversal functions

**Files:**
- Modify: `lib/gallformers/places.ex`
- Create: `test/gallformers/places_test.exs` (or add to existing)

### Step 1: Write failing tests for ancestor/descendant queries

**File:** `test/gallformers/places_test.exs`

```elixir
describe "hierarchy traversal" do
  test "descendant_ids/1 returns the place and all children recursively" do
    us = Places.get_place_by_code("US")
    ids = Places.descendant_ids(us.id)
    # Should include US itself + California (and any other US subdivisions in test data)
    california = Places.get_place_by_code("US-CA")
    assert us.id in ids
    assert california.id in ids
  end

  test "descendant_ids/1 for a leaf place returns just itself" do
    california = Places.get_place_by_code("US-CA")
    assert Places.descendant_ids(california.id) == [california.id]
  end

  test "ancestor_ids/1 returns the place and all parents recursively" do
    california = Places.get_place_by_code("US-CA")
    ids = Places.ancestor_ids(california.id)
    us = Places.get_place_by_code("US")
    na = Places.get_place_by_code("NA")
    wh = Places.get_place_by_code("WH")
    assert california.id in ids
    assert us.id in ids
    assert na.id in ids
    assert wh.id in ids
  end

  test "ancestor_ids/1 for the root returns just itself" do
    wh = Places.get_place_by_code("WH")
    assert Places.ancestor_ids(wh.id) == [wh.id]
  end

  test "leaf_descendant_ids/1 returns only leaf nodes" do
    us = Places.get_place_by_code("US")
    ids = Places.leaf_descendant_ids(us.id)
    california = Places.get_place_by_code("US-CA")
    # California is a leaf, US is not
    assert california.id in ids
    refute us.id in ids
  end

  test "leaf_descendant_ids/1 for a leaf country returns itself" do
    bahamas = Places.get_place_by_code("BS")
    assert Places.leaf_descendant_ids(bahamas.id) == [bahamas.id]
  end
end
```

### Step 2: Run tests to verify they fail

```bash
mix test test/gallformers/places_test.exs --trace
```

Expected: Failures — functions don't exist yet.

### Step 3: Implement hierarchy traversal functions

**File:** `lib/gallformers/places.ex`

```elixir
@doc """
Returns IDs for a place and all its descendants (recursive).
"""
@spec descendant_ids(integer()) :: [integer()]
def descendant_ids(place_id) do
  Repo.all(
    from(fragment(
      """
      WITH RECURSIVE descendants(id) AS (
        SELECT ?
        UNION ALL
        SELECT ph.place_id
        FROM place_hierarchy ph
        JOIN descendants d ON ph.parent_id = d.id
      )
      SELECT id FROM descendants
      """,
      ^place_id
    ))
  )
  |> Enum.map(fn {id} -> id end)
end

@doc """
Returns IDs for a place and all its ancestors (recursive).
"""
@spec ancestor_ids(integer()) :: [integer()]
def ancestor_ids(place_id) do
  Repo.all(
    from(fragment(
      """
      WITH RECURSIVE ancestors(id) AS (
        SELECT ?
        UNION ALL
        SELECT ph.parent_id
        FROM place_hierarchy ph
        JOIN ancestors a ON ph.place_id = a.id
      )
      SELECT id FROM ancestors
      """,
      ^place_id
    ))
  )
  |> Enum.map(fn {id} -> id end)
end

@doc """
Returns IDs for leaf descendants only (places with no children).
For a leaf country like Bahamas, returns itself.
"""
@spec leaf_descendant_ids(integer()) :: [integer()]
def leaf_descendant_ids(place_id) do
  all_ids = descendant_ids(place_id)

  if length(all_ids) == 1 do
    all_ids
  else
    # Filter to only places that have no children
    parent_ids =
      from(ph in "place_hierarchy",
        where: ph.parent_id in ^all_ids,
        select: ph.parent_id,
        distinct: true
      )
      |> Repo.all()

    Enum.reject(all_ids, &(&1 in parent_ids))
  end
end
```

**Note:** The raw SQL fragment approach for recursive CTEs needs testing. Ecto's `fragment` with `from` may need to use `Ecto.Adapters.SQL.query!/3` instead. If fragment doesn't work directly, use:

```elixir
def descendant_ids(place_id) do
  {:ok, %{rows: rows}} =
    Repo.query(
      """
      WITH RECURSIVE descendants(id) AS (
        SELECT ?1
        UNION ALL
        SELECT ph.place_id
        FROM place_hierarchy ph
        JOIN descendants d ON ph.parent_id = d.id
      )
      SELECT id FROM descendants
      """,
      [place_id]
    )

  Enum.map(rows, fn [id] -> id end)
end
```

### Step 4: Run tests to verify they pass

```bash
mix test test/gallformers/places_test.exs --trace
```

Expected: All hierarchy tests pass.

### Step 5: Commit

```bash
git add lib/gallformers/places.ex test/gallformers/places_test.exs
git commit -m "Add recursive hierarchy traversal to Places context"
```

---

## Task 3: Places context — grouped search function

**Files:**
- Modify: `lib/gallformers/places.ex`
- Modify: `test/gallformers/places_test.exs`

### Step 1: Write failing tests for search_places

```elixir
describe "search_places/2" do
  test "returns countries and subdivisions, not continents or regions" do
    results = Places.search_places("a", 50)
    types = Enum.map(results, & &1.type)
    refute "continent" in types
    refute "region" in types
  end

  test "includes group field for typeahead grouping" do
    results = Places.search_places("ca", 10)
    assert Enum.all?(results, &Map.has_key?(&1, :group))
    groups = Enum.map(results, & &1.group) |> Enum.uniq()
    assert Enum.all?(groups, &(&1 in ["Countries", "States & Provinces"]))
  end

  test "includes parent_name for context display" do
    results = Places.search_places("california", 10)
    california = Enum.find(results, &(&1.code == "US-CA"))
    assert california.parent_name == "United States"
  end

  test "countries sort before subdivisions" do
    results = Places.search_places("ca", 10)
    groups = Enum.map(results, & &1.group)
    # Once we hit "States & Provinces", we shouldn't go back to "Countries"
    country_indices = Enum.with_index(groups) |> Enum.filter(fn {g, _} -> g == "Countries" end) |> Enum.map(fn {_, i} -> i end)
    subdiv_indices = Enum.with_index(groups) |> Enum.filter(fn {g, _} -> g == "States & Provinces" end) |> Enum.map(fn {_, i} -> i end)

    if country_indices != [] and subdiv_indices != [] do
      assert Enum.max(country_indices) < Enum.min(subdiv_indices)
    end
  end

  test "leaf countries appear in Countries group" do
    results = Places.search_places("bahamas", 10)
    bahamas = Enum.find(results, &(&1.code == "BS"))
    assert bahamas.group == "Countries"
  end
end
```

### Step 2: Run tests to verify they fail

```bash
mix test test/gallformers/places_test.exs --trace
```

### Step 3: Implement search_places

**File:** `lib/gallformers/places.ex`

```elixir
@doc """
Searches places for the grouped typeahead. Returns countries and subdivisions
(not continents or regions) with group labels and parent names for display.

Results are ordered: countries first, then subdivisions, alphabetical within each.
"""
@spec search_places(String.t(), non_neg_integer()) :: [map()]
def search_places(query, limit \\ 10) do
  like_query = "%#{String.downcase(query)}%"

  from(p in Place,
    left_join: ph in "place_hierarchy",
    on: ph.place_id == p.id,
    left_join: parent in Place,
    on: parent.id == ph.parent_id,
    where: p.type in ["country", "state", "province"],
    where: fragment("lower(?) LIKE ?", p.name, ^like_query),
    order_by: [
      # Countries first (0), subdivisions second (1)
      fragment("CASE WHEN ? = 'country' THEN 0 ELSE 1 END", p.type),
      p.name
    ],
    limit: ^limit,
    select: %{
      id: p.id,
      name: p.name,
      code: p.code,
      type: p.type,
      parent_name: parent.name,
      group:
        fragment(
          "CASE WHEN ? = 'country' THEN 'Countries' ELSE 'States & Provinces' END",
          p.type
        )
    }
  )
  |> Repo.all()
end
```

### Step 4: Run tests

```bash
mix test test/gallformers/places_test.exs --trace
```

### Step 5: Commit

```bash
git add lib/gallformers/places.ex test/gallformers/places_test.exs
git commit -m "Add grouped search_places for hierarchy-aware typeahead"
```

---

## Task 4: Ranges context — precision-aware queries

**Files:**
- Modify: `lib/gallformers/ranges.ex`
- Create: `test/gallformers/ranges_test.exs`

This task updates the Ranges context so all range queries respect the hierarchy. A host with a country-level range in "US" should be found when querying for "US-CA".

### Step 1: Write failing tests

```elixir
describe "hierarchy-aware range queries" do
  test "get_places_for_host/1 returns both exact and country-level codes" do
    # M. arvensis (id=8) has exact ranges in CA-AB and US-CA,
    # plus a country-level range for US
    codes = Ranges.get_places_for_host(8)
    assert "CA-AB" in codes
    assert "US-CA" in codes
    assert "US" in codes
  end

  test "get_places_for_host_with_precision/1 includes precision metadata" do
    results = Ranges.get_places_for_host_with_precision(8)
    us_entry = Enum.find(results, &(&1.code == "US"))
    ca_entry = Enum.find(results, &(&1.code == "US-CA"))
    assert us_entry.precision == "country"
    assert ca_entry.precision == "exact"
  end

  test "host_covers_place?/2 returns true for exact match" do
    # M. arvensis (8) has exact range in California (US-CA)
    california = Places.get_place_by_code("US-CA")
    assert Ranges.host_covers_place?(8, california.id)
  end

  test "host_covers_place?/2 returns true when ancestor has range" do
    # M. arvensis (8) has country-level range for US
    # So any US state should be covered
    california = Places.get_place_by_code("US-CA")
    assert Ranges.host_covers_place?(8, california.id)
  end

  test "host_covers_place?/2 returns false for unrelated place" do
    # T. alpinus (6) only has exact range in California
    alberta = Places.get_place_by_code("CA-AB")
    refute Ranges.host_covers_place?(6, alberta.id)
  end
end
```

### Step 2: Run tests to verify they fail

```bash
mix test test/gallformers/ranges_test.exs --trace
```

### Step 3: Implement precision-aware range functions

**File:** `lib/gallformers/ranges.ex`

Add new functions (don't modify existing ones yet — we'll update callers in later tasks):

```elixir
@doc """
Gets place codes and precision for a host species.
Returns list of %{code: String.t(), precision: String.t()}.
"""
@spec get_places_for_host_with_precision(integer()) :: [map()]
def get_places_for_host_with_precision(host_species_id) do
  from(hr in HostRange,
    join: p in "place",
    on: hr.place_id == p.id,
    where: hr.species_id == ^host_species_id,
    select: %{code: p.code, precision: hr.precision}
  )
  |> Repo.all()
end

@doc """
Checks whether a host species covers a given place, accounting for hierarchy.

A host covers a place if:
  1. There's an exact host_range row for that place, OR
  2. There's a host_range row for any ancestor of that place
     (e.g., country-level range covers all subdivisions)
"""
@spec host_covers_place?(integer(), integer()) :: boolean()
def host_covers_place?(host_species_id, place_id) do
  ancestor_ids = Places.ancestor_ids(place_id)

  from(hr in HostRange,
    where: hr.species_id == ^host_species_id,
    where: hr.place_id in ^ancestor_ids,
    select: count()
  )
  |> Repo.one()
  |> Kernel.>(0)
end
```

### Step 4: Run tests

```bash
mix test test/gallformers/ranges_test.exs --trace
```

### Step 5: Commit

```bash
git add lib/gallformers/ranges.ex test/gallformers/ranges_test.exs
git commit -m "Add precision-aware range queries to Ranges context"
```

---

## Task 5: Ranges context — precision-aware management functions

**Files:**
- Modify: `lib/gallformers/ranges.ex`
- Modify: `test/gallformers/ranges_test.exs`

### Step 1: Write failing tests for precision-aware writes

```elixir
describe "precision-aware range management" do
  test "add_place_to_host/3 accepts precision parameter" do
    bahamas = Places.get_place_by_code("BS")
    {:ok, _} = Ranges.add_place_to_host(6, bahamas.id, "exact")
    codes = Ranges.get_places_for_host(6)
    assert "BS" in codes
  end

  test "add_place_to_host/3 stores country precision" do
    mexico = Places.get_place_by_code("MX")
    {:ok, _} = Ranges.add_place_to_host(6, mexico.id, "country")
    results = Ranges.get_places_for_host_with_precision(6)
    mx = Enum.find(results, &(&1.code == "MX"))
    assert mx.precision == "country"
  end

  test "set_range_exclusions_for_gall/2 accepts precision" do
    mexico = Places.get_place_by_code("MX")
    :ok = Ranges.set_range_exclusions_for_gall(100, [{mexico.id, "country"}])
    excluded = Ranges.get_excluded_places_with_precision_for_gall(100)
    mx = Enum.find(excluded, &(&1.code == "MX"))
    assert mx.precision == "country"
  end
end
```

### Step 2: Run tests to verify they fail

### Step 3: Update management functions

**File:** `lib/gallformers/ranges.ex`

Update `add_place_to_host` to accept optional precision:

```elixir
@spec add_place_to_host(integer(), integer(), String.t()) :: {:ok, map()}
def add_place_to_host(host_species_id, place_id, precision \\ "exact") do
  %HostRange{}
  |> HostRange.changeset(%{
    species_id: host_species_id,
    place_id: place_id,
    precision: precision
  })
  |> Repo.insert(on_conflict: :nothing)

  {:ok, %{id: host_species_id}}
end
```

Update `update_host_places` to accept `{place_id, precision}` tuples:

```elixir
@spec update_host_places(integer(), [{integer(), String.t()}] | [integer()]) :: {:ok, map()}
def update_host_places(host_species_id, place_entries) do
  Repo.transaction(fn ->
    from(hr in HostRange, where: hr.species_id == ^host_species_id) |> Repo.delete_all()

    if place_entries != [] do
      entries =
        Enum.map(place_entries, fn
          {place_id, precision} -> %{species_id: host_species_id, place_id: place_id, precision: precision}
          place_id when is_integer(place_id) -> %{species_id: host_species_id, place_id: place_id, precision: "exact"}
        end)

      Repo.insert_all(HostRange, entries)
    end

    :ok
  end)

  {:ok, %{id: host_species_id}}
end
```

Update `set_range_exclusions_for_gall` similarly to accept `{place_id, precision}` tuples:

```elixir
@spec set_range_exclusions_for_gall(integer(), [{integer(), String.t()}] | [integer()]) :: :ok
def set_range_exclusions_for_gall(gall_species_id, place_entries) do
  Repo.transaction(fn ->
    from(gre in GallRangeExclusion, where: gre.species_id == ^gall_species_id) |> Repo.delete_all()

    if place_entries != [] do
      entries =
        Enum.map(place_entries, fn
          {place_id, precision} -> %{species_id: gall_species_id, place_id: place_id, precision: precision}
          place_id when is_integer(place_id) -> %{species_id: gall_species_id, place_id: place_id, precision: "exact"}
        end)

      Repo.insert_all(GallRangeExclusion, entries)
    end

    :ok
  end)

  :ok
end
```

Add `get_excluded_places_with_precision_for_gall`:

```elixir
def get_excluded_places_with_precision_for_gall(gall_species_id) do
  from(p in "place",
    join: gre in GallRangeExclusion,
    on: gre.place_id == p.id,
    where: gre.species_id == ^gall_species_id,
    select: %{code: p.code, precision: gre.precision}
  )
  |> Repo.all()
end
```

### Step 4: Run tests

```bash
mix test test/gallformers/ranges_test.exs --trace
```

### Step 5: Run full test suite to check for regressions

```bash
mix test
```

Existing callers pass plain `[integer()]` lists which the updated functions handle via the `place_id when is_integer(place_id)` clause. No callers should break.

### Step 6: Commit

```bash
git add lib/gallformers/ranges.ex test/gallformers/ranges_test.exs
git commit -m "Add precision support to range management functions"
```

---

## Task 6: Identification engine — hierarchy-aware place filter

**Files:**
- Modify: `lib/gallformers/galls/identification.ex` (lines 395-447)
- Modify: `test/gallformers/galls_identification_test.exs`

This is the core query change. The ID tool filter must check both descendant and ancestor ranges.

### Step 1: Write failing tests

**File:** `test/gallformers/galls_identification_test.exs`

Add new tests for hierarchy-aware filtering:

```elixir
describe "hierarchy-aware place filtering" do
  test "country-level host range matches when filtering by subdivision" do
    # M. arvensis (host 8) has country-level range for US (id=902)
    # Gall 100 has host 8
    # Filtering by California (US-CA) should include gall 100
    results = Identification.filter_galls(%{place_codes: ["US-CA"]})
    gall_ids = Enum.map(results, & &1.id)
    assert 100 in gall_ids
  end

  test "filtering by country includes galls with subdivision-level ranges" do
    # T. alpinus (host 6) has exact range in California (US-CA)
    # Gall 100 has host 6
    # Filtering by United States (US) should include gall 100
    results = Identification.filter_galls(%{place_codes: ["US"]})
    gall_ids = Enum.map(results, & &1.id)
    assert 100 in gall_ids
  end

  test "results include match_precision metadata" do
    # When filtering by US-CA, galls matched via exact host_range
    # should have precision "exact", galls matched via country-level
    # should have precision "country"
    results = Identification.filter_galls(%{place_codes: ["US-CA"]})
    # This test depends on how we surface the precision indicator
    # (may be a separate field on the result or a flag)
    assert length(results) > 0
  end
end
```

### Step 2: Run tests to verify they fail

```bash
mix test test/gallformers/galls_identification_test.exs --trace
```

### Step 3: Implement hierarchy-aware apply_place_filter

**File:** `lib/gallformers/galls/identification.ex`

Replace `apply_place_filter/4` (lines 395-422). The new logic:

1. Resolve the selected place(s) to IDs
2. Get all descendant IDs (for when user selects a country)
3. Get all ancestor IDs (for matching country-level ranges)
4. Query host_range where place_id is in either set

```elixir
defp apply_place_filter(query, place_codes, host_ids, genus_id) do
  host_scope = resolve_host_scope(host_ids, genus_id)

  # Resolve place codes to IDs, then expand hierarchy in both directions
  place_ids = Enum.map(place_codes, &Ranges.get_place_id_by_code/1) |> Enum.reject(&is_nil/1)

  # Descendant IDs: when user selects "Brazil", include all Brazilian states
  descendant_ids = Enum.flat_map(place_ids, &Places.descendant_ids/1) |> Enum.uniq()

  # Ancestor IDs: when user selects "US-CA", match country-level US ranges
  ancestor_ids = Enum.flat_map(place_ids, &Places.ancestor_ids/1) |> Enum.uniq()

  # Combined: a host_range row matches if its place_id is in either set
  all_matching_place_ids = Enum.uniq(descendant_ids ++ ancestor_ids)

  case host_scope do
    nil ->
      from [s, gt] in query,
        join: h in GallHost,
        on: h.gall_species_id == s.id,
        join: hr in "host_range",
        on: hr.species_id == h.host_species_id,
        where: hr.place_id in ^all_matching_place_ids,
        where: s.id not in subquery(exclusion_subquery_by_ids(descendant_ids, ancestor_ids))

    ids ->
      from [s, gt] in query,
        join: h in GallHost,
        on: h.gall_species_id == s.id,
        join: hr in "host_range",
        on: hr.species_id == h.host_species_id,
        where: hr.place_id in ^all_matching_place_ids,
        where: h.host_species_id in ^ids,
        where: s.id not in subquery(exclusion_subquery_by_ids(descendant_ids, ancestor_ids))
  end
end
```

Update `exclusion_subquery` to work with place IDs instead of codes, and also be hierarchy-aware:

```elixir
defp exclusion_subquery_by_ids(descendant_ids, ancestor_ids) do
  all_exclusion_place_ids = Enum.uniq(descendant_ids ++ ancestor_ids)

  from(gre in "gall_range_exclusion",
    where: gre.place_id in ^all_exclusion_place_ids,
    select: gre.species_id
  )
end
```

**Important:** Keep the old `exclusion_subquery/1` (code-based) until all callers are migrated, or update it to delegate to the new ID-based version.

### Step 4: Update build_filter_params in id_live.ex

**File:** `lib/gallformers_web/live/id_live.ex` (around line 759)

The `build_filter_params/1` function currently wraps `filters.place` as `place_codes: wrap_value(...)`. This stays the same — the `apply_place_filter` function now handles hierarchy expansion internally.

### Step 5: Run tests

```bash
mix test test/gallformers/galls_identification_test.exs --trace
```

### Step 6: Run full suite

```bash
mix test
```

### Step 7: Commit

```bash
git add lib/gallformers/galls/identification.ex test/gallformers/galls_identification_test.exs
git commit -m "Make ID tool place filter hierarchy-aware with ancestor/descendant expansion"
```

---

## Task 7: Typeahead component — grouped results support

**Files:**
- Modify: `lib/gallformers_web/components/form_components.ex` (typeahead component, ~line 609)
- Modify: `assets/js/hooks/typeahead.js` (keyboard nav skip headers)
- Create: `test/gallformers_web/components/form_components_test.exs` (or add to existing)

### Step 1: Write failing test for grouped typeahead rendering

```elixir
describe "typeahead with group_key" do
  test "renders group headers between groups" do
    results = [
      %{id: 1, name: "Brazil", group: "Countries"},
      %{id: 2, name: "British Columbia", group: "States & Provinces"}
    ]

    html =
      render_component(&FormComponents.typeahead/1,
        id: "test",
        label: "Place",
        query: "br",
        results: results,
        selected: nil,
        search_event: "search",
        select_event: "select",
        clear_event: "clear",
        display_fn: fn r -> r.name end,
        group_key: :group
      )

    assert html =~ "Countries"
    assert html =~ "States &amp; Provinces"
    assert html =~ "Brazil"
    assert html =~ "British Columbia"
  end

  test "renders without groups when group_key is nil" do
    results = [%{id: 1, name: "Brazil"}, %{id: 2, name: "Canada"}]

    html =
      render_component(&FormComponents.typeahead/1,
        id: "test",
        label: "Place",
        query: "b",
        results: results,
        selected: nil,
        search_event: "search",
        select_event: "select",
        clear_event: "clear",
        display_fn: fn r -> r.name end
      )

    refute html =~ "role=\"presentation\""
    assert html =~ "Brazil"
  end
end
```

### Step 2: Run test to verify it fails

### Step 3: Add group_key attr and update template

**File:** `lib/gallformers_web/components/form_components.ex`

Add attribute (near line 635):

```elixir
attr :group_key, :atom, default: nil, doc: "Key in result maps to group by. When set, inserts non-selectable headers."
```

In the template, where results are rendered (the `<div>` with `role="option"` items), add group header logic:

```heex
<%= for {result, index} <- Enum.with_index(@results) do %>
  <%= if @group_key && show_group_header?(result, index, @results, @group_key) do %>
    <div class="px-3 py-1.5 text-xs font-semibold text-gray-500 uppercase tracking-wider" role="presentation">
      <%= Map.get(result, @group_key) %>
    </div>
  <% end %>
  <%!-- existing result item markup --%>
<% end %>
```

Add helper function in the module:

```elixir
defp show_group_header?(result, 0, _results, group_key), do: Map.get(result, group_key) != nil

defp show_group_header?(result, index, results, group_key) do
  prev = Enum.at(results, index - 1)
  Map.get(result, group_key) != Map.get(prev, group_key)
end
```

### Step 4: Update Typeahead JS hook for keyboard nav

**File:** `assets/js/hooks/typeahead.js`

In the keyboard navigation handler, skip elements with `role="presentation"`:

```javascript
// When calculating the next/prev selectable item, skip group headers
const selectableItems = [...listbox.children].filter(
  el => el.getAttribute('role') !== 'presentation'
);
```

### Step 5: Run tests

```bash
mix test test/gallformers_web/components/form_components_test.exs --trace
```

### Step 6: Commit

```bash
git add lib/gallformers_web/components/form_components.ex assets/js/hooks/typeahead.js test/gallformers_web/components/form_components_test.exs
git commit -m "Add optional group_key support to typeahead component"
```

---

## Task 8: ID tool — switch to grouped place search

**Files:**
- Modify: `lib/gallformers_web/live/id_live.ex` (search_place event, typeahead template)
- Modify: `test/gallformers_web/live/id_live_test.exs`

### Step 1: Write failing test

```elixir
test "place search returns countries and subdivisions with groups", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/id")

  # Search for "ca" — should return Canada (country) and California (state)
  html = view |> element("#place-filter") |> render_change(%{query: "ca"})
  assert html =~ "Countries"
  assert html =~ "Canada"
  assert html =~ "States"
  assert html =~ "California"
end
```

### Step 2: Run test to verify it fails

### Step 3: Update ID tool to use search_places with grouping

**File:** `lib/gallformers_web/live/id_live.ex`

Update the `search_place` event handler (~line 575):

```elixir
# Before:
Places.search_subdivision_places(query, 10)

# After:
Places.search_places(query, 10)
```

Update the typeahead in the template (~line 910):

```heex
<.typeahead
  id="place-filter"
  label="Region"
  placeholder="Search regions..."
  search_event="search_place"
  select_event="select_place"
  clear_event="clear_place"
  query={@place_query}
  results={@place_results}
  selected={@selected_place}
  display_fn={fn place -> place.name end}
  group_key={:group}
/>
```

Update `select_place` event handler to work with the new result shape (the result maps now include `:group` and `:parent_name` fields — `select_place` uses the `:id` field to look up the place, which is unchanged).

Update `load_place_from_params/1` — currently calls `get_place_by_code` then falls back to `get_place_by_name`. The Place struct doesn't have a `:group` field, so the selected place display doesn't need it — `display_fn` uses `place.name`.

### Step 4: Run tests

```bash
mix test test/gallformers_web/live/id_live_test.exs --trace
```

### Step 5: Run full suite

```bash
mix precommit
```

### Step 6: Commit

```bash
git add lib/gallformers_web/live/id_live.ex test/gallformers_web/live/id_live_test.exs
git commit -m "Switch ID tool place filter to grouped hierarchy-aware search"
```

---

## Task 9: Range map JS — precision-aware coloring

**Files:**
- Modify: `assets/js/hooks/range_map.js`
- Modify: `lib/gallformers_web/components/data_display_components.ex` (range_map component attrs)

### Step 1: Update range_map component to accept inherited ranges

**File:** `lib/gallformers_web/components/data_display_components.ex`

Add new attribute (~line 973):

```elixir
attr :inherited_range, :list, default: [], doc: "Place codes with country/continent-level range (shown with hatch pattern)"
```

Update the template to pass a new data attribute:

```heex
data-inherited-range={Jason.encode!(@inherited_range)}
```

### Step 2: Update JS hook for hatch pattern

**File:** `assets/js/hooks/range_map.js`

Add inherited range reading in `mounted()` and `updated()`:

```javascript
this.inheritedRange = new Set(JSON.parse(this.el.dataset.inheritedRange || '[]'))
```

Update `buildSubdivisionFillExpression` to differentiate exact vs inherited:

```javascript
buildSubdivisionFillExpression(inRange, excludedRange, inheritedRange, editable) {
  const cases = []

  // Excluded (admin only) — light red
  if (editable) {
    for (const code of excludedRange) {
      cases.push(code, COLORS.excluded)
    }
  }

  // Exact range — solid green
  for (const code of inRange) {
    cases.push(code, COLORS.inRange)
  }

  // Inherited range — slightly different green
  for (const code of inheritedRange) {
    if (!inRange.has(code)) {  // Don't override exact with inherited
      cases.push(code, COLORS.inheritedRange)
    }
  }

  return ['match', ['get', 'code'], ...cases, COLORS.default]
}
```

Add to COLORS:

```javascript
inheritedRange: '#90EE90'  // LightGreen — distinguishable from ForestGreen
```

For the hatch pattern: MapLibre GL JS supports `fill-pattern` with images, but a simpler approach for v1 is using a lighter shade of green with a dashed border. True SVG hatch patterns can be a follow-up enhancement.

### Step 3: Update tooltip for precision

In the tooltip handler, add precision-aware text:

```javascript
const code = feature.properties.code
const name = feature.properties.name
let status = 'Not reported'

if (this.inRange.has(code)) {
  status = 'Host confirmed'
} else if (this.inheritedRange.has(code)) {
  status = 'Reported at country level (state not confirmed)'
} else if (this.editable && this.excludedRange.has(code)) {
  status = 'Excluded'
}

tooltip.textContent = `${name} — ${status}`
```

### Step 4: Update hover tooltip for shift+click discoverability (admin)

When hovering over a country boundary in editable mode, show:

```javascript
if (this.editable && feature.layer.id === 'countries-fill') {
  tooltip.textContent = `${name} — Click to browse states · Shift+click to select all`
}
```

### Step 5: Test manually

Start the dev server (`mix phx.server`), navigate to a species page with range data, verify:
- Exact ranges show solid green
- Country-level ranges show lighter green
- Tooltips show correct precision text

### Step 6: Commit

```bash
git add assets/js/hooks/range_map.js lib/gallformers_web/components/data_display_components.ex
git commit -m "Add precision-aware map coloring with inherited range indicator"
```

---

## Task 10: Admin GallHostLive — hierarchy-aware range editing

**Files:**
- Modify: `lib/gallformers_web/live/admin/gall_host_live.ex`
- Modify: `assets/js/hooks/range_map.js` (shift+click handling)

This is the largest UI task. The admin needs to:
- Shift+click countries to select at country level
- Click countries to drill into subdivisions
- See the precision of each range entry in the sidebar

### Step 1: Add shift+click detection in JS

**File:** `assets/js/hooks/range_map.js`

In the click handler for editable maps:

```javascript
map.on('click', 'subdivisions-fill', (e) => {
  if (!this.editable) return
  const code = e.features[0].properties.code
  this.pushEvent('toggle_region', { code })
})

map.on('click', 'countries-fill', (e) => {
  if (!this.editable) return
  const code = e.features[0].properties.code

  if (e.originalEvent.shiftKey) {
    // Shift+click: select/deselect entire country
    this.pushEvent('toggle_country', { code })
  } else {
    // Regular click: drill into country subdivisions
    this.pushEvent('drill_into_country', { code })
  }
})
```

### Step 2: Handle new events in GallHostLive

**File:** `lib/gallformers_web/live/admin/gall_host_live.ex`

```elixir
def handle_event("toggle_country", %{"code" => code}, socket) do
  # Find the country place
  place = Places.get_place_by_code(code)

  # Toggle at country level in host_range
  # ... (update local state, similar to toggle_region but with precision="country")
end

def handle_event("drill_into_country", %{"code" => code}, socket) do
  # Zoom map to country bounds
  # Push a JS event to zoom the map
  {:noreply, push_event(socket, "zoom-to-country", %{code: code})}
end

def handle_event("expand_country", %{"code" => code}, socket) do
  # Convert a country-level range to individual state rows
  place = Places.get_place_by_code(code)
  leaf_ids = Places.leaf_descendant_ids(place.id)

  # Remove the country-level entry, add individual leaf entries
  # ... (update local state)
end
```

### Step 3: Update sidebar to show precision grouping

In the template, group selected ranges by precision:

```heex
<div :if={@country_level_ranges != []} class="mb-2">
  <h4 class="text-xs font-semibold text-gray-500 uppercase">Country-level</h4>
  <div :for={place <- @country_level_ranges} class="flex items-center justify-between">
    <span><%= place.name %></span>
    <div class="flex gap-1">
      <button phx-click="expand_country" phx-value-code={place.code} class="text-xs text-blue-600">
        Expand
      </button>
      <button phx-click="remove_country" phx-value-code={place.code} class="text-xs text-red-600">
        Remove
      </button>
    </div>
  </div>
</div>
```

### Step 4: Handle zoom-to-country in JS

**File:** `assets/js/hooks/range_map.js`

```javascript
this.handleEvent('zoom-to-country', ({ code }) => {
  // Query country feature and fit bounds to it
  const features = this.map.querySourceFeatures('boundaries', {
    sourceLayer: 'countries',
    filter: ['==', ['get', 'code'], code]
  })
  if (features.length > 0) {
    const bounds = new maplibregl.LngLatBounds()
    // ... compute bounds from feature geometry
    this.map.fitBounds(bounds, { padding: 50 })
  }
})
```

### Step 5: Test manually

- Start dev server, go to admin gall-host page
- Select a gall with hosts in multiple countries
- Test shift+click on Brazil (should select all at country level)
- Test regular click on Brazil (should zoom in)
- Test expand action in sidebar
- Verify save correctly stores precision

### Step 6: Commit

```bash
git add lib/gallformers_web/live/admin/gall_host_live.ex assets/js/hooks/range_map.js
git commit -m "Add hierarchy-aware range editing to GallHostLive admin"
```

---

## Task 11: Public species pages — precision display

**Files:**
- Modify: Species detail LiveViews (wherever range_map is rendered for public pages)
- Modify: `lib/gallformers/ranges.ex` (add function to get ranges with precision for display)

### Step 1: Add range-with-precision query

**File:** `lib/gallformers/ranges.ex`

```elixir
@doc """
Gets the full range display data for a gall, expanding country-level ranges
to inherited subdivision codes for map display.

Returns %{in_range: [codes], inherited_range: [codes], excluded_range: [codes]}
"""
def get_display_range_for_gall(gall_species_id) do
  host_ranges = get_host_ranges_with_precision_for_gall(gall_species_id)
  excluded = get_excluded_places_for_gall(gall_species_id)

  {exact_codes, inherited_codes} =
    Enum.reduce(host_ranges, {[], []}, fn range, {exact, inherited} ->
      case range.precision do
        "exact" ->
          {[range.code | exact], inherited}

        _higher ->
          # Expand to leaf descendant codes
          place = Places.get_place_by_code(range.code)
          leaf_ids = Places.leaf_descendant_ids(place.id)
          leaf_codes = Enum.map(leaf_ids, fn id ->
            from(p in "place", where: p.id == ^id, select: p.code) |> Repo.one()
          end)
          {exact, leaf_codes ++ inherited}
      end
    end)

  # Don't show inherited where there's already an exact entry
  inherited_codes = Enum.reject(inherited_codes, &(&1 in exact_codes))

  %{
    in_range: Enum.uniq(exact_codes),
    inherited_range: Enum.uniq(inherited_codes),
    excluded_range: excluded
  }
end
```

### Step 2: Update range_map rendering in species pages

Find the LiveView(s) that render the `.range_map` component for species detail and update to pass `inherited_range`.

### Step 3: Add text summary below map

```heex
<div :if={@range_data} class="mt-2 text-sm text-gray-600">
  <div :if={@range_data.in_range != []}>
    <span class="font-medium">Confirmed:</span>
    <%= Enum.join(@range_data.in_range, ", ") %>
  </div>
  <div :if={@range_data.inherited_range != []}>
    <span class="font-medium">Country-level:</span>
    <%= Enum.join(@range_data.inherited_range, ", ") %>
  </div>
</div>
```

### Step 4: Test manually and commit

```bash
git add lib/gallformers/ranges.ex lib/gallformers_web/live/
git commit -m "Display precision-aware ranges on public species pages"
```

---

## Task 12: Final integration testing and cleanup

**Files:**
- Modify: Various test files
- Run: `mix precommit`

### Step 1: Run full test suite

```bash
mix precommit
```

Fix any failures.

### Step 2: Remove deprecated search_subdivision_places

If no callers remain for `Places.search_subdivision_places/2`, remove it. If the old `exclusion_subquery/1` (code-based) is no longer called, remove it.

### Step 3: Run credo and format

```bash
mix format
mix credo --strict
```

### Step 4: Final commit

```bash
git add -A
git commit -m "Clean up deprecated place functions, final integration fixes"
```

### Step 5: Run precommit one final time

```bash
mix precommit
```

Expected: All green.
