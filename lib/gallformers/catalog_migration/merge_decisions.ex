defmodule Gallformers.CatalogMigration.MergeDecisions do
  @moduledoc """
  What every merge decision file shares (`taxon_merges.csv`,
  `plant_merges.csv`): one row per merged ID, naming the ID it merges into,
  with an optional note.

  Loading reads the rows by merged ID. A row merged into itself, a second
  row for the same ID, or a row merging into an ID that is itself merged
  is an error naming the row. Checking runs a file's own test on each row
  in file order: a row is used, reported as not used, or an error naming
  the row.
  """

  alias Gallformers.CatalogMigration.Curated

  @type merge :: %{
          id: integer(),
          into_id: integer(),
          note: String.t() | nil,
          line: pos_integer()
        }

  @type check_result :: :ok | {:stale, String.t()} | {:error, String.t()}

  @doc """
  Reads a merge decision file, by merged ID. `id_column` and `into_column`
  name its two ID columns; `noun` is what an ID names, for the error a
  chained merge gets ("merge 5 into that `noun` instead").
  """
  @spec load(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, %{integer() => merge()}} | {:error, String.t()}
  def load(path, id_column, into_column, noun) do
    with {:ok, rows} <- Curated.read(path, [id_column, into_column], ~w(note)),
         {:ok, parsed} <- Curated.parse_rows(path, rows, &parse(&1, id_column, into_column)),
         parsed = Enum.map(parsed, fn {line, merge} -> {line, %{merge | line: line}} end),
         {:ok, merges} <- Curated.index(path, parsed, & &1.id) do
      no_chains(path, parsed, merges, noun)
    end
  end

  defp parse(row, id_column, into_column) do
    with {:ok, id} <- Curated.integer(row[id_column], id_column),
         {:ok, into_id} <- Curated.integer(row[into_column], into_column) do
      if id == into_id,
        do: {:error, "#{id} is merged into itself"},
        else: {:ok, %{id: id, into_id: into_id, note: row["note"], line: 0}}
    end
  end

  defp no_chains(path, parsed, merges, noun) do
    case Enum.find(parsed, fn {_line, merge} -> Map.has_key?(merges, merge.into_id) end) do
      nil ->
        {:ok, merges}

      {line, merge} ->
        Curated.row_error(
          path,
          line,
          "#{merge.into_id} is itself merged into #{merges[merge.into_id].into_id}: " <>
            "merge #{merge.id} into that #{noun} instead"
        )
    end
  end

  @doc """
  Runs `check_one` on each decision, in file order: `:ok` uses the row,
  `{:stale, line}` reports it as not used, and `{:error, message}` stops
  with `{:error, "<input> row N: message"}`. Returns the rows used, in file
  order, and the report lines.
  """
  @spec check(%{integer() => merge()}, String.t(), (merge() -> check_result())) ::
          {:ok, [merge()], [String.t()]} | {:error, String.t()}
  def check(merges, input, check_one) do
    merges
    |> Map.values()
    |> Enum.sort_by(& &1.line)
    |> Enum.reduce_while({:ok, [], []}, fn merge, {:ok, used, stale} ->
      case check_one.(merge) do
        :ok -> {:cont, {:ok, [merge | used], stale}}
        {:stale, detail} -> {:cont, {:ok, used, [detail | stale]}}
        {:error, message} -> {:halt, Curated.row_error(input, merge.line, message)}
      end
    end)
    |> case do
      {:ok, used, stale} -> {:ok, Enum.reverse(used), Enum.reverse(stale)}
      error -> error
    end
  end
end
