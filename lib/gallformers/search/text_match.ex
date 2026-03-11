defmodule Gallformers.Search.TextMatch do
  @moduledoc """
  Shared text matching utilities for consistent multi-term search across the app.

  Splits search queries on whitespace into terms, where ALL terms must match.
  Each term is matched as a case-insensitive substring.
  """

  import Ecto.Query

  @doc """
  Parses a search string into LIKE-ready patterns.

  Splits on whitespace, lowercases, wraps each term in %.
  Returns [] for nil/empty/whitespace-only input.
  """
  @spec parse_terms(String.t() | nil) :: [String.t()]
  def parse_terms(nil), do: []

  def parse_terms(search) when is_binary(search) do
    search
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&"%#{&1}%")
  end

  @doc """
  Builds an Ecto dynamic filter for multi-term matching.

  All terms must match. Each term can match in any of the given fields.
  Fields are atoms referencing columns on the first query binding.

  Returns dynamic(true) for empty search (matches everything).

  For complex queries with joins/COALESCE, use parse_terms/1 directly
  and build your own dynamic clauses.
  """
  @spec build_filter(String.t() | nil, [atom()]) :: Ecto.Query.dynamic_expr()
  def build_filter(search, fields) when is_list(fields) do
    case parse_terms(search) do
      [] ->
        dynamic(true)

      terms ->
        Enum.reduce(terms, dynamic(true), &dynamic([], ^&2 and ^match_any_field(&1, fields)))
    end
  end

  defp match_any_field(term, fields) do
    Enum.reduce(fields, dynamic(false), fn field_name, acc ->
      dynamic([q], ^acc or fragment("lower(?) LIKE ?", field(q, ^field_name), ^term))
    end)
  end

  @doc """
  Client-side multi-term matching.

  Returns true if all whitespace-split terms from the search string
  match case-insensitively somewhere in the text.

  Returns true for empty/nil search (matches everything).
  Returns false for nil text.
  """
  @spec matches_all_terms?(String.t() | nil, String.t() | nil) :: boolean()
  def matches_all_terms?(nil, _text), do: true
  def matches_all_terms?(_search, nil), do: false

  def matches_all_terms?(search, text) when is_binary(search) and is_binary(text) do
    terms = search |> String.downcase() |> String.split(~r/\s+/, trim: true)

    if terms == [] do
      true
    else
      text_lower = String.downcase(text)
      Enum.all?(terms, fn term -> String.contains?(text_lower, term) end)
    end
  end
end
