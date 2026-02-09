defmodule Gallformers.Search.Ranking do
  @moduledoc """
  Match quality scoring for FTS5 search results.

  Prioritizes natural name matches over compound/hyphenated names.
  For "q alba", "Quercus alba" ranks higher than "q-alba-gall".
  """

  @score_exact -1
  @score_best 0
  @score_good 1
  @score_ok 2

  @whitespace ~r/\s+/

  @doc """
  Parses a search query into lowercase terms.

  ## Examples

      iex> Ranking.parse_query("Quercus Alba")
      ["quercus", "alba"]

      iex> Ranking.parse_query("  q   alba  ")
      ["q", "alba"]
  """
  @spec parse_query(String.t() | any()) :: [String.t()]
  def parse_query(query) when is_binary(query) do
    query
    |> String.downcase()
    |> String.split(@whitespace, trim: true)
  end

  def parse_query(_), do: []

  @doc """
  Adds a `:match_score` field to each result and sorts by match quality.
  Results must have a `:name` key. Best matches (lowest scores) come first.
  Returns results unchanged if search_terms is empty.
  """
  @spec add_scores_and_sort([%{name: String.t()}], [String.t()]) :: [map()]
  def add_scores_and_sort(results, []), do: results

  def add_scores_and_sort(results, search_terms) do
    results
    |> Enum.map(fn result ->
      Map.put(result, :match_score, calculate_score(result.name, search_terms))
    end)
    |> Enum.sort_by(& &1.match_score)
  end

  # Calculates a match quality score for a name against search terms.
  # Lower is better: 0 = best, 1 = good, 2 = ok.
  defp calculate_score(nil, _search_terms), do: @score_ok
  defp calculate_score(_name, []), do: @score_ok

  defp calculate_score(name, search_terms) do
    name_words = parse_query(name)

    cond do
      name_words == [] ->
        @score_ok

      name_words == search_terms ->
        @score_exact

      String.starts_with?(hd(name_words), hd(search_terms)) ->
        @score_best

      all_terms_match_word_prefixes?(search_terms, name_words) ->
        @score_good

      true ->
        @score_ok
    end
  end

  defp all_terms_match_word_prefixes?(search_terms, name_words) do
    Enum.all?(search_terms, fn term ->
      Enum.any?(name_words, &String.starts_with?(&1, term))
    end)
  end
end
