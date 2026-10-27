defmodule Gallformers.Catalog.LegacyTraitIds do
  @moduledoc """
  Old ID-tool bookmarks' Trait parameters (`co`, `sh`, `fo`, `se`, `lo`,
  `te`, ...) hold row IDs of today's vocabulary tables (`color`, `shape`,
  `form`, ...), which go when the old tables are dropped. `803b` §3: they
  are translated through a small fixed file, `legacy_trait_ids.csv`
  (`table,old_id,trait,value`), generated once from the old tables
  (`mix gallformers.catalog.export_legacy_trait_ids`) and committed.

  `columns/0` is the file's header; `read/1` reads it.
  """
  alias NimbleCSV.RFC4180, as: CSV

  @columns ["table", "old_id", "trait", "value"]

  @type values :: %{{String.t(), integer()} => %{trait: String.t(), value: String.t()}}

  @doc "The file's columns, in order."
  @spec columns() :: [String.t()]
  def columns, do: @columns

  @doc "The shipped file."
  @spec default_path() :: String.t()
  def default_path,
    do: Application.app_dir(:gallformers, "priv/catalog_migration/legacy_trait_ids.csv")

  @doc """
  Reads the file at `path`: each old table and row ID's Trait value, or
  `{:error, message}` naming the file (and row).
  """
  @spec read(String.t()) :: {:ok, values()} | {:error, String.t()}
  def read(path) do
    name = Path.basename(path)

    with {:ok, text} <- read_file(path, name),
         [@columns | rows] <- CSV.parse_string(text, skip_headers: false) do
      rows
      |> Enum.with_index(2)
      |> Enum.reduce_while({:ok, %{}}, fn {row, line}, {:ok, acc} ->
        case parse_row(row) do
          {:ok, key, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
          {:error, message} -> {:halt, {:error, "#{name} row #{line}: #{message}"}}
        end
      end)
    else
      {:error, message} -> {:error, message}
      _ -> {:error, "#{name}: the header must be #{Enum.join(@columns, ",")}"}
    end
  end

  defp parse_row([table, old_id, trait, value]) do
    case Integer.parse(old_id) do
      {id, ""} -> {:ok, {table, id}, %{trait: trait, value: value}}
      _ -> {:error, "old_id must be a number"}
    end
  end

  defp parse_row(_row), do: {:error, "expected #{length(@columns)} columns"}

  defp read_file(path, name) do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, reason} -> {:error, "#{name}: #{:file.format_error(reason)}"}
    end
  end
end
