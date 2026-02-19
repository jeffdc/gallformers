# Public Places Experience — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace admin places CRUD with a public places browse tree and hierarchy-aware detail page with clickable range maps.

**Architecture:** Remove admin place LiveViews and CUD context functions. Add `Places.get_places_tree/0` to build a nested hierarchy for the tree browser. Rework `PlaceLive` to use code-based URLs, breadcrumb ancestors, children links, and a range map. Add `navigable` mode to the range map JS hook so clicking a region navigates to `/place/:code`.

**Tech Stack:** Phoenix LiveView, existing `TreeComponents.tree_browser`, MapLibre GL JS + PMTiles range map hook, SQLite recursive CTEs.

**Design doc:** `docs/plans/2026-02-19-public-places-experience-design.md`

---

### Task 1: Remove Admin Places Pages

Delete admin place CRUD and all code only used by it.

**Files:**
- Delete: `lib/gallformers_web/live/admin/place_live/index.ex`
- Delete: `lib/gallformers_web/live/admin/place_live/form.ex`
- Modify: `lib/gallformers_web/router.ex:131-134` (remove 3 admin routes)
- Modify: `lib/gallformers/places.ex:282-338` (remove `change_place`, `create_place`, `update_place`, `delete_place`, `broadcast`)

**Step 1: Remove admin routes from router**

In `lib/gallformers_web/router.ex`, delete these three lines (inside the superadmin scope, lines 131-134):

```elixir
    # Place admin (superadmin only)
    live "/places", Admin.PlaceLive.Index, :index
    live "/places/new", Admin.PlaceLive.Form, :new
    live "/places/:id", Admin.PlaceLive.Form, :edit
```

**Step 2: Delete admin LiveView files**

Delete:
- `lib/gallformers_web/live/admin/place_live/index.ex`
- `lib/gallformers_web/live/admin/place_live/form.ex`

Check if the `place_live/` directory is now empty and delete it too.

**Step 3: Remove CUD functions from Places context**

In `lib/gallformers/places.ex`, delete everything from the `# Admin functions` comment (line 282) through the `broadcast/2` private function (line 338). This removes:
- `change_place/2`
- `create_place/1`
- `update_place/2`
- `delete_place/1`
- `subscribe/0`
- `broadcast/2` (private)

Also remove the PubSub-related alias if present (check imports at top of file).

**Step 4: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation. If anything else references these deleted functions, fix the callers.

**Step 5: Run tests**

Run: `mix test`
Expected: All tests pass. No existing tests cover admin place pages (confirmed — none exist).

**Step 6: Commit**

```bash
git add -A && git commit -m "Remove admin places pages and CUD context functions

Place data is now managed through migrations. Admin UI for flat
place CRUD provided no value with the new hierarchy model."
```

---

### Task 2: Add Context Functions for Place Hierarchy

New query functions needed by the browse and detail pages.

**Files:**
- Modify: `lib/gallformers/places.ex` (add 4 new functions)
- Modify: `test/gallformers/places_test.exs` (add tests)

**Step 1: Write tests for `get_place_by_code!/1`**

In `test/gallformers/places_test.exs`, add a new describe block:

```elixir
describe "get_place_by_code!/1" do
  test "returns place for valid code" do
    place = Places.get_place_by_code!("US-CA")
    assert place.name == "California"
    assert place.code == "US-CA"
  end

  test "raises for invalid code" do
    assert_raise Ecto.NoResultsError, fn ->
      Places.get_place_by_code!("XX-ZZ")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/gallformers/places_test.exs --seed 0`
Expected: FAIL — `get_place_by_code!/1` is undefined.

**Step 3: Implement `get_place_by_code!/1`**

In `lib/gallformers/places.ex`, add after `get_place_by_code/1` (around line 34):

```elixir
@doc """
Gets a place by code, raising if not found.
"""
@spec get_place_by_code!(String.t()) :: Place.t()
def get_place_by_code!(code) do
  from(p in Place, where: p.code == ^code)
  |> Repo.one!()
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/gallformers/places_test.exs --seed 0`
Expected: PASS.

**Step 5: Write tests for `get_ancestors/1`**

