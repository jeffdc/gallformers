defmodule Gallformers.TextMatchTest do
  use Gallformers.DataCase, async: true

  alias Gallformers.TextMatch

  # Rows of a table with two text columns to filter on: the old model's
  # `species` table (not audited), mapped here for the test only.
  defmodule Species do
    use Ecto.Schema

    schema "species" do
      field :name, :string
      field :taxoncode, :string
      field :datacomplete, :boolean
      timestamps(type: :utc_datetime)
    end
  end

  defp create_species(name, taxoncode) do
    Repo.insert!(%Species{name: name, taxoncode: taxoncode, datacomplete: false})
  end

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
    setup do
      tag = System.unique_integer([:positive])
      quercus_name = "Quercusfixture#{tag}"
      alba_name = "alba#{tag}"

      quercus_alba = create_species("#{quercus_name} #{alba_name}", "plant")
      quercus_rubra = create_species("#{quercus_name} rubra#{tag}", "plant")
      quercus_velutina = create_species("#{quercus_name} velutina#{tag}", "plant")
      andricus = create_species("Andricusfixture#{tag} confluenta#{tag}", "gall")

      {:ok,
       species: [quercus_alba, quercus_rubra, quercus_velutina, andricus],
       quercus_name: quercus_name,
       alba_name: alba_name,
       quercus_alba: quercus_alba,
       quercus_rubra: quercus_rubra,
       quercus_velutina: quercus_velutina}
    end

    test "empty search matches everything", %{species: species} do
      filter = TextMatch.build_filter("", [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      result_ids = MapSet.new(Enum.map(results, & &1.id))

      for species_record <- species do
        assert species_record.id in result_ids
      end
    end

    test "nil search matches everything", %{species: species} do
      filter = TextMatch.build_filter(nil, [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      result_ids = MapSet.new(Enum.map(results, & &1.id))

      for species_record <- species do
        assert species_record.id in result_ids
      end
    end

    test "single term filters correctly", %{alba_name: alba_name, quercus_alba: quercus_alba} do
      filter = TextMatch.build_filter(alba_name, [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      assert length(results) == 1
      assert hd(results).id == quercus_alba.id
    end

    test "multi-term requires all terms to match", %{
      quercus_name: quercus_name,
      alba_name: alba_name,
      quercus_alba: quercus_alba
    } do
      filter = TextMatch.build_filter("#{quercus_name} #{alba_name}", [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      assert length(results) == 1
      assert hd(results).id == quercus_alba.id
    end

    test "partial term matches", %{
      quercus_name: quercus_name,
      quercus_alba: quercus_alba,
      quercus_rubra: quercus_rubra,
      quercus_velutina: quercus_velutina
    } do
      filter = TextMatch.build_filter(quercus_name, [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      quercus_ids = MapSet.new(Enum.map(results, & &1.id))

      assert quercus_alba.id in quercus_ids
      assert quercus_rubra.id in quercus_ids
      assert quercus_velutina.id in quercus_ids
    end

    test "search is case insensitive", %{
      quercus_name: quercus_name,
      alba_name: alba_name,
      quercus_alba: quercus_alba
    } do
      filter = TextMatch.build_filter(String.upcase("#{quercus_name} #{alba_name}"), [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      assert length(results) == 1
      assert hd(results).id == quercus_alba.id
    end

    test "no match returns empty list" do
      filter = TextMatch.build_filter("zzzznotfound", [:name])
      results = from(s in Species, where: ^filter) |> Repo.all()

      assert results == []
    end

    test "multi-field matches in any field" do
      filter = TextMatch.build_filter("plant", [:name, :taxoncode])
      results = from(s in Species, where: ^filter) |> Repo.all()

      assert Enum.all?(results, &(&1.taxoncode == "plant")) == true
    end

    test "multi-term across multiple fields requires all terms match somewhere", %{
      alba_name: alba_name,
      quercus_alba: quercus_alba
    } do
      filter = TextMatch.build_filter("#{alba_name} plant", [:name, :taxoncode])
      results = from(s in Species, where: ^filter) |> Repo.all()

      assert length(results) == 1
      assert hd(results).id == quercus_alba.id
    end
  end

  describe "matches_all_terms?/2" do
    test "partial terms match" do
      assert TextMatch.matches_all_terms?("q alba", "Quercus alba") == true
    end

    test "full terms match" do
      assert TextMatch.matches_all_terms?("quercus alba", "Quercus alba") == true
    end

    test "matching is case insensitive" do
      assert TextMatch.matches_all_terms?("QUERCUS ALBA", "Quercus alba") == true
      assert TextMatch.matches_all_terms?("quercus alba", "QUERCUS ALBA") == true
    end

    test "all terms must match (fails when one misses)" do
      refute TextMatch.matches_all_terms?("q xyz", "Quercus alba")
    end

    test "empty search matches anything" do
      assert TextMatch.matches_all_terms?("", "Quercus alba") == true
      assert TextMatch.matches_all_terms?("", "anything at all") == true
    end

    test "nil search matches anything" do
      assert TextMatch.matches_all_terms?(nil, "Quercus alba") == true
    end

    test "nil text returns false" do
      refute TextMatch.matches_all_terms?("alba", nil)
    end

    test "single term match" do
      assert TextMatch.matches_all_terms?("alba", "Quercus alba") == true
    end

    test "whitespace-only search matches anything" do
      assert TextMatch.matches_all_terms?("   ", "Quercus alba") == true
    end
  end
end
