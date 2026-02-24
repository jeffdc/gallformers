# Range Precision System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add precision-aware range editing (country-level vs exact) with a country drill-down panel in admin forms, update public display terminology, and distinguish precision levels in ID tool results.

**Architecture:** The `host_range.precision` column already exists. The main work is: (1) a new `CountryDrillDown` LiveComponent for the admin panel UX, (2) updating the host form and gall-host page to track precision-aware state, (3) updating the RangeMap JS hook to support drill-down zoom and a new `drill_down_country` event, (4) updating public page hover text, and (5) tagging ID tool results with match quality.

**Tech Stack:** Phoenix LiveView, LiveComponents, Ecto, MapLibre GL JS, PMTiles, SQLite

**Design doc:** `docs/plans/2026-02-19-range-precision-design.md`

---

### Task 1: Remove continent precision level from schemas

Drop `continent` from valid precisions. It's unused in practice and the design specifies only `exact` and `country`.

**Files:**
- Modify: `lib/gallformers/ranges/host_range.ex:16`
- Modify: `lib/gallformers/ranges/gall_range_exclusion.ex:19`
- Modify: `lib/gallformers/ranges.ex:364` (the `_higher` catch-all in `split_by_precision`)
- Test: `test/gallformers/ranges_test.exs`

**Step 1: Update HostRange schema**

In `lib/gallformers/ranges/host_range.ex`, line 16, change:
```elixir
@valid_precisions ~w(exact country continent)
```
to:
```elixir
@valid_precisions ~w(exact country)
```

**Step 2: Update GallRangeExclusion schema**

In `lib/gallformers/ranges/gall_range_exclusion.ex`, line 19, change:
```elixir
@valid_precisions ~w(exact country continent)
```
to:
```elixir
@valid_precisions ~w(exact country)
```

**Step 3: Tighten `split_by_precision` catch-all**

In `lib/gallformers/ranges.ex`, lines 358-374, change the `_higher` match to explicitly match `"country"`:

```elixir
defp split_by_precision(host_ranges) do
  Enum.reduce(host_ranges, {[], []}, fn range, {exact, inherited} ->
    case range.precision do
      "exact" ->
        {[range.code | exact], inherited}

      "country" ->
        leaf_ids = Places.leaf_descendant_ids(range.place_id)

        leaf_codes =
          from(p in "place", where: p.id in ^leaf_ids, select: p.code)
          |> Repo.all()

        {exact, leaf_codes ++ inherited}
    end
  end)
end
```

**Step 4: Add test for invalid precision rejection**

In `test/gallformers/ranges_test.exs`, add a test that changeset rejects `"continent"`:

```elixir
test "rejects continent precision" do
  changeset =
    HostRange.changeset(%HostRange{}, %{
      species_id: 1,
      place_id: 1,
      precision: "continent"
    })

  assert %{precision: ["is invalid"]} = errors_on(changeset)
end
```

**Step 5: Run tests**

Run: `mix test test/gallformers/ranges_test.exs`
Expected: All pass

**Step 6: Commit**

```
Remove continent precision level — only exact and country are supported
```

---

### Task 2: Update host form state to track precision

The admin host form currently stores `@places` as a flat list of codes. It needs to track which entries are exact vs country-level.

