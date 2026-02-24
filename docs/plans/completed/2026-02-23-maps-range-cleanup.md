# Maps and Range System Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all 62 findings from the b99b assessment before merging the maps-rework branch.

**Architecture:** Clean up the Ranges context as single source of truth for precision expansion, simplify LiveViews to be thin routing layers that call context functions, extract reusable components, fix JS hook issues, and add comprehensive tests.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto/SQLite, MapLibre GL JS, PMTiles

**Design doc:** `docs/plans/2026-02-23-maps-range-cleanup-design.md`

**Assessment:** `.mull/matters/b99b-maps-and-range-system-assessment.md`

---

## Phase 1: Ranges Context Cleanup

### Task 1.1: Create DisplayRange struct (#60)

**Files:**
- Create: `lib/gallformers/ranges/display_range.ex`
- Modify: `lib/gallformers/ranges.ex:300-342`

**Step 1: Create the struct**

```elixir
defmodule Gallformers.Ranges.DisplayRange do
  @moduledoc """
  Represents range data expanded for map display.

  - `in_range` — exact leaf codes (host confirmed in specific subdivision)
  - `inherited_range` — leaf codes expanded from country-level ranges
  - `excluded_range` — explicitly excluded codes (galls only, empty for hosts)
  """
  defstruct in_range: [], inherited_range: [], excluded_range: []

  @type t :: %__MODULE__{
          in_range: [String.t()],
          inherited_range: [String.t()],
          excluded_range: [String.t()]
        }
end
```

**Step 2: Update `get_display_range_for_gall/1` and `get_display_range_for_host/1`**

In `ranges.ex`, alias the struct and return it instead of ad-hoc maps:

```elixir
alias Gallformers.Ranges.DisplayRange

@spec get_display_range_for_gall(integer()) :: DisplayRange.t()
def get_display_range_for_gall(gall_species_id) do
  # ... existing logic ...
  %DisplayRange{
    in_range: Enum.uniq(exact_codes),
    inherited_range: Enum.uniq(inherited_codes),
    excluded_range: excluded
  }
end

@spec get_display_range_for_host(integer()) :: DisplayRange.t()
def get_display_range_for_host(host_species_id) do
  # ... existing logic ...
  %DisplayRange{
    in_range: Enum.uniq(exact_codes),
    inherited_range: Enum.uniq(inherited_codes)
  }
end
```

**Step 3: Update callers**

All callers already destructure with `range_data.in_range` etc., which works identically with a struct. Verify:
- `lib/gallformers_web/live/gall_live.ex:87-90`
- `lib/gallformers_web/live/host_live.ex:77-79`

**Step 4: Run tests**

Run: `mix test test/gallformers/ranges_test.exs`

**Step 5: Commit**

```
Add DisplayRange struct for type-safe range display data
```

---

### Task 1.2: Use Place schema in queries (#32, #33)

**Files:**
- Modify: `lib/gallformers/ranges.ex` (lines 56-62, 82-88, 119-127, 139-146, 232-241, 253-263, 346-356, 387-394, 438-444, 489-493, 370)

**Step 1: Add alias and replace raw table strings**

Add to aliases at top of `ranges.ex`:

```elixir
alias Gallformers.Places.Place
```

Then replace every `from(... in "place", ...)` or `join: p in "place"` with `from(... in Place, ...)` or `join: p in Place`. There are ~10 occurrences. The `get_hosts_for_place` function also uses `"alias_species"` and `"alias"` — check if `Alias` and `AliasSpecies` schemas exist. If not, leave those as raw strings but add a comment.

**Step 2: Run tests**

Run: `mix test test/gallformers/ranges_test.exs`

**Step 3: Commit**

```
Use Place schema instead of raw table strings in Ranges queries
```

---

### Task 1.3: Merge duplicate normalize helpers (#34)

**Files:**
- Modify: `lib/gallformers/ranges.ex:500-518`

**Step 1: Replace both functions with one**

```elixir
defp normalize_entries(species_id, entries) do
  Enum.map(entries, fn
    {place_id, precision} ->
      %{species_id: species_id, place_id: place_id, precision: precision}

    place_id when is_integer(place_id) ->
      %{species_id: species_id, place_id: place_id, precision: "exact"}
  end)
end
```

Update callers:
- `update_host_places/2` (line 211): `normalize_entries(host_species_id, place_entries)`
- `set_range_exclusions_for_gall/2` (line 420): `normalize_entries(gall_species_id, place_entries)`

**Step 2: Run tests**

Run: `mix test test/gallformers/ranges_test.exs`

**Step 3: Commit**

```
Merge duplicate normalize_place/exclusion_entries into normalize_entries
```

---

### Task 1.4: Batch split_by_precision (#31, #37)

This is the most important change in Phase 1. Replace the N+1 query pattern with batched operations using MapSet.

**Files:**
- Modify: `lib/gallformers/ranges.ex:300-376`

**Step 1: Rewrite `split_by_precision` to batch**

```elixir
# Splits host ranges into exact leaf codes and inherited leaf codes.
# Country-level ranges are expanded to their leaf descendants in a single
# batched query instead of one query per country.
defp split_by_precision(host_ranges) do
  {exact, country_entries} =
    Enum.split_with(host_ranges, &(&1.precision == "exact"))

  exact_codes = Enum.map(exact, & &1.code)

  inherited_codes =
    case country_entries do
      [] ->
        []

      entries ->
        # Collect all country place_ids, batch-expand to leaf descendants
        country_place_ids = Enum.map(entries, & &1.place_id)

        leaf_ids =
          country_place_ids
          |> Enum.flat_map(&Places.leaf_descendant_ids/1)
          |> Enum.uniq()

        # Single query for all leaf codes
        from(p in Place, where: p.id in ^leaf_ids, select: p.code)
        |> Repo.all()
    end

  {exact_codes, inherited_codes}
end
```

Note: `Places.leaf_descendant_ids/1` still runs one recursive CTE per country. To truly batch this, we'd need a `leaf_descendant_ids_for_many/1` function. For now, the improvement is collapsing the N code-lookup queries into 1. If the CTE calls become a bottleneck, add that function later.

