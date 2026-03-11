defmodule Gallformers.Search.TextMatchTest do
  use Gallformers.DataCase, async: false

  alias Gallformers.Search.TextMatch
  alias Gallformers.Species.Species

  describe "parse_terms/1" do
    test "nil returns empty list" do
      assert TextMatch.parse_terms(nil) == []
    end

    test "empty string returns empty list" do
      assert TextMatch.parse_terms("") == []
    end

    test "whitespace-only returns empty list" do
      assert TextMatch.parse_terms("   ") == []
    end

    test "single term is wrapped in wildcards" do
      assert TextMatch.parse_terms("alba") == ["%alba%"]
    end

    test "multiple terms are split and wrapped" do
      assert TextMatch.parse_terms("q alba") == ["%q%", "%alba%"]
    end

    test "input is lowercased and trimmed" do
      assert TextMatch.parse_terms("  Q   Alba  ") == ["%q%", "%alba%"]
    end

    test "single character term works" do
      assert TextMatch.parse_terms("a") == ["%a%"]
    end
  end

  describe "build_filter/2" do
    test "empty search matches everything" do
      filter = TextMatch.build_filter("", [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      # Should return all species in test seeds
      assert length(results) > 0
    end

    test "nil search matches everything" do
      filter = TextMatch.build_filter(nil, [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      assert length(results) > 0
    end

    test "single term filters correctly" do
      filter = TextMatch.build_filter("alba", [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      assert length(results) == 1
      assert hd(results).name == "Quercus alba"
    end

    test "multi-term requires all terms to match" do
      filter = TextMatch.build_filter("quercus alba", [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      assert length(results) == 1
      assert hd(results).name == "Quercus alba"
    end

    test "partial term matches" do
      # "q" should match all Quercus species
      filter = TextMatch.build_filter("q", [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      quercus_names = Enum.map(results, & &1.name) |> Enum.sort()

      assert "Quercus alba" in quercus_names
      assert "Quercus rubra" in quercus_names
      assert "Quercus velutina" in quercus_names
    end

    test "search is case insensitive" do
      filter = TextMatch.build_filter("QUERCUS ALBA", [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      assert length(results) == 1
      assert hd(results).name == "Quercus alba"
    end

    test "no match returns empty list" do
      filter = TextMatch.build_filter("zzzznotfound", [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      assert results == []
    end

    test "multi-field matches in any field" do
      # "plant" should match via taxoncode field
      filter = TextMatch.build_filter("plant", [:name, :taxoncode])
      results = from(s in Species, where: ^filter) |> Repo.all()

      assert Enum.all?(results, &(&1.taxoncode == "plant"))
    end

    test "multi-term across multiple fields requires all terms match somewhere" do
      # "alba plant" - "alba" matches name, "plant" matches taxoncode
      filter = TextMatch.build_filter("alba plant", [:name, :taxoncode])
      results = from(s in Species, where: ^filter) |> Repo.all()

      assert length(results) == 1
      assert hd(results).name == "Quercus alba"
    end
  end

  describe "matches_all_terms?/2" do
    test "partial terms match" do
      assert TextMatch.matches_all_terms?("q alba", "Quercus alba")
    end

    test "full terms match" do
      assert TextMatch.matches_all_terms?("quercus alba", "Quercus alba")
    end

    test "matching is case insensitive" do
      assert TextMatch.matches_all_terms?("QUERCUS ALBA", "Quercus alba")
      assert TextMatch.matches_all_terms?("quercus alba", "QUERCUS ALBA")
    end

    test "all terms must match (fails when one misses)" do
      refute TextMatch.matches_all_terms?("q xyz", "Quercus alba")
    end

    test "empty search matches anything" do
      assert TextMatch.matches_all_terms?("", "Quercus alba")
      assert TextMatch.matches_all_terms?("", "anything at all")
    end

    test "nil search matches anything" do
      assert TextMatch.matches_all_terms?(nil, "Quercus alba")
    end

    test "nil text returns false" do
      refute TextMatch.matches_all_terms?("alba", nil)
    end

    test "single term match" do
      assert TextMatch.matches_all_terms?("alba", "Quercus alba")
    end

    test "whitespace-only search matches anything" do
      assert TextMatch.matches_all_terms?("   ", "Quercus alba")
    end
  end
end
