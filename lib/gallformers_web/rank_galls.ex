defmodule GallformersWeb.RankGalls do
  @moduledoc """
  The Galls list of a rank page (genus, family, tribe …: every Gall whose
  current Inducer is in the taxon's subtree) or a place page (the Galls that
  known there), as photo cards or a table, with
  facets (Host genus, plant part, form, season), the page's name filter, its
  sort, and pagination (docs/design-system/patterns.md, "Rank pages").

  `load/1` reads the Galls; the rest is pure. A list is a map: the Galls
  (`all`), the facet selection, the view, the page, and what the last
  `compute/3` made of them (`shown` for this page, `shown_count`, `facets`,
  `total_pages`, `page_size`). Rendered by
  `GallformersWeb.RankPageComponents.rank_galls/1`.
  """
  alias Gallformers.Catalog
  alias GallformersWeb.RankPage

  @facets [
    {"host", "Host genus"},
    {"plant_part", "Plant part"},
    {"form", "Form"},
    {"season", "Season"}
  ]

  # Facets earn their place only when there are enough Galls to narrow.
  @min_for_facets 8
  # A large taxon opens as a table: a wall of 1,000 photos helps no one.
  @max_for_photos 150
  @page_size %{photos: 48, table: 50}

  @type gall :: %{
          id: integer(),
          name: String.t(),
          common_name: String.t() | nil,
          count: non_neg_integer(),
          undescribed: boolean(),
          image_url: String.t() | nil,
          traits: %{String.t() => [String.t()]},
          host_genera: [String.t()]
        }

  @doc """
  The Galls the ID tool finds with `filters` (`Catalog.identify/1`: a
  rank page's `%{inducer_family_id: taxon_id}`, a place page's
  `%{place_codes: [code]}`), by name: each with its photo, Traits and
  undescribed flag, first common name and Host count (`count`), and its
  Hosts' genera.
  """
  @spec load(map()) :: [gall()]
  def load(filters) do
    cards = Catalog.identify(filters)

    rows =
      cards
      |> Enum.map(&%{id: &1.id, name: &1.name, datacomplete: false})
      |> RankPage.gall_rows()
      |> Map.new(&{&1.id, &1})

    host_genera =
      for genus <- cards |> Enum.map(& &1.id) |> Catalog.host_genera_of_galls(),
          id <- genus.focal_ids,
          reduce: %{} do
        acc -> Map.update(acc, id, [genus.name], &[genus.name | &1])
      end

    Enum.map(cards, fn card ->
      row = Map.get(rows, card.id, %{common_name: nil, count: 0})

      %{
        id: card.id,
        name: card.name,
        common_name: row.common_name,
        count: row.count,
        undescribed: card.undescribed,
        image_url: card.image_url,
        traits: card.traits,
        host_genera: host_genera |> Map.get(card.id, []) |> Enum.sort()
      }
    end)
  end

  @doc """
  A list of `galls`, unfiltered, on its first page; a large one opens as a
  table. `views:` the views it offers (default `[:photos, :table]`; the
  Host page offers `[:photos]`, which also keeps a large list in photos).
  """
  @spec new([gall()], keyword()) :: map()
  def new(galls, opts \\ []) do
    views = Keyword.get(opts, :views, [:photos, :table])
    large? = length(galls) > @max_for_photos

    %{
      all: galls,
      selected: %{},
      views: views,
      view: if(large? and :table in views, do: :table, else: hd(views)),
      page: 1
    }
  end

  @doc ~S|The facet selection from a facet form's params (`%{"plant_part" => ["leaf"]}`), back to page 1.|
  @spec filter(map(), map()) :: map()
  def filter(list, params) do
    selected =
      for {key, _} <- @facets,
          values = Enum.reject(List.wrap(params[key]), &(&1 == "")),
          values != [],
          into: %{},
          do: {key, MapSet.new(values)}

    %{list | selected: selected, page: 1}
  end

  @doc "No facet selected, back to page 1."
  @spec clear(map()) :: map()
  def clear(list), do: %{list | selected: %{}, page: 1}

  @doc ~S|Photos or table (`"photos"`, `"table"`), back to page 1; a view the list doesn't offer is ignored.|
  @spec view(map(), String.t()) :: map()
  def view(list, view) when view in ["photos", "table"] do
    view = String.to_existing_atom(view)
    if view in list.views, do: %{list | view: view, page: 1}, else: list
  end

  @doc "A page, kept within the list's pages (`compute/3` clamps it again)."
  @spec page(map(), String.t() | integer()) :: map()
  def page(list, page) do
    page = page |> to_string() |> Integer.parse() |> elem(0) |> max(1)
    %{list | page: page}
  end

  @doc """
  The list after one of its events (sent by `rank_galls/1`):
  `galls_filter` (the facet form), `galls_clear`, `galls_view` and
  `galls_page`.
  """
  @spec handle(map(), String.t(), map()) :: map()
  def handle(list, "galls_filter", params), do: filter(list, params)
  def handle(list, "galls_clear", _params), do: clear(list)
  def handle(list, "galls_view", %{"view" => view}), do: view(list, view)
  def handle(list, "galls_page", %{"page" => page}), do: page(list, page)

  @doc """
  The list as shown: the Galls matching the facets and `query` (name or
  common name, as `RankPage.filter_rows/2`), sorted by `sort` (`:name`,
  `:common_name` or `:count`; any other field sorts by name), and this
  page's slice, each a card (`gall_card`'s attributes plus the table's
  columns). Facets are offered from `#{@min_for_facets}` Galls, each with
  more than one option; an option's count is what choosing it would leave.
  """
  @spec compute(map(), String.t(), %{field: atom(), dir: :asc | :desc}) :: map()
  def compute(list, query, %{field: field, dir: dir}) do
    %{all: all, selected: selected, view: view} = list
    searched = RankPage.filter_rows(all, query)
    matching = matching(searched, selected, nil)
    field = if field in [:name, :common_name, :count], do: field, else: :name
    sorted = RankPage.sort_rows(matching, field, dir)

    size = @page_size[view]
    total_pages = max(1, ceil(length(sorted) / size))
    page = min(list.page, total_pages)

    facets =
      for {key, title} <- @facets,
          length(all) >= @min_for_facets,
          options = options(searched, selected, key),
          length(options) > 1,
          do: %{key: key, title: title, options: options}

    Map.merge(list, %{
      page: page,
      page_size: size,
      total_pages: total_pages,
      shown_count: length(sorted),
      shown: sorted |> Enum.slice((page - 1) * size, size) |> Enum.map(&card/1),
      facets: facets
    })
  end

  # What a card and a table row show: the Host count leads the subtitle.
  defp card(gall) do
    hosts = if gall.count == 1, do: "1 host", else: "#{gall.count} hosts"
    traits = for key <- ["plant_part", "form", "season"], v = first(gall, key), do: v

    Map.merge(gall, %{
      navigate: "/gall/#{gall.id}",
      subtitle: Enum.join([hosts | traits], " · "),
      plant_part: gall.traits |> Map.get("plant_part", []) |> Enum.join(", "),
      season: gall.traits |> Map.get("season", []) |> Enum.join(", ")
    })
  end

  defp first(gall, key), do: gall.traits |> Map.get(key, []) |> List.first()

  defp values(gall, "host"), do: gall.host_genera
  defp values(gall, key), do: Map.get(gall.traits, key, [])

  defp matching(galls, selected, except) do
    Enum.filter(galls, fn g ->
      Enum.all?(selected, fn {key, set} ->
        key == except or Enum.any?(values(g, key), &MapSet.member?(set, &1))
      end)
    end)
  end

  defp options(galls, selected, key) do
    counts =
      galls |> matching(selected, key) |> Enum.flat_map(&values(&1, key)) |> Enum.frequencies()

    chosen = Map.get(selected, key, MapSet.new())

    galls
    |> Enum.flat_map(&values(&1, key))
    |> Enum.uniq()
    |> Enum.map(
      &%{
        value: &1,
        label: &1,
        count: Map.get(counts, &1, 0),
        selected: MapSet.member?(chosen, &1)
      }
    )
    |> Enum.sort_by(&{-&1.count, &1.label})
  end
end
