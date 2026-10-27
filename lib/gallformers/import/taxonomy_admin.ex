defmodule Gallformers.Import.TaxonomyAdmin do
  @moduledoc """
  The taxonomy admin's writes that make several edits as one (`a856`
  Task 9), each edit through `Gallformers.Import.record_taxonomy_edit/2` (or
  `record_plant_added/2`) so it reaches the replay log, all of a write's
  edits in one audited transaction as `actor` — all of them or none.
  Called through `Gallformers.Import`.
  """
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Import
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon

  @typedoc "A Host range entry: `{place_id, precision, distribution_type}`."
  @type range_entry :: {integer(), String.t(), String.t()}

  @doc """
  Saves a plant's Host range (`:set_host_range`) and, when `link_attrs` is
  not empty, its WCVP link's fields (`:set_wcvp`): what a WCVP refresh
  staged, a confirmation.
  """
  @spec save_host_range(Actor.t(), integer(), [range_entry()], map()) ::
          {:ok, :ok} | {:error, term()}
  def save_host_range(%Actor{} = actor, taxon_id, entries, link_attrs) do
    Audit.transaction(actor, "import.taxonomy_admin.save_host_range", fn ->
      ok!(Import.record_taxonomy_edit(actor, {:set_host_range, taxon_id, entries}))

      if link_attrs != %{},
        do: ok!(Import.record_taxonomy_edit(actor, {:set_wcvp, taxon_id, link_attrs}))

      :ok
    end)
  end

  @doc """
  Creates a taxon (`attrs`: `:name`, `:rank`, `:parent_id`, `:kingdom`),
  moves `child_ids` under it (an intermediate rank made over existing
  taxa) and gives a plant its Host range `entries`. A plant (Plantae at
  species rank or below) is added as the Host-name step adds one
  (`Gallformers.Import.record_plant_added/2`); any other taxon is
  `:curated`, or `:powo` in Plantae.
  """
  @spec create_taxon(Actor.t(), map(), [integer()], [range_entry()]) ::
          {:ok, Taxon.t()} | {:error, term()}
  def create_taxon(%Actor{} = actor, attrs, child_ids, entries) do
    Audit.transaction(actor, "import.taxonomy_admin.create_taxon", fn ->
      taxon = ok!(create(actor, attrs))

      for id <- child_ids,
          do: ok!(Import.record_taxonomy_edit(actor, {:place, id, taxon.id}))

      if entries != [],
        do: ok!(Import.record_taxonomy_edit(actor, {:set_host_range, taxon.id, entries}))

      taxon
    end)
  end

  defp create(actor, %{kingdom: "Plantae", rank: rank} = attrs) do
    if rank in Rank.species_and_below(),
      do: Import.record_plant_added(actor, Map.take(attrs, [:name, :rank, :parent_id])),
      else: create_listed(actor, Map.put(attrs, :origin, :powo))
  end

  defp create(actor, attrs), do: create_listed(actor, Map.put(attrs, :origin, :curated))

  defp create_listed(actor, attrs) do
    edit = {:create_taxon, Map.take(attrs, [:name, :rank, :parent_id, :kingdom, :origin])}
    Import.record_taxonomy_edit(actor, edit)
  end

  @doc """
  Adds a plant from its WCVP record (`wcvp`: `taxon_name`, `taxon_authors`,
  `family`, `genus`, `plant_name_id`, `powo_id`) at `rank` under its WCVP
  genus and family — WCVP is authoritative for a plant's family — making the
  family or genus when there is none, with its Host range `entries` and its
  WCVP link.
  """
  @spec add_plant_from_wcvp(Actor.t(), map(), Rank.t(), [range_entry()]) ::
          {:ok, Taxon.t()} | {:error, term()}
  def add_plant_from_wcvp(%Actor{} = actor, wcvp, rank, entries) do
    Audit.transaction(actor, "import.taxonomy_admin.add_plant_from_wcvp", fn ->
      family_id = find_or_create_plant_taxon(actor, wcvp.family, :family, nil)
      genus_name = wcvp.genus || wcvp.taxon_name |> String.split() |> hd()
      genus_id = find_or_create_plant_taxon(actor, genus_name, :genus, family_id)

      plant =
        ok!(
          Import.record_plant_added(actor, %{
            name: wcvp.taxon_name,
            rank: rank,
            parent_id: genus_id,
            authorship: blank_to_nil(wcvp.taxon_authors)
          })
        )

      if entries != [],
        do: ok!(Import.record_taxonomy_edit(actor, {:set_host_range, plant.id, entries}))

      link = %{
        wcvp_id: wcvp.plant_name_id,
        powo_id: wcvp.powo_id,
        wcvp_synced_at: DateTime.utc_now(:second)
      }

      ok!(Import.record_taxonomy_edit(actor, {:set_wcvp, plant.id, link}))
      plant
    end)
  end

  defp find_or_create_plant_taxon(actor, name, rank, parent_id) do
    case Taxa.resolve_name(name, rank: rank, kingdom: "Plantae") do
      {:ok, taxon} ->
        taxon.id

      {:ambiguous, [taxon | _]} ->
        taxon.id

      :none ->
        attrs = %{name: name, rank: rank, parent_id: parent_id, kingdom: "Plantae", origin: :powo}
        ok!(Import.record_taxonomy_edit(actor, {:create_taxon, attrs})).id
    end
  end

  @doc "Moves each of `taxon_ids` under `parent_id` (`:place`); returns how many."
  @spec move_all(Actor.t(), [integer()], integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def move_all(%Actor{} = actor, taxon_ids, parent_id) do
    Audit.transaction(actor, "import.taxonomy_admin.move_all", fn ->
      for id <- taxon_ids, do: ok!(Import.record_taxonomy_edit(actor, {:place, id, parent_id}))
      length(taxon_ids)
    end)
  end

  defp ok!({:ok, value}), do: value
  defp ok!({:error, reason}), do: Repo.rollback(reason)

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