```elixir
describe "get_ancestors/1" do
  test "returns ancestors from root to parent for a subdivision" do
    california = Places.get_place_by_code!("US-CA")
    ancestors = Places.get_ancestors(california.id)

    codes = Enum.map(ancestors, & &1.code)
    assert codes == ["WH", "NA", "US"]
  end

  test "returns ancestors for a country" do
    us = Places.get_place_by_code!("US")
    ancestors = Places.get_ancestors(us.id)

    codes = Enum.map(ancestors, & &1.code)
    assert codes == ["WH", "NA"]
  end

  test "returns empty list for the root" do
    wh = Places.get_place_by_code!("WH")
    assert Places.get_ancestors(wh.id) == []
  end
end
```

**Step 6: Run test to verify it fails**

Run: `mix test test/gallformers/places_test.exs --seed 0`
Expected: FAIL — `get_ancestors/1` is undefined.

**Step 7: Implement `get_ancestors/1`**

In `lib/gallformers/places.ex`:

```elixir
@doc """
Returns the ancestor places for a given place, ordered from root to immediate parent.
Does not include the place itself.
"""
@spec get_ancestors(integer()) :: [Place.t()]
def get_ancestors(place_id) do
  {:ok, %{rows: rows}} =
    Repo.query(
      """
      WITH RECURSIVE ancestors(id, depth) AS (
        SELECT ph.parent_id, 1
        FROM place_hierarchy ph
        WHERE ph.place_id = ?1
        UNION ALL
        SELECT ph.parent_id, a.depth + 1
        FROM place_hierarchy ph
        JOIN ancestors a ON ph.place_id = a.id
      )
      SELECT p.id, p.name, p.code, p.type
      FROM ancestors a
      JOIN place p ON p.id = a.id
      ORDER BY a.depth DESC
      """,
      [place_id]
    )

  Enum.map(rows, fn [id, name, code, type] ->
    %Place{id: id, name: name, code: code, type: type}
  end)
end
```

**Step 8: Run test to verify it passes**

Run: `mix test test/gallformers/places_test.exs --seed 0`
Expected: PASS.

**Step 9: Write tests for `get_children/1`**

```elixir
describe "get_children/1" do
  test "returns direct children of a country ordered by name" do
    us = Places.get_place_by_code!("US")
    children = Places.get_children(us.id)

    # Test seeds only have California under US
    assert length(children) == 1
    assert hd(children).code == "US-CA"
  end

  test "returns empty list for leaf places" do
    california = Places.get_place_by_code!("US-CA")
    assert Places.get_children(california.id) == []
  end

  test "returns children of a continent" do
    na = Places.get_place_by_code!("NA")
    children = Places.get_children(na.id)

    codes = Enum.map(children, & &1.code) |> Enum.sort()
    assert codes == ["CA", "MX", "US"]
  end
end
```

**Step 10: Run test to verify it fails**

Run: `mix test test/gallformers/places_test.exs --seed 0`
Expected: FAIL.

**Step 11: Implement `get_children/1`**

```elixir
@doc """
Returns the direct children of a place, ordered by name.
"""
@spec get_children(integer()) :: [Place.t()]
def get_children(place_id) do
  from(p in Place,
    join: ph in "place_hierarchy",
    on: ph.place_id == p.id,
    where: ph.parent_id == ^place_id,
    order_by: p.name
  )
  |> Repo.all()
end
```

**Step 12: Run test to verify it passes**

Run: `mix test test/gallformers/places_test.exs --seed 0`
Expected: PASS.

**Step 13: Write tests for `get_descendant_codes/1`**

```elixir
describe "get_descendant_codes/1" do
  test "returns codes for all descendants of a country" do
    us = Places.get_place_by_code!("US")
    codes = Places.get_descendant_codes(us.id)

    # US itself + California
    assert "US" in codes
    assert "US-CA" in codes
  end

  test "returns just the place's own code for a leaf" do
    california = Places.get_place_by_code!("US-CA")
    assert Places.get_descendant_codes(california.id) == ["US-CA"]
  end

  test "returns full tree for a continent" do
    na = Places.get_place_by_code!("NA")
    codes = Places.get_descendant_codes(na.id)

    assert "NA" in codes
    assert "US" in codes
    assert "US-CA" in codes
    assert "CA" in codes
    assert "CA-AB" in codes
    assert "MX" in codes
    assert "MX-JAL" in codes
  end
end
```

