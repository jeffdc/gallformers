defmodule Gallformers.CatalogMigration.TaxonMerges do
  @moduledoc """
  Taxa kept twice in today's tree, merged (`9449` Task 15): e.g. the plant
  family Santalaceae and the "Plant (gall forming)" family
  "Santalaceae (gall)", each with its own Phoradendron, are one family with
  one genus.

  `priv/catalog_migration/taxon_merges.csv` holds the decisions, one row per
  merged `taxonomy` row (`old_taxonomy_id, into_old_taxonomy_id, note`). The
  row `old_taxonomy_id` becomes no taxon of its own
  (`Gallformers.CatalogMigration.Taxa`):

    * its `:taxonomy` crosswalk entry points at the taxon made from
      `into_old_taxonomy_id`, so `/taxonomy/:id` and old bookmarks resolve;
    * what is below it — genera, sections, placeholder genera, plants, the
      Galls' Inducer links — attaches to that taxon and takes its kingdom.

  Both rows must become taxa of the same rank (a family into a family, a
  genus into a genus). A row merged into itself, into a merged row or into
  a row below it, or one that does not become a taxon, is an error naming
  the row. A row naming an old ID that is no `taxonomy` row is reported and
  not used.
  """

  alias Gallformers.CatalogMigration.MergeDecisions
  alias Gallformers.CatalogMigration.Taxa, as: MigrationTaxa

  @input "taxon_merges.csv"

  @doc "Reads the decisions, by merged old taxonomy ID."
  @spec load(String.t()) :: {:ok, %{integer() => MergeDecisions.merge()}} | {:error, String.t()}
  def load(path),
    do: MergeDecisions.load(path, "old_taxonomy_id", "into_old_taxonomy_id", "row")

  @doc """
  Checks the decisions against today's `taxonomy` rows (by ID): the merges
  to apply (merged old ID → the old ID it merges into) and a report line for
  each row not used, or `{:error, "taxon_merges.csv row N: ..."}`.
  """
  @spec check(%{integer() => MergeDecisions.merge()}, %{integer() => map()}) ::
          {:ok, %{integer() => integer()}, [String.t()]} | {:error, String.t()}
  def check(merges, rows) do
    with {:ok, used, stale} <- MergeDecisions.check(merges, @input, &check_one(&1, rows)) do
      {:ok, Map.new(used, &{&1.id, &1.into_id}), stale}
    end
  end

  defp check_one(merge, rows) do
    with {:ok, row} <- known(merge, merge.id, rows),
         {:ok, into} <- known(merge, merge.into_id, rows),
         {:ok, rank} <- taxon_rank(row),
         {:ok, into_rank} <- taxon_rank(into),
         :ok <- same_rank(row, rank, into, into_rank) do
      not_below(row, into, rows)
    end
  end

  defp known(merge, id, rows) do
    case rows do
      %{^id => row} ->
        {:ok, row}

      _ ->
        {:stale,
         "#{merge.id} into #{merge.into_id}: #{id} is not a taxonomy row; the merge is not used"}
    end
  end

  defp taxon_rank(row) do
    case MigrationTaxa.classify(row) do
      {:rank, rank} ->
        {:ok, rank}

      :unknown_family ->
        {:error, "#{label(row)} is the Unknown family, which becomes no taxon"}

      :placeholder_genus ->
        {:error, "#{label(row)} is a placeholder genus, which becomes no taxon"}

      {:skip, reason} ->
        {:error, "#{label(row)} becomes no taxon (#{reason})"}
    end
  end

  defp same_rank(_row, rank, _into, rank), do: :ok

  defp same_rank(row, rank, into, into_rank),
    do:
      {:error,
       "#{label(row)} is a #{rank} and #{label(into)} a #{into_rank}: a merge needs the same rank"}

  defp not_below(row, into, rows) do
    if ancestor?(row.id, into.parent_id, rows),
      do:
        {:error, "#{label(into)} is below #{label(row)}: a row cannot merge into its own child"},
      else: :ok
  end

  defp ancestor?(_id, nil, _rows), do: false
  defp ancestor?(id, id, _rows), do: true

  defp ancestor?(id, parent_id, rows),
    do: ancestor?(id, rows[parent_id] && rows[parent_id].parent_id, rows)

  defp label(row), do: MigrationTaxa.row_label(row)
end