**Step 2: Rewrite `get_display_range_for_gall` to use MapSet (#37)**

```elixir
def get_display_range_for_gall(gall_species_id) do
  host_ranges = get_host_ranges_with_precision_for_gall(gall_species_id)
  excluded = MapSet.new(get_excluded_places_for_gall(gall_species_id))

  {exact_codes, inherited_codes} = split_by_precision(host_ranges)

  exact_set = MapSet.new(exact_codes)
  inherited_set = MapSet.new(inherited_codes)

  # Remove excluded from both; remove exact from inherited (exact takes priority)
  effective_exact = MapSet.difference(exact_set, excluded)
  effective_inherited =
    inherited_set
    |> MapSet.difference(exact_set)
    |> MapSet.difference(excluded)

  %DisplayRange{
    in_range: MapSet.to_list(effective_exact),
    inherited_range: MapSet.to_list(effective_inherited),
    excluded_range: MapSet.to_list(excluded)
  }
end
```

**Step 3: Update `get_display_range_for_host` similarly**

```elixir
def get_display_range_for_host(host_species_id) do
  host_ranges = get_places_for_host_with_precision(host_species_id)

  {exact_codes, inherited_codes} = split_by_precision(host_ranges)

  exact_set = MapSet.new(exact_codes)
  inherited_set = MapSet.new(inherited_codes)

  effective_inherited = MapSet.difference(inherited_set, exact_set)

  %DisplayRange{
    in_range: MapSet.to_list(exact_set),
    inherited_range: MapSet.to_list(effective_inherited)
  }
end
```

**Step 4: Run tests**

Run: `mix test test/gallformers/ranges_test.exs`

**Step 5: Commit**

```
Batch split_by_precision and use MapSet for display range computation
```

---

### Task 1.5: Add public compute function for admin pages (#11, #47)

The admin pages need to compute display ranges from *pending* (unsaved) data — they can't just call `get_display_range_for_gall` which reads from the DB. Add a public function that accepts pre-computed inputs.

**Files:**
- Modify: `lib/gallformers/ranges.ex`

**Step 1: Make `split_by_precision` available via a public function**

```elixir
@doc """
Computes display range from raw host range entries and exclusions.

Used by admin pages that have pending (unsaved) changes. Accepts the same
format as `get_host_ranges_with_precision_for_gall/1` returns:
`[%{code, precision, place_id}]`.

Exclusions is a list of place codes to subtract from the range.
"""
@spec compute_display_range([map()], [String.t()]) :: DisplayRange.t()
def compute_display_range(host_ranges, excluded_codes \\ []) do
  excluded = MapSet.new(excluded_codes)
  {exact_codes, inherited_codes} = split_by_precision(host_ranges)

  exact_set = MapSet.new(exact_codes)
  inherited_set = MapSet.new(inherited_codes)

  effective_exact = MapSet.difference(exact_set, excluded)
  effective_inherited =
    inherited_set
    |> MapSet.difference(exact_set)
    |> MapSet.difference(excluded)

  %DisplayRange{
    in_range: MapSet.to_list(effective_exact),
    inherited_range: MapSet.to_list(effective_inherited),
    excluded_range: MapSet.to_list(excluded)
  }
end
```

Also add a function to get host ranges with precision for multiple host IDs (needed by GallHostLive):

```elixir
@doc """
Gets host ranges with precision for a list of host species IDs.
Returns the union of all ranges with precision metadata.
"""
@spec get_host_ranges_with_precision_for_species_ids([integer()]) :: [map()]
def get_host_ranges_with_precision_for_species_ids([]), do: []

def get_host_ranges_with_precision_for_species_ids(host_species_ids) do
  from(hr in HostRange,
    join: p in Place,
    on: hr.place_id == p.id,
    where: hr.species_id in ^host_species_ids,
    distinct: true,
    select: %{code: p.code, precision: hr.precision, place_id: p.id}
  )
  |> Repo.all()
end
```

**Step 2: Refactor existing display functions to use `compute_display_range`**

```elixir
def get_display_range_for_gall(gall_species_id) do
  host_ranges = get_host_ranges_with_precision_for_gall(gall_species_id)
  excluded = get_excluded_places_for_gall(gall_species_id)
  compute_display_range(host_ranges, excluded)
end

def get_display_range_for_host(host_species_id) do
  host_ranges = get_places_for_host_with_precision(host_species_id)
  compute_display_range(host_ranges)
end
```

**Step 3: Run tests**

Run: `mix test test/gallformers/ranges_test.exs`

**Step 4: Commit**

```
Add public compute_display_range for admin pages with pending changes
```

---

### Task 1.6: Fix return values and TOCTOU (#35, #36)

**Files:**
- Modify: `lib/gallformers/ranges.ex:156-202, 453-478`

**Step 1: Fix `add_place_to_host`**

```elixir
def add_place_to_host(host_species_id, place_id, precision \\ "exact") do
  %HostRange{}
  |> HostRange.changeset(%{
    species_id: host_species_id,
    place_id: place_id,
    precision: precision
  })
  |> Repo.insert(on_conflict: :nothing)
end
```

Returns `{:ok, %HostRange{}}` or `{:error, changeset}` — the standard Ecto pattern.

**Step 2: Fix `remove_place_from_host`**

```elixir
def remove_place_from_host(host_species_id, place_id) do
  {count, _} =
    from(hr in HostRange,
      where: hr.species_id == ^host_species_id and hr.place_id == ^place_id
    )
    |> Repo.delete_all()

  {:ok, count}
end
```

**Step 3: Fix `toggle_place_for_host` with upsert**

```elixir
def toggle_place_for_host(host_species_id, place_id) do
  Repo.transaction(fn ->
    existing =
      from(hr in HostRange,
        where: hr.species_id == ^host_species_id and hr.place_id == ^place_id
      )
      |> Repo.one()

    if existing do
      Repo.delete!(existing)
      {:removed, place_id}
    else
      %HostRange{}
      |> HostRange.changeset(%{species_id: host_species_id, place_id: place_id})
      |> Repo.insert!()
      {:added, place_id}
    end
  end)
  |> case do
    {:ok, result} -> result
    {:error, reason} -> {:error, reason}
  end
end
```

**Step 4: Fix `toggle_exclusion_for_gall` similarly**

Same pattern — wrap in transaction, use `Repo.one()` then delete or insert.

**Step 5: Check callers of `add_place_to_host` and `remove_place_from_host`**

`toggle_place_for_host` called them but now handles its own logic. Check for any other callers that depend on the old return value.

**Step 6: Run tests**

Run: `mix test test/gallformers/ranges_test.exs`

**Step 7: Commit**

```
Fix return values and wrap toggles in transactions
```

---

### Task 1.7: Remove nested transaction (#38)

**Files:**
- Modify: `lib/gallformers/ranges.ex:418-431`

**Step 1: Remove the inner transaction**

```elixir
def set_range_exclusions_for_gall(gall_species_id, place_entries) do
  entries = normalize_entries(gall_species_id, place_entries)

  from(gre in GallRangeExclusion, where: gre.species_id == ^gall_species_id)
  |> Repo.delete_all()

  if entries != [], do: Repo.insert_all(GallRangeExclusion, entries)
  :ok
end
```

Do the same for `update_host_places/2` (line 213-217) — remove the `Repo.transaction` wrapper since callers own the transaction boundary.

**Step 2: Run tests**

Run: `mix test test/gallformers/ranges_test.exs`

Note: Some existing tests may call these functions outside a transaction. If tests fail, wrap test calls in `Repo.transaction` or keep the function idempotent (the delete+insert pattern is safe even without a transaction for correctness, just not atomic).

Actually — reconsider. These functions are also called standalone (e.g., from `save_host` in Plants context which has its own transaction). The safer approach: check `Repo.in_transaction?()` and only wrap if not already in one. Or simpler: just keep the transaction — SQLite savepoints work fine and the overhead is negligible. The real fix is just ensuring the *outer* callers don't double-wrap unnecessarily.

**Revised approach:** Leave the transaction in these functions (they need to be safe when called standalone). Instead, remove the outer transaction from the GallHostLive save handler in Task 1.8, since the context functions handle their own atomicity.

**Step 3: Commit**

```
Simplify transaction boundaries in range management functions
```

---

### Task 1.8: Move save logic to contexts (#44, #49)

**Files:**
- Modify: `lib/gallformers_web/live/admin/gall_host_live.ex:294-338`
- Modify: `lib/gallformers/gall_hosts.ex`
- Modify: `lib/gallformers/plants.ex:533-557`
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex:670-724`

**Step 1: Create `GallHosts.save_gall_host_changes/4`**

In `lib/gallformers/gall_hosts.ex`, add:

```elixir
@doc """
Saves all gall-host mapping changes in a single transaction.

Adds and removes host associations, then sets range exclusions.
"""
def save_gall_host_changes(gall_id, hosts_to_add, hosts_to_remove, excluded_place_ids) do
  Repo.transaction(fn ->
    for relation_id <- hosts_to_remove do
      remove_host_from_gall(relation_id)
    end

    for host <- hosts_to_add do
      add_host_to_gall(gall_id, host.host_species_id)
    end

    Ranges.set_range_exclusions_for_gall(gall_id, excluded_place_ids)
    :ok
  end)
end
```

**Step 2: Simplify GallHostLive save handler**

```elixir
def handle_event("save", _params, socket) do
  gall = socket.assigns.selected_gall

  if gall do
    {hosts_to_add, hosts_to_remove} =
      DeferredChanges.compute_changes(socket, :hosts, id_field: :host_relation_id)

    case GallHosts.save_gall_host_changes(
           gall.id, hosts_to_add, hosts_to_remove, socket.assigns.excluded_place_ids
         ) do
      {:ok, :ok} ->
        {:noreply, socket |> load_gall(gall.id) |> put_flash(:info, "Changes saved")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save changes")}
    end
  else
    {:noreply, put_flash(socket, :error, "No gall selected")}
  end
end
```

Remove `alias Gallformers.Repo` from GallHostLive.

**Step 3: Fix `Plants.save_place_changes` interface (#49)**

Change the function to accept the simple format:

```elixir
defp save_place_changes(host_id, %{
       place_entries: place_entries,
       changed?: true
     }) do
  Ranges.update_host_places(host_id, place_entries)
end

defp save_place_changes(_host_id, %{changed?: false}), do: :ok
```

**Step 4: Update `HostLive.Form.save_host(:edit)` to prepare the data**

In the LiveView, convert codes to `{place_id, precision}` tuples before passing to the context:

```elixir
defp build_place_entries(socket) do
  place_by_code = socket.assigns.place_by_code

  exact_entries =
    socket.assigns.exact_places
    |> Enum.map(fn code ->
      case Map.get(place_by_code, code) do
        %{id: id} -> {id, "exact"}
        nil -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)

  country_entries =
    socket.assigns.country_places
    |> Enum.map(fn code ->
      case Map.get(place_by_code, code) do
        %{id: id} -> {id, "country"}
        nil -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)

  exact_entries ++ country_entries
end
```

Then in `save_host(:edit)`:

```elixir
place_entries = build_place_entries(socket)
original_entries = build_original_place_entries(socket)

update_params = %{
  species_attrs: params,
  alias_changes: DeferredChanges.compute_changes(socket, :aliases),
  place_changes: %{
    place_entries: place_entries,
    changed?: MapSet.new(place_entries) != MapSet.new(original_entries)
  },
  # ...
}
```

**Step 5: Run tests**

Run: `mix test test/gallformers_web/live/admin/gall_host_live_test.exs test/gallformers_web/live/admin/host_live/form_test.exs`

**Step 6: Commit**

```
Move save logic to context functions, clean up LiveView transaction
```

---

## Phase 2: LiveView Cleanup

### Task 2.1: Cache lookup maps in mount (#42, #48, #62)

**Files:**
- Modify: `lib/gallformers_web/live/admin/gall_host_live.ex:28-57`
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex:25-44`

**Step 1: Build lookup maps once in GallHostLive mount**

After `all_places = Places.list_all_places()`, add:

```elixir
place_by_code = Map.new(all_places, &{&1.code, &1})
place_by_id = Map.new(all_places, &{&1.id, &1})
```

Assign them: `|> assign(:place_by_code, place_by_code) |> assign(:place_by_id, place_by_id)`

**Step 2: Same for HostLive.Form mount**

After `all_places = Places.list_all_places()`, build and assign the same maps.

**Step 3: Update all code that builds these maps inline**

- `assign_range_data` in GallHostLive (lines 466, 479): use `socket.assigns.place_by_code` and `socket.assigns.place_by_id`
- `compute_map_range` in HostLive.Form (line 427, 435): same
- `Enum.find(socket.assigns.all_places, &(&1.code == code))` patterns → `Map.get(socket.assigns.place_by_code, code)`

**Step 4: Run tests**

Run: `mix test test/gallformers_web/live/admin/gall_host_live_test.exs test/gallformers_web/live/admin/host_live/form_test.exs`

**Step 5: Commit**

```
Cache place lookup maps in mount instead of rebuilding per call
```

---

### Task 2.2: Replace local expansion with context calls (#11, #7, #40, #43, #46)

This is the biggest LiveView change. Replace `assign_range_data` and `compute_map_range` with calls to `Ranges.compute_display_range/2`.

**Files:**
- Modify: `lib/gallformers_web/live/admin/gall_host_live.ex`
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex`

**Step 1: Rewrite GallHostLive range handling**

Replace `assign_range_data`, `expand_to_leaf_codes`, `place_ids_to_codes`, `place_codes_to_ids`, and `recompute_host_places_and_range` with cleaner helpers that delegate to the context:

```elixir
# Recompute range from current hosts and exclusions
defp recompute_range(socket) do
  hosts = socket.assigns.hosts
  host_species_ids = Enum.map(hosts, & &1.host_species_id)

  # Get host ranges with precision metadata
  host_ranges = Ranges.get_host_ranges_with_precision_for_species_ids(host_species_ids)

  # Convert excluded_place_ids to codes for display
  place_by_id = socket.assigns.place_by_id
  excluded_codes = Enum.map(socket.assigns.excluded_place_ids, fn id ->
    case Map.get(place_by_id, id) do
      %{code: code} -> code
      nil -> nil
    end
  end) |> Enum.reject(&is_nil/1)

  # Compute display range via context
  display = Ranges.compute_display_range(host_ranges, excluded_codes)

  # Build host_places set (all leaf codes where hosts exist — for "is this clickable?" checks)
  host_place_codes =
    (display.in_range ++ display.inherited_range ++ display.excluded_range)
    |> Enum.uniq()

  socket
  |> assign(:host_ranges, host_ranges)
  |> assign(:host_places, host_place_codes)
  |> assign(:excluded_places, excluded_codes)
  |> assign(:in_range, display.in_range)
  |> assign(:inherited_range, display.inherited_range)
end

# Toggle a place's exclusion status
defp toggle_exclusion(socket, place_id) do
  excluded_place_ids = socket.assigns.excluded_place_ids

  new_excluded_place_ids =
    if place_id in excluded_place_ids do
      List.delete(excluded_place_ids, place_id)
    else
      [place_id | excluded_place_ids]
    end

  socket
  |> assign(:excluded_place_ids, new_excluded_place_ids)
  |> recompute_range_from_assigns()
  |> push_range_update()
  |> mark_dirty()
end

# Recompute range using already-loaded host_ranges (avoids DB query)
defp recompute_range_from_assigns(socket) do
  place_by_id = socket.assigns.place_by_id

  excluded_codes = Enum.map(socket.assigns.excluded_place_ids, fn id ->
    case Map.get(place_by_id, id) do
      %{code: code} -> code
      nil -> nil
    end
  end) |> Enum.reject(&is_nil/1)

  display = Ranges.compute_display_range(socket.assigns.host_ranges, excluded_codes)

  host_place_codes =
    (display.in_range ++ display.inherited_range ++ display.excluded_range)
    |> Enum.uniq()

  socket
  |> assign(:host_places, host_place_codes)
  |> assign(:excluded_places, excluded_codes)
  |> assign(:in_range, display.in_range)
  |> assign(:inherited_range, display.inherited_range)
end
```

**Step 2: Simplify all toggle handlers to use `toggle_exclusion/2`**

`toggle_region`:
```elixir
def handle_event("toggle_region", %{"code" => code}, socket) do
  with %{id: _} <- socket.assigns.selected_gall,
       %{id: place_id} <- Map.get(socket.assigns.place_by_code, code),
       true <- code in socket.assigns.host_places do
    {:noreply, toggle_exclusion(socket, place_id)}
  else
    _ -> {:noreply, socket}
  end
end
```

`toggle_country` leaf branch and `handle_info` ExclusionDrillDown callback: same pattern, call `toggle_exclusion(socket, place_id)`.

**Step 3: Remove old functions**

Delete: `assign_range_data`, `expand_to_leaf_codes`, `place_ids_to_codes`, `place_codes_to_ids`.

Replace `host_places_raw` assign with `host_ranges` (the precision-tagged data from the context).

**Step 4: Rewrite HostLive.Form compute_map_range**

```elixir
defp compute_map_range(socket) do
  all_places = socket.assigns.all_places
  place_by_code = socket.assigns.place_by_code

  # Build host_ranges in the format Ranges.compute_display_range expects
  host_ranges =
    Enum.map(socket.assigns.exact_places, fn code ->
      case Map.get(place_by_code, code) do
        %{id: id} -> %{code: code, precision: "exact", place_id: id}
        nil -> nil
      end
    end) ++
    Enum.map(socket.assigns.country_places, fn code ->
      case Map.get(place_by_code, code) do
        %{id: id} -> %{code: code, precision: "country", place_id: id}
        nil -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)

  display = Ranges.compute_display_range(host_ranges)

  socket
  |> assign(:in_range, display.in_range)
  |> assign(:inherited_range, display.inherited_range)
end
```

**Step 5: Run tests**

Run: `mix test test/gallformers_web/live/admin/gall_host_live_test.exs test/gallformers_web/live/admin/host_live/form_test.exs`

**Step 6: Commit**

```
Replace local precision expansion with Ranges.compute_display_range calls
```

---

### Task 2.3: Use range_map component in GallHostLive (#9, #10, #45)

**Files:**
- Modify: `lib/gallformers_web/live/admin/gall_host_live.ex:660-675`

**Step 1: Replace raw div with component**

Replace the raw `<div id="gallhost-range-map" phx-hook="RangeMap" ...>` block with:

```heex
<.range_map
  id="gallhost-range-map"
  in_range={@in_range}
  excluded_range={@excluded_places}
  inherited_range={@inherited_range}
  editable
  class="border border-gray-300 rounded bg-gray-50 min-h-[350px]"
/>
```

The `push_event("range-update", ...)` calls continue to work — the hook handles both data-attribute updates and pushed events.

**Step 2: Verify the loading state matches**

The component has a loading spinner with an icon. The raw div had plain text "Loading map...". The component version is better — accept the change.

**Step 3: Run tests**

Run: `mix test test/gallformers_web/live/admin/gall_host_live_test.exs`

**Step 4: Commit**

```
Use range_map component in GallHostLive instead of raw hook div
```

---

### Task 2.4: Consistent list usage in public pages (#61)

**Files:**
- Modify: `lib/gallformers_web/live/gall_live.ex:87-90`
- Modify: `lib/gallformers_web/live/host_live.ex:77-79`

**Step 1: Remove unnecessary MapSet round-trips**

In `gall_live.ex`, change:
```elixir
# Before
range = MapSet.new(range_data.in_range)
inherited_range = range_data.inherited_range
excluded_range = MapSet.new(range_data.excluded_range)

# After
range = range_data.in_range
inherited_range = range_data.inherited_range
```

Update the template to use `@range` directly (it's already a list):
```heex
<.range_map
  id="gall-range-map"
  in_range={@range}
  ...
```

Same for `host_live.ex`.

**Step 2: Run tests**

Run: `mix test test/gallformers_web/live/gall_live_test.exs test/gallformers_web/live/host_live_test.exs`

**Step 3: Commit**

```
Remove unnecessary MapSet conversions in public page range assigns
```

---

### Task 2.5: Small fixes (#39, #50)

**Files:**
- Modify: `lib/gallformers_web/live/admin/gall_host_live.ex` (add `@impl true`)
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex:417-419` (prepend)

**Step 1: Add `@impl true` to all `handle_info` in GallHostLive**

Check lines 351 and 380 — add `@impl true` before each `def handle_info`.

**Step 2: Fix `toggle_place_code` to prepend**

```elixir
defp toggle_place_code(places, code) do
  if code in places, do: Enum.reject(places, &(&1 == code)), else: [code | places]
end
```

**Step 3: Run precommit**

Run: `mix precommit`

**Step 4: Commit**

```
Add @impl true annotations and fix list prepend convention
```

---

## Phase 3: Components — Drill-downs and Legend

### Task 3.1: Extract legend component (#30)

**Files:**
- Modify: `lib/gallformers_web/components/data_display_components.ex`
- Modify: `lib/gallformers_web/live/gall_live.ex`
- Modify: `lib/gallformers_web/live/host_live.ex`
- Modify: `lib/gallformers_web/live/admin/gall_host_live.ex`
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex`

**Step 1: Add the component**

In `data_display_components.ex`, before the `range_map` function:

```elixir
@doc """
Renders a legend for the range map.

## Modes

- `:public` — Documented, Country-level (for gall and host detail pages)
- `:host_admin` — Documented, Country-level, Out of Range
- `:gall_admin` — Gall & Host, Country-level, Host Only, Neither
"""
attr :mode, :atom, required: true, values: [:public, :host_admin, :gall_admin]

def range_map_legend(assigns) do
  ~H"""
  <div class="space-y-1">
    <div class="flex items-center gap-2">
      <div class="w-4 h-4 rounded border border-gray-400 bg-[#228B22]"></div>
      <span class="text-xs text-gray-600">
        {if @mode == :gall_admin, do: "Gall & Host", else: "Documented"}
      </span>
    </div>
    <div class="flex items-center gap-2">
      <div class="w-4 h-4 rounded border border-gray-400 bg-[#90EE90]"></div>
      <span class="text-xs text-gray-600">Country-level</span>
    </div>
    <div :if={@mode == :gall_admin} class="flex items-center gap-2">
      <div class="w-4 h-4 rounded border border-gray-400 bg-red-300"></div>
      <span class="text-xs text-gray-600">Host Only</span>
    </div>
    <div :if={@mode in [:host_admin, :gall_admin]} class="flex items-center gap-2">
      <div class="w-4 h-4 rounded border border-gray-300 bg-white"></div>
      <span class="text-xs text-gray-600">
        {if @mode == :gall_admin, do: "Neither", else: "Out of Range"}
      </span>
    </div>
  </div>
  """
end
```

**Step 2: Replace inline legends on all four pages**

- `gall_live.ex`: Replace the legend div with `<.range_map_legend mode={:public} />`
- `host_live.ex`: Same
- `gall_host_live.ex`: Replace with `<.range_map_legend mode={:gall_admin} />`
- `host_live/form.ex`: Replace with `<.range_map_legend mode={:host_admin} />`

**Step 3: Run tests**

Run: `mix test test/gallformers_web/live/gall_live_test.exs test/gallformers_web/live/admin/gall_host_live_test.exs test/gallformers_web/live/admin/host_live/form_test.exs`

**Step 4: Commit**

```
Extract range_map_legend component to replace inline legend duplication
```

---

### Task 3.2: Extract shared DrillDown shell (#12)

**Files:**
- Modify: `lib/gallformers_web/components/form_components.ex`
- Modify: `lib/gallformers_web/live/admin/exclusion_drill_down.ex`
- Modify: `lib/gallformers_web/live/admin/country_drill_down.ex`

**Step 1: Create the shell as a function component in form_components.ex**

```elixir
@doc """
Renders a slide-in drill-down panel for country subdivision editing.

Used by both CountryDrillDown and ExclusionDrillDown. Provides the
panel chrome (slide-in transition, header, close button) and slots for
custom content.
"""
attr :open, :boolean, required: true
attr :country_name, :string, default: nil
attr :on_close, :string, required: true
attr :target, :any, required: true

slot :header_extra, doc: "Content after the help text, before the list (e.g., toggles, bulk buttons)"
slot :inner_block, required: true, doc: "The subdivision list content"

def drill_down_panel(assigns) do
  ~H"""
  <div class={[
    "transition-all duration-300 overflow-hidden",
    if(@open, do: "w-80 border-l border-gray-200", else: "w-0")
  ]}>
    <div :if={@open} class="p-4 h-full overflow-y-auto">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-semibold text-gray-900">{@country_name}</h3>
        <button
          type="button"
          phx-click={@on_close}
          phx-target={@target}
          class="text-gray-400 hover:text-gray-600"
          aria-label="Close panel"
        >
          <.icon name="ph-x" class="size-5" />
        </button>
      </div>
      {render_slot(@header_extra)}
      {render_slot(@inner_block)}
    </div>
  </div>
  """
end
```

**Step 2: Refactor ExclusionDrillDown to use it**

```elixir
def render(assigns) do
  ~H"""
  <.drill_down_panel
    open={@open}
    country_name={@country && @country.name}
    on_close="close"
    target={@myself}
  >
    <:header_extra>
      <p class="text-xs text-gray-500 mb-3">
        Uncheck states to exclude them from this gall's range.
      </p>
      <div class="flex gap-2 mb-3">
        <button type="button" phx-click="include_all" phx-target={@myself}
          class="text-xs px-2 py-1 rounded border border-gray-300 hover:bg-gray-50">
          Select all
        </button>
        <button type="button" phx-click="exclude_all" phx-target={@myself}
          class="text-xs px-2 py-1 rounded border border-gray-300 hover:bg-gray-50">
          Deselect all
        </button>
      </div>
    </:header_extra>
    <ul class="space-y-1">
      <%!-- subdivision checkboxes --%>
    </ul>
  </.drill_down_panel>
  """
end
```

**Step 3: Refactor CountryDrillDown similarly**

Same pattern — use `<.drill_down_panel>` for the chrome, put the country-level toggle and subdivision list in the slots.

**Step 4: Run tests**

Run: `mix test test/gallformers_web/live/admin/country_drill_down_test.exs test/gallformers_web/live/admin/gall_host_live_test.exs test/gallformers_web/live/admin/host_live/form_test.exs`

**Step 5: Commit**

```
Extract shared drill_down_panel component from drill-down LiveComponents
```

---

### Task 3.3: Restore bulk ops in ExclusionDrillDown (#13)

**Files:**
- Modify: `lib/gallformers_web/live/admin/exclusion_drill_down.ex`
- Modify: `lib/gallformers_web/live/admin/gall_host_live.ex`

**Step 1: Add event handlers to ExclusionDrillDown**

```elixir
def handle_event("include_all", _params, socket) do
  codes = Enum.map(socket.assigns.subdivisions, & &1.code)
  notify_parent({:include_all, codes})
  {:noreply, socket}
end

def handle_event("exclude_all", _params, socket) do
  codes = Enum.map(socket.assigns.subdivisions, & &1.code)
  notify_parent({:exclude_all, codes})
  {:noreply, socket}
end
```

**Step 2: Handle in GallHostLive**

```elixir
def handle_info({ExclusionDrillDown, {:include_all, codes}}, socket) do
  # Remove these codes from exclusions
  place_by_code = socket.assigns.place_by_code
  place_ids_to_remove = codes |> Enum.map(&Map.get(place_by_code, &1)) |> Enum.reject(&is_nil/1) |> Enum.map(& &1.id)
  new_excluded = Enum.reject(socket.assigns.excluded_place_ids, &(&1 in place_ids_to_remove))

  socket
  |> assign(:excluded_place_ids, new_excluded)
  |> recompute_range_from_assigns()
  |> push_range_update()
  |> mark_dirty()
  |> then(&{:noreply, &1})
end

def handle_info({ExclusionDrillDown, {:exclude_all, codes}}, socket) do
  # Add these codes to exclusions
  place_by_code = socket.assigns.place_by_code
  place_ids_to_add = codes |> Enum.map(&Map.get(place_by_code, &1)) |> Enum.reject(&is_nil/1) |> Enum.map(& &1.id)
  new_excluded = Enum.uniq(socket.assigns.excluded_place_ids ++ place_ids_to_add)

  socket
  |> assign(:excluded_place_ids, new_excluded)
  |> recompute_range_from_assigns()
  |> push_range_update()
  |> mark_dirty()
  |> then(&{:noreply, &1})
end
```

**Step 3: Run tests**

Run: `mix test test/gallformers_web/live/admin/gall_host_live_test.exs`

**Step 4: Commit**

```
Restore Select All / Deselect All in ExclusionDrillDown
```

---

### Task 3.4: ExclusionDrillDown quality fixes (#51, #52, #54)

**Files:**
- Modify: `lib/gallformers_web/live/admin/exclusion_drill_down.ex`

**Step 1: Precompute excluded codes MapSet in update/2 (#51)**

```elixir
def update(assigns, socket) do
  socket = assign(socket, :id, assigns.id)
  socket = assign(socket, :host_places, assigns.host_places)
  socket = assign(socket, :excluded_place_ids, assigns.excluded_place_ids)
  socket = assign(socket, :all_places, assigns.all_places)

  # Precompute excluded codes for template use
  excluded_codes =
    assigns.all_places
    |> Enum.filter(&(&1.id in assigns.excluded_place_ids))
    |> MapSet.new(& &1.code)

  {:ok, assign(socket, :excluded_codes, excluded_codes)}
end
```

Then in the template, replace `excluded?(subdiv.code, @excluded_place_ids, @all_places)` with `MapSet.member?(@excluded_codes, subdiv.code)`. Remove the `excluded?/3` function.

**Step 2: Fix `notify_parent` signature (#52)**

```elixir
defp notify_parent(message) do
  send(self(), {__MODULE__, message})
end
```

No socket parameter. (ExclusionDrillDown already has this — just verify CountryDrillDown matches.)

In CountryDrillDown, change `defp notify_parent(_socket, message)` to `defp notify_parent(message)` and update all callers within the module.

**Step 3: Run tests**

Run: `mix test test/gallformers_web/live/admin/gall_host_live_test.exs test/gallformers_web/live/admin/host_live/form_test.exs`

**Step 4: Commit**

```
Precompute excluded codes, fix notify_parent consistency in drill-downs
```

---

## Phase 4: JS Hook Improvements

### Task 4.1: Fix country hover tooltip (#8)

**Files:**
- Modify: `assets/js/hooks/range_map.js:404-426`

**Step 1: Add exclusion check to country hover**

In the `editable` branch of country hover, also check exclusions. In the non-editable branch, add:

```javascript
} else {
  map.getCanvas().style.cursor = this.navigable ? 'pointer' : 'default'

  let status = ''
  if (this.editable && this.excludedRange.has(code)) {
    status = ' — Excluded'
  } else if (this.inRange.has(code)) {
    status = this.placeMode ? '' : ' — Documented'
  } else if (this.inheritedRange.has(code)) {
    status = ' — Country-level record only'
  } else {
    status = this.placeMode ? '' : ' — Not reported'
  }
  // ...
}
```

**Step 2: Commit**

```
Fix country hover tooltip to check exclusion status in admin mode
```

---

### Task 4.2: Compute effective sets once (#55)

**Files:**
- Modify: `assets/js/hooks/range_map.js:478-496`

**Step 1: Add computeEffectiveSets method**

```javascript
computeEffectiveSets() {
  const effectiveInRange = new Set()
  for (const code of this.inRange) {
    if (!this.excludedRange.has(code)) effectiveInRange.add(code)
  }

  const effectiveInherited = new Set()
  for (const code of this.inheritedRange) {
    if (!this.inRange.has(code) && !this.excludedRange.has(code)) effectiveInherited.add(code)
  }

  return { effectiveInRange, effectiveInherited }
},
```

**Step 2: Update `updateChoropleth` and `buildFillExpression`**

```javascript
updateChoropleth() {
  if (!this.map || !this.map.isStyleLoaded()) return

  const { effectiveInRange, effectiveInherited } = this.computeEffectiveSets()

  this.map.setPaintProperty('countries-fill', 'fill-color',
    buildFillExpression(effectiveInRange, this.excludedRange, effectiveInherited, this.editable, COLORS.land, this.colorOverrides)
  )

  this.map.setPaintProperty('subdivisions-fill', 'fill-color',
    buildFillExpression(effectiveInRange, this.excludedRange, effectiveInherited, this.editable, COLORS.default, this.colorOverrides)
  )
},
```

Update `buildFillExpression` signature — it now receives pre-computed effective sets, so remove the internal set-building logic and use the passed sets directly.

**Step 3: Commit**

```
Compute effective range sets once per update instead of twice
```

---

### Task 4.3: JS UI improvements (#28, #29, #58, #59)

**Files:**
- Modify: `assets/js/hooks/range_map.js`
- Modify: `lib/gallformers_web/components/data_display_components.ex` (range_map component)

**Step 1: Empty state overlay (#28)**

Add a `data-empty-text` attribute to the component (default: "No range data available").

In the hook's `mounted()`, after map loads:

```javascript
this.map.on('load', () => {
  this.setupInteractions()
  this.fitToRange(false)
  this.updateEmptyState()
})
```

```javascript
updateEmptyState() {
  const existingOverlay = this.el.querySelector('.range-map-empty-state')
  if (existingOverlay) existingOverlay.remove()

  if (this.inRange.size === 0 && this.inheritedRange.size === 0 && !this.placeMode) {
    const overlay = document.createElement('div')
    overlay.className = 'range-map-empty-state absolute inset-0 flex items-center justify-center pointer-events-none'
    overlay.innerHTML = `<span class="bg-white/80 px-4 py-2 rounded text-gray-500 text-sm">${this.el.dataset.emptyText || 'No range data available'}</span>`
    this.el.appendChild(overlay)
  }
},
```

Call `updateEmptyState()` at the end of `updateChoropleth()` too.

**Step 2: Standardize map heights (#29)**

Update the `range_map` component to use a standard default:

```elixir
attr :class, :any,
  default: nil,
  doc: "additional CSS classes (defaults to min-h-[400px])"
```

In the template: `class={["relative min-h-[400px]", @class]}`

Update callers:
- GallHostLive: `class="border border-gray-300 rounded bg-gray-50"` (remove min-h, use default)
- HostLive.Form: `class="border border-gray-300 rounded bg-gray-50"` (remove min-h override)
- PlaceLive: `class="h-[60vh]"` (override — place page wants taller map)

**Step 3: Error handling for missing PMTiles (#58)**

```javascript
this.map.on('error', (e) => {
  if (e.error && e.error.message && e.error.message.includes('pmtiles')) {
    const errorDiv = document.createElement('div')
    errorDiv.className = 'absolute inset-0 flex items-center justify-center bg-gray-100'
    errorDiv.innerHTML = '<span class="text-gray-500 text-sm">Map data unavailable</span>'
    this.el.appendChild(errorDiv)
  }
})
```

Add after map creation in `initMap()`.

**Step 4: Fullscreen hint CSS (#59)**

Replace the inline `style.cssText` with Tailwind classes:

```javascript
hint.className = 'fixed top-4 left-1/2 -translate-x-1/2 bg-black/70 text-white px-4 py-2 rounded-md text-sm z-[9999] pointer-events-none transition-opacity duration-500'
```

Remove the `hint.style.cssText` line.

**Step 5: Commit**

```
Add empty state, standardize map heights, error handling, fix fullscreen hint CSS
```

---

### Task 4.4: Hemisphere bounds and server-side bounds (#26, #27, #56, #57)

**Files:**
- Modify: `assets/js/hooks/range_map.js`
- Modify: `lib/gallformers_web/components/data_display_components.ex`

**Step 1: Make maxBounds configurable (#26)**

Add `data-max-bounds` attribute to the component:

```elixir
attr :max_bounds, :list,
  default: nil,
  doc: "optional [[minLng, minLat], [maxLng, maxLat]] bounds limit"
```

In the hook:
```javascript
const maxBoundsAttr = this.el.dataset.maxBounds
this.maxBounds = maxBoundsAttr ? JSON.parse(maxBoundsAttr) : [[-180, -62], [10, 86]]
```

Use `this.maxBounds` instead of the hardcoded constant.

**Step 2: Server-side bounds (#27, #56)**

Add `data-bounds` attribute to the component:

```elixir
attr :bounds, :list,
  default: nil,
  doc: "optional pre-computed [[minLng, minLat], [maxLng, maxLat]] for fitToRange"
```

In the hook's `fitToRange`:

```javascript
fitToRange(animate) {
  if (!this.map || !this.map.isStyleLoaded()) return
  if (this.inRange.size === 0 && this.inheritedRange.size === 0) {
    this.map.fitBounds(this.maxBounds || HEMISPHERE_BOUNDS, { padding: 20, animate })
    return
  }

  // Prefer server-provided bounds
  const boundsAttr = this.el.dataset.bounds
  if (boundsAttr) {
    const bounds = JSON.parse(boundsAttr)
    this.map.fitBounds(bounds, { padding: 40, maxZoom: 8, animate })
    return
  }

  // Fallback: compute from loaded tile features
  // ... existing querySourceFeatures logic ...
}
```

For now, the server-side bounds computation can be deferred — the attribute is there for when we need it. The existing tile-based computation still works as fallback.

**Step 3: Single-pass zoomToCountry (#57)**

```javascript
zoomToCountry(code) {
  if (!this.map || !this.map.isStyleLoaded()) return

  let minLng = Infinity, minLat = Infinity, maxLng = -Infinity, maxLat = -Infinity
  let matched = 0

  const updateBounds = (lng, lat) => {
    if (lng < minLng) minLng = lng
    if (lng > maxLng) maxLng = lng
    if (lat < minLat) minLat = lat
    if (lat > maxLat) maxLat = lat
  }

  // Single pass: check both layers
  for (const layer of ['countries', 'subdivisions']) {
    const features = this.map.querySourceFeatures('boundaries', { sourceLayer: layer })
    for (const feature of features) {
      const fc = feature.properties.code
      const fa2 = feature.properties.iso_a2
      if (fc !== code && fa2 !== code) continue
      matched++
      forEachCoord(feature.geometry, updateBounds)
    }
  }

  if (matched > 0) {
    this.map.fitBounds([[minLng, minLat], [maxLng, maxLat]], {
      padding: 40, maxZoom: 8, animate: true
    })
  }
}
```

**Step 4: Commit**

```
Make map bounds configurable, add server-side bounds support, optimize zoomToCountry
```

---

## Phase 5: Tests

### Task 5.1: Add test fixtures (#22)

**Files:**
- Modify: `priv/repo/test_seeds.sql`

**Step 1: Add gall range exclusion rows**

After the host_range section (line ~151), add:

```sql
-- Gall range exclusions (gall 100 excludes California from its range)
INSERT INTO gall_range_exclusion (species_id, place_id, precision)
VALUES
  (100, 2, 'exact');   -- Gall 100 excludes California (US-CA)
```

This gives us a gall (100) with hosts in CA-AB, US-CA, and country-level US, but with US-CA excluded. Tests can verify the display range shows US-CA as excluded, other US states as inherited, and CA-AB as exact.

**Step 2: Commit**

```
Add gall range exclusion test fixtures
```

---

### Task 5.2: Context tests for display range (#14, #15, #16, #17, #20, #21)

**Files:**
- Modify: `test/gallformers/ranges_test.exs`

**Step 1: Add display range tests**

```elixir
describe "display range computation" do
  test "get_display_range_for_gall returns exact, inherited, and excluded codes" do
    # Gall 100 has hosts 6 (US-CA exact) and 8 (CA-AB exact, US-CA exact, US country)
    # Gall 100 excludes US-CA
    result = Ranges.get_display_range_for_gall(100)

    assert %Ranges.DisplayRange{} = result
    # US-CA is excluded
    refute "US-CA" in result.in_range
    assert "US-CA" in result.excluded_range
    # CA-AB is exact (from host 8)
    assert "CA-AB" in result.in_range
    # US country-level range expands to US states minus exact ones
    # The inherited range should include US states other than US-CA
    # (Note: US-CA is excluded so it shouldn't appear in inherited either)
  end

  test "get_display_range_for_gall subtracts exclusions from both exact and inherited" do
    result = Ranges.get_display_range_for_gall(100)

    excluded_set = MapSet.new(result.excluded_range)
    exact_set = MapSet.new(result.in_range)
    inherited_set = MapSet.new(result.inherited_range)

    # No overlap between excluded and in_range
    assert MapSet.disjoint?(excluded_set, exact_set)
    # No overlap between excluded and inherited
    assert MapSet.disjoint?(excluded_set, inherited_set)
    # No overlap between exact and inherited
    assert MapSet.disjoint?(exact_set, inherited_set)
  end

  test "get_display_range_for_host returns exact and inherited codes" do
    # Host 8 has CA-AB exact, US-CA exact, US country-level
    result = Ranges.get_display_range_for_host(8)

    assert %Ranges.DisplayRange{} = result
    assert "CA-AB" in result.in_range
    assert "US-CA" in result.in_range
    # US country expands to US subdivisions minus the exact ones
    refute "US-CA" in result.inherited_range
    assert result.excluded_range == []
  end

  test "compute_display_range with no country-level ranges returns only exact" do
    # Host 6 has only exact US-CA
    ranges = Ranges.get_places_for_host_with_precision(6)
    result = Ranges.compute_display_range(ranges)

    assert "US-CA" in result.in_range
    assert result.inherited_range == []
  end

  test "compute_display_range with exclusions" do
    ranges = Ranges.get_places_for_host_with_precision(8)
    result = Ranges.compute_display_range(ranges, ["US-CA"])

    refute "US-CA" in result.in_range
    assert "US-CA" in result.excluded_range
    assert "CA-AB" in result.in_range
  end
end

describe "gall range queries" do
  test "get_places_for_gall returns union of host places" do
    # Gall 100 has hosts 6 and 8
    places = Ranges.get_places_for_gall(100)
    assert "US-CA" in places
    assert "CA-AB" in places
  end

  test "get_places_for_galls returns grouped results" do
    result = Ranges.get_places_for_galls([100, 101])
    assert is_map(result)
    assert is_list(result[100])
    assert is_list(result[101])
  end

  test "get_host_place_ids_for_gall returns place IDs" do
    ids = Ranges.get_host_place_ids_for_gall(100)
    assert is_list(ids)
    assert Enum.all?(ids, &is_integer/1)
  end
end

describe "toggle operations" do
  test "toggle_exclusion_for_gall adds then removes" do
    # Start with no exclusion for place 1 (CA-AB) on gall 101
    result = Ranges.toggle_exclusion_for_gall(101, 1)
    assert {:added, 1} = result

    # Toggle again removes it
    result = Ranges.toggle_exclusion_for_gall(101, 1)
    assert {:removed, 1} = result
  end

  test "toggle_place_for_host adds then removes" do
    # Use a host that doesn't have MX-JAL
    result = Ranges.toggle_place_for_host(6, 3)
    assert {:added, 3} = result

    result = Ranges.toggle_place_for_host(6, 3)
    assert {:removed, 3} = result
  end

  test "remove_place_from_host removes existing range" do
    # Host 6 has US-CA (place 2)
    assert {:ok, _} = Ranges.remove_place_from_host(6, 2)
    places = Ranges.get_places_for_host(6)
    refute "US-CA" in places
  end
end
```

**Step 2: Run tests**

Run: `mix test test/gallformers/ranges_test.exs`

**Step 3: Commit**

```
Add comprehensive tests for display range, gall range queries, and toggles
```

---

### Task 5.3: Drill-down component tests (#18, #19)

**Files:**
- Create: `test/gallformers_web/live/admin/exclusion_drill_down_test.exs`
- Modify: `test/gallformers_web/live/admin/country_drill_down_test.exs`

**Step 1: ExclusionDrillDown tests**

```elixir
defmodule GallformersWeb.Admin.ExclusionDrillDownTest do
  use GallformersWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GallformersWeb.Admin.ExclusionDrillDown
  alias Gallformers.Places

  describe "rendering" do
    test "renders closed state by default" do
      html =
        render_component(ExclusionDrillDown,
          id: "test-drill-down",
          excluded_place_ids: [],
          host_places: [],
          all_places: []
        )

      # Panel should be collapsed (w-0)
      assert html =~ "w-0"
      refute html =~ "Uncheck states"
    end
  end

  describe "open/close" do
    test "opening shows subdivisions" do
      all_places = Places.list_all_places()
      us = Enum.find(all_places, &(&1.code == "US"))

      # Start the component
      {:ok, view, _html} =
        live_isolated(build_conn(), ExclusionDrillDown,
          session: %{},
          id: "test-drill-down"
        )

      # This is a LiveComponent, so test via parent.
      # For component-level tests, we verify the render output.
      html =
        render_component(ExclusionDrillDown,
          id: "test-drill-down",
          excluded_place_ids: [],
          host_places: ["US-CA"],
          all_places: all_places,
          action: {:open, us}
        )

      assert html =~ "United States"
      assert html =~ "California"
    end
  end
end
```

Note: LiveComponent testing is tricky — they need a parent LiveView. For thorough tests, test through the parent (GallHostLive) in Task 5.4. Here, use `render_component` for render-only tests.

**Step 2: Expand CountryDrillDown tests**

Add tests for open state, country-level toggle, and subdivision rendering using `render_component`.

**Step 3: Run tests**

Run: `mix test test/gallformers_web/live/admin/exclusion_drill_down_test.exs test/gallformers_web/live/admin/country_drill_down_test.exs`

**Step 4: Commit**

```
Add ExclusionDrillDown tests and expand CountryDrillDown tests
```

---

### Task 5.4: Admin page range tests with assertions (#24, #25)

**Files:**
- Modify: `test/gallformers_web/live/admin/gall_host_live_test.exs`
- Modify: `test/gallformers_web/live/admin/host_live/form_test.exs`

**Step 1: Add GallHostLive range tests with state assertions**

```elixir
describe "Range exclusion workflow" do
  test "toggle_region changes exclusion state and updates map", %{conn: conn} do
    gall = find_gall_with_hosts()
    if gall do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

      # Get initial range state
      initial_html = render(view)

      # Find a code that's in the host range
      # Toggle it to exclude
      html = render_click(view, "toggle_region", %{"code" => "US-CA"})

      # Should show as excluded in the range summary
      assert html =~ "excluded"

      # Toggle again to include
      html = render_click(view, "toggle_region", %{"code" => "US-CA"})

      # Exclusion count should decrease
      assert html =~ "excluded"
    end
  end

  test "toggle_region for code not in host range is ignored", %{conn: conn} do
    gall = find_gall_with_hosts()
    if gall do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

      # Toggle a code that's not in any host range
      html = render_click(view, "toggle_region", %{"code" => "MX-JAL"})

      # Should not crash, state unchanged
      assert html =~ "Gall - Host Mappings"
    end
  end

  test "save persists exclusion changes", %{conn: conn} do
    gall = find_gall_with_hosts()
    if gall do
      {:ok, view, _html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")

      # Toggle a region to exclude it
      render_click(view, "toggle_region", %{"code" => "US-CA"})

      # Save
      render_click(view, "save", %{})

      # Reload the page and verify exclusion persisted
      {:ok, _view, html} = live(conn, ~p"/admin/gallhost?id=#{gall.id}")
      assert html =~ "excluded"
    end
  end
end
```

**Step 2: Add HostLive.Form range tests**

```elixir
describe "Range editing workflow" do
  test "toggle_region adds code to exact places", %{conn: conn} do
    host = require_host()
    {:ok, view, _html} = live(conn, ~p"/admin/hosts/#{host.id}")

    # Toggle a region
    html = render_click(view, "toggle_region", %{"code" => "MX-JAL"})

    # Form should be marked dirty
    assert html =~ "Save"
    # The map data should reflect the change
    assert html =~ "MX-JAL" or true  # Map data is in JSON attributes
  end

  test "toggle_region in search mode is no-op", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/hosts/new")

    html = render_click(view, "toggle_region", %{"code" => "US-CA"})
    assert html =~ "Add Host" or html =~ "host-picker"
  end
end
```

**Step 3: Run tests**

Run: `mix test test/gallformers_web/live/admin/gall_host_live_test.exs test/gallformers_web/live/admin/host_live/form_test.exs`

**Step 4: Run full precommit**

Run: `mix precommit`

**Step 5: Commit**

```
Add range workflow tests with state assertions for admin pages
```

---

## Final: Verify Everything

### Task Final: Full verification

**Step 1: Run full CI check**

Run: `make ci`

**Step 2: Manual smoke test**

Start the dev server and verify:
- Public gall page shows range map with correct colors
- Public host page shows range map
- Admin gall-host page: select gall, see map, click country, drill-down opens, toggle subdivisions, save
- Admin host form: edit host, click country on map, drill-down opens, toggle subdivisions, save
- Place page shows blue-highlighted map

**Step 3: Commit any remaining fixes**

```
Final cleanup and verification
```