**Step 14: Run test to verify it fails**

Run: `mix test test/gallformers/places_test.exs --seed 0`
Expected: FAIL.

**Step 15: Implement `get_descendant_codes/1`**

```elixir
@doc """
Returns codes for a place and all its descendants (recursive).
Used for map highlighting — pass the result as `in_range` to the range map.
"""
@spec get_descendant_codes(integer()) :: [String.t()]
def get_descendant_codes(place_id) do
  ids = descendant_ids(place_id)

  from(p in Place,
    where: p.id in ^ids,
    select: p.code
  )
  |> Repo.all()
end
```

**Step 16: Run test to verify it passes**

Run: `mix test test/gallformers/places_test.exs --seed 0`
Expected: PASS.

**Step 17: Write tests for `get_places_tree/0`**

```elixir
describe "get_places_tree/0" do
  test "returns a nested tree rooted at Western Hemisphere" do
    tree = Places.get_places_tree()

    # Tree is a list with one root node
    assert length(tree) == 1
    root = hd(tree)
    assert root.key == "p-WH"
    assert root.name == "Western Hemisphere"
    assert root.url == "/place/WH"
    assert is_list(root.nodes)
  end

  test "tree has correct continent children" do
    [root] = Places.get_places_tree()
    continent_keys = Enum.map(root.nodes, & &1.key) |> Enum.sort()
    assert "p-NA" in continent_keys
    assert "p-XB" in continent_keys
  end

  test "countries contain subdivisions" do
    [root] = Places.get_places_tree()
    na = Enum.find(root.nodes, &(&1.key == "p-NA"))
    us = Enum.find(na.nodes, &(&1.key == "p-US"))

    # US should have California as a child in test seeds
    assert Enum.any?(us.nodes, &(&1.key == "p-US-CA"))
  end

  test "leaf countries have no nodes key" do
    [root] = Places.get_places_tree()
    caribbean = Enum.find(root.nodes, &(&1.key == "p-XB"))
    bahamas = Enum.find(caribbean.nodes, &(&1.key == "p-BS"))

    # Bahamas is a leaf country — should not have :nodes key
    refute Map.has_key?(bahamas, :nodes)
  end
end
```

**Step 18: Run test to verify it fails**

Run: `mix test test/gallformers/places_test.exs --seed 0`
Expected: FAIL.

**Step 19: Implement `get_places_tree/0`**

```elixir
@doc """
Returns the full place hierarchy as a nested tree for the tree browser.

The tree is rooted at the "Western Hemisphere" region node. Each node follows
the `TreeComponents.tree_browser` contract:
- Branch nodes have a `:nodes` key with child nodes
- Leaf nodes have no `:nodes` key
- All nodes have `:key`, `:label`, `:name`, `:url`
"""
@spec get_places_tree() :: [map()]
def get_places_tree do
  # Load all places and hierarchy links
  places = Repo.all(from(p in Place, order_by: p.name))

  links =
    from(ph in "place_hierarchy", select: {ph.place_id, ph.parent_id})
    |> Repo.all()

  # Build lookup maps
  place_map = Map.new(places, &{&1.id, &1})
  children_map = Enum.group_by(links, fn {_child, parent} -> parent end, fn {child, _parent} -> child end)

  # Find root(s) — places that are never children
  all_child_ids = MapSet.new(links, fn {child, _parent} -> child end)
  roots = Enum.reject(places, &MapSet.member?(all_child_ids, &1.id))

  Enum.map(roots, &build_tree_node(&1, place_map, children_map))
end

defp build_tree_node(place, place_map, children_map) do
  child_ids = Map.get(children_map, place.id, [])

  base = %{
    key: "p-#{place.code}",
    label: place.name,
    name: place.name,
    url: "/place/#{place.code}"
  }

  if child_ids == [] do
    base
  else
    children =
      child_ids
      |> Enum.map(&Map.get(place_map, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.name)
      |> Enum.map(&build_tree_node(&1, place_map, children_map))

    Map.put(base, :nodes, children)
  end
end
```

