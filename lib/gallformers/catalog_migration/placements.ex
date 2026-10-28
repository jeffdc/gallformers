defmodule Gallformers.CatalogMigration.Placements do
  @moduledoc """
  Taxa Gallformers places elsewhere than today's taxonomy has them
  (`294c` step 3): e.g. the genus *Besbicus* sits directly under the family
  Cynipidae today but belongs in the tribe Cynipini.

  `priv/catalog_migration/placements.csv` holds the decisions, one row per
  taxon moved (`taxon, rank, parent, parent_rank, note`): the taxon's and
  its new parent's accepted names and ranks. The taxa step
  (`Gallformers.CatalogMigration.Taxa`) applies them, in file order, once
  the higher taxa, added taxa (`added_taxa.csv`) and plants exist, through
  `Gallformers.Taxa.place/3`, which rebuilds the moved subtree's ancestry:
  so a taxon can be placed under an added taxon, and the Galls' Inducers,
  created after, sit under the taxon where it now is.

  A rank outside the contract's, a rank not below its parent's, a blank
  name, or a taxon placed twice is an error naming the row. A row whose
  taxon or parent matches no taxon by name and rank, or several, whose
  taxon and parent are in different kingdoms, or whose move the tree
  validator rejects (`Gallformers.Taxa.check_place/2`) is a pending
  decision: a strict run stops, a lenient run leaves the taxon where it is.
  A row whose taxon is already under its parent changes nothing and is
  reported.
  """

  alias Gallformers.CatalogMigration.Curated
  alias Gallformers.Taxa.Rank

  @type decision :: %{
          taxon: String.t(),
          rank: Rank.t(),
          parent: String.t(),
          parent_rank: Rank.t(),
          note: String.t(),
          line: pos_integer()
        }

  @doc "Reads the decisions, in file order."
  @spec load(String.t()) :: {:ok, [decision()]} | {:error, String.t()}
  def load(path) do
    with {:ok, rows} <- Curated.read(path, ~w(taxon rank parent parent_rank), ~w(note)),
         {:ok, parsed} <- Curated.parse_rows(path, rows, &parse/1),
         parsed = Enum.map(parsed, fn {line, decision} -> {line, %{decision | line: line}} end),
         {:ok, _by_key} <- Curated.index(path, parsed, &key/1) do
      {:ok, Enum.map(parsed, &elem(&1, 1))}
    end
  end

  @doc "A decision's key in its file (and in the report's pending list): `{taxon, rank}`."
  @spec key(decision()) :: {String.t(), Rank.t()}
  def key(decision), do: {decision.taxon, decision.rank}

  @doc "A decision for the report: `\"Besbicus (genus) under Cynipini (tribe)\"`."
  @spec label(decision()) :: String.t()
  def label(decision),
    do: "#{decision.taxon} (#{decision.rank}) under #{decision.parent} (#{decision.parent_rank})"

  defp parse(row) do
    with :ok <- present(row["taxon"], "taxon"),
         :ok <- present(row["parent"], "parent"),
         {:ok, rank} <- Curated.rank(row["rank"], "rank"),
         {:ok, parent_rank} <- Curated.rank(row["parent_rank"], "parent_rank"),
         :ok <- below(rank, parent_rank) do
      {:ok,
       %{
         taxon: row["taxon"],
         rank: rank,
         parent: row["parent"],
         parent_rank: parent_rank,
         note: row["note"],
         line: 0
       }}
    end
  end

  defp present("", column), do: {:error, "#{column} is blank"}
  defp present(_text, _column), do: :ok

  defp below(rank, parent_rank) do
    if Rank.below?(rank, parent_rank),
      do: :ok,
      else: {:error, "rank #{rank} must be below parent_rank #{parent_rank}"}
  end
end
