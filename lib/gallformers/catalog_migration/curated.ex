defmodule Gallformers.CatalogMigration.Curated do
  @moduledoc """
  The data migration's curated inputs (`9449` Task 17): CSV files in
  `priv/catalog_migration/` holding a curator's decisions —
  `non_galls.csv`, `range_decisions.csv`, `aliases.csv`, `keys.csv`,
  `taxon_merges.csv`, `kingdoms.csv` — and the worksheets the migration
  writes for filling the first four
  (`Gallformers.CatalogMigration.Report.write_curation/2`).

  Columns are found by their header, so a worksheet with extra columns can
  be saved as a decision file as it is. A decision file needs only its
  required columns; blank lines are skipped.
  """

  alias NimbleCSV.RFC4180, as: CSV

  @inputs [:non_galls, :range_decisions, :aliases, :keys, :taxon_merges, :kingdoms]

  @type input :: :non_galls | :range_decisions | :aliases | :keys | :taxon_merges | :kingdoms

  @typedoc "A row as a map of column → trimmed text, with its line number (the header is 1)."
  @type row :: {pos_integer(), %{String.t() => String.t()}}

  @doc "The curated inputs."
  @spec inputs() :: [input()]
  def inputs, do: @inputs

  @doc "An input's file name (`range_decisions` → `\"range_decisions.csv\"`)."
  @spec file_name(input()) :: String.t()
  def file_name(input) when input in @inputs, do: "#{input}.csv"

  @doc "The shipped file of an input."
  @spec default_path(input()) :: String.t()
  def default_path(input),
    do: Application.app_dir(:gallformers, "priv/catalog_migration/#{file_name(input)}")

  @doc """
  Reads a decision file: `{:ok, rows}` with the `required` and `optional`
  columns of each row (a missing optional column reads as `""`), or
  `{:error, "file: ..."}`.
  """
  @spec read(String.t(), [String.t()], [String.t()]) :: {:ok, [row()]} | {:error, String.t()}
  def read(path, required, optional \\ []) do
    name = Path.basename(path)

    with {:ok, text} <- read_file(path, name),
         [header | rows] <- CSV.parse_string(text, skip_headers: false),
         header = Enum.map(header, &String.trim/1),
         :ok <- has_columns(header, required, name) do
      wanted = required ++ optional

      rows =
        for {fields, line} <- Enum.with_index(rows, 2),
            Enum.any?(fields, &(String.trim(&1) != "")) do
          values = header |> Enum.zip(Enum.map(fields, &String.trim/1)) |> Map.new()
          {line, Map.new(wanted, &{&1, Map.get(values, &1, "")})}
        end

      {:ok, rows}
    else
      [] -> {:error, "#{name}: the file is empty (it needs its header row)"}
      {:error, message} -> {:error, message}
    end
  end

  defp read_file(path, name) do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, reason} -> {:error, "#{name}: #{:file.format_error(reason)}"}
    end
  end

  defp has_columns(header, required, name) do
    case required -- header do
      [] -> :ok
      missing -> {:error, "#{name} row 1: missing columns #{Enum.join(missing, ", ")}"}
    end
  end

  @doc "An error naming a row: `\"file row N: message\"`."
  @spec row_error(String.t(), pos_integer(), String.t()) :: {:error, String.t()}
  def row_error(path, line, message),
    do: {:error, "#{Path.basename(path)} row #{line}: #{message}"}

  @doc "Parses an integer column, or `{:error, message}`."
  @spec integer(String.t(), String.t()) :: {:ok, integer()} | {:error, String.t()}
  def integer(text, column) do
    case Integer.parse(text) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "#{column} must be a number, got #{inspect(text)}"}
    end
  end

  @doc "Reads rows with `fun` (`row → {:ok, value} | {:error, message}`), stopping at the first error."
  @spec parse_rows(String.t(), [row()], (map() -> {:ok, term()} | {:error, String.t()})) ::
          {:ok, [{pos_integer(), term()}]} | {:error, String.t()}
  def parse_rows(path, rows, fun) do
    Enum.reduce_while(rows, {:ok, []}, fn {line, row}, {:ok, acc} ->
      case fun.(row) do
        {:ok, value} -> {:cont, {:ok, [{line, value} | acc]}}
        {:error, message} -> {:halt, row_error(path, line, message)}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  @doc """
  Collects parsed rows into a map by `key_fun`; a key given twice is an
  error naming the second row.
  """
  @spec index(String.t(), [{pos_integer(), term()}], (term() -> term())) ::
          {:ok, map()} | {:error, String.t()}
  def index(path, parsed, key_fun) do
    Enum.reduce_while(parsed, {:ok, %{}}, fn {line, value}, {:ok, acc} ->
      key = key_fun.(value)

      if Map.has_key?(acc, key),
        do: {:halt, row_error(path, line, "#{inspect(key)} is listed twice")},
        else: {:cont, {:ok, Map.put(acc, key, value)}}
    end)
  end

  @doc "Writes a worksheet: `columns` in order, `rows` as maps by column."
  @spec write(String.t(), [String.t()], [map()]) :: :ok
  def write(path, columns, rows) do
    lines = [columns | Enum.map(rows, fn row -> Enum.map(columns, &cell(row[&1])) end)]
    File.write!(path, CSV.dump_to_iodata(lines))
  end

  defp cell(nil), do: ""
  defp cell(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp cell(%NaiveDateTime{} = at), do: NaiveDateTime.to_iso8601(at)
  defp cell(list) when is_list(list), do: Enum.join(list, " ")
  defp cell(value), do: to_string(value)
end
