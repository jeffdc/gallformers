# Public Places Experience Design

Covers matters 554e (public place browse/index page), 67e0 (admin places redesign — resolved by removal), and rework of the existing `/place/:id` detail page.

## Context

The place table is expanding from ~60 US/Canada entries to 567 Western Hemisphere places organized in a 4-level hierarchy: region → continent → country → subdivision. Place data is now managed through migrations, not admin UI.

The current state:
- Admin places pages exist but only support flat CRUD — no hierarchy management. Being removed.
- Public `/place/:id` shows a flat host list with no hierarchy awareness. Essentially orphaned — no navigation path leads to it except global search and sitemap.
- Range maps on species pages are not clickable for public users.

## Decisions

- **Remove admin places pages entirely.** Data is migration-managed.
- **Use code-based URLs** (`/place/US-CA`) instead of integer IDs (`/place/342`).
- **Tree browser for the index page.** Reuse `TreeComponents.tree_browser` — consistent with Explore and Family pages.
- **Detail page shows hierarchy nav + map only.** No species lists for now — future enhancement.
- **Clickable map regions** navigate to the corresponding place's detail page.

## Part 1: Remove Admin Places Pages

Delete:
- `lib/gallformers_web/live/admin/place_live/index.ex`
- `lib/gallformers_web/live/admin/place_live/form.ex`
- Three routes in router.ex: `/admin/places`, `/admin/places/new`, `/admin/places/:id`

The `superadmin_nav_links` list in `layouts.ex` is already empty — no nav link to remove.

Keep:
- `Gallformers.Places` context module (read functions used everywhere)
- `Gallformers.Places.Place` schema
- `GET /api/v2/places` endpoint
- `Places.subscribe/0` and PubSub (still used by range assignment on host/gall admin forms)

Also remove:
- `Places.create_place/1`, `Places.update_place/2`, `Places.delete_place/1` — no longer needed. Keep `change_place/2` if used by anything else; otherwise remove.

## Part 2: Places Browse Page (`/places`)

### Route

```elixir
live "/places", PlacesLive
```

Public, unauthenticated. Added to the site nav as a peer of "Identify" and "Explore":

```elixir
nav_links = [
  %{href: "/id", label: "Identify"},
  %{href: "/explore", label: "Explore"},
  %{href: "/places", label: "Places"}
]
```

### LiveView: `PlacesLive`

Mounts by calling `Places.get_places_tree/0` to get the full hierarchy as a nested tree structure. Uses `TreeComponents.tree_browser` with search, expand all, collapse all.

Assigns:
- `places_tree` — full tree from context
- `places_filtered` — filtered copy (search applied)
- `places_expanded` — `MapSet` of expanded node keys
- `search_query` — current search text

Events: `toggle_node`, `expand_all`, `collapse_all`, `search` — identical pattern to `ExploreLive`.

Each leaf and branch node links to `/place/:code`. Branch nodes (continents, countries with children) are expandable and also link to their detail page.

### Tree Structure

Mirrors the place hierarchy. Node shape follows the existing `tree_browser` contract:

```elixir
%{
  key: "p-WH",           # "p-" prefix + place code
  label: "Western Hemisphere",
  name: "Western Hemisphere",
  rank: nil,              # no taxonomic rank — places don't italicize
  url: "/place/WH",
  nodes: [
    %{
      key: "p-NA",
      label: "North America",
      name: "North America",
      url: "/place/NA",
      nodes: [
        %{
          key: "p-US",
          label: "United States",
          name: "United States",
          url: "/place/US",
          nodes: [
            %{key: "p-US-CA", label: "California", name: "California", url: "/place/US-CA"},
            %{key: "p-US-TX", label: "Texas", name: "Texas", url: "/place/US-TX"},
            ...
          ]
        },
        %{
          key: "p-BS",
          label: "Bahamas",
          name: "Bahamas",
          url: "/place/BS"
          # no nodes key — leaf country
        },
        ...
      ]
    },
    ...
  ]
}
```

