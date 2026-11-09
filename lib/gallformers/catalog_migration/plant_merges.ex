defmodule Gallformers.CatalogMigration.PlantMerges do
  @moduledoc """
  Plants kept twice in today's data, merged: e.g. *Silphium dentatum*
  (species 4878) and *Silphium asteriscus var. dentatum* (4863), which
  WCVP holds as one plant, each with Galls of its own or a synonym naming
  the other.

  `priv/catalog_migration/plant_merges.csv` holds the decisions, one row per
  absorbed plant (`species_id, into_species_id, note`): both are plant
  `species` rows that become plants (not genus placeholders). The merge is
  the editorial plant merge (`Gallformers.Import.Merge`, "A plant merge"),
  run once the plants' Facts, names, notes and images exist: the absorbed
  plant's names become the kept plant's synonyms, its Host Facts and notes
  move over, its ID redirects, and it is deleted. Being a decision file, it
  is applied on every run and logs nothing for replay.

  A row merging a plant into itself, into a merged plant, or naming a
  species that is not a plant, is an error naming the row. A row naming an
  ID that is no `species` row is reported and not used.
  """

  alias Gallformers.Audit.Actor
  alias Gallformers.CatalogMigration.MergeDecisions
  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Import

  @input "plant_merges.csv"

  @doc "Reads the decisions, by absorbed species ID."
  @spec load(String.t()) :: {:ok, %{integer() => MergeDecisions.merge()}} | {:error, String.t()}
  def load(path), do: MergeDecisions.load(path, "species_id", "into_species_id", "plant")

  @doc """
  Checks the decisions against today's `species` rows, before anything is
  written: the merges to apply (in file order) and a report line for each
  row not used, or `{:error, "plant_merges.csv row N: ..."}`.
  """
  @spec check(%{integer() => MergeDecisions.merge()}) ::
          {:ok, [MergeDecisions.merge()], [String.t()]} | {:error, String.t()}
  def check(merges) when map_size(merges) == 0, do: {:ok, [], []}

  def check(merges) do
    ids = merges |> Map.values() |> Enum.flat_map(&[&1.id, &1.into_id]) |> Enum.uniq()

    species =
      ("SELECT id, name, taxoncode, COALESCE(genus_placeholder, false) AS placeholder " <>
         "FROM species WHERE id = ANY($1)")
      |> Old.rows([ids])
      |> Map.new(&{&1.id, &1})

    MergeDecisions.check(merges, @input, &check_one(&1, species))
  end

  defp check_one(merge, species) do
    with {:ok, plant} <- known(merge, merge.id, species),
         {:ok, into} <- known(merge, merge.into_id, species),
         :ok <- plant(plant) do
      plant(into)
    end
  end

  defp known(merge, id, species) do
    case species do
      %{^id => row} ->
        {:ok, row}

      _ ->
        {:stale,
         "#{merge.id} into #{merge.into_id}: #{id} is not a species row; the merge is not used"}
    end
  end

  defp plant(%{taxoncode: "plant", placeholder: false}), do: :ok

  defp plant(%{taxoncode: "plant"} = row),
    do: {:error, "#{label(row)} is a genus placeholder, which becomes no plant"}

  defp plant(row), do: {:error, "#{label(row)} is not a plant"}

  defp label(row), do: "#{row.name} (species #{row.id})"

  @doc """
  Merges each plant into the one kept, in file order (`check/1`'s merges),
  once everything else is written; reports how many and the rows not used.
  A merge that cannot be done (a blocker the merge finds) raises, naming
  the row.
  """
  @spec run(Actor.t(), [MergeDecisions.merge()], [String.t()], Report.t()) :: Report.t()
  def run(%Actor{} = actor, merges, stale, report) do
    for merge <- merges do
      case Import.apply_merge_unlogged(actor, {:plant, merge.id, merge.into_id}) do
        {:ok, _result} ->
          :ok

        {:error, reason} ->
          raise "#{@input} row #{merge.line}: merging #{merge.id} into " <>
                  "#{merge.into_id} failed: #{inspect(reason)}"
      end
    end

    report
    |> Report.count("Plants kept twice, merged (#{@input})", length(merges))
    |> Report.problems(@input, stale)
  end
end
