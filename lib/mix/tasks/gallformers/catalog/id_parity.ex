defmodule Mix.Tasks.Gallformers.Catalog.IdParity do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Compares the ID tool's old query (`Gallformers.Galls.Identification`, over
  today's tables) with the new one (`Gallformers.Catalog.identify/1`, over
  `gall_index`) on the same database (`803b` Task 9): runs a sample of
  filter sets through both and prints every difference, classed.

  Run it on the converted production copy, after the catalog migration has
  filled the new tables (and `gall_index`). It only reads, and starts
  nothing but the repo:

      MIX_ENV=dev PGDATABASE=gallformers_taxogall mix gallformers.catalog.id_parity
      MIX_ENV=dev PGDATABASE=gallformers_taxogall mix gallformers.catalog.id_parity --hosts 100 --seed 7

  ## Filter sets

  The old tool needs a Host or a Host genus, so every set has one. For each
  of `--hosts` sampled plants with galls (default 40; `--seed`, default 1,
  makes the sample repeatable): the Host alone; with a place in its range
  and a place drawn from all places; with a Trait value of one of its
  galls; with a detachability; with the family of one of its galls'
  genera; undescribed only; and its genus, alone and with a place. Old IDs
  are translated as the new tool will: plants keep their IDs, taxonomy IDs
  go through `legacy_taxon_ids`, Trait IDs through the old vocabulary
  (`Gallformers.CatalogMigration.TraitIdExport`). The old query excludes
  non-galls (`ng=0`), which the new catalog does not hold.

  ## Classes

  A difference with a place filter that also shows without it is not the
  place's: it is classed on its own. Expected (`803b` §3, `b5bd` M5):

    * `introduced` — gained: a current Host's introduced range meets the
      place (the old tool read native ranges only).
    * `hosts_whole_range` — gained: the old tool read the gall's stored
      range; the new one its Hosts' whole range.

  Explained, for review:

    * `everywhere` — gained: the Gall has no range data, so it is in every
      region (`Gallformers.Catalog.ReadModels.PotentialRange`).
    * `placeholder_waiver` — lost: the old tool let a gall on the genus
      placeholder through any place filter with a genus selected. Rare
      since a genus Host's range became its species' (`803b` decision 8):
      only a place where no species of the genus grows.
    * `range_adjustment` — lost: a current range Fact (`exclude` /
      `only`) narrows the Gall's range.
    * `outside_hosts_range` — lost: the old stored range had the place,
      none of the Gall's Hosts grows there (nothing widens a range).
    * `no_inducer` — gained with "undescribed only": the Gall has no
      current Inducer, which the new rule (the Gall page's: no Inducer at
      species rank) counts as undescribed; the old flag did not.
    * `not_in_catalog` — the gall row is no Gall (an excluded non-gall).

  Anything else is `unexpected`.
  """
  use Mix.Task

  alias Gallformers.Catalog
  alias Gallformers.CatalogMigration.TraitIdExport
  alias Gallformers.Galls
  alias Gallformers.Places
  alias Gallformers.Repo
  alias Gallformers.Taxa

  @shortdoc "Compares the old and new ID tool queries on one database (read-only)"

  @expected [:introduced, :hosts_whole_range]
  @explained [
    :everywhere,
    :placeholder_waiver,
    :range_adjustment,
    :outside_hosts_range,
    :no_inducer,
    :not_in_catalog
  ]

  @old_trait_keys %{
    "color" => :color_ids,
    "shape" => :shape_ids,
    "texture" => :texture_ids,
    "alignment" => :alignment_ids,
    "cells" => :cells_ids,
    "walls" => :walls_ids,
    "form" => :form_ids,
    "season" => :season_ids,
    "plant_part" => :plant_part_ids
  }

  @typedoc """
  A filter set in the old tool's terms: `:host` (plant species ID),
  `:genus` / `:family` (old taxonomy IDs), `:trait` (`{table, old_id}`),
  `:detachable`, `:undescribed`, `:place` (a code).
  """
  @type filter_set :: map()

  @type difference :: %{
          set: filter_set(),
          gall_id: integer(),
          direction: :gained | :lost,
          class: atom()
        }

  @type report :: %{
          compared: non_neg_integer(),
          skipped: [{filter_set(), String.t()}],
          differences: [difference()]
        }

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [hosts: :integer, seed: :integer])

    start_repo()

    report =
      opts
      |> Keyword.get(:hosts, 40)
      |> sample(Keyword.get(opts, :seed, 1))
      |> compare()

    shell = Mix.shell()
    Enum.each(format(report), &shell.info/1)
  end

  @doc "The filter sets for `hosts` sampled plants, repeatable by `seed`."
  @spec sample(pos_integer(), integer()) :: [filter_set()]
  def sample(hosts, seed) do
    :rand.seed(:exsss, {seed, seed, seed})

    ("SELECT DISTINCT gh.host_species_id AS id FROM gallhost gh " <>
       "JOIN species s ON s.id = gh.host_species_id " <>
       "WHERE NOT s.genus_placeholder ORDER BY 1")
    |> rows([])
    |> Enum.map(& &1.id)
    |> Enum.take_random(hosts)
    |> Enum.sort()
    |> Enum.flat_map(&sets_for_host/1)
  end

  defp sets_for_host(host) do
    galls = rows("SELECT gall_species_id AS id FROM gallhost WHERE host_species_id = $1", [host])
    gall_ids = Enum.map(galls, & &1.id)

    in_range =
      rows(
        "SELECT p.code FROM host_range hr JOIN place p ON p.id = hr.place_id " <>
          "WHERE hr.species_id = $1 ORDER BY p.code",
        [host]
      )

    any_place =
      rows("SELECT code FROM place WHERE type IN ('state', 'province') ORDER BY code", [])

    genus =
      one(
        "SELECT t.id FROM species_taxonomy st JOIN taxonomy t ON t.id = st.taxonomy_id " <>
          "WHERE st.species_id = $1 AND t.type = 'genus' ORDER BY t.id LIMIT 1",
        [host]
      )

    [
      %{host: host},
      random(in_range, &%{host: host, place: &1.code}),
      random(any_place, &%{host: host, place: &1.code}),
      random(gall_traits(gall_ids), &%{host: host, trait: &1}),
      %{host: host, detachable: Enum.random(~w(integral detachable both))},
      random(gall_families(gall_ids), &%{host: host, family: &1}),
      %{host: host, undescribed: true},
      genus && %{genus: genus},
      genus && random(in_range, &%{genus: genus, place: &1.code})
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp random([], _fun), do: nil
  defp random(list, fun), do: fun.(Enum.random(list))

  # The old vocabulary rows {table, ID} the galls have.
  defp gall_traits([]), do: []

  defp gall_traits(gall_ids) do
    for table <- Map.keys(@old_trait_keys),
        %{id: id} <-
          rows(
            "SELECT DISTINCT #{table}_id AS id FROM gall_#{table} " <>
              "WHERE species_id = ANY($1) ORDER BY 1",
            [gall_ids]
          ) do
      {table, id}
    end
  end

  defp gall_families([]), do: []

  defp gall_families(gall_ids) do
    """
    WITH RECURSIVE up(id, parent_id, type) AS (
      SELECT t.id, t.parent_id, t.type FROM species_taxonomy st
      JOIN taxonomy t ON t.id = st.taxonomy_id
      WHERE st.species_id = ANY($1) AND t.type = 'genus'
      UNION
      SELECT t.id, t.parent_id, t.type FROM up JOIN taxonomy t ON t.id = up.parent_id
    )
    SELECT DISTINCT id FROM up WHERE type = 'family' ORDER BY id
    """
    |> rows([gall_ids])
    |> Enum.map(& &1.id)
  end

  @doc "Runs each filter set through both tools and classes every difference."
  @spec compare([filter_set()]) :: report()
  def compare(sets) do
    traits = trait_values()

    Enum.reduce(sets, %{compared: 0, skipped: [], differences: []}, fn set, acc ->
      case new_filters(set, traits) do
        {:ok, new} ->
          diffs = differences(set, old_filters(set), new)
          %{acc | compared: acc.compared + 1, differences: acc.differences ++ diffs}

        {:skip, reason} ->
          %{acc | skipped: acc.skipped ++ [{set, reason}]}
      end
    end)
  end

  defp trait_values do
    {mapped, _unmapped} = TraitIdExport.rows()
    Map.new(mapped, &{{&1.table, &1.old_id}, {&1.trait, &1.value}})
  end

  defp old_filters(set) do
    trait =
      case set[:trait] do
        {table, id} -> %{Map.fetch!(@old_trait_keys, table) => [id]}
        nil -> %{}
      end

    Map.merge(
      %{
        host_ids: set[:host] && [set[:host]],
        genus_id: set[:genus],
        family_id: set[:family],
        detachable: set[:detachable],
        undescribed: set[:undescribed] || false,
        place_codes: set[:place] && [set[:place]],
        exclude_non_galls: true
      },
      trait
    )
  end

  defp new_filters(set, traits) do
    with {:ok, host} <- plant(set[:host]),
         {:ok, genus} <- legacy_taxon(set[:genus]),
         {:ok, family} <- legacy_taxon(set[:family]),
         {:ok, trait} <- trait(set[:trait], traits) do
      {:ok,
       %{
         host_id: host,
         host_group_id: genus,
         inducer_family_id: family,
         traits: trait,
         detachable: set[:detachable],
         undescribed: set[:undescribed] || false,
         place_codes: set[:place] && [set[:place]]
       }}
    end
  end

  defp plant(nil), do: {:ok, nil}

  defp plant(id) do
    case Taxa.get_taxon(id) do
      nil -> {:skip, "plant #{id} is no taxon"}
      taxon -> {:ok, taxon.id}
    end
  end

  defp legacy_taxon(nil), do: {:ok, nil}

  defp legacy_taxon(old_id) do
    case Taxa.get_by_legacy_id(:taxonomy, old_id) do
      nil -> {:skip, "taxonomy #{old_id} has no taxon"}
      taxon -> {:ok, taxon.id}
    end
  end

  defp trait(nil, _traits), do: {:ok, %{}}

  defp trait({table, id}, traits) do
    case traits[{table, id}] do
      nil -> {:skip, "#{table} #{id} is no Trait value"}
      {trait, value} -> {:ok, %{trait => [value]}}
    end
  end

  defp differences(set, old, new) do
    old_ids = ids(Galls.filter_galls(old))
    new_ids = ids(Catalog.identify(new))

    {old_all, new_all} =
      if set[:place],
        do:
          {ids(Galls.filter_galls(%{old | place_codes: nil})),
           ids(Catalog.identify(%{new | place_codes: nil}))},
        else: {old_ids, new_ids}

    gained = for id <- MapSet.difference(new_ids, old_ids), do: {id, :gained}
    lost = for id <- MapSet.difference(old_ids, new_ids), do: {id, :lost}

    for {gall_id, direction} <- Enum.sort(gained ++ lost) do
      by_place? = MapSet.member?(old_all, gall_id) and MapSet.member?(new_all, gall_id)

      %{
        set: set,
        gall_id: gall_id,
        direction: direction,
        class: class(set, gall_id, direction, by_place?)
      }
    end
  end

  defp ids(results), do: MapSet.new(results, & &1.id)

  defp class(set, gall_id, direction, false) do
    cond do
      one("SELECT 1 FROM galls WHERE id = $1", [gall_id]) == nil ->
        :not_in_catalog

      set[:undescribed] && direction == :gained && Catalog.gall_summary(gall_id).inducers == [] ->
        :no_inducer

      true ->
        :unexpected
    end
  end

  defp class(set, gall_id, :gained, true) do
    places = place_and_relatives(set[:place])
    hosts = range_taxa(gall_id)

    cond do
      one("SELECT everywhere FROM gall_index WHERE gall_id = $1", [gall_id]) ->
        :everywhere

      host_range?(hosts, places, "introduced") and not host_range?(hosts, places, "native") ->
        :introduced

      one("SELECT 1 FROM gall_range WHERE species_id = $1 LIMIT 1", [gall_id]) &&
          host_range?(hosts, places, "native") ->
        :hosts_whole_range

      true ->
        :unexpected
    end
  end

  defp class(set, gall_id, :lost, true) do
    places = place_and_relatives(set[:place])
    hosts = range_taxa(gall_id)

    cond do
      set[:genus] && placeholder_in_genus?(gall_id, set[:genus]) ->
        :placeholder_waiver

      one(
        "SELECT 1 FROM range_facts r JOIN facts f ON f.id = r.fact_id " <>
            "WHERE r.gall_id = $1 AND f.standing = 'current' LIMIT 1",
        [gall_id]
      ) ->
        :range_adjustment

      not host_range?(hosts, places, "native") and not host_range?(hosts, places, "introduced") ->
        :outside_hosts_range

      true ->
        :unexpected
    end
  end

  # The taxa whose host-range rows make the Gall's range: its current Hosts,
  # a Host above species rank with its subtree (`803b` decision 8, as
  # `Gallformers.Catalog.ReadModels.PotentialRange` reads them).
  defp range_taxa(gall_id) do
    {species, groups} =
      gall_id
      |> Catalog.gall_summary()
      |> Map.fetch!(:hosts)
      |> Enum.split_with(&(&1.rank in Taxa.Rank.species_and_below()))

    subtrees = groups |> Enum.map(& &1.taxon_id) |> Taxa.subtree_ids()

    Enum.uniq(
      Enum.map(species, & &1.taxon_id) ++
        Enum.flat_map(groups, &Map.get(subtrees, &1.taxon_id, [&1.taxon_id]))
    )
  end

  # The place, its descendants and its ancestors (how the old tool matched).
  defp place_and_relatives(code) do
    case Places.get_place_by_code(code) do
      nil -> []
      place -> Enum.uniq(Places.descendant_ids(place.id) ++ Places.ancestor_ids(place.id))
    end
  end

  defp host_range?([], _places, _distribution), do: false

  defp host_range?(hosts, places, distribution) do
    one(
      "SELECT 1 FROM host_range WHERE taxon_id = ANY($1) AND place_id = ANY($2) " <>
        "AND distribution_type = $3 LIMIT 1",
      [hosts, places, distribution]
    ) == 1
  end

  defp placeholder_in_genus?(gall_id, genus) do
    one(
      "SELECT 1 FROM gallhost gh JOIN species s ON s.id = gh.host_species_id " <>
        "JOIN species_taxonomy st ON st.species_id = s.id " <>
        "WHERE gh.gall_species_id = $1 AND s.genus_placeholder AND st.taxonomy_id = $2 LIMIT 1",
      [gall_id, genus]
    ) == 1
  end

  @doc "The report as lines to print."
  @spec format(report()) :: [String.t()]
  def format(report) do
    by_class = Enum.group_by(report.differences, & &1.class)
    names = gall_names(report.differences)

    summary =
      for {label, classes} <- [
            {"Expected", @expected},
            {"Explained (review)", @explained},
            {"Unexpected", [:unexpected]}
          ],
          class <- classes do
        "  #{label}: #{class}: #{length(Map.get(by_class, class, []))}"
      end

    details =
      for {class, diffs} <- Enum.sort(by_class) do
        shown = if class == :unexpected, do: diffs, else: Enum.take(diffs, 10)

        [
          "#{class} (#{length(diffs)}#{if length(shown) < length(diffs), do: ", first 10", else: ""}):"
        ] ++
          for d <- shown do
            "  #{d.direction} #{d.gall_id} #{names[d.gall_id]} — #{inspect(d.set)}"
          end
      end

    skipped = for {set, reason} <- report.skipped, do: "  #{inspect(set)}: #{reason}"

    [
      "ID tool parity: #{report.compared} filter sets compared, #{length(report.skipped)} skipped",
      "Differences (gall × filter set):"
    ] ++
      summary ++ List.flatten(details) ++ if(skipped == [], do: [], else: ["Skipped:" | skipped])
  end

  defp gall_names([]), do: %{}

  defp gall_names(differences) do
    "SELECT id, name FROM species WHERE id = ANY($1)"
    |> rows([Enum.uniq(Enum.map(differences, & &1.gall_id))])
    |> Map.new(&{&1.id, &1.name})
  end

  # -- SQL ---------------------------------------------------------------------------

  defp rows(sql, params) do
    %{columns: columns, rows: rows} = Repo.query!(sql, params)
    keys = Enum.map(columns, &String.to_existing_atom/1)
    Enum.map(rows, &(keys |> Enum.zip(&1) |> Map.new()))
  end

  defp one(sql, params) do
    case Repo.query!(sql, params).rows do
      [[value] | _] -> value
      [] -> nil
    end
  end

  # The repo only: this task reads, and must not start Oban's queues on the
  # database it reads.
  defp start_repo do
    Mix.Task.run("app.config")
    # Hundreds of queries: no per-query debug log.
    if Logger.compare_levels(Logger.level(), :info) == :lt, do: Logger.configure(level: :info)
    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)

    case Repo.start_link(pool_size: 2) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