Leaf countries (no subdivisions) appear as leaf nodes — no `nodes` key, just like species leaves in the taxonomy tree.

### Context Function: `Places.get_places_tree/0`

Queries all places and the `place_hierarchy` join table, builds the nested structure in memory. The dataset is small (567 rows) so this can be a simple eager load. Returns the tree rooted at the "Western Hemisphere" region node.

## Part 3: Place Detail Page (`/place/:code`)

### Route Change

```elixir
# Before
live "/place/:id", PlaceLive

# After
live "/place/:code", PlaceLive
```

The mount function changes from `get_place!/1` (by ID) to `get_place_by_code!/1`.

### Layout

```
┌─────────────────────────────────────────────────────┐
│ Western Hemisphere › North America › United States   │  ← breadcrumb (each segment links)
│                                                      │
│ United States                                        │  ← h1, place name
│ Country · US                                         │  ← type + code badge
│                                                      │
│ ┌─────────────────────────┐  ┌────────────────────┐ │
│ │                         │  │ Subdivisions       │ │
│ │     [Range Map]         │  │                    │ │
│ │  (clickable regions)    │  │ • Alabama          │ │
│ │                         │  │ • Alaska           │ │
│ │                         │  │ • Arizona          │ │
│ │                         │  │ • ...              │ │
│ └─────────────────────────┘  └────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

- **Breadcrumb**: Built from the place's ancestor chain (queried via `Places.get_ancestors/1` using the recursive CTE). Each segment is a link to `/place/:code`.
- **Heading**: Place name, type label (capitalized), code as a badge.
- **Range map**: Shows the current place highlighted. For a country or continent, highlights all descendant subdivisions. Clicking a region navigates to `/place/:code` for that region.
- **Children list**: If the place has children, show them as links in a sidebar column. Sorted alphabetically. For leaf places (e.g., a state), this section is omitted.

### Map Behavior

The range map component gets a new mode for place pages. Instead of showing "in range" vs "excluded" for a species, it shows "this place and its descendants" as the highlighted set.

The `navigable` behavior is added to the JS hook:
- When `data-navigable="true"`, clicking a region calls `pushEvent('navigate_to_place', {code: "US-CA"})`.
- The LiveView handles this event with `push_navigate(to: "/place/US-CA")`.
- Hover popup shows place name and code (same as current behavior).

The `in_range` attribute is repurposed: pass the codes of the current place + all its descendants to highlight the geographic extent.

### Context Functions

New or modified functions in `Places`:

- `get_place_by_code!/1` — raises on not found (for LiveView mount)
- `get_ancestors/1` — returns ordered list from root to parent, using recursive CTE up the hierarchy
- `get_children/1` — returns direct children of a place, ordered by name
- `get_descendant_codes/1` — returns all descendant codes (for map highlighting), using recursive CTE down the hierarchy

## Part 4: Sitemap Update

Change sitemap generation to use codes instead of IDs:

```elixir
defp place_urls do
  from(p in "place", select: p.code)
  |> Repo.all()
  |> Enum.map(fn code ->
    %{loc: "#{@base_url}/place/#{code}", changefreq: "monthly", priority: "0.5"}
  end)
end
```

## Part 5: Clickable Range Maps on Species Pages

On public gall and host detail pages, make the range map regions clickable to navigate to the place detail page. Add `data-navigable="true"` to the range map component when rendered on public pages (not admin). The LiveView handles `navigate_to_place` the same way.

This gives users a navigation path: see a species range map → click a highlighted state → land on the place detail page.

## Not In Scope

- Species lists on place pages (host/gall tables with hierarchy roll-up)
- Aggregate counts (host/gall counts per place)
- Map-first browse (map as primary navigation with sidebar tree)
- Admin place management (permanently removed — data is migration-managed)
- Place-based filtering in the ID tool (separate work, already designed in the hierarchy doc)
