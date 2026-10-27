defmodule Gallformers.Search do
  @moduledoc """
  The Search context.

  The global search (`global_search/2`, the search page and the API's
  `/search`) reads Galls from `Gallformers.Catalog` and plants and higher
  taxa from `Gallformers.Taxa` (`803b` Task 11); glossary entries, Sources
  and places from their own tables.
  """
  use Boundary,
    deps: [
      Gallformers.Catalog,
      Gallformers.Repo,
      Gallformers.Ranges,
      Gallformers.Sources,
      Gallformers.Glossaries,
      Gallformers.Places,
      Gallformers.Taxa,
      Gallformers.TextMatch
    ],
    exports: :all

  import Ecto.Query

  alias Gallformers.Catalog
  alias Gallformers.Glossaries.Glossary
  alias Gallformers.Places
  alias Gallformers.Places.Place
  alias Gallformers.Ranges.HostRange
  alias Gallformers.Repo
  alias Gallformers.Search.Ranking
  alias Gallformers.Sources.Source
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.TextMatch

  # The ranks with a public page (`GallformersWeb.TaxonomyURL`): the
  # taxonomy results.
  @page_ranks [:family, :subfamily, :tribe, :subtribe, :genus, :section]

  @doc """
  Performs a global search across all entity types.

  Returns a map with results grouped by type, each group ranked by match
  quality (`Gallformers.Search.Ranking`):

    * `galls` — `Gallformers.Catalog.search_galls/2`: display name, alias
      Facts, the Inducer's names;
    * `hosts` — plants (Plantae at species rank or below) from
      `Gallformers.Taxa.search/2`: accepted names, synonyms, common names;
    * `taxonomy` — taxa at the ranks with a public page (family, subfamily,
      tribe, subtribe, genus, section) from `Gallformers.Taxa.search/2`,
      with their parent when it too has a page;
    * `glossary`, `sources`, `places`.

  When `continent_code` names a place, galls are kept when their potential
  range (`gall_index`) meets the continent's places or is everywhere, and
  hosts when they have a `host_range` row there. Other result types are not
  filtered.
  """
  @spec global_search(String.t(), String.t() | nil) :: map()
  def global_search(query, continent_code \\ nil) when is_binary(query) do
    query
    |> String.trim()
    |> do_global_search(continent_code)
  end

  defp do_global_search("", _continent_code), do: empty_results()

  defp do_global_search(query, continent_code) do
    search_terms = Ranking.parse_query(query)
    place_ids = continent_code && continent_descendant_ids(continent_code)

    %{
      galls: galls(query, place_ids) |> Ranking.add_scores_and_sort(search_terms),
      hosts: hosts(query, place_ids) |> Ranking.add_scores_and_sort(search_terms),
      glossary: search_glossary(query) |> Ranking.add_scores_and_sort(search_terms),
      sources: search_sources(query) |> Ranking.add_scores_and_sort(search_terms),
      taxonomy: taxonomy(query) |> Ranking.add_scores_and_sort(search_terms),
      places: search_places(query) |> Ranking.add_scores_and_sort(search_terms)
    }
  end

  defp galls(query, place_ids) do
    for gall <- Catalog.search_galls(query, place_ids: place_ids) do
      %{
        id: gall.id,
        name: gall.name,
        type: "gall",
        undescribed: gall.undescribed,
        aliases: gall.aliases
      }
    end
  end

  defp hosts(query, place_ids) do
    query
    |> Taxa.search(kingdom: "Plantae", ranks: Rank.species_and_below())
    |> in_places(place_ids)
    |> Enum.map(
      &%{id: &1.id, name: &1.name, type: "host", genus_placeholder: false, aliases: &1.aliases}
    )
  end

  # The plants with a `host_range` row at one of `place_ids` (all of them for nil).
  defp in_places(plants, nil), do: plants
  defp in_places([], _place_ids), do: []

  defp in_places(plants, place_ids) do
    found =
      from(hr in HostRange,
        where: hr.taxon_id in ^Enum.map(plants, & &1.id) and hr.place_id in ^place_ids,
        distinct: true,
        select: hr.taxon_id
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.filter(plants, &MapSet.member?(found, &1.id))
  end

  # Taxa at the ranks with a public page, in the shape of the old taxonomy
  # results: `type` "family", "genus", "section" or "intermediate" (with its
  # `rank`, e.g. "Tribe"), common names as `description`, and the parent
  # when its rank has a page too.
  defp taxonomy(query) do
    taxa = Taxa.search(query, ranks: @page_ranks)
    parents = taxa |> Enum.map(& &1.parent_id) |> Enum.reject(&is_nil/1) |> Taxa.lineages()
    common_names = taxa |> Enum.map(& &1.id) |> Taxa.common_names()

    for taxon <- taxa do
      {type, rank} = type_and_rank(taxon.rank)
      parent = parents |> Map.get(taxon.parent_id, []) |> List.last()

      {parent_type, parent_rank} =
        if parent && parent.rank in @page_ranks, do: type_and_rank(parent.rank), else: {nil, nil}

      %{
        id: taxon.id,
        name: taxon.name,
        type: type,
        rank: rank,
        description: describe(Map.get(common_names, taxon.id, [])),
        parent_name: parent_type && parent.name,
        parent_type: parent_type,
        parent_rank: parent_rank
      }
    end
  end

  defp type_and_rank(rank) when rank in [:family, :genus, :section], do: {to_string(rank), nil}
  defp type_and_rank(rank), do: {"intermediate", rank |> to_string() |> String.capitalize()}

  defp describe([]), do: nil
  defp describe(names), do: Enum.join(names, ", ")

  @doc """
  Returns empty search results.
  """
  @spec empty_results() :: map()
  def empty_results do
    %{
      galls: [],
      hosts: [],
      glossary: [],
      sources: [],
      taxonomy: [],
      places: []
    }
  end

  @doc """
  Searches glossary entries by word or definition.
  """
  @spec search_glossary(String.t()) :: [map()]
  def search_glossary(query) do
    filter = TextMatch.build_filter(query, [:word, :definition])

    from(g in Glossary,
      where: ^filter,
      order_by: g.word,
      select: %{
        id: g.id,
        name: g.word,
        type: "glossary",
        definition: g.definition
      }
    )
    |> Repo.all()
  end

  @doc """
  Searches sources by title or author.
  """
  @spec search_sources(String.t()) :: [map()]
  def search_sources(query) do
    filter = TextMatch.build_filter(query, [:title, :author])

    from(s in Source,
      where: ^filter,
      order_by: s.title,
      select: %{
        id: s.id,
        name: s.title,
        type: "source",
        author: s.author,
        pubyear: s.pubyear
      }
    )
    |> Repo.all()
  end

  @doc """
  Searches places by name or code.
  """
  @spec search_places(String.t()) :: [map()]
  def search_places(query) do
    filter = TextMatch.build_filter(query, [:name, :code])

    from(p in Place,
      where: ^filter,
      order_by: p.name,
      select: %{
        id: p.id,
        name: p.name,
        type: "place",
        code: p.code
      }
    )
    |> Repo.all()
  end

  # The IDs of a continent's places (its descendants), or nil for an unknown code.
  defp continent_descendant_ids(continent_code) do
    case Places.get_place_by_code(continent_code) do
      nil -> nil
      continent -> Places.descendant_ids(continent.id)
    end
  end
end
