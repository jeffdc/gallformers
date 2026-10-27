defmodule GallformersWeb.RankPage do
  @moduledoc """
  The data the rank pages (`GallformersWeb.FamilyLive`, `IntermediateLive`,
  `GenusLive`, `SectionLive`) share, from `Gallformers.Taxa` and
  `Gallformers.Catalog`: a taxon found by name and rank (or an old numeric
  URL redirected through the crosswalk), its description, its children
  with gall and host counts, and Galls as table rows.
  """
  alias Gallformers.Catalog
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon
  alias GallformersWeb.TaxonomyURL

  @typedoc "A child taxon as the rank pages' tables show it."
  @type child :: %{
          id: integer(),
          name: String.t(),
          rank: String.t(),
          description: String.t() | nil,
          url: String.t() | nil,
          gall_count: non_neg_integer(),
          host_count: non_neg_integer()
        }

  @typedoc "A Gall or plant as the rank pages' species tables show it."
  @type row :: %{
          id: integer(),
          name: String.t(),
          common_name: String.t() | nil,
          count: non_neg_integer()
        }

  @doc """
  The page a rank page's `name` parameter asks for: `{:redirect, path}` for
  an old numeric URL whose taxonomy ID the crosswalk knows, `{:ok, taxa}`
  (the taxa of `rank` with that accepted name, by ID; empty when none).
  """
  @spec lookup(String.t(), Gallformers.Taxa.Rank.t()) ::
          {:redirect, String.t()} | {:ok, [Taxon.t()]}
  def lookup(name, rank) do
    if TaxonomyURL.numeric?(name) do
      case TaxonomyURL.legacy_path(name) do
        nil -> {:ok, []}
        path -> {:redirect, path}
      end
    else
      {:ok, Taxa.get_by_name(name, rank)}
    end
  end

  @doc "A taxon's common names as its description (`\"Elms, Oaks\"`), or nil."
  @spec description(integer()) :: String.t() | nil
  def description(taxon_id) do
    case Taxa.list_common_names(taxon_id) do
      [] -> nil
      names -> Enum.map_join(names, ", ", & &1.name)
    end
  end

  @doc """
  The taxa directly under `taxon_id`, by name, each with the Galls whose
  Inducer is in its subtree (`gall_count`) and the plants in it
  (`host_count`).
  """
  @spec children(integer()) :: [child()]
  def children(taxon_id) do
    children = Taxa.children_with_ranks(taxon_id)
    ids = Enum.map(children, & &1.taxon_id)
    gall_counts = Catalog.count_galls_under(ids)
    host_counts = Taxa.count_plants_under(ids)

    Enum.map(children, fn child ->
      %{
        id: child.taxon_id,
        name: child.name,
        rank: Atom.to_string(child.rank),
        description: join(child.common_names),
        url: TaxonomyURL.public_path(child),
        gall_count: Map.fetch!(gall_counts, child.taxon_id),
        host_count: Map.fetch!(host_counts, child.taxon_id)
      }
    end)
  end

  @doc "The Galls whose current Inducer is one of `taxon_ids`, as rows by name."
  @spec galls_of_inducers([integer()]) :: [row()]
  def galls_of_inducers(taxon_ids),
    do: taxon_ids |> Catalog.list_galls_for_inducers() |> gall_rows()

  @doc "The children whose name, description or rank contains `query` (case-insensitive)."
  @spec filter_children([child()], String.t()) :: [child()]
  def filter_children(children, ""), do: children

  def filter_children(children, query) do
    query = String.downcase(query)

    Enum.filter(children, fn c ->
      String.contains?(String.downcase(c.name), query) ||
        (c.description != nil && String.contains?(String.downcase(c.description), query)) ||
        String.contains?(c.rank, query)
    end)
  end

  @doc "The children sorted by `:name`, `:type` (rank), `:gall_count` or `:host_count`."
  @spec sort_children([child()], atom(), :asc | :desc) :: [child()]
  def sort_children(children, sort_by, sort_dir) do
    sorted =
      Enum.sort_by(children, fn child ->
        case sort_by do
          :type -> child.rank
          :gall_count -> child.gall_count
          :host_count -> child.host_count
          _ -> String.downcase(child.name)
        end
      end)

    if sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  @doc "The next `{sort_by, sort_dir}` after a click on `column`: the same column flips direction."
  @spec toggle_sort(atom(), :asc | :desc, atom()) :: {atom(), :asc | :desc}
  def toggle_sort(sort_by, :asc, sort_by), do: {sort_by, :desc}
  def toggle_sort(sort_by, :desc, sort_by), do: {sort_by, :asc}
  def toggle_sort(_sort_by, _sort_dir, column), do: {column, :asc}

  @doc "The Galls with a current Host among `taxon_ids` (a genus as a whole), as rows by name."
  @spec galls_on_hosts([integer()]) :: [row()]
  def galls_on_hosts(taxon_ids),
    do: taxon_ids |> Catalog.list_galls_for_hosts() |> gall_rows()

  @doc "Gall cards (`Gallformers.Catalog`) as rows: each with its first common name and Host count."
  @spec gall_rows([Catalog.gall_card()]) :: [row()]
  def gall_rows(cards) do
    cards
    |> Catalog.add_gall_details()
    |> Enum.map(&%{id: &1.id, name: &1.name, common_name: &1.common_name, count: &1.host_count})
  end

  @doc "The plants in `taxon_id`'s subtree as rows: each with its first common name and Gall count."
  @spec host_rows(integer()) :: [row()]
  def host_rows(taxon_id) do
    plants = Taxa.list_plants_under(taxon_id)
    counts = plants |> Enum.map(& &1.id) |> Catalog.count_galls_for_hosts()

    Enum.map(
      plants,
      &%{id: &1.id, name: &1.name, common_name: &1.common_name, count: Map.fetch!(counts, &1.id)}
    )
  end

  @doc "The rows whose name or common name contains `query` (case-insensitive)."
  @spec filter_rows([row()], String.t()) :: [row()]
  def filter_rows(rows, ""), do: rows

  def filter_rows(rows, query) do
    query = String.downcase(query)

    Enum.filter(rows, fn row ->
      String.contains?(String.downcase(row.name), query) ||
        (row.common_name != nil && String.contains?(String.downcase(row.common_name), query))
    end)
  end

  @doc "The rows sorted by `:name`, `:common_name` or `:count`, `:asc` or `:desc`."
  @spec sort_rows([row()], atom(), :asc | :desc) :: [row()]
  def sort_rows(rows, sort_by, sort_dir) do
    sorted =
      Enum.sort_by(rows, fn row ->
        case sort_by do
          :common_name -> String.downcase(row.common_name || "zzz")
          :count -> row.count
          _ -> String.downcase(row.name)
        end
      end)

    if sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp join([]), do: nil
  defp join(names), do: Enum.join(names, ", ")
end
