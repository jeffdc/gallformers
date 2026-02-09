defmodule Gallformers.Search.RankingTest do
  use ExUnit.Case, async: true

  alias Gallformers.Search.Ranking

  describe "parse_query/1" do
    test "splits and lowercases" do
      assert Ranking.parse_query("Quercus Alba") == ["quercus", "alba"]
    end

    test "trims extra whitespace" do
      assert Ranking.parse_query("  q   alba  ") == ["q", "alba"]
    end

    test "returns empty list for non-binary" do
      assert Ranking.parse_query(nil) == []
      assert Ranking.parse_query(123) == []
    end
  end

  describe "add_scores_and_sort/2" do
    test "returns results unchanged for empty search terms" do
      results = [%{name: "b"}, %{name: "a"}]
      assert Ranking.add_scores_and_sort(results, []) == results
    end

    test "exact match gets best score" do
      results = [
        %{name: "agamic"},
        %{name: "Callirhytis furva (agamic)"},
        %{name: "Acraspis erinacei (agamic)"}
      ]

      scored = Ranking.add_scores_and_sort(results, ["agamic"])

      # Exact match should be first with score -1
      assert hd(scored).name == "agamic"
      assert hd(scored).match_score == -1
    end

    test "name starting with search term beats prefix match" do
      results = [
        %{name: "Quercus alba"},
        %{name: "alba Quercus"}
      ]

      scored = Ranking.add_scores_and_sort(results, ["quercus"])

      assert hd(scored).name == "Quercus alba"
      assert hd(scored).match_score == 0
    end

    test "prefix match beats no match" do
      results = [
        %{name: "zzz no match"},
        %{name: "alba quercus"}
      ]

      scored = Ranking.add_scores_and_sort(results, ["alba", "quercus"])

      assert hd(scored).name == "alba quercus"
    end

    test "glossary term ranks above parenthesized species names" do
      # Simulates searching "agamic" - glossary entry vs gall species
      results = [
        %{name: "Callirhytis furva (agamic)"},
        %{name: "Acraspis erinacei (agamic)"},
        %{name: "agamic"}
      ]

      scored = Ranking.add_scores_and_sort(results, ["agamic"])

      # Glossary exact match should be first
      assert hd(scored).name == "agamic"
      assert hd(scored).match_score == -1

      # Species with parenthesized terms should score lower
      # "(agamic)" doesn't prefix-match "agamic" due to the paren
      species_scores = scored |> tl() |> Enum.map(& &1.match_score)
      assert Enum.all?(species_scores, &(&1 > -1))
    end
  end
end
