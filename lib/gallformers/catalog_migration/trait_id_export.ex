defmodule Gallformers.CatalogMigration.TraitIdExport do
  @moduledoc """
  The old vocabulary tables' row IDs mapped to the Trait values they became
  (`803b` §3): old ID-tool bookmarks hold those IDs. Each row of the old
  Trait vocabulary tables (`Gallformers.CatalogMigration.LegacyFacts.trait_tables/0`)
  is matched to a Trait value by name, as the data migration matches the
  old Trait joins — against the contract's vocabulary
  (`Gallformers.Catalog.contract_trait_values/0`, what `trait_values` is
  loaded from), so it reads a database whose new tables are not made yet.
  A value the vocabulary lacks (`form` "non-gall") is left out and listed.

  Read-only; `mix gallformers.catalog.export_legacy_trait_ids` writes the
  result as `legacy_trait_ids.csv` (`Gallformers.Catalog.LegacyTraitIds`).
  """
  alias Gallformers.Catalog
  alias Gallformers.Catalog.LegacyTraitIds
  alias Gallformers.CatalogMigration.LegacyFacts
  alias Gallformers.CatalogMigration.Old
  alias NimbleCSV.RFC4180, as: CSV

  @type row :: %{table: String.t(), old_id: integer(), trait: String.t(), value: String.t()}

  @doc "`{mapped, unmapped}`: each old vocabulary row, by table then ID."
  @spec rows() :: {[row()], [row()]}
  def rows do
    vocabulary = MapSet.new(Catalog.contract_trait_values(), &{&1.trait, &1.value})

    LegacyFacts.trait_tables()
    |> Enum.flat_map(fn {trait, table, column} ->
      for row <- Old.rows("SELECT id, #{column} AS value FROM #{table} ORDER BY id") do
        %{table: table, old_id: row.id, trait: trait, value: row.value}
      end
    end)
    |> Enum.sort_by(&{&1.table, &1.old_id})
    |> Enum.split_with(&MapSet.member?(vocabulary, {&1.trait, &1.value}))
  end

  @doc """
  Writes the mapped rows to `path` (a committed file: LF line ends);
  returns `{mapped, unmapped}` as `rows/0`.
  """
  @spec write(String.t()) :: {[row()], [row()]}
  def write(path) do
    {mapped, unmapped} = rows()

    lines =
      [LegacyTraitIds.columns() | for(r <- mapped, do: [r.table, r.old_id, r.trait, r.value])]

    text =
      lines
      |> Enum.map(fn line -> Enum.map(line, &to_string/1) end)
      |> CSV.dump_to_iodata()
      |> IO.iodata_to_binary()
      |> String.replace("\r\n", "\n")

    File.write!(path, text)
    {mapped, unmapped}
  end
end