**Step 20: Run test to verify it passes**

Run: `mix test test/gallformers/places_test.exs --seed 0`
Expected: PASS.

**Step 21: Run full test suite**

Run: `mix test`
Expected: All pass.

**Step 22: Commit**

```bash
git add -A && git commit -m "Add place hierarchy context functions

get_place_by_code!/1, get_ancestors/1, get_children/1,
get_descendant_codes/1, and get_places_tree/0 for the public
places browse and detail pages."
```

---

### Task 3: Add Navigable Mode to Range Map

Add a `navigable` attribute to the range map component and JS hook so clicking a region pushes a navigation event to the server.

**Files:**
- Modify: `lib/gallformers_web/components/data_display_components.ex:958-1023`
- Modify: `assets/js/hooks/range_map.js`

**Step 1: Add `navigable` attribute to range map component**

In `lib/gallformers_web/components/data_display_components.ex`, add a new attr after `editable` (around line 982):

```elixir
attr :navigable, :boolean,
  default: false,
  doc: "whether clicking a region navigates to its place page"
```

Add `data-navigable={to_string(@navigable)}` to the div in the template, after `data-editable`:

```elixir
data-navigable={to_string(@navigable)}
```

**Step 2: Update JS hook to handle navigable mode**

In `assets/js/hooks/range_map.js`, in the `mounted()` function (around line 103), add:

```javascript
this.navigable = this.el.dataset.navigable === 'true'
```

In the `updated()` function, add navigable tracking alongside editable:

```javascript
const newNavigable = this.el.dataset.navigable === 'true'
```

And include it in the change check and assignment.

In `setupInteractions()`, update the subdivision click handler (around line 328) to handle navigable mode:

```javascript
map.on('click', 'subdivisions-fill', (e) => {
  if (!e.features || e.features.length === 0) return

  const code = e.features[0].properties.code
  if (!code) return

  if (this.editable) {
    this.pushEvent('toggle_region', { code })
  } else if (this.navigable) {
    this.pushEvent('navigate_to_place', { code })
  }
})
```

Also update the cursor style in the mousemove handler:

```javascript
map.getCanvas().style.cursor = (this.editable || this.navigable) ? 'pointer' : 'default'
```

**Step 3: Verify compilation and asset build**

Run: `mix compile --warnings-as-errors`
Expected: Clean.

**Step 4: Commit**

```bash
git add -A && git commit -m "Add navigable mode to range map component

When navigable=true, clicking a region pushes navigate_to_place
event with the region code. Used by public place and species pages."
```

---

### Task 4: Create Places Browse Page (`/places`)

The tree-based index page for browsing the place hierarchy.

**Files:**
- Create: `lib/gallformers_web/live/places_live.ex`
- Modify: `lib/gallformers_web/router.ex:182` (add route)
- Modify: `lib/gallformers_web/components/layouts.ex:60-63` (add nav link)
- Create: `test/gallformers_web/live/places_live_test.exs`

**Step 1: Write tests**

Create `test/gallformers_web/live/places_live_test.exs`:

```elixir
defmodule GallformersWeb.PlacesLiveTest do
  use GallformersWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "places browse page" do
    test "renders the tree with Western Hemisphere root", %{conn: conn} do
      {:ok, view, html} = live(conn, "/places")

      assert html =~ "Places"
      assert html =~ "Western Hemisphere"
    end

    test "shows continents when root is expanded", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/places")

      html =
        view
        |> element(~s{button[phx-click="toggle_node"][phx-value-key="p-WH"]})
        |> render_click()

      assert html =~ "North America"
      assert html =~ "Caribbean"
    end

    test "search filters the tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/places")

      html =
        view
        |> element("form")
        |> render_change(%{"query" => "California"})

      assert html =~ "California"
    end

    test "has correct page title", %{conn: conn} do
      {:ok, _view, _html} = live(conn, "/places")
      assert page_title(conn) =~ "Places"
    end
  end
end
```

Note: The `page_title` assertion may need adjustment depending on how the test helper works — check other LiveView tests for the pattern. The key behaviors to test are: renders, tree expands, search works.

**Step 2: Run tests to verify they fail**

Run: `mix test test/gallformers_web/live/places_live_test.exs`
Expected: FAIL — route not found or module undefined.

