defmodule Gallformers.Catalog.ReadModels.Browse do
  @moduledoc """
  Gall reads for the rank pages and the Galls browse tree (`803b` Task 6),
  from current `inducer_of` and `host_of` Facts and the taxon lineages
  `Gallformers.Taxa` gives (batched, a few queries per page).

  A Gall sits under its Inducer: its family and genus are the Inducer's
  (the Inducer itself when it is a genus). A Gall whose Inducer ranks above
  genus (undescribed, placed at a family or tribe) sits in an "Unknown
  (<Inducer>)" genus node, as today's placeholder genera did, linking to
  its Inducer's page. A Gall without an Inducer, or whose Inducer has no
  family, is in no tree.
  """
  import Ecto.Query

  alias Gallformers.Catalog.Facts.AliasFact
  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Facts.Fact
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.TreeBuilder

  @typedoc "A genus related to a list's Galls or plants (the genus page's filters)."
  @type related_genus :: %{
          taxon_id: integer(),
          name: String.t(),
          focal_ids: [integer()],
          association_count: non_neg_integer()
        }

  @doc "The Galls browse tree (`Gallformers.Taxa.TreeBuilder` shape), every Gall with an Inducer."
  @spec gall_tree() :: [map()]
  def gall_tree, do: tree(fn _inducer -> true end)

  @doc "The Galls browse tree of the undescribed Galls: those whose Inducer ranks above species."
  @spec undescribed_gall_tree() :: [map()]
  def undescribed_gall_tree, do: tree(&(&1.rank not in Rank.species_and_below()))

  defp tree(keep?) do
    galls =
      Repo.all(
        from(r in Current.relationships("inducer_of"),
          join: g in Gall,
          on: g.id == r.object_gall_id,
          select: {g.id, fragment("COALESCE(?, ?)", g.name_override, g.name), r.subject_taxon_id}
        )
      )

    lineages = galls |> Enum.map(&elem(&1, 2)) |> Taxa.lineages()

    rows =
      for {gall_id, name, inducer_id} <- galls,
          lineage = Map.get(lineages, inducer_id, []),
          inducer = List.last(lineage),
          family = Enum.find(lineage, &(&1.rank == :family)),
          inducer != nil and family != nil and keep?.(inducer),
          genus = genus_of(lineage, inducer),
          genus != nil do
        %{family: family, genus: genus, leaf_id: gall_id, leaf_name: name}
      end

    described =
      rows
      |> Enum.flat_map(&[&1.family.taxon_id, &1.genus.taxon_id])
      |> Taxa.common_names()

    rows
    |> Enum.map(fn row ->
      %{
        family_id: row.family.taxon_id,
        family_name: row.family.name,
        family_description: describe(described, row.family.taxon_id),
        genus_id: row.genus.taxon_id,
        genus_name: row.genus.name,
        genus_description: describe(described, row.genus.taxon_id),
        genus_url: row.genus.url,
        leaf_id: row.leaf_id,
        leaf_name: row.leaf_name
      }
    end)
    |> Enum.sort_by(&{&1.family_name, &1.family_id, &1.genus_name, &1.genus_id, &1.leaf_name})
    |> TreeBuilder.build_tree("/gall/")
  end

  # The genus node of a Gall: its Inducer's genus, or for an Inducer above
  # genus an "Unknown (<Inducer>)" node linking to the Inducer's page.
  defp genus_of(lineage, inducer) do
    case Enum.find(lineage, &(&1.rank == :genus)) do
      %{} = genus ->
        Map.put(genus, :url, TreeBuilder.rank_path(:genus, genus.name))

      nil ->
        if Rank.below?(:genus, inducer.rank) do
          %{
            taxon_id: inducer.taxon_id,
            name: "Unknown (#{inducer.name})",
            url: TreeBuilder.rank_path(inducer.rank, inducer.name)
          }
        end
    end
  end

  defp describe(common_names, taxon_id) do
    case Map.get(common_names, taxon_id, []) do
      [] -> nil
      names -> Enum.join(names, ", ")
    end
  end

  @doc "How many Galls have a current Inducer in each taxon's subtree, by taxon ID."
  @spec count_galls_under([integer()]) :: %{integer() => non_neg_integer()}
  def count_galls_under([]), do: %{}

  def count_galls_under(taxon_ids) when is_list(taxon_ids) do
    subtrees = Taxa.subtree_ids(taxon_ids)

    galls_by_inducer =
      from(r in Current.relationships("inducer_of"),
        where: r.subject_taxon_id in ^Enum.uniq(List.flatten(Map.values(subtrees))),
        select: {r.subject_taxon_id, r.object_gall_id}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Map.new(taxon_ids, fn id ->
      count =
        subtrees
        |> Map.get(id, [])
        |> Enum.flat_map(&Map.get(galls_by_inducer, &1, []))
        |> Enum.uniq()
        |> length()

      {id, count}
    end)
  end

  @doc """
  Each card's first common name (a current `common_name` alias Fact, by
  name) and its number of current Hosts, added as `:common_name` and
  `:host_count`.
  """
  @spec add_gall_details([map()]) :: [map()]
  def add_gall_details([]), do: []

  def add_gall_details(cards) when is_list(cards) do
    ids = Enum.map(cards, & &1.id)

    common_names =
      from(a in AliasFact,
        join: f in Fact,
        on: f.id == a.fact_id,
        where: a.gall_id in ^ids and a.kind == :common_name and f.standing == :current,
        order_by: [a.gall_id, a.name],
        select: {a.gall_id, a.name}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    host_counts =
      from(r in Current.relationships("host_of"),
        where: r.object_gall_id in ^ids,
        group_by: r.object_gall_id,
        select: {r.object_gall_id, count(r.subject_taxon_id, :distinct)}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(cards, fn card ->
      card
      |> Map.put(:common_name, common_names |> Map.get(card.id, []) |> List.first())
      |> Map.put(:host_count, Map.get(host_counts, card.id, 0))
    end)
  end

  @doc "How many Galls have a current Host Fact on each taxon, by taxon ID."
  @spec count_galls_for_hosts([integer()]) :: %{integer() => non_neg_integer()}
  def count_galls_for_hosts([]), do: %{}

  def count_galls_for_hosts(taxon_ids) when is_list(taxon_ids) do
    counts =
      from(r in Current.relationships("host_of"),
        where: r.subject_taxon_id in ^taxon_ids,
        group_by: r.subject_taxon_id,
        select: {r.subject_taxon_id, count(r.object_gall_id, :distinct)}
      )
      |> Repo.all()
      |> Map.new()

    Map.new(taxon_ids, &{&1, Map.get(counts, &1, 0)})
  end

  @doc """
  The genera of the current Hosts of `gall_ids` (a Host's genus, or the
  Host itself when it is a genus), by name: for each, the Galls on it
  (`focal_ids`) and how many Gall–Host pairs.
  """
  @spec host_genera_of_galls([integer()]) :: [related_genus()]
  def host_genera_of_galls([]), do: []

  def host_genera_of_galls(gall_ids) when is_list(gall_ids) do
    from(r in Current.relationships("host_of"),
      where: r.object_gall_id in ^gall_ids,
      distinct: true,
      select: {r.object_gall_id, r.subject_taxon_id}
    )
    |> Repo.all()
    |> related_genera(fn {gall_id, host_id} -> {gall_id, host_id, {gall_id, host_id}} end)
  end

  @doc """
  The genera of the current Inducers of the Galls on `host_ids` (an
  Inducer's genus, or the Inducer itself when it is a genus), by name: for
  each, the hosts with such a Gall (`focal_ids`) and how many Host–Gall
  pairs.
  """
  @spec inducer_genera_on_hosts([integer()]) :: [related_genus()]
  def inducer_genera_on_hosts([]), do: []

  def inducer_genera_on_hosts(host_ids) when is_list(host_ids) do
    from(h in Current.relationships("host_of"),
      join: i in subquery(Current.relationships("inducer_of")),
      on: i.object_gall_id == h.object_gall_id,
      where: h.subject_taxon_id in ^host_ids,
      distinct: true,
      select: {h.subject_taxon_id, h.object_gall_id, i.subject_taxon_id}
    )
    |> Repo.all()
    |> related_genera(fn {host_id, gall_id, inducer_id} ->
      {host_id, inducer_id, {host_id, gall_id}}
    end)
  end

  # `rows` mapped by `split` to {focal ID, related taxon ID, pair}: grouped
  # by the related taxon's genus.
  defp related_genera(rows, split) do
    rows = Enum.map(rows, split)
    lineages = rows |> Enum.map(&elem(&1, 1)) |> Taxa.lineages()

    rows
    |> Enum.flat_map(fn {focal, related, pair} ->
      case Enum.find(Map.get(lineages, related, []), &(&1.rank == :genus)) do
        nil -> []
        genus -> [{genus, focal, pair}]
      end
    end)
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {genus, entries} ->
      %{
        taxon_id: genus.taxon_id,
        name: genus.name,
        focal_ids: entries |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort(),
        association_count: entries |> Enum.map(&elem(&1, 2)) |> Enum.uniq() |> length()
      }
    end)
    |> Enum.sort_by(&{&1.name, &1.taxon_id})
  end
end