**Files:**
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex`
- Modify: `lib/gallformers/plants.ex:496-511` (`save_place_changes`)
- Test: `test/gallformers_web/live/admin/host_live/form_test.exs`
- Test: `test/gallformers/plants_test.exs`

**Step 1: Change how places are loaded in the form**

In `lib/gallformers_web/live/admin/host_live/form.ex`, change the place loading (around line 83) from:

```elixir
places = Ranges.get_places_for_host(host_id)
```

to:

```elixir
place_entries = Ranges.get_places_for_host_with_precision(host_id)
exact_places = place_entries |> Enum.filter(&(&1.precision == "exact")) |> Enum.map(& &1.code)
country_places = place_entries |> Enum.filter(&(&1.precision == "country")) |> Enum.map(& &1.code)
```

Update the assigns (around lines 94-95) from:

```elixir
|> assign(:original_places, places)
|> assign(:places, places)
```

to:

```elixir
|> assign(:original_exact_places, exact_places)
|> assign(:original_country_places, country_places)
|> assign(:exact_places, exact_places)
|> assign(:country_places, country_places)
```

**Step 2: Update `build_default_assigns` (lines 321-346)**

Change the default place assigns from:

```elixir
|> assign(:original_places, [])
|> assign(:places, [])
```

to:

```elixir
|> assign(:original_exact_places, [])
|> assign(:original_country_places, [])
|> assign(:exact_places, [])
|> assign(:country_places, [])
```

**Step 3: Compute combined `@in_range` and `@inherited_range` for the map**

Add a helper that computes what the map needs from the two lists. This runs after every change to `exact_places` or `country_places`:

```elixir
defp compute_map_range(socket) do
  exact = socket.assigns.exact_places
  country_codes = socket.assigns.country_places
  all_places = socket.assigns.all_places
  place_by_code = Map.new(all_places, &{&1.code, &1})

  # Expand country codes to leaf descendants
  inherited =
    country_codes
    |> Enum.flat_map(fn code ->
      case Map.get(place_by_code, code) do
        %{id: id} ->
          leaf_ids = Places.leaf_descendant_ids(id)
          id_to_code = Map.new(all_places, &{&1.id, &1.code})
          Enum.map(leaf_ids, &Map.get(id_to_code, &1)) |> Enum.reject(&is_nil/1)

        nil ->
          []
      end
    end)
    |> Enum.uniq()
    |> Enum.reject(&(&1 in exact))

  socket
  |> assign(:in_range, exact)
  |> assign(:inherited_range, inherited)
end
```

Call this after every places change (toggle_region, toggle_country, select_all, etc.).

**Step 4: Update the range_map in the template (around line 759)**

Change from:

```heex
<.range_map
  id="host-range-map"
  in_range={@places}
  excluded_range={[]}
  editable
  class="border border-gray-300 rounded bg-gray-50 min-h-[300px]"
/>
```

to:

```heex
<.range_map
  id="host-range-map"
  in_range={@in_range}
  inherited_range={@inherited_range}
  editable
  class="border border-gray-300 rounded bg-gray-50 min-h-[300px]"
/>
```

**Step 5: Update `toggle_region` (lines 304-313)**

This toggles individual states — always exact precision. Change to operate on `exact_places`:

```elixir
defp toggle_region(socket, code) do
  place = Enum.find(socket.assigns.all_places, &(&1.code == code))

  if place do
    new_exact = toggle_place_code(socket.assigns.exact_places, code)

    socket
    |> assign(:exact_places, new_exact)
    |> compute_map_range()
    |> mark_dirty()
  else
    socket
  end
end
```

**Step 6: Update `toggle_country` (lines 278-300)**

This now opens the drill-down panel instead of bulk-toggling. Replace the current implementation:

```elixir
defp toggle_country(%{assigns: %{mode: mode}} = socket, _code) when mode != :edit, do: socket

defp toggle_country(socket, code) do
  case Places.get_place_by_code(code) do
    nil ->
      socket

    place ->
      # Leaf country (no subdivisions): toggle directly as exact
      leaf_ids = Places.leaf_descendant_ids(place.id)

      if leaf_ids == [place.id] do
        new_exact = toggle_place_code(socket.assigns.exact_places, code)

        socket
        |> assign(:exact_places, new_exact)
        |> compute_map_range()
        |> mark_dirty()
      else
        # Country with subdivisions: open drill-down panel
        send_update(GallformersWeb.Admin.CountryDrillDown,
          id: "country-drill-down",
          action: {:open, place}
        )

        socket
      end
  end
