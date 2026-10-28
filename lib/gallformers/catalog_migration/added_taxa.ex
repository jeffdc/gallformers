defmodule Gallformers.CatalogMigration.AddedTaxa do
  @moduledoc """
  Taxa Gallformers adds above today's taxonomy (`294c` step 3): today's
  tree has no orders, so e.g. the rust families have no parent until the
  order Pucciniales is added above them.

  `priv/catalog_migration/added_taxa.csv` holds the decisions, one row per
  added taxon (`name, rank, kingdom, children, note`): `children` are the
  accepted names of the taxa placed under it, separated by `;`. The taxa
  step (`Gallformers.CatalogMigration.Taxa`) creates each added taxon, in
  file order, after the higher taxa (origin `:curated`, no parent), and
  places its children under it.

  A child is found by its accepted name among the taxa in the added taxon's
  kingdom that rank below it; it must have no parent yet. A child found
  nowhere, found more than once, or already placed is a pending decision
  (a strict run stops; a lenient run leaves it where it is). A rank or
  kingdom outside the contract's, or a taxon added twice, is an error
  naming the row.
  """

  alias Gallformers.CatalogMigration.Curated
  alias Gallformers.CatalogMigration.Kingdoms
  alias Gallformers.Taxa.Rank

  @type decision :: %{
          name: String.t(),
          rank: Rank.t(),
          kingdom: String.t(),
          children: [String.t()],
          note: String.t(),
          line: pos_integer()
        }

  @doc "Reads the decisions, in file order."
  @spec load(String.t()) :: {:ok, [decision()]} | {:error, String.t()}
  def load(path) do
    with {:ok, rows} <- Curated.read(path, ~w(name rank kingdom children), ~w(note)),
         {:ok, parsed} <- Curated.parse_rows(path, rows, &parse/1),
         parsed = Enum.map(parsed, fn {line, decision} -> {line, %{decision | line: line}} end),
         {:ok, _by_key} <- Curated.index(path, parsed, &{&1.name, &1.rank}) do
      {:ok, Enum.map(parsed, &elem(&1, 1))}
    end
  end

  defp parse(row) do
    with :ok <- present(row["name"], "name"),
         {:ok, rank} <- Curated.rank(row["rank"], "rank"),
         :ok <- kingdom(row["kingdom"]) do
      children =
        row["children"]
        |> String.split(";")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {:ok,
       %{
         name: row["name"],
         rank: rank,
         kingdom: row["kingdom"],
         children: children,
         note: row["note"],
         line: 0
       }}
    end
  end

  defp present("", column), do: {:error, "#{column} is blank"}
  defp present(_text, _column), do: :ok

  defp kingdom(kingdom) do
    if kingdom in Kingdoms.kingdoms(),
      do: :ok,
      else:
        {:error,
         "kingdom must be one of #{Enum.join(Kingdoms.kingdoms(), ", ")}, got #{inspect(kingdom)}"}
  end
end
