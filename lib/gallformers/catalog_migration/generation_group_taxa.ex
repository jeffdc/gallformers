defmodule Gallformers.CatalogMigration.GenerationGroupTaxa do
  @moduledoc """
  The taxa each generation group applies to (`8567` *Generation groups*;
  `294c` step 3): heterogony on the oak gall wasps' tribe, seasonal
  generations on the gall midges, ... The vocabulary loader writes the
  groups and their values (`Gallformers.Catalog.Vocab.Loader`); these
  mappings (`generation_group_taxa`) are written here, after the taxa exist.

  `priv/catalog_migration/generation_group_taxa.csv` holds the decisions,
  one row per mapping (`group, taxon, rank, note`): the group's name and the
  taxon's accepted name and rank. A group the loader does not have, a rank
  outside the contract's, or a mapping listed twice is an error naming the
  row. A row whose name and rank match no taxon, or several, is a pending
  decision: a strict run stops, a lenient run writes the others.
  """

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Vocab.GenerationGroupTaxon
  alias Gallformers.CatalogMigration.Curated
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank

  @input "generation_group_taxa.csv"

  @type mapping :: %{
          group: String.t(),
          taxon: String.t(),
          rank: Rank.t(),
          note: String.t(),
          line: pos_integer()
        }

  @doc "Reads the decisions, in file order."
  @spec load(String.t()) :: {:ok, [mapping()]} | {:error, String.t()}
  def load(path) do
    groups = Catalog.generation_group_names()

    with {:ok, rows} <- Curated.read(path, ~w(group taxon rank), ~w(note)),
         {:ok, parsed} <- Curated.parse_rows(path, rows, &parse(&1, groups)),
         parsed = Enum.map(parsed, fn {line, mapping} -> {line, %{mapping | line: line}} end),
         {:ok, _by_key} <- Curated.index(path, parsed, &key/1) do
      {:ok, Enum.map(parsed, &elem(&1, 1))}
    end
  end

  defp parse(row, groups) do
    with :ok <- group(row["group"], groups),
         :ok <- taxon(row["taxon"]),
         {:ok, rank} <- Curated.rank(row["rank"], "rank") do
      {:ok, %{group: row["group"], taxon: row["taxon"], rank: rank, note: row["note"], line: 0}}
    end
  end

  defp group(name, groups) do
    if name in groups,
      do: :ok,
      else: {:error, "group must be one of #{Enum.join(groups, ", ")}, got #{inspect(name)}"}
  end

  defp taxon(""), do: {:error, "taxon is blank"}
  defp taxon(_name), do: :ok

  defp key(mapping), do: {mapping.group, mapping.taxon, mapping.rank}

  @doc """
  Writes the mappings whose taxon resolves (by accepted name and rank, one
  taxon); the rest are reported pending. Run after every taxon is created.
  """
  @spec run([mapping()], Report.t()) :: Report.t()
  def run(mappings, report) do
    group_ids = Map.new(Catalog.list_generation_groups(), &{&1.name, &1.id})

    {found, pending} =
      mappings
      |> Enum.map(&resolve/1)
      |> Enum.split_with(&match?({:ok, _, _}, &1))

    rows =
      for {:ok, mapping, taxon_id} <- found,
          do: %{group_id: Map.fetch!(group_ids, mapping.group), taxon_id: taxon_id}

    {written, _} = Repo.insert_all(GenerationGroupTaxon, rows)
    pending = for {:pending, mapping, reason} <- pending, do: {key(mapping), reason}

    report
    |> Report.reconcile(
      "Generation group taxa (generation_group_taxa.csv)",
      length(mappings),
      written,
      [{"pending", length(pending)}]
    )
    |> Report.pending(@input, pending)
  end

  defp resolve(mapping) do
    label = "#{mapping.group} → #{mapping.taxon} (#{mapping.rank})"

    case Taxa.get_by_name(mapping.taxon, mapping.rank) do
      [taxon] ->
        {:ok, mapping, taxon.id}

      [] ->
        {:pending, mapping, "#{label}: no taxon has this accepted name and rank"}

      taxa ->
        ids = Enum.map_join(taxa, ", ", & &1.id)

        {:pending, mapping,
         "#{label}: #{length(taxa)} taxa have this accepted name and rank (#{ids})"}
    end
  end
end
