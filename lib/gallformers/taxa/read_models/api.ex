defmodule Gallformers.Taxa.ReadModels.Api do
  @moduledoc """
  Taxon reads for API v2 (`803b` Task 13): the paged host (plant) and taxon
  lists, one taxon's summary, the sections list and batched synonyms.

  "Plants" are Plantae taxa at species rank or below, as in
  `Gallformers.Taxa.ReadModels.Browse`. A list's `:q` finds taxa as the
  global search does (`Gallformers.Taxa.search_ids/2`: every word in the
  accepted name, a synonym or a common name); lists are by accepted name,
  then ID, so pages are stable.

  A taxon's `description` is its common names joined (`803b` decision 7:
  today's taxonomy descriptions became common names), or nil.
  """
  import Ecto.Query

  alias Gallformers.Repo
  alias Gallformers.Taxa.Ancestry
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.ReadModels.Browse
  alias Gallformers.Taxa.ReadModels.Search
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.TaxonName

  @typedoc "Paging options: `:q` (a search query; blank for none), `:limit` (nil for all), `:offset`."
  @type page_opts :: [q: String.t() | nil, limit: pos_integer() | nil, offset: non_neg_integer()]

  @type page(entry) :: %{entries: [entry], total: non_neg_integer()}

  @type plant :: %{id: integer(), name: String.t(), datacomplete: boolean()}

  @type summary :: %{
          id: integer(),
          name: String.t(),
          rank: Rank.t(),
          parent_id: integer() | nil,
          description: String.t() | nil
        }

  @type section :: %{
          id: integer(),
          name: String.t(),
          description: String.t() | nil,
          genus_id: integer() | nil,
          genus_name: String.t() | nil,
          species_count: non_neg_integer()
        }

  @type synonym :: %{id: integer(), name: String.t(), sensu: String.t() | nil}

  @doc "A page of plants, by accepted name, with how many there are in all (matching `:q`)."
  @spec paginate_plants(page_opts()) :: page(plant())
  def paginate_plants(opts) when is_list(opts) do
    base = from(t in Taxon, where: t.kingdom == "Plantae" and t.rank in ^Rank.species_and_below())

    paginate(base, opts, [ranks: Rank.species_and_below(), kingdom: "Plantae"], fn query ->
      from([t, n] in query, select: %{id: t.id, name: n.name, datacomplete: t.datacomplete})
      |> Repo.all()
    end)
  end

  @doc "A page of the taxa of `rank`, by accepted name, with how many there are in all (matching `:q`)."
  @spec paginate_taxa(Rank.t(), page_opts()) :: page(summary())
  def paginate_taxa(rank, opts) when is_atom(rank) and is_list(opts) do
    paginate(from(t in Taxon, where: t.rank == ^rank), opts, [ranks: [rank]], &summaries/1)
  end

  @doc "One taxon as `paginate_taxa/2` lists it, or nil."
  @spec taxon_summary(integer()) :: summary() | nil
  def taxon_summary(id) when is_integer(id) do
    from(t in Taxon, where: t.id == ^id) |> named() |> summaries() |> List.first()
  end

  @doc """
  Every section, by its genus's name and its own, with its genus (the
  nearest genus above it) and how many plants its subtree holds.
  """
  @spec list_sections() :: [section()]
  def list_sections do
    sections = from(t in Taxon, where: t.rank == :section) |> named() |> summaries()
    ids = Enum.map(sections, & &1.id)

    genera =
      from(a in Ancestry,
        join: g in Taxon,
        on: g.id == a.ancestor_id and g.rank == :genus,
        join: n in TaxonName,
        on: n.taxon_id == g.id and n.status == :accepted,
        where: a.descendant_id in ^ids,
        select: {a.descendant_id, %{id: g.id, name: n.name}}
      )
      |> Repo.all()
      |> Map.new()

    counts = Browse.count_plants_under(ids)

    sections
    |> Enum.map(fn section ->
      genus = Map.get(genera, section.id, %{id: nil, name: nil})

      %{
        id: section.id,
        name: section.name,
        description: section.description,
        genus_id: genus.id,
        genus_name: genus.name,
        species_count: Map.get(counts, section.id, 0)
      }
    end)
    |> Enum.sort_by(&{&1.genus_name || "", &1.name, &1.id})
  end

  @doc "Each taxon's synonyms (`%{id, name, sensu}`), in the order added, by taxon ID (taxa without any left out)."
  @spec list_synonyms_by_taxon([integer()]) :: %{integer() => [synonym()]}
  def list_synonyms_by_taxon([]), do: %{}

  def list_synonyms_by_taxon(taxon_ids) when is_list(taxon_ids) do
    from(n in TaxonName,
      where: n.taxon_id in ^Enum.uniq(taxon_ids) and n.status == :synonym,
      order_by: [n.taxon_id, n.id],
      select: {n.taxon_id, %{id: n.id, name: n.name, sensu: n.sensu}}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # -- paging ------------------------------------------------------------------

  # `base` (taxa `t`) narrowed by `:q` through the search, ordered by accepted
  # name `n`, paged, and read by `read`.
  defp paginate(base, opts, search_opts, read) do
    {query, total} =
      case query_text(opts[:q]) do
        nil ->
          {base, Repo.aggregate(base, :count)}

        q ->
          ids = Search.taxon_ids(q, search_opts)
          {from(t in base, where: t.id in ^ids), length(ids)}
      end

    entries =
      query
      |> named()
      |> order_by([t, n], [n.name, t.id])
      |> offset(^(opts[:offset] || 0))
      |> limit_to(opts[:limit])
      |> read.()

    %{entries: entries, total: total}
  end

  defp query_text(q) when is_binary(q) do
    case String.trim(q) do
      "" -> nil
      text -> text
    end
  end

  defp query_text(_q), do: nil

  defp limit_to(query, nil), do: query
  defp limit_to(query, limit), do: limit(query, ^limit)

  # Taxa `t` joined to their accepted names `n`.
  defp named(query) do
    from(t in query, join: n in TaxonName, on: n.taxon_id == t.id and n.status == :accepted)
  end

  defp summaries(query) do
    taxa =
      from([t, n] in query,
        select: %{id: t.id, name: n.name, rank: t.rank, parent_id: t.parent_id}
      )
      |> Repo.all()

    common = taxa |> Enum.map(& &1.id) |> Browse.common_names()

    Enum.map(taxa, fn taxon ->
      description =
        case Map.get(common, taxon.id, []) do
          [] -> nil
          names -> Enum.join(names, ", ")
        end

      Map.put(taxon, :description, description)
    end)
  end
end
