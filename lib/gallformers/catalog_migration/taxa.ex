defmodule Gallformers.CatalogMigration.Taxa do
  @moduledoc """
  The skeletal taxonomy, taken as today's tables define it (`9449` §6,
  Task 15; `b5bd` M2):

    * **Higher taxa** — each `taxonomy` row becomes a taxon with a new ID
      from `entity_id_seq`, under its parent's taxon, with a `:taxonomy`
      crosswalk entry (`legacy_taxon_ids`). Families take their kingdom from
      their description (the old "type": Plant → Plantae, Wasp → Animalia,
      Fungus → Fungi, ...), or from `kingdoms.csv`
      (`Gallformers.CatalogMigration.Kingdoms`) where a curator set it;
      everything below inherits it. Taxa in Plantae are `:powo`, the rest
      `:curated`. Intermediate ranks the contract does not have
      (Infrafamily, Supertribe, Infratribe) are skipped, their children
      attached to the nearest taxon above, and reported.
    * **Merged rows** (`taxon_merges.csv`,
      `Gallformers.CatalogMigration.TaxonMerges`) — a row kept twice today
      becomes no taxon of its own: its crosswalk entry points at the taxon
      of the row it merges into, and what is below it attaches there. It
      is placed after that row.
    * **Placeholders** — a placeholder genus ("Unknown (Cynipidae)") is no
      taxon: its crosswalk entry points at its family, and the "Unknown"
      family (with its "Unknown (Unknown)" genus) is no taxon at all.
    * **Plants** — each plant `species` row becomes a species-rank (or
      variety, subspecies, form, by its name) taxon keeping its ID, origin
      `:powo`, kingdom Plantae, under its section or else its genus.
    * **Genus placeholder plants** ("Quercus spp.") become no taxon; they
      stand for their genus taxon.
    * **`host_range`** is re-keyed by `taxon_id`: a plant's rows to its own
      ID, a genus placeholder's rows to its genus taxon.

  Taxa are created through `Gallformers.Taxa.create_taxon/2`, which keeps
  the ancestry closure (depth-0 rows included) and validates each parent.
  """

  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank

  @intermediate_ranks %{"Subfamily" => :subfamily, "Tribe" => :tribe, "Subtribe" => :subtribe}

  # The old family "type" (its description) → kingdom. Viruses have none.
  @kingdoms %{
    "Plant" => "Plantae",
    "Plant (gall forming)" => "Plantae",
    "Wasp" => "Animalia",
    "Midge" => "Animalia",
    "Mite" => "Animalia",
    "Fly" => "Animalia",
    "Aphid" => "Animalia",
    "Moth" => "Animalia",
    "Beetle" => "Animalia",
    "Sawfly" => "Animalia",
    "Psyllid" => "Animalia",
    "Scale" => "Animalia",
    "Thrips" => "Animalia",
    "True Bug" => "Animalia",
    "Nematode" => "Animalia",
    "Fungus" => "Fungi",
    "Bacteria" => "Bacteria",
    "Oomycete" => "Chromista",
    "Virus" => nil
  }

  @type taxon_info :: %{
          name: String.t(),
          rank: Rank.t(),
          kingdom: String.t() | nil,
          parent: integer() | nil
        }

  @type t :: %{
          rows: %{integer() => map()},
          anchors: %{integer() => integer() | nil},
          taxa: %{integer() => taxon_info()},
          plants: %{integer() => integer() | nil}
        }

  @typedoc """
  The curated decisions on taxonomy rows, checked against today's rows:
  `merges` (merged old ID → the old ID it merges into), `kingdoms` (old
  family ID → kingdom) and `stale` (rows not used, as report lines by
  decision file).
  """
  @type decisions :: %{
          merges: %{integer() => integer()},
          kingdoms: %{integer() => String.t()},
          stale: [{String.t(), [String.t()]}]
        }

  @doc """
  Builds the higher taxa and plants and re-keys `host_range`, as `actor`,
  applying the curated `decisions`.

  Returns the crosswalk the later steps use: `rows` (old taxonomy rows by
  ID), `anchors` (old taxonomy ID → the taxon its children and species
  attach to, nil for the Unknown family), `taxa` (taxa created, by ID) and
  `plants` (plant species ID → taxon ID; a genus placeholder → its genus
  taxon, or nil).
  """
  @spec run(Gallformers.Audit.Actor.t(), decisions(), Report.t()) :: {t(), Report.t()}
  def run(actor, decisions, report) do
    {ctx, report} = higher_taxa(actor, decisions, report)
    {ctx, report} = plants(actor, ctx, report)
    report = rekey_host_range(ctx, report)
    {ctx, report}
  end

  # -- higher taxa ---------------------------------------------------------------

  defp higher_taxa(actor, decisions, report) do
    rows = Old.taxonomy()
    by_id = Map.new(rows, &{&1.id, &1})
    ordered = top_down(rows, decisions.merges)

    acc = %{
      ctx: %{rows: by_id, anchors: %{}, taxa: %{}, plants: %{}},
      merges: decisions.merges,
      kingdoms: decisions.kingdoms,
      created: 0,
      merged: 0,
      placeholders: 0,
      unknown: 0,
      skipped: [],
      problems: []
    }

    acc = Enum.reduce(ordered, acc, &place_row(actor, &1, &2))

    unreached =
      for row <- rows, not Map.has_key?(acc.ctx.anchors, row.id), do: row_label(row)

    report =
      report
      |> Report.reconcile("Higher taxa (taxonomy rows)", length(rows), acc.created, [
        {"merged into another taxon (taxon_merges.csv)", acc.merged},
        {"placeholder genera (crosswalk to their family)", acc.placeholders},
        {"Unknown families", acc.unknown},
        {"skipped intermediate ranks", length(acc.skipped)},
        {"unreachable from a root", length(unreached)}
      ])
      |> Report.problems("unmapped rank", Enum.reverse(acc.skipped))
      |> Report.problems("taxonomy", Enum.reverse(acc.problems))
      |> Report.problems("unreachable taxonomy row", unreached)

    report =
      Enum.reduce(decisions.stale, report, fn {input, details}, report ->
        Report.problems(report, input, details)
      end)

    {acc.ctx, report}
  end

  # Parents before children; siblings by name, then ID. A merged row (with
  # everything below it) waits until the row it merges into is placed.
  defp top_down(rows, merges) do
    children = Enum.group_by(rows, & &1.parent_id)
    state = %{out: [], placed: MapSet.new(), deferred: []}

    Map.get(children, nil, [])
    |> walk(children, merges, state)
    |> retry_deferred(children, merges)
    |> Map.fetch!(:out)
    |> Enum.reverse()
  end

  defp walk(level, children, merges, state) do
    level
    |> Enum.sort_by(&{&1.name, &1.id})
    |> Enum.reduce(state, fn row, state ->
      into = merges[row.id]

      if into && not MapSet.member?(state.placed, into) do
        %{state | deferred: [row | state.deferred]}
      else
        state = %{state | out: [row | state.out], placed: MapSet.put(state.placed, row.id)}
        walk(Map.get(children, row.id, []), children, merges, state)
      end
    end)
  end

  # Rows still waiting when nothing more can be placed are left unreached.
  defp retry_deferred(%{deferred: []} = state, _children, _merges), do: state

  defp retry_deferred(state, children, merges) do
    next = walk(state.deferred, children, merges, %{state | deferred: []})

    if length(next.deferred) < length(state.deferred),
      do: retry_deferred(next, children, merges),
      else: next
  end

  defp place_row(actor, row, acc) do
    case acc.merges[row.id] do
      nil -> place_own(actor, row, acc)
      into -> merge_row(actor, row, into, acc)
    end
  end

  # The taxon of the row it merges into (placed first) stands for it.
  defp merge_row(actor, row, into, acc) do
    taxon = acc.ctx.anchors[into]
    legacy_id!(actor, taxon, :taxonomy, row.id, row.name)

    acc |> anchor(row.id, taxon) |> Map.update!(:merged, &(&1 + 1))
  end

  defp place_own(actor, row, acc) do
    parent_anchor = row.parent_id && acc.ctx.anchors[row.parent_id]

    case classify(row) do
      :unknown_family ->
        acc |> anchor(row.id, nil) |> Map.update!(:unknown, &(&1 + 1))

      :placeholder_genus ->
        if parent_anchor,
          do: legacy_id!(actor, parent_anchor, :taxonomy, row.id, row.name)

        acc |> anchor(row.id, parent_anchor) |> Map.update!(:placeholders, &(&1 + 1))

      {:skip, reason} ->
        acc
        |> anchor(row.id, parent_anchor)
        |> Map.update!(:skipped, &["#{row_label(row)}: #{reason}" | &1])

      {:rank, rank} ->
        create_higher(actor, row, rank, parent_anchor, acc)
    end
  end

  @doc """
  What an old `taxonomy` row becomes: a taxon of a rank, the Unknown family
  or a placeholder genus (no taxon), or nothing (`{:skip, reason}`).
  """
  @spec classify(map()) ::
          {:rank, Rank.t()} | :unknown_family | :placeholder_genus | {:skip, String.t()}
  def classify(%{type: "family"} = row) do
    if row.is_placeholder or String.trim(row.name) == "Unknown",
      do: :unknown_family,
      else: {:rank, :family}
  end

  def classify(%{type: "genus", is_placeholder: true}), do: :placeholder_genus
  def classify(%{type: "genus"}), do: {:rank, :genus}
  def classify(%{type: "section"}), do: {:rank, :section}

  def classify(%{type: "intermediate", rank: rank}) do
    case Map.fetch(@intermediate_ranks, rank) do
      {:ok, rank} -> {:rank, rank}
      :error -> {:skip, "rank #{inspect(rank)} is not in the contract's rank list"}
    end
  end

  def classify(%{type: type}), do: {:skip, "type #{inspect(type)} is not a taxon"}

  defp create_higher(actor, row, rank, parent_anchor, acc) do
    {parent, acc} = valid_parent(row, rank, parent_anchor, acc)
    name = String.trim(row.name)

    {kingdom, acc} =
      if rank == :family,
        do: family_kingdom(row, acc),
        else: {parent && acc.ctx.taxa[parent].kingdom, acc}

    taxon =
      create_taxon!(actor, %{
        rank: rank,
        origin: origin(kingdom),
        name: name,
        parent_id: parent,
        kingdom: kingdom
      })

    legacy_id!(actor, taxon.id, :taxonomy, row.id, row.name)

    acc
    |> anchor(row.id, taxon.id)
    |> put_taxon(taxon.id, %{name: name, rank: rank, kingdom: kingdom, parent: parent})
    |> Map.update!(:created, &(&1 + 1))
  end

  # The nearest taxon above that ranks above `rank`; a rank inversion in
  # today's tree is reported and attached higher up.
  defp valid_parent(_row, _rank, nil, acc), do: {nil, acc}

  defp valid_parent(row, rank, parent, acc) do
    case climb(rank, parent, acc.ctx.taxa) do
      ^parent ->
        {parent, acc}

      other ->
        problem =
          "#{row_label(row)}: #{rank} is not below #{acc.ctx.taxa[parent].rank} " <>
            "#{acc.ctx.taxa[parent].name}; placed under #{(other && acc.ctx.taxa[other].name) || "no parent"}"

        {other, Map.update!(acc, :problems, &[problem | &1])}
    end
  end

  defp climb(_rank, nil, _taxa), do: nil

  defp climb(rank, id, taxa) do
    if Rank.below?(rank, taxa[id].rank), do: id, else: climb(rank, taxa[id].parent, taxa)
  end

  # A curator's kingdom (kingdoms.csv) wins over the family type.
  defp family_kingdom(%{id: id}, %{kingdoms: kingdoms} = acc) when is_map_key(kingdoms, id),
    do: {kingdoms[id], acc}

  defp family_kingdom(row, acc) do
    description = String.trim(row.description || "")

    case Map.fetch(@kingdoms, description) do
      {:ok, kingdom} ->
        {kingdom, acc}

      :error ->
        problem = "#{row_label(row)}: family type #{inspect(description)} has no kingdom"
        {nil, Map.update!(acc, :problems, &[problem | &1])}
    end
  end

  defp anchor(acc, old_id, taxon_id), do: put_in(acc, [:ctx, :anchors, old_id], taxon_id)
  defp put_taxon(acc, id, info), do: put_in(acc, [:ctx, :taxa, id], info)

  # -- plants ----------------------------------------------------------------------

  defp plants(actor, ctx, report) do
    links = Old.links("plant")
    rows = Old.plants()

    acc =
      Enum.reduce(rows, %{ctx: ctx, created: 0, placeholders: 0, unplaced: [], rootless: []}, fn
        %{genus_placeholder: true} = plant, acc ->
          placeholder(plant, links, acc)

        plant, acc ->
          plant!(actor, plant, links, acc)
      end)

    {placeholders, plants} = Enum.split_with(rows, & &1.genus_placeholder)

    report =
      report
      |> Report.reconcile("Plants", length(plants), acc.created)
      |> Report.reconcile(
        "Genus placeholder plants (→ their genus taxon)",
        length(placeholders),
        acc.placeholders,
        [{"without a genus", length(acc.unplaced)}]
      )
      |> Report.problems("plant without a genus (a root taxon)", Enum.reverse(acc.rootless))
      |> Report.problems("genus placeholder without a genus", Enum.reverse(acc.unplaced))
      |> Report.problems("species row neither gall nor plant (not migrated)", neither())

    {acc.ctx, report}
  end

  defp neither do
    for row <-
          Old.rows("""
          SELECT id, name, taxoncode FROM species
          WHERE taxoncode NOT IN ('gall', 'plant') ORDER BY id
          """) do
      "#{row.id} #{row.name} (#{row.taxoncode})"
    end
  end

  defp placeholder(plant, links, acc) do
    genus = get_in(links, [plant.id, :genus])
    taxon = genus && acc.ctx.anchors[genus]

    acc = put_in(acc, [:ctx, :plants, plant.id], taxon)

    if taxon,
      do: Map.update!(acc, :placeholders, &(&1 + 1)),
      else: Map.update!(acc, :unplaced, &["#{plant.id} #{plant.name}" | &1])
  end

  defp plant!(actor, plant, links, acc) do
    link = Map.get(links, plant.id, %{genus: nil, section: nil})
    parent = acc.ctx.anchors[link.section] || acc.ctx.anchors[link.genus]
    name = String.trim(plant.name)
    rank = plant_rank(name)

    create_taxon!(actor, %{
      id: plant.id,
      rank: rank,
      origin: :powo,
      name: name,
      parent_id: parent,
      kingdom: "Plantae"
    })

    acc =
      acc
      |> put_in([:ctx, :plants, plant.id], plant.id)
      |> put_taxon(plant.id, %{name: name, rank: rank, kingdom: "Plantae", parent: parent})
      |> Map.update!(:created, &(&1 + 1))

    if parent,
      do: acc,
      else: Map.update!(acc, :rootless, &["#{plant.id} #{name}" | &1])
  end

  @doc "A plant's rank by its name: variety, subspecies, form, else species."
  @spec plant_rank(String.t()) :: Rank.t()
  def plant_rank(name) do
    cond do
      name =~ ~r/ var\. / -> :variety
      name =~ ~r/ (subsp|ssp)\. / -> :subspecies
      name =~ ~r/ f\. / -> :form
      true -> :species
    end
  end

  # -- host_range ----------------------------------------------------------------

  defp rekey_host_range(ctx, report) do
    Repo.query!(
      """
      UPDATE host_range hr SET taxon_id = hr.species_id
      FROM taxa t WHERE t.id = hr.species_id
      """,
      [],
      timeout: :infinity
    )

    {species_ids, taxon_ids} =
      for {species_id, taxon_id} <- ctx.plants, taxon_id != nil, taxon_id != species_id do
        {species_id, taxon_id}
      end
      |> Enum.unzip()

    Repo.query!(
      """
      UPDATE host_range hr SET taxon_id = m.taxon_id
      FROM unnest($1::bigint[], $2::bigint[]) AS m(species_id, taxon_id)
      WHERE hr.species_id = m.species_id
      """,
      [species_ids, taxon_ids],
      timeout: :infinity
    )

    total = Old.count("SELECT count(*) FROM host_range")
    keyed = Old.count("SELECT count(*) FROM host_range WHERE taxon_id IS NOT NULL")

    report
    |> Report.reconcile("Host range rows (re-keyed by taxon)", total, keyed, [
      {"left without a taxon", total - keyed}
    ])
    |> Report.count(
      "Host range rows moved from genus placeholders to their genus",
      Old.count(
        "SELECT count(*) FROM host_range WHERE taxon_id IS NOT NULL AND taxon_id <> species_id"
      )
    )
  end

  # -- helpers ---------------------------------------------------------------------

  @doc "The origin of a taxon in `kingdom`: plants come from POWO."
  @spec origin(String.t() | nil) :: :powo | :curated
  def origin("Plantae"), do: :powo
  def origin(_kingdom), do: :curated

  @doc "Creates a taxon (`Gallformers.Taxa.create_taxon/2`), raising on error."
  @spec create_taxon!(Gallformers.Audit.Actor.t(), map()) :: Taxa.Taxon.t()
  def create_taxon!(actor, attrs) do
    case Taxa.create_taxon(actor, attrs) do
      {:ok, taxon} ->
        taxon

      {:error, changeset} ->
        raise "could not create taxon #{inspect(attrs)}: #{inspect(changeset.errors)}"
    end
  end

  @doc "Adds a crosswalk entry, raising on error."
  @spec legacy_id!(Gallformers.Audit.Actor.t(), integer(), atom(), integer(), String.t()) :: :ok
  def legacy_id!(actor, taxon_id, kind, legacy_id, legacy_name) do
    case Taxa.add_legacy_id(actor, taxon_id, kind, legacy_id, legacy_name) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        raise "could not map #{kind} #{legacy_id}: #{inspect(changeset.errors)}"
    end
  end

  @doc "An old `taxonomy` row for the report: `\"family 30 Cynipidae\"`."
  @spec row_label(map()) :: String.t()
  def row_label(row), do: "#{row.type} #{row.id} #{row.name}"
end