end
```

**Step 7: Remove `select_all_places` and `deselect_all_places` handlers (lines 242-260)**

Delete these handlers and remove the corresponding buttons from the template. These are replaced by the per-country select/deselect in the drill-down panel.

**Step 8: Update `save_place_changes` in `lib/gallformers/plants.ex` (lines 496-511)**

Change from computing place_ids from a flat code list to building `{place_id, precision}` tuples:

```elixir
defp save_place_changes(host_id, %{
       original_exact_places: original_exact,
       original_country_places: original_country,
       exact_places: exact_places,
       country_places: country_places,
       all_places: all_places
     }) do
  place_code_to_id = Map.new(all_places, &{&1.code, &1.id})

  original_set = MapSet.new(original_exact ++ original_country)
  current_set = MapSet.new(exact_places ++ country_places)

  if original_set != current_set do
    entries =
      Enum.map(exact_places, fn code ->
        {Map.get(place_code_to_id, code), "exact"}
      end) ++
        Enum.map(country_places, fn code ->
          {Map.get(place_code_to_id, code), "country"}
        end)

    entries = Enum.reject(entries, fn {id, _} -> is_nil(id) end)
    Ranges.update_host_places(host_id, entries)
  end
end
```

**Step 9: Update the `save_host` function call (around lines 439-443)**

Change the `place_changes` map from:

```elixir
place_changes: %{
  original_places: socket.assigns.original_places,
  current_places: socket.assigns.places,
  all_places: socket.assigns.all_places
}
```

to:

```elixir
place_changes: %{
  original_exact_places: socket.assigns.original_exact_places,
  original_country_places: socket.assigns.original_country_places,
  exact_places: socket.assigns.exact_places,
  country_places: socket.assigns.country_places,
  all_places: socket.assigns.all_places
}
```

**Step 10: Update place reload after save (around line 455)**

Change from:

```elixir
places = Ranges.get_places_for_host(host_id)
```

to the same precision-aware loading from Step 1:

```elixir
place_entries = Ranges.get_places_for_host_with_precision(host_id)
exact_places = place_entries |> Enum.filter(&(&1.precision == "exact")) |> Enum.map(& &1.code)
country_places = place_entries |> Enum.filter(&(&1.precision == "country")) |> Enum.map(& &1.code)
```

And update the assigns accordingly.

**Step 11: Write tests**

Test that saving with precision tuples persists correctly, and that the form loads precision-aware data.

**Step 12: Run tests**

Run: `mix test test/gallformers_web/live/admin/host_live/ test/gallformers/plants_test.exs`
Expected: All pass

**Step 13: Commit**

```
Update host form to track range precision (exact vs country)
```

---

### Task 3: Build the CountryDrillDown LiveComponent

This is the panel that slides in beside the map when a curator clicks a country.

**Files:**
- Create: `lib/gallformers_web/live/admin/country_drill_down.ex`
- Test: `test/gallformers_web/live/admin/country_drill_down_test.exs`

**Step 1: Write tests for the component**

```elixir
defmodule GallformersWeb.Admin.CountryDrillDownTest do
  use GallformersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias GallformersWeb.Admin.CountryDrillDown
  alias Gallformers.Places

  describe "rendering" do
    test "renders closed state by default" do
      html =
        render_component(CountryDrillDown,
          id: "drill-down",
          exact_places: [],
          country_places: [],
          all_places: Places.list_all_places()
        )

      refute html =~ "Country-level range"
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/gallformers_web/live/admin/country_drill_down_test.exs`
Expected: FAIL — module does not exist

**Step 3: Implement the LiveComponent**

Create `lib/gallformers_web/live/admin/country_drill_down.ex`:

```elixir
defmodule GallformersWeb.Admin.CountryDrillDown do
  @moduledoc """
  LiveComponent for the country drill-down panel in admin range editing.

  When a curator clicks a country on the range map, this panel slides in
  showing:
  - A toggle for country-level range (imprecise)
  - A checkbox list of subdivisions (exact precision)
  - Select all / Deselect all bulk buttons
  """
  use GallformersWeb, :live_component

  alias Gallformers.Places

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       open: false,
       country: nil,
       subdivisions: [],
       country_level_on: false
     )}
  end

  @impl true
  def update(%{action: {:open, country}}, socket) do
    subdivisions =
      Places.get_children(country.id)
      |> Enum.sort_by(& &1.name)

    country_code = country.code
    country_level_on = country_code in socket.assigns.country_places

    {:ok,
     assign(socket,
       open: true,
       country: country,
       subdivisions: subdivisions,
       country_level_on: country_level_on
     )}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, Map.take(assigns, [:exact_places, :country_places, :all_places, :id]))}
  end

  @impl true
  def handle_event("close", _params, socket) do
    notify_parent(socket, :zoom_out)
    {:noreply, assign(socket, open: false, country: nil)}
  end

  @impl true
  def handle_event("toggle_country_level", _params, socket) do
    new_val = !socket.assigns.country_level_on
    code = socket.assigns.country.code

    notify_parent(socket, {:set_country_level, code, new_val})
    {:noreply, assign(socket, country_level_on: new_val)}
  end

  @impl true
  def handle_event("toggle_subdivision", %{"code" => code}, socket) do
    notify_parent(socket, {:toggle_exact, code})
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    codes = Enum.map(socket.assigns.subdivisions, & &1.code)
    notify_parent(socket, {:select_all_exact, codes})
    {:noreply, socket}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    codes = Enum.map(socket.assigns.subdivisions, & &1.code)
    notify_parent(socket, {:deselect_all_exact, codes})
    {:noreply, socket}
  end

  defp notify_parent(socket, message) do
    send(self(), {__MODULE__, message})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={[
      "transition-all duration-300 overflow-hidden",
      if(@open, do: "w-80 border-l border-gray-200", else: "w-0")
    ]}>
      <div :if={@open} class="p-4 h-full overflow-y-auto">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-gray-900">{@country.name}</h3>
          <button
            type="button"
            phx-click="close"
            phx-target={@myself}
            class="text-gray-400 hover:text-gray-600"
            aria-label="Close panel"
          >
            <.icon name="ph-x" class="size-5" />
          </button>
        </div>

        <%!-- Country-level toggle --%>
        <div class="mb-4 p-3 bg-gray-50 rounded-lg">
          <label class="flex items-center justify-between cursor-pointer">
            <span class="text-sm font-medium text-gray-700">Country-level range</span>
            <.toggle
              name="country_level"
              checked={@country_level_on}
              phx-click="toggle_country_level"
              phx-target={@myself}
            />
          </label>
          <p :if={@country_level_on} class="mt-2 text-xs text-gray-500">
            All states shown as probable — check individual states to mark as documented.
          </p>
        </div>

        <%!-- Bulk buttons --%>
        <div class="flex gap-2 mb-3">
          <button
            type="button"
            phx-click="select_all"
            phx-target={@myself}
            class="text-xs px-2 py-1 rounded border border-gray-300 hover:bg-gray-50"
          >
            Select all
          </button>
          <button
            type="button"
            phx-click="deselect_all"
            phx-target={@myself}
            class="text-xs px-2 py-1 rounded border border-gray-300 hover:bg-gray-50"
          >
            Deselect all
          </button>
        </div>

        <%!-- Subdivision list --%>
        <ul class="space-y-1">
          <li :for={subdiv <- @subdivisions} class="flex items-center">
            <label class={[
              "flex items-center gap-2 w-full px-2 py-1.5 rounded text-sm cursor-pointer hover:bg-gray-50",
              subdiv.code in @exact_places && "bg-green-50",
              subdiv.code not in @exact_places && @country_level_on && "bg-emerald-50/50"
            ]}>
              <input
                type="checkbox"
                checked={subdiv.code in @exact_places}
                phx-click="toggle_subdivision"
                phx-target={@myself}
                phx-value-code={subdiv.code}
                class="rounded border-gray-300 text-green-600 focus:ring-green-500"
              />
              <span>{subdiv.name}</span>
              <span class="ml-auto text-xs text-gray-400">{subdiv.code}</span>
            </label>
          </li>
        </ul>
      </div>
    </div>
    """
  end
end
```

**Step 4: Run tests**

Run: `mix test test/gallformers_web/live/admin/country_drill_down_test.exs`
Expected: Pass

**Step 5: Commit**

```
Add CountryDrillDown LiveComponent for admin range editing
```

---

### Task 4: Wire CountryDrillDown into the host form

Connect the component to the host form so clicking a country opens the panel and panel events update form state.

**Files:**
- Modify: `lib/gallformers_web/live/admin/host_live/form.ex`

**Step 1: Add the component to the template**

In the template, wrap the range map section in a flex container and add the component:

```heex
<div class="flex">
  <div class="flex-1">
    <.range_map
      id="host-range-map"
      in_range={@in_range}
      inherited_range={@inherited_range}
      editable
      class="border border-gray-300 rounded bg-gray-50 min-h-[300px]"
    />
  </div>
  <.live_component
    module={GallformersWeb.Admin.CountryDrillDown}
    id="country-drill-down"
    exact_places={@exact_places}
    country_places={@country_places}
    all_places={@all_places}
  />
</div>
```

**Step 2: Handle messages from the component**

Add `handle_info` clauses for the messages the component sends:

```elixir
@impl true
def handle_info({CountryDrillDown, {:set_country_level, code, true}}, socket) do
  new_country = Enum.uniq([code | socket.assigns.country_places])

  socket =
    socket
    |> assign(:country_places, new_country)
    |> compute_map_range()
    |> mark_dirty()

  {:noreply, socket}
end

def handle_info({CountryDrillDown, {:set_country_level, code, false}}, socket) do
  new_country = Enum.reject(socket.assigns.country_places, &(&1 == code))

  socket =
    socket
    |> assign(:country_places, new_country)
    |> compute_map_range()
    |> mark_dirty()

  {:noreply, socket}
end

def handle_info({CountryDrillDown, {:toggle_exact, code}}, socket) do
  new_exact = toggle_place_code(socket.assigns.exact_places, code)

  socket =
    socket
    |> assign(:exact_places, new_exact)
    |> compute_map_range()
    |> mark_dirty()

  {:noreply, socket}
end

def handle_info({CountryDrillDown, {:select_all_exact, codes}}, socket) do
  new_exact = Enum.uniq(socket.assigns.exact_places ++ codes)

  socket =
    socket
    |> assign(:exact_places, new_exact)
    |> compute_map_range()
    |> mark_dirty()

  {:noreply, socket}
end

def handle_info({CountryDrillDown, {:deselect_all_exact, codes}}, socket) do
  new_exact = Enum.reject(socket.assigns.exact_places, &(&1 in codes))

  socket =
    socket
    |> assign(:exact_places, new_exact)
    |> compute_map_range()
    |> mark_dirty()

  {:noreply, socket}
end

def handle_info({CountryDrillDown, :zoom_out}, socket) do
  # Push event to JS to zoom map back to hemisphere
  {:noreply, push_event(socket, "range-zoom-out", %{})}
end
```

**Step 3: Push zoom-to-country event when panel opens**

In the `toggle_country` handler (from Task 2, Step 6), after `send_update`, also push a JS event:

```elixir
socket
|> push_event("range-zoom-to-country", %{code: country.code})
```

**Step 4: Write integration tests**

Test the full flow: click country → panel opens → toggle country level → toggle subdivisions → save.

**Step 5: Run tests**

Run: `mix test test/gallformers_web/live/admin/host_live/`
Expected: All pass

**Step 6: Commit**

```
Wire CountryDrillDown into host admin form
```

---

### Task 5: Add drill-down support to RangeMap JS hook

The JS hook needs to handle zoom-to-country and zoom-out events, and change click behavior so country clicks push `drill_down_country` instead of `toggle_country`.

**Files:**
- Modify: `assets/js/hooks/range_map.js`

**Step 1: Add event listeners for zoom events**

In `mounted()`, after the existing `range-update` handler (around line 136), add:

```javascript
this.handleEvent('range-zoom-to-country', ({ code }) => {
  this.zoomToCountry(code)
})

this.handleEvent('range-zoom-out', () => {
  this.fitToRange(true)
})
```

**Step 2: Implement `zoomToCountry` method**

Add after `fitToRange`:

```javascript
zoomToCountry(code) {
  if (!this.map || !this.map.isStyleLoaded()) return

  // Query country features to get bounds
  const features = this.map.querySourceFeatures('boundaries', {
    sourceLayer: 'countries'
  })

  let minLng = Infinity, minLat = Infinity, maxLng = -Infinity, maxLat = -Infinity
  let matched = 0

  for (const feature of features) {
    if (feature.properties.code !== code) continue
    matched++
    forEachCoord(feature.geometry, (lng, lat) => {
      if (lng < minLng) minLng = lng
      if (lng > maxLng) maxLng = lng
      if (lat < minLat) minLat = lat
      if (lat > maxLat) maxLat = lat
    })
  }

  // Also check subdivisions for this country (iso_a2 property)
  const subdivFeatures = this.map.querySourceFeatures('boundaries', {
    sourceLayer: 'subdivisions'
  })

  for (const feature of subdivFeatures) {
    if (feature.properties.iso_a2 !== code) continue
    matched++
    forEachCoord(feature.geometry, (lng, lat) => {
      if (lng < minLng) minLng = lng
      if (lng > maxLng) maxLng = lng
      if (lat < minLat) minLat = lat
      if (lat > maxLat) maxLat = lat
    })
  }

  if (matched > 0) {
    this.map.fitBounds([[minLng, minLat], [maxLng, maxLat]], {
      padding: 40,
      maxZoom: 8,
      animate: true
    })
  }
}
```

**Step 3: Update click handler for country drill-down**

In `setupInteractions`, the editable click handler (around line 440-451), change the country click from `toggle_country` to `drill_down_country` when shift is NOT held:

```javascript
if (this.editable) {
  if (isRealSubdiv) {
    // Regular click on a subdivision: toggle single region
    this.pushEvent('toggle_region', { code: subdivCode })
  } else if (countryCode) {
    // Click on a country: open drill-down panel
    this.pushEvent('toggle_country', { code: countryCode })
  }
}
```

Remove the shift+click branch entirely — shift+click is no longer needed since the panel has "Select all" / "Deselect all" buttons.

**Step 4: Run the dev server and manually verify**

Run: `mix phx.server`
Verify: Click a country on the host admin map → panel slides in, map zooms

**Step 5: Commit**

```
Add country drill-down zoom support to RangeMap JS hook
```

---

### Task 6: Wire CountryDrillDown into gall-host exclusion page

Same drill-down pattern, adapted for exclusions.

**Files:**
- Modify: `lib/gallformers_web/live/admin/gall_host_live.ex`
- Create: `lib/gallformers_web/live/admin/exclusion_drill_down.ex`
- Test: `test/gallformers_web/live/admin/gall_host_live_test.exs`

**Step 1: Create ExclusionDrillDown LiveComponent**

Create `lib/gallformers_web/live/admin/exclusion_drill_down.ex` — similar to CountryDrillDown but simpler:
- No country-level toggle
- Checkboxes represent exclusions (checked = excluded)
- Bulk buttons: "Exclude all" / "Include all"
- Messages: `{:toggle_exclusion, code}`, `{:exclude_all, codes}`, `{:include_all, codes}`, `:zoom_out`

**Step 2: Update gall-host page toggle_country handler**

Change from bulk-toggling exclusions to opening the ExclusionDrillDown panel. Leaf countries still toggle directly.

**Step 3: Add the component to the gall-host template**

Wrap the range map and component in a flex container, same pattern as the host form.

**Step 4: Handle messages from ExclusionDrillDown**

Add `handle_info` clauses for exclusion panel messages. These update `@excluded_place_ids` and `@excluded_places`, then call `assign_range_data` and `push_range_update`.

**Step 5: Write tests**

Test the exclusion drill-down flow: click country → panel opens → toggle exclusions → save.

**Step 6: Run tests**

Run: `mix test test/gallformers_web/live/admin/gall_host_live_test.exs`
Expected: All pass

**Step 7: Commit**

```
Add ExclusionDrillDown to gall-host admin page
```

---

### Task 7: Update public page hover text and legend

Change terminology on host and gall detail pages.

**Files:**
- Modify: `assets/js/hooks/range_map.js` (hover tooltips)
- Modify: `lib/gallformers_web/live/host_live.ex` (legend text)
- Modify: `lib/gallformers_web/live/gall_live.ex` (legend text)

**Step 1: Update JS hover tooltips**

In `range_map.js`, `setupInteractions` subdivision hover handler, change:

```javascript
// Old
status = ' — Host confirmed'
// ...
status = ' — Reported at country level (state not confirmed)'
```

to:

```javascript
// New
status = ' — Documented'
// ...
status = ' — Country-level record only'
```

Update the same text in the countries-fill hover handler.

**Step 2: Update host_live.ex legend**

Find the legend text (around line 591):

```
= reported at country level (state not confirmed)
```

Change to:

```
= Country-level record only
```

And change the green legend text from implied "Host confirmed" to "Documented".

**Step 3: Update gall_live.ex legend**

Same changes as host_live.ex (around line 516).

**Step 4: Remove excluded range from public gall page**

Verify that `excluded_range` is not passed to the public range_map component. If it is, remove it so excluded states appear white (not red) on the public page.

Check `lib/gallformers_web/live/gall_live.ex` for the range_map call — if it passes `excluded_range`, change to `excluded_range={[]}`.

**Step 5: Run tests**

Run: `mix test test/gallformers_web/live/host_live_test.exs test/gallformers_web/live/gall_live_test.exs`
Expected: All pass

**Step 6: Commit**

```
Update public page range terminology to Documented / Country-level record only
```

---

### Task 8: Add precision-distinguished results to ID tool

Tag ID results with match quality when a place filter is active.

**Files:**
- Modify: `lib/gallformers/galls/identification.ex:77-99` (`filter_galls` and `apply_place_filter`)
- Modify: `lib/gallformers_web/live/id_live.ex` (gall_card component, result rendering)
- Test: `test/gallformers/galls/identification_test.exs`
- Test: `test/gallformers_web/live/id_live_test.exs`

**Step 1: Update `filter_galls` to accept and return precision info**

The current `filter_galls` returns a list of maps. When a place filter is active, results need a `:place_match` field (`:documented` or `:country_level`).

Change `apply_place_filter` (lines 397-434) to split into two queries:

```elixir
defp apply_place_filter(query, place_codes, host_ids, genus_id) do
  host_scope = resolve_host_scope(host_ids, genus_id)

  place_ids =
    Enum.map(place_codes, &Ranges.get_place_id_by_code/1)
    |> Enum.reject(&is_nil/1)

  # Exact descendant matches (place itself + its subdivisions)
  descendant_ids = Enum.flat_map(place_ids, &Places.descendant_ids/1) |> Enum.uniq()

  # Ancestor matches (country-level ranges that cover the selected place)
  ancestor_ids = Enum.flat_map(place_ids, &Places.ancestor_ids/1) |> Enum.uniq()

  # IDs that are ONLY in ancestors (not in descendants) indicate country-level matches
  ancestor_only_ids = ancestor_ids -- descendant_ids

  all_matching_place_ids = Enum.uniq(descendant_ids ++ ancestor_ids)

  # Tag results: if a gall matches ONLY via ancestor place IDs, it's country-level
  # This is done post-query via attach_place_match
  case host_scope do
    nil ->
      from [s, gt] in query,
        join: h in GallHost,
        on: h.gall_species_id == s.id,
        join: hr in "host_range",
        on: hr.species_id == h.host_species_id,
        where: hr.place_id in ^all_matching_place_ids,
        where: s.id not in subquery(exclusion_subquery_by_ids(all_matching_place_ids)),
        # Track which match type by selecting min place precision info
        select_merge: %{
          has_exact_place_match:
            fragment(
              "MAX(CASE WHEN ? IN (?) THEN 1 ELSE 0 END)",
              hr.place_id,
              ^descendant_ids
            )
        }

    ids ->
      from [s, gt] in query,
        join: h in GallHost,
        on: h.gall_species_id == s.id,
        join: hr in "host_range",
        on: hr.species_id == h.host_species_id,
        where: hr.place_id in ^all_matching_place_ids,
        where: h.host_species_id in ^ids,
        where: s.id not in subquery(exclusion_subquery_by_ids(all_matching_place_ids)),
        select_merge: %{
          has_exact_place_match:
            fragment(
              "MAX(CASE WHEN ? IN (?) THEN 1 ELSE 0 END)",
              hr.place_id,
              ^descendant_ids
            )
        }
  end
end
```

Note: The `select_merge` with `MAX(CASE...)` requires a `group_by` — this will need careful integration with `select_gall_fields()`. An alternative approach is to do a post-query check: after getting results, query which gall IDs have exact-descendant matches and tag accordingly. This avoids modifying the complex filter chain. Evaluate which is cleaner during implementation.

**Step 2: Pass place_match info through to the LiveView**

In `id_live.ex`, the `load_results` function (line 707) calls `Galls.filter_galls(filter_params)`. If place filter is active, attach a `:place_match` field to each result:

```elixir
defp load_results(socket) do
  filter_params = build_filter_params(socket)
  results = Galls.filter_galls(filter_params)

  # Tag place match quality when a place filter is active
  results =
    if socket.assigns.filters.place do
      attach_place_match_quality(results, socket.assigns.filters.place)
    else
      results
    end

  # ... rest of existing code
end
```

**Step 3: Update gall_card to show the badge**

In `gall_card` (lines 1309-1351), add a badge for country-level matches:

```heex
<span
  :if={@gall[:place_match] == :country_level}
  class="inline-flex items-center px-1.5 py-0.5 text-xs font-medium rounded bg-blue-100 text-blue-700 cursor-help"
  title="This gall occurs on hosts with country-level range records — state-level data unavailable for your selected region."
>
  Country-level
</span>
```

Add this inside the existing badge div alongside the undescribed and non_gall badges.

**Step 4: Write tests**

Test that filtering by a state returns documented matches and country-level matches with correct tagging.

**Step 5: Run tests**

Run: `mix test test/gallformers/galls/identification_test.exs test/gallformers_web/live/id_live_test.exs`
Expected: All pass

**Step 6: Commit**

```
Add precision badge to ID tool results for country-level matches
```

---

### Task 9: Full integration test and cleanup

**Files:**
- All modified files
- Test: E2E tests if needed

**Step 1: Run full precommit**

Run: `mix precommit`
Expected: All checks pass

**Step 2: Manual smoke test**

Start dev server and verify:
1. Host admin: click US → panel opens → toggle country level → check states → save → reload shows correct data
2. Host admin: click leaf country (e.g., Grenada) → toggles directly, no panel
3. Gall-host admin: click country → exclusion panel → exclude states → save
4. Public host page: hover text shows "documented" / "country-level record only"
5. Public gall page: no red exclusions shown, hover text updated
6. ID tool: filter by Florida → see documented and country-level badges

**Step 3: Run full CI check**

Run: `make ci`
Expected: All pass

**Step 4: Final commit if any cleanup needed**

```
Clean up range precision integration
```
