defmodule Gallformers.Catalog.ReadModels.GallIndex do
  @moduledoc """
  The ID tool's stored per-Gall lookup table, `gall_index` (`803b` §3,
  Task 8): one row per Gall holding what the ID tool (and search) filter on,
  so filtering is one query over it (`Gallformers.Catalog.Identify`).

  A row is computed from the read models, never by rules of its own: the
  current Inducer and Hosts (`inducer_of` / `host_of` Facts, as
  `Gallformers.Catalog.ReadModels.GallSummary` reads them) with their
  lineages from `Gallformers.Taxa`; the current Trait values; the default
  image; and the potential range,
  `Gallformers.Catalog.ReadModels.PotentialRange.for_galls/1`'s result
  (empty `place_ids` with `everywhere` for a range that is every region).
  Ancestor columns hold the taxa themselves too, so a family filter matches
  an Inducer that is the family and a genus filter a Host that is the
  genus. `undescribed` is the Gall page's rule: no current Inducer at
  species rank or below.

  ## Refreshing

  `refresh/1` recomputes the rows of some Galls; `rebuild_all/0` all of
  them (the catalog data migration's last step), in a few batched queries
  either way. `enqueue_refresh/2` is how changes reach it: the Catalog's
  "Facts changed" and "taxon changed" listeners
  (`Gallformers.Catalog.FactListener`, `Gallformers.Catalog.TaxonListener`)
  enqueue a `Gallformers.Catalog.ReadModels.GallIndexWorker` job per Gall
  inside the change's transaction, so it runs after the change commits (in
  tests, Oban's inline mode runs it at once, inside the transaction). Where
  Oban is not running (a release task such as the replay) the refresh runs
  at once instead. Inside `without_refresh/1` (the data migration, which
  rebuilds everything at its end) nothing is refreshed or enqueued.

  A Gall's name, edited deliberately (`Gallformers.Catalog.update_name_parts/3`),
  enqueues its refresh the same way. Not refreshed by anything yet: a Gall's
  images, which have no write path in the new back-end (the data migration
  sets them and rebuilds the table).
  """
  use Ecto.Schema

  import Ecto.Query

  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Catalog.ReadModels.GallIndexWorker
  alias Gallformers.Catalog.ReadModels.PotentialRange
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Images
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank

  @deferred {__MODULE__, :without_refresh}
  @chunk 1_000

  @type t :: %__MODULE__{
          gall_id: integer() | nil,
          name: String.t() | nil,
          inducer_taxon_id: integer() | nil,
          inducer_ancestor_ids: [integer()],
          host_taxon_ids: [integer()],
          host_ancestor_ids: [integer()],
          trait_value_ids: [integer()],
          detachable: String.t() | nil,
          undescribed: boolean() | nil,
          image_id: integer() | nil,
          place_ids: [integer()],
          everywhere: boolean() | nil,
          refreshed_at: DateTime.t() | nil
        }

  @primary_key {:gall_id, :id, autogenerate: false}
  schema "gall_index" do
    field :name, :string
    field :inducer_taxon_id, :id
    field :inducer_ancestor_ids, {:array, :id}, default: []
    field :host_taxon_ids, {:array, :id}, default: []
    field :host_ancestor_ids, {:array, :id}, default: []
    field :trait_value_ids, {:array, :id}, default: []
    field :detachable, :string
    field :undescribed, :boolean
    field :image_id, :id
    field :place_ids, {:array, :id}, default: []
    field :everywhere, :boolean
    field :refreshed_at, :utc_datetime
  end

  @doc """
  Recomputes the rows of the Galls among `gall_ids`; an ID that is no Gall
  (any more) loses its row.
  """
  @spec refresh([integer()]) :: :ok
  def refresh([]), do: :ok

  def refresh(gall_ids) when is_list(gall_ids) do
    gall_ids = Enum.uniq(gall_ids)

    Repo.transaction(fn ->
      Repo.delete_all(from(r in __MODULE__, where: r.gall_id in ^gall_ids))
      gall_ids |> Enum.chunk_every(@chunk) |> Enum.each(&insert_rows/1)
    end)

    :ok
  end

  @doc "Recomputes every Gall's row, in one transaction."
  @spec rebuild_all() :: :ok
  def rebuild_all do
    {:ok, :ok} =
      Repo.transaction(
        fn ->
          Repo.delete_all(__MODULE__)

          from(g in Gall, order_by: g.id, select: g.id)
          |> Repo.all()
          |> Enum.chunk_every(@chunk)
          |> Enum.each(&insert_rows/1)
        end,
        timeout: :infinity
      )

    :ok
  end

  @doc """
  Has the rows of the Galls among `gall_ids` refreshed: a
  `Gallformers.Catalog.ReadModels.GallIndexWorker` job per Gall (unique
  while waiting) through the Oban instance `oban`, or at once when that
  instance is not running; nothing inside `without_refresh/1`.
  """
  @spec enqueue_refresh([integer()], Oban.name()) :: :ok
  def enqueue_refresh(gall_ids, oban \\ Oban)

  def enqueue_refresh([], _oban), do: :ok

  def enqueue_refresh(gall_ids, oban) when is_list(gall_ids) do
    cond do
      Process.get(@deferred, false) ->
        :ok

      Oban.whereis(oban) == nil ->
        refresh(gall_ids)

      true ->
        for gall_id <- Enum.uniq(gall_ids) do
          {:ok, _job} = Oban.insert(oban, GallIndexWorker.new(%{gall_id: gall_id}))
        end

        :ok
    end
  end

  @doc """
  Runs `fun` with refreshes off for this process (`enqueue_refresh/2` does
  nothing), returning its result. For bulk writes that rebuild the table
  when done (the catalog data migration).
  """
  @spec without_refresh((-> result)) :: result when result: var
  def without_refresh(fun) when is_function(fun, 0) do
    previous = Process.put(@deferred, true)

    try do
      fun.()
    after
      if previous, do: Process.put(@deferred, previous), else: Process.delete(@deferred)
    end
  end

  # -- building rows ---------------------------------------------------------------

  defp insert_rows(gall_ids) do
    galls =
      Repo.all(
        from(g in Gall,
          where: g.id in ^gall_ids,
          select: {g.id, fragment("COALESCE(?, ?)", g.name_override, g.name)}
        )
      )

    ids = Enum.map(galls, &elem(&1, 0))
    inducers = related("inducer_of", ids)
    hosts = related("host_of", ids)

    lineages =
      (inducers ++ hosts) |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq() |> Taxa.lineages()

    traits = traits(ids)
    detachable = detachable_values()
    images = Images.default_image_ids_for_galls(ids)
    ranges = PotentialRange.for_galls(ids)
    inducers = Map.new(inducers)
    hosts = Map.new(hosts)
    now = DateTime.utc_now(:second)

    rows =
      for {id, name} <- galls do
        inducer_ids = Map.get(inducers, id, [])
        host_ids = Map.get(hosts, id, [])
        value_ids = Map.get(traits, id, [])
        range = Map.fetch!(ranges, id)

        %{
          gall_id: id,
          name: name,
          inducer_taxon_id: List.first(inducer_ids),
          inducer_ancestor_ids: lineage_ids(inducer_ids, lineages),
          host_taxon_ids: host_ids,
          host_ancestor_ids: lineage_ids(host_ids, lineages),
          trait_value_ids: value_ids,
          detachable: Enum.find_value(value_ids, &Map.get(detachable, &1)),
          undescribed: undescribed?(inducer_ids, lineages),
          image_id: Map.get(images, id),
          place_ids: if(range == :everywhere, do: [], else: Enum.map(range, & &1.place_id)),
          everywhere: range == :everywhere,
          refreshed_at: now
        }
      end

    Repo.insert_all(__MODULE__, rows)
  end

  # {gall_id, [taxon_id]} of the Galls' current `type` Relationships, IDs sorted.
  defp related(type, gall_ids) do
    from(r in Current.relationships(type),
      where: r.object_gall_id in ^gall_ids,
      distinct: true,
      order_by: [r.object_gall_id, r.subject_taxon_id],
      select: {r.object_gall_id, r.subject_taxon_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.to_list()
  end

  defp traits(gall_ids) do
    from(t in Current.traits(gall_ids),
      distinct: true,
      order_by: [t.gall_id, t.trait_value_id],
      select: {t.gall_id, t.trait_value_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp detachable_values do
    Repo.all(from(v in TraitValue, where: v.trait == "detachable", select: {v.id, v.value}))
    |> Map.new()
  end

  # The taxa and every taxon above them, sorted.
  defp lineage_ids(taxon_ids, lineages) do
    taxon_ids
    |> Enum.flat_map(&Map.get(lineages, &1, []))
    |> Enum.map(& &1.taxon_id)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # No current Inducer at species rank or below (`Gallformers.Catalog.ReadModels.GallPage`).
  defp undescribed?(inducer_ids, lineages) do
    not Enum.any?(inducer_ids, fn id ->
      case Map.get(lineages, id, []) |> List.last() do
        %{rank: rank} -> rank in Rank.species_and_below()
        nil -> false
      end
    end)
  end
end