**Step 3: Add route**

In `lib/gallformers_web/router.ex`, in the public live_session scope (near line 182 where `PlaceLive` is), add:

```elixir
live "/places", PlacesLive
```

Add it before the `/place/:code` route (which we'll change in Task 5).

**Step 4: Add nav link**

In `lib/gallformers_web/components/layouts.ex`, update `nav_links` (around line 60):

```elixir
nav_links = [
  %{href: "/id", label: "Identify"},
  %{href: "/explore", label: "Explore"},
  %{href: "/places", label: "Places"}
]
```

**Step 5: Create the LiveView**

Create `lib/gallformers_web/live/places_live.ex`:

```elixir
defmodule GallformersWeb.PlacesLive do
  @moduledoc """
  LiveView for browsing places by geographic hierarchy.

  Displays the place hierarchy (Region → Continent → Country → Subdivision)
  in an expandable tree with search.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Places
  alias GallformersWeb.TreeComponents

  @max_families_to_auto_expand 3
  @max_children_per_node 5

  @impl true
  def mount(_params, _session, socket) do
    places_tree = Places.get_places_tree()

    {:ok,
     assign(socket,
       page_title: "Places",
       page_description:
         "Browse geographic places in the Gallformers database - regions, countries, and subdivisions of the Western Hemisphere.",
       page_url: "/places",
       page_image: nil,
       page_json_ld: nil,
       places_tree: places_tree,
       places_filtered: places_tree,
       places_expanded: MapSet.new(),
       search_query: ""
     )}
  end

  @impl true
  def handle_event("toggle_node", %{"key" => key}, socket) do
    expanded = socket.assigns.places_expanded

    new_expanded =
      if MapSet.member?(expanded, key) do
        MapSet.delete(expanded, key)
      else
        MapSet.put(expanded, key)
      end

    {:noreply, assign(socket, places_expanded: new_expanded)}
  end

  @impl true
  def handle_event("expand_all", _params, socket) do
    all_keys = collect_branch_keys(socket.assigns.places_filtered)
    {:noreply, assign(socket, places_expanded: MapSet.new(all_keys))}
  end

  @impl true
  def handle_event("collapse_all", _params, socket) do
    {:noreply, assign(socket, places_expanded: MapSet.new())}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    filtered = filter_tree(socket.assigns.places_tree, query)

    new_expanded =
      if String.trim(query) != "" do
        matching_top = length(filtered)

        if matching_top <= @max_families_to_auto_expand do
          filtered
          |> collect_branch_keys_with_limit(@max_children_per_node)
          |> MapSet.new()
        else
          socket.assigns.places_expanded
        end
      else
        socket.assigns.places_expanded
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:places_filtered, filtered)
     |> assign(:places_expanded, new_expanded)}
  end

  defp collect_branch_keys(nodes) do
    Enum.flat_map(nodes, fn node ->
      if Map.has_key?(node, :nodes) and node.nodes != [] do
        [node.key | collect_branch_keys(node.nodes)]
      else
        []
      end
    end)
  end

  defp collect_branch_keys_with_limit(nodes, max_children) do
    Enum.flat_map(nodes, &collect_node_keys_with_limit(&1, max_children))
  end

  defp collect_node_keys_with_limit(%{nodes: children} = node, max_children)
       when is_list(children) and children != [] do
    child_keys = collect_branch_keys_with_limit(children, max_children)

    if length(children) <= max_children do
      [node.key | child_keys]
    else
      child_keys
    end
  end

  defp collect_node_keys_with_limit(_node, _max_children), do: []

  defp filter_tree(nodes, ""), do: nodes

  defp filter_tree(nodes, query) do
    query_lower = String.downcase(query)

    nodes
    |> Enum.map(&filter_node(&1, query_lower))
    |> Enum.reject(&is_nil/1)
  end

  defp filter_node(node, query_lower) do
    if Map.has_key?(node, :nodes) and node.nodes != [] do
      filtered_children = filter_tree(node.nodes, query_lower)

      if filtered_children != [] or label_matches?(node.label, query_lower) do
        %{node | nodes: filtered_children}
      else
        nil
      end
    else
      if label_matches?(node.label, query_lower), do: node, else: nil
    end
  end

  defp label_matches?(label, query_lower),
    do: String.contains?(String.downcase(label), query_lower)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="places-container">
        <p class="text-lg text-gray-600 mb-6">
          Browse geographic places in the Western Hemisphere. Click on regions, countries,
          and subdivisions to explore.
        </p>

        <TreeComponents.tree_browser
          id="places-tree"
          nodes={@places_filtered}
          expanded={@places_expanded}
          search_query={@search_query}
          show_search={true}
          show_controls={true}
          on_toggle="toggle_node"
          on_expand_all="expand_all"
          on_collapse_all="collapse_all"
          on_search="search"
        />
      </div>
    </Layouts.app>
    """
  end
end
```

Note: The tree filter/expand helper functions are duplicated from `ExploreLive`. This is intentional for now — both are short, and extracting a shared module is premature until a third consumer appears. If it bothers you during review, a shared `TreeHelpers` module could hold them, but it's not required.

**Step 6: Run tests**

Run: `mix test test/gallformers_web/live/places_live_test.exs`
Expected: PASS.

**Step 7: Run full suite**

Run: `mix test`
Expected: All pass.

**Step 8: Commit**

```bash
git add -A && git commit -m "Add public places browse page with tree navigation

New /places route shows the full place hierarchy using the tree
browser component. Added Places link to site navigation."
```

---

### Task 5: Rework Place Detail Page

Change from integer ID to code-based URL. Replace host list with hierarchy nav, breadcrumbs, children list, and range map.

**Files:**
- Rewrite: `lib/gallformers_web/live/place_live.ex`
- Modify: `lib/gallformers_web/router.ex` (change route param)
- Create: `test/gallformers_web/live/place_live_test.exs`

**Step 1: Write tests**

Create `test/gallformers_web/live/place_live_test.exs`:

```elixir
defmodule GallformersWeb.PlaceLiveTest do
  use GallformersWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "place detail page" do
    test "renders a subdivision by code", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/place/US-CA")

      assert html =~ "California"
      assert html =~ "US-CA"
      assert html =~ "state"
    end

    test "renders a country with children links", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/place/US")

      assert html =~ "United States"
      # Should show California as a child
      assert html =~ "California"
    end

    test "renders breadcrumb ancestors", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/place/US-CA")

      # Breadcrumb should include ancestors
      assert html =~ "Western Hemisphere"
      assert html =~ "North America"
      assert html =~ "United States"
    end

    test "renders a leaf country with no children section", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/place/BS")

      assert html =~ "Bahamas"
      # No "Subdivisions" section for a leaf country
      refute html =~ "Subdivisions"
    end

    test "renders the root region", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/place/WH")

      assert html =~ "Western Hemisphere"
      # Should show continents as children
      assert html =~ "North America"
      assert html =~ "Caribbean"
    end

    test "returns error for invalid code", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, "/place/XX-ZZ")
      end
    end

    test "includes range map", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/place/US")

      assert html =~ "range-map"
      assert html =~ "phx-hook=\"RangeMap\""
    end

    test "navigate_to_place event redirects to place page", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/place/US")

      # Simulate the JS hook pushing a navigate event
      assert {:error, {:live_redirect, %{to: "/place/US-CA"}}} =
               render_hook(view, "navigate_to_place", %{"code" => "US-CA"})
    end
  end
end
```

Note: The `navigate_to_place` redirect test uses `render_hook` to simulate the JS event. The exact assertion format may need adjustment based on how Phoenix LiveView handles `push_navigate` in tests — it may return `{:error, {:live_redirect, ...}}` or `{:error, {:redirect, ...}}`. Check other test files for the pattern used in this project.

**Step 2: Run tests to verify they fail**

Run: `mix test test/gallformers_web/live/place_live_test.exs`
Expected: FAIL — route uses `:id` not `:code`.

**Step 3: Update route**

In `lib/gallformers_web/router.ex`, change:

```elixir
# Before
live "/place/:id", PlaceLive

# After
live "/place/:code", PlaceLive
```

**Step 4: Rewrite PlaceLive**

Replace the contents of `lib/gallformers_web/live/place_live.ex`:

```elixir
defmodule GallformersWeb.PlaceLive do
  @moduledoc """
  LiveView for the geographic place detail page.

  Displays a place with breadcrumb ancestors, children links, and a range map
  showing the place and its descendants highlighted.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Places

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    place = Places.get_place_by_code!(code)
    ancestors = Places.get_ancestors(place.id)
    children = Places.get_children(place.id)
    descendant_codes = Places.get_descendant_codes(place.id)

    {:ok,
     assign(socket,
       page_title: place.name,
       page_description:
         "#{place.name} (#{place.code}) — geographic place in the Gallformers database.",
       page_url: "/place/#{place.code}",
       page_image: nil,
       page_json_ld: nil,
       place: place,
       ancestors: ancestors,
       children: children,
       descendant_codes: descendant_codes
     )}
  end

  @impl true
  def handle_event("navigate_to_place", %{"code" => code}, socket) do
    {:noreply, push_navigate(socket, to: "/place/#{code}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-7xl">
        <%!-- Breadcrumb --%>
        <nav :if={@ancestors != []} class="mb-4 text-sm text-gray-500" aria-label="Breadcrumb">
          <ol class="flex items-center gap-1">
            <li :for={ancestor <- @ancestors}>
              <.link navigate={"/place/#{ancestor.code}"} class="hover:underline hover:text-gf-maroon">
                {ancestor.name}
              </.link>
              <span class="mx-1 text-gray-400">›</span>
            </li>
            <li class="text-gray-700 font-medium">{@place.name}</li>
          </ol>
        </nav>

        <%!-- Header --%>
        <div class="mb-6">
          <h1 class="text-2xl font-bold text-gf-maroon">{@place.name}</h1>
          <div class="flex items-center gap-2 mt-1">
            <span class="text-gray-600 capitalize">{@place.type}</span>
            <.badge>{@place.code}</.badge>
          </div>
        </div>

        <%!-- Content: map + children --%>
        <div class={[
          "grid gap-6",
          if(@children != [], do: "grid-cols-1 md:grid-cols-3", else: "grid-cols-1 max-w-2xl")
        ]}>
          <%!-- Range map --%>
          <div class={if @children != [], do: "md:col-span-2"}>
            <.range_map
              id="place-range-map"
              in_range={@descendant_codes}
              navigable
            />
          </div>

          <%!-- Children sidebar --%>
          <div :if={@children != []} class="md:col-span-1">
            <h2 class="text-lg font-semibold text-gray-800 mb-3">
              {children_label(@place.type)}
            </h2>
            <ul class="space-y-1">
              <li :for={child <- @children}>
                <.link
                  navigate={"/place/#{child.code}"}
                  class="text-gf-maroon hover:underline"
                >
                  {child.name}
                </.link>
              </li>
            </ul>
          </div>
        </div>

        <%!-- Back to browse --%>
        <div class="mt-8">
          <.link navigate="/places" class="text-sm text-gray-500 hover:underline">
            ← Browse all places
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp children_label("region"), do: "Continents"
  defp children_label("continent"), do: "Countries"
  defp children_label("country"), do: "Subdivisions"
  defp children_label(_), do: "Children"
end
```

**Step 5: Run tests**

Run: `mix test test/gallformers_web/live/place_live_test.exs`
Expected: PASS (or close — adjust test assertions if needed for exact HTML matching).

**Step 6: Run full suite**

Run: `mix test`
Expected: All pass. Check that no other tests reference `/place/:id` with integer IDs. The global search test may need updating if it links to place pages.

**Step 7: Commit**

```bash
git add -A && git commit -m "Rework place detail page with code-based URLs and hierarchy

Replace flat host list with breadcrumb ancestors, children links,
and range map. URL changes from /place/:id to /place/:code."
```

---

### Task 6: Update Sitemap and Fix External References

Update sitemap to use code-based URLs. Fix any remaining references to old `/place/:id` routes.

**Files:**
- Modify: `lib/gallformers_web/controllers/sitemap_controller.ex:120-128`
- Search & fix: any remaining `/place/#{id}` or `~p"/place"` references

**Step 1: Update sitemap**

In `lib/gallformers_web/controllers/sitemap_controller.ex`, replace the `place_urls/0` function:

```elixir
defp place_urls do
  from(p in "place", select: p.code)
  |> Repo.all()
  |> Enum.map(fn code ->
    %{loc: "#{@base_url}/place/#{code}", changefreq: "monthly", priority: "0.5"}
  end)
end
```

Also add `/places` (the browse index) to the sitemap. Check if there's a static_urls or similar function — add a `/places` entry there with higher priority.

**Step 2: Search for remaining old-style place links**

Search the entire codebase for patterns like `/place/#{` and `~p"/place"` and `"/place/"`. Fix any that still use integer IDs.

Key places to check:
- `lib/gallformers_web/live/search_live.ex` — the `build_entity_link` function may construct `/place/:id` links
- Any test files

In `search_live.ex`, the `build_entity_link/2` function currently builds `/place/#{id}`. This needs to change to use the place code. The search result data must include the code. Check how search results are structured and update accordingly.

**Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean.

**Step 4: Run full suite**

Run: `mix test`
Expected: All pass.

**Step 5: Commit**

```bash
git add -A && git commit -m "Update sitemap and search to use code-based place URLs"
```

---

### Task 7: Make Species Page Range Maps Navigable

Add `navigable` to range maps on public gall and host detail pages so clicking a region navigates to the place page.

**Files:**
- Modify: `lib/gallformers_web/live/host_live.ex:568`
- Modify: `lib/gallformers_web/live/gall_live.ex:492`

**Step 1: Add navigable to host range map**

In `lib/gallformers_web/live/host_live.ex`, line 568, change:

```elixir
# Before
<.range_map id="host-range-map" in_range={MapSet.to_list(@range)} />

# After
<.range_map id="host-range-map" in_range={MapSet.to_list(@range)} navigable />
```

**Step 2: Add navigable to gall range map**

In `lib/gallformers_web/live/gall_live.ex`, around line 492, add `navigable` to the range_map component:

```elixir
<.range_map
  id="gall-range-map"
  in_range={MapSet.to_list(@range)}
  excluded_range={MapSet.to_list(@excluded_range)}
  navigable
/>
```

**Step 3: Add navigate_to_place handler to both LiveViews**

Both `host_live.ex` and `gall_live.ex` need a handler for the `navigate_to_place` event:

```elixir
@impl true
def handle_event("navigate_to_place", %{"code" => code}, socket) do
  {:noreply, push_navigate(socket, to: "/place/#{code}")}
end
```

Add this to each LiveView. Check for existing `handle_event` catch-all clauses that might swallow the event.

**Step 4: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean.

**Step 5: Run full suite**

Run: `mix test`
Expected: All pass.

**Step 6: Commit**

```bash
git add -A && git commit -m "Make range maps on species pages navigate to place detail

Clicking a region on the gall or host detail page range map now
navigates to /place/:code for that region."
```

---

### Task 8: Final Verification

Run the full precommit suite and manually verify the experience.

**Step 1: Run precommit**

Run: `mix precommit`
Expected: All checks pass (format, credo, compile warnings-as-errors, tests).

**Step 2: Manual smoke test**

Start the dev server (`mix phx.server`) and verify:

1. `/places` — tree renders, search works, expand/collapse works, clicking a node navigates to detail page
2. `/place/US` — shows breadcrumb, children list, range map with US + all states highlighted
3. `/place/US-CA` — shows breadcrumb, no children, map highlights California
4. `/place/WH` — root node, shows continents as children
5. `/place/BS` — leaf country, no children section
6. Click a region on the map → navigates to that place
7. Admin nav — no "Places" link
8. Old URL `/place/2` — returns 404 or error (no longer valid)
9. Host detail page → click a range map region → navigates to place
10. Gall detail page → same
11. Nav bar shows "Places" link between "Explore" and "Resources"

**Step 3: Commit any final fixes**

If smoke testing reveals issues, fix and commit.

---

### Summary of All Commits

1. Remove admin places pages and CUD context functions
2. Add place hierarchy context functions
3. Add navigable mode to range map component
4. Add public places browse page with tree navigation
5. Rework place detail page with code-based URLs and hierarchy
6. Update sitemap and search to use code-based place URLs
7. Make range maps on species pages navigate to place detail
