defmodule Gallformers.Catalog.Identify do
  @moduledoc """
  The ID tool's query (`803b` §3, Task 9): one query over the lookup table
  (`Gallformers.Catalog.ReadModels.GallIndex`), so a filter change costs a
  query, not a pass over every Gall.

  ## Filters

  A map; every filter given must hold, and a filter that is absent, `nil`,
  empty or `false` filters nothing.

    * `:host_id` — a plant taxon: Galls with it as a current Host.
    * `:host_group_id` — a Host genus or section (any taxon): Galls with a
      current Host in its subtree, the taxon itself included, so a genus
      finds the Galls whose Host is the genus (today's genus placeholders).
    * `:inducer_family_id` — Galls whose current Inducer is in the taxon's
      subtree (the family itself, for an Inducer placed at the family).
    * `:traits` — `%{trait => [value]}` by name (`"color" => ["red"]`): a
      Gall matches a Trait when it has any of the values, or all of them
      when `:trait_logic` says `%{trait => :and}` (the tool offers that for
      plant parts and textures). A value the vocabulary lacks matches
      nothing.
    * `:detachable` — `"integral"` or `"detachable"` (each also matching
      `"both"`), or `"both"`; `"unknown"` filters nothing.
    * `:undescribed` — `true` for undescribed Galls only.
    * `:place_codes` — place codes (a state, a country, a continent): Galls
      whose potential range meets any of the places' leaves, and Galls whose
      range is every region (no range data). A code that is no place leaves
      only those.

  Non-galls are not in the catalog, and a match carries no tag saying how
  its place matched (`803b` decision 2): every place match is the potential
  range.

  ## Results

  Each matching Gall, by name: `%{id, name, undescribed, detachable,
  image_url, traits}` — `image_url` the default image's small size (or
  nil), `traits` its current Trait values by Trait (as
  `Gallformers.Catalog.ReadModels.GallSummary` gives them, for
  `Gallformers.Galls.Summary.from_traits/1`). Two queries, whatever the
  number of results.
  """
  import Ecto.Query

  alias Gallformers.Catalog.ReadModels.GallIndex
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Images.Image
  alias Gallformers.Places
  alias Gallformers.Repo
  alias Gallformers.Taxa

  @type filters :: %{
          optional(:host_id) => integer() | nil,
          optional(:host_group_id) => integer() | nil,
          optional(:inducer_family_id) => integer() | nil,
          optional(:traits) => %{String.t() => [String.t()]} | nil,
          optional(:trait_logic) => %{String.t() => :and | :or} | nil,
          optional(:detachable) => String.t() | nil,
          optional(:undescribed) => boolean() | nil,
          optional(:place_codes) => [String.t()] | nil
        }

  @type result :: %{
          id: integer(),
          name: String.t(),
          undescribed: boolean(),
          detachable: String.t() | nil,
          image_url: String.t() | nil,
          traits: %{String.t() => [String.t()]}
        }

  @type family :: %{id: integer(), name: String.t()}

  @doc "The Galls matching `filters`, by name."
  @spec identify(filters()) :: [result()]
  def identify(filters) when is_map(filters) do
    rows =
      from(g in query(filters),
        left_join: i in Image,
        on: i.id == g.image_id,
        order_by: [g.name, g.gall_id],
        select: %{
          id: g.gall_id,
          name: g.name,
          undescribed: g.undescribed,
          detachable: g.detachable,
          image_path: i.path,
          trait_value_ids: g.trait_value_ids
        }
      )
      |> Repo.all()

    values = Map.new(Repo.all(TraitValue), &{&1.id, &1})

    Enum.map(rows, fn row ->
      %{
        id: row.id,
        name: row.name,
        undescribed: row.undescribed,
        detachable: row.detachable,
        image_url: row.image_path && Image.sized_url(row.image_path, :small),
        traits: traits(row.trait_value_ids, values)
      }
    end)
  end

  @doc "How many Galls match `filters`."
  @spec count_identified(filters()) :: non_neg_integer()
  def count_identified(filters) when is_map(filters) do
    Repo.one(from(g in query(filters), select: count(g.gall_id)))
  end

  @doc "Each Trait's values (with their definitions), by Trait, each list by value."
  @spec options() :: %{String.t() => [TraitValue.t()]}
  def options do
    from(v in TraitValue, order_by: [v.trait, v.value])
    |> Repo.all()
    |> Enum.group_by(& &1.trait)
  end

  @doc """
  The families of the current Inducers of the Galls with a current Host in
  the subtree of one of `taxon_ids` (a Host, or a Host genus or section),
  by name.
  """
  @spec gall_families_for_hosts([integer()]) :: [family()]
  def gall_families_for_hosts([]), do: []

  def gall_families_for_hosts(taxon_ids) when is_list(taxon_ids) do
    from(g in GallIndex,
      where:
        not is_nil(g.inducer_taxon_id) and
          fragment("? && ?::bigint[]", g.host_ancestor_ids, ^taxon_ids),
      distinct: true,
      select: g.inducer_taxon_id
    )
    |> Repo.all()
    |> Taxa.lineages()
    |> Map.values()
    |> List.flatten()
    |> Enum.filter(&(&1.rank == :family))
    |> Enum.uniq_by(& &1.taxon_id)
    |> Enum.map(&%{id: &1.taxon_id, name: &1.name})
    |> Enum.sort_by(&{&1.name, &1.id})
  end

  # -- the query -----------------------------------------------------------------

  defp query(filters) do
    from(g in GallIndex)
    |> host(filters[:host_id])
    |> host_group(filters[:host_group_id])
    |> inducer_family(filters[:inducer_family_id])
    |> traits_filter(filters[:traits] || %{}, filters[:trait_logic] || %{})
    |> detachable(filters[:detachable])
    |> undescribed(filters[:undescribed])
    |> place(filters[:place_codes])
  end

  defp host(query, nil), do: query

  defp host(query, taxon_id),
    do: where(query, [g], fragment("? = ANY(?)", ^taxon_id, g.host_taxon_ids))

  defp host_group(query, nil), do: query

  defp host_group(query, taxon_id),
    do: where(query, [g], fragment("? = ANY(?)", ^taxon_id, g.host_ancestor_ids))

  defp inducer_family(query, nil), do: query

  defp inducer_family(query, taxon_id),
    do: where(query, [g], fragment("? = ANY(?)", ^taxon_id, g.inducer_ancestor_ids))

  defp traits_filter(query, traits, logic) do
    wanted =
      for {trait, values} <- traits, values not in [nil, []], do: {trait, Enum.uniq(values)}

    ids = trait_value_ids(Enum.map(wanted, &elem(&1, 0)))

    Enum.reduce(wanted, query, fn {trait, values}, query ->
      found = for value <- values, id = ids[{trait, value}], do: id
      trait_filter(query, Map.get(logic, trait, :or), found, length(values))
    end)
  end

  # The IDs of the values of `traits`, by {trait, value}.
  defp trait_value_ids([]), do: %{}

  defp trait_value_ids(traits) do
    from(v in TraitValue, where: v.trait in ^traits, select: {{v.trait, v.value}, v.id})
    |> Repo.all()
    |> Map.new()
  end

  # `found` are the known values' IDs of the `wanted` asked for.
  defp trait_filter(query, _logic, [], _wanted), do: where(query, [_g], false)

  defp trait_filter(query, :and, found, wanted) when length(found) < wanted,
    do: where(query, [_g], false)

  defp trait_filter(query, :and, found, _wanted),
    do: where(query, [g], fragment("? @> ?::bigint[]", g.trait_value_ids, ^found))

  defp trait_filter(query, _or, found, _wanted),
    do: where(query, [g], fragment("? && ?::bigint[]", g.trait_value_ids, ^found))

  defp detachable(query, value) when value in [nil, "", "unknown"], do: query
  defp detachable(query, "both"), do: where(query, [g], g.detachable == "both")

  defp detachable(query, value) when value in ["integral", "detachable"],
    do: where(query, [g], g.detachable in [^value, "both"])

  defp undescribed(query, true), do: where(query, [g], g.undescribed)
  defp undescribed(query, _), do: query

  defp place(query, codes) when codes in [nil, []], do: query

  defp place(query, codes) when is_list(codes) do
    leaves =
      codes
      |> Enum.map(&Places.get_place_by_code/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.id)
      |> Places.batch_leaf_descendant_ids()

    where(query, [g], g.everywhere or fragment("? && ?::bigint[]", g.place_ids, ^leaves))
  end

  defp traits(value_ids, values) do
    value_ids
    |> Enum.map(&Map.fetch!(values, &1))
    |> Enum.sort_by(&{&1.trait, &1.value})
    |> Enum.group_by(& &1.trait, & &1.value)
  end
end
