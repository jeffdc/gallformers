defmodule Gallformers.CatalogMigration.Kingdoms do
  @moduledoc """
  Kingdoms a curator sets for old families (`9449` Task 15): a family takes
  its kingdom from its old type (`Gallformers.CatalogMigration.Taxa`), and
  some types give none (today: "Unknown").

  `priv/catalog_migration/kingdoms.csv` holds the decisions, one row per
  family (`old_taxonomy_id, kingdom, note`). The kingdom wins over the
  family type; everything below the family inherits it, as from a type.
  `kingdom` is one of the GBIF backbone's kingdoms (Animalia, Archaea,
  Bacteria, Chromista, Fungi, Plantae, Protozoa); viruses have none, as the
  old type "Virus" gives none.

  A row on a `taxonomy` row that is not a family is an error naming the
  row. A row naming an old ID that is no `taxonomy` row, or a family merged
  into another (`taxon_merges.csv`, `Gallformers.CatalogMigration.TaxonMerges`;
  it is its target's taxon, kingdom included), is reported and not used.
  """

  alias Gallformers.CatalogMigration.Curated
  alias Gallformers.CatalogMigration.Taxa, as: MigrationTaxa

  @input "kingdoms.csv"

  @kingdoms ~w(Animalia Archaea Bacteria Chromista Fungi Plantae Protozoa)

  @type decision :: %{
          old_id: integer(),
          kingdom: String.t(),
          note: String.t(),
          line: pos_integer()
        }

  @doc "The kingdoms a decision may set (the GBIF backbone's)."
  @spec kingdoms() :: [String.t()]
  def kingdoms, do: @kingdoms

  @doc "Reads the decisions, by old taxonomy ID."
  @spec load(String.t()) :: {:ok, %{integer() => decision()}} | {:error, String.t()}
  def load(path) do
    with {:ok, rows} <- Curated.read(path, ~w(old_taxonomy_id kingdom), ~w(note)),
         {:ok, parsed} <- Curated.parse_rows(path, rows, &parse/1) do
      parsed = Enum.map(parsed, fn {line, decision} -> {line, %{decision | line: line}} end)
      Curated.index(path, parsed, & &1.old_id)
    end
  end

  defp parse(row) do
    with {:ok, id} <- Curated.integer(row["old_taxonomy_id"], "old_taxonomy_id") do
      if row["kingdom"] in @kingdoms,
        do: {:ok, %{old_id: id, kingdom: row["kingdom"], note: row["note"], line: 0}},
        else:
          {:error,
           "kingdom must be one of #{Enum.join(@kingdoms, ", ")}, got #{inspect(row["kingdom"])}"}
    end
  end

  @doc """
  Checks the decisions against today's `taxonomy` rows (by ID) and the
  merges to apply (`Gallformers.CatalogMigration.TaxonMerges.check/2`): the
  kingdoms to set (old family ID → kingdom) and a report line for each row
  not used, or `{:error, "kingdoms.csv row N: ..."}`.
  """
  @spec check(%{integer() => decision()}, %{integer() => map()}, %{integer() => integer()}) ::
          {:ok, %{integer() => String.t()}, [String.t()]} | {:error, String.t()}
  def check(decisions, rows, merges) do
    decisions
    |> Map.values()
    |> Enum.sort_by(& &1.line)
    |> Enum.reduce_while({:ok, %{}, []}, fn decision, {:ok, used, stale} ->
      case check_one(decision, rows, merges) do
        :ok -> {:cont, {:ok, Map.put(used, decision.old_id, decision.kingdom), stale}}
        {:stale, detail} -> {:cont, {:ok, used, [detail | stale]}}
        {:error, message} -> {:halt, Curated.row_error(@input, decision.line, message)}
      end
    end)
    |> case do
      {:ok, used, stale} -> {:ok, used, Enum.reverse(stale)}
      error -> error
    end
  end

  defp check_one(%{old_id: id}, rows, merges) do
    case rows[id] do
      nil ->
        {:stale, "#{id} is not a taxonomy row; its kingdom is not used"}

      row ->
        cond do
          MigrationTaxa.classify(row) != {:rank, :family} ->
            {:error,
             "#{MigrationTaxa.row_label(row)} is not a family: only a family's kingdom is set"}

          Map.has_key?(merges, id) ->
            {:stale,
             "#{MigrationTaxa.row_label(row)} is merged into #{merges[id]} (taxon_merges.csv); " <>
               "its kingdom is not used"}

          true ->
            :ok
        end
    end
  end
end
