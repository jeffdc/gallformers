defmodule Gallformers.CatalogMigration.NameSuffixes do
  @moduledoc """
  Reading today's gall names for the data migration (`9449` Task 15;
  `b5bd` *Name-suffix categorization*): "a curated mapping, not a parser".

  Parentheses in a gall name carry its generation ("agamic", "sexgen",
  seasonal generations, rust stages) and, for a few names, host, form or
  name-history qualifiers. The mapping file
  (`priv/catalog_migration/name_suffixes.csv`) has two kinds of rows, with
  the columns `kind, key, name, inducer, generation, needs_review, category,
  handling`:

    * `token` rows map a parenthetical token (`key`, compared without case
      or extra spaces) to a generation value (`generation`, a value of
      `Gallformers.Catalog`'s generation vocabulary, or blank for none). A
      token row is mechanical: it applies to any gall name.
    * `gall` rows are curated, one per gall (`key` is its species ID, `name`
      its name when it was curated): the Inducer's name (`inducer`, blank
      when the gall links to a genus or family instead) and the generation.
      A gall row replaces the reading of the name entirely.

  A row with `needs_review` true is applied as written but reported for a
  curator, with its `handling` as the reason. A name with a token the file
  does not have, or a curated row whose `name` is no longer the gall's
  name, is an error: the migration reports it and guesses nothing.
  """

  alias NimbleCSV.RFC4180, as: CSV

  @columns ~w(kind key name inducer generation needs_review category handling)

  @type row :: %{
          kind: :token | :gall,
          key: String.t() | integer(),
          name: String.t() | nil,
          inducer: String.t() | nil,
          generation: String.t() | nil,
          needs_review: boolean(),
          category: String.t(),
          handling: String.t()
        }

  @type t :: %{tokens: %{String.t() => row()}, galls: %{integer() => row()}}

  @type parsed :: %{
          base: String.t() | nil,
          generation: String.t() | nil,
          review: String.t() | nil,
          curated?: boolean()
        }

  @placeholder_prefix ~r/^Unknown \([^)]*\)/
  @group ~r/\(([^()]*)\)/

  @doc "The shipped mapping file."
  @spec default_path() :: String.t()
  def default_path,
    do: Application.app_dir(:gallformers, "priv/catalog_migration/name_suffixes.csv")

  @doc """
  Reads a mapping file. `{:error, "row N: ..."}` names the first bad row
  (the header is row 1).
  """
  @spec load(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load(path \\ default_path()) do
    [header | rows] = path |> File.read!() |> CSV.parse_string(skip_headers: false)

    if Enum.map(header, &String.trim/1) == @columns do
      rows
      |> Enum.with_index(2)
      |> Enum.reduce_while({:ok, %{tokens: %{}, galls: %{}}}, &add_row/2)
    else
      {:error, "row 1: the columns must be #{Enum.join(@columns, ", ")}"}
    end
  end

  defp add_row({fields, line}, {:ok, acc}) do
    case row(fields) do
      {:ok, row} -> add(acc, row, line)
      {:error, message} -> {:halt, {:error, "row #{line}: #{message}"}}
    end
  end

  defp add(acc, %{kind: kind, key: key} = row, line) do
    table = if kind == :token, do: :tokens, else: :galls

    if Map.has_key?(acc[table], key),
      do: {:halt, {:error, "row #{line}: #{key} is listed twice"}},
      else: {:cont, {:ok, put_in(acc, [table, key], row)}}
  end

  defp row(fields) when length(fields) == length(@columns) do
    [kind, key, name, inducer, generation, needs_review, category, handling] =
      Enum.map(fields, &String.trim/1)

    with {:ok, kind} <- kind(kind),
         {:ok, key} <- key(kind, key),
         {:ok, needs_review} <- boolean(needs_review) do
      {:ok,
       %{
         kind: kind,
         key: key,
         name: blank_nil(name),
         inducer: blank_nil(inducer),
         generation: blank_nil(generation),
         needs_review: needs_review,
         category: category,
         handling: handling
       }}
    end
  end

  defp row(fields), do: {:error, "expected #{length(@columns)} columns, got #{length(fields)}"}

  defp kind("token"), do: {:ok, :token}
  defp kind("gall"), do: {:ok, :gall}
  defp kind(other), do: {:error, "kind must be token or gall, got #{inspect(other)}"}

  defp key(:token, ""), do: {:error, "a token row needs a token"}
  defp key(:token, token), do: {:ok, normalize_token(token)}

  defp key(:gall, id) do
    case Integer.parse(id) do
      {id, ""} -> {:ok, id}
      _ -> {:error, "a gall row's key must be a species ID, got #{inspect(id)}"}
    end
  end

  defp boolean("true"), do: {:ok, true}
  defp boolean("false"), do: {:ok, false}
  defp boolean(other), do: {:error, "needs_review must be true or false, got #{inspect(other)}"}

  defp blank_nil(""), do: nil
  defp blank_nil(value), do: value

  @doc """
  Reads gall `id`'s name `name`: its base (the name without its suffixes;
  for a curated gall, the row's Inducer name, which may be nil), its
  generation value, and why a curator must review it (nil if not).

  A "Unknown (Family)" placeholder prefix stays in the base; the caller
  decides what a base means for the gall's genus link.
  """
  @spec parse(t(), integer(), String.t()) :: {:ok, parsed()} | {:error, String.t()}
  def parse(%{galls: galls} = mapping, id, name) do
    case Map.fetch(galls, id) do
      {:ok, row} -> curated(row, name)
      :error -> mechanical(mapping, name)
    end
  end

  defp curated(row, name) do
    if squish(name) == squish(row.name) do
      {:ok,
       %{
         base: row.inducer,
         generation: row.generation,
         review: if(row.needs_review, do: row.handling),
         curated?: true
       }}
    else
      {:error, "curated row is for #{row.name}"}
    end
  end

  defp mechanical(%{tokens: tokens}, name) do
    name = squish(name)

    {prefix, rest} =
      case Regex.run(@placeholder_prefix, name) do
        [prefix] -> {prefix, String.replace_prefix(name, prefix, "")}
        nil -> {"", name}
      end

    written = for [_group, token] <- Regex.scan(@group, rest), do: token
    base = squish(prefix <> " " <> Regex.replace(@group, rest, " "))

    with {:ok, rows} <- token_rows(tokens, written),
         {:ok, generation} <- generation(rows) do
      review =
        case for(row <- rows, row.needs_review, do: row.handling) do
          [] -> nil
          reasons -> Enum.join(reasons, "; ")
        end

      {:ok, %{base: base, generation: generation, review: review, curated?: false}}
    end
  end

  defp token_rows(tokens, written) do
    Enum.reduce_while(written, {:ok, []}, fn token, {:ok, acc} ->
      case Map.fetch(tokens, normalize_token(token)) do
        {:ok, row} -> {:cont, {:ok, acc ++ [row]}}
        :error -> {:halt, {:error, "unknown suffix (#{String.trim(token)})"}}
      end
    end)
  end

  defp generation(rows) do
    case for(%{generation: g} <- rows, g != nil, do: g) do
      [] -> {:ok, nil}
      [generation] -> {:ok, generation}
      several -> {:error, "two generations (#{Enum.join(several, ", ")})"}
    end
  end

  defp normalize_token(token), do: token |> squish() |> String.downcase()

  defp squish(text), do: text |> String.trim() |> String.replace(~r/\s+/u, " ")
end
