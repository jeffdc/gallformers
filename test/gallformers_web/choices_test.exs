defmodule GallformersWeb.ChoicesTest do
  @moduledoc """
  The shared pickers' results as a `typeahead` shows them (matter `87a1`,
  task 6): a Host's plants (`Gallformers.Taxa.host_choices/2`) and a
  Fact's places (`Gallformers.Places.search_fact_places/3`).
  """
  use Gallformers.DataCase, async: true

  import Gallformers.TaxaFixtures

  alias Gallformers.Taxa
  alias GallformersWeb.Choices

  defp plant(attrs), do: taxon_fixture(Map.merge(%{kingdom: "Plantae", origin: :powo}, attrs))

  describe "hosts/2" do
    test "grouped Plants, then Genera and sections, each with its rank and aliases" do
      genus = plant(%{rank: :genus, name: "Qwebicus"})
      rubra = plant(%{name: "Qwebicus rubra", parent: genus})
      {:ok, _} = Taxa.add_synonym(test_actor(), rubra, "Qwebicus borealis")

      assert Choices.hosts("qwebicus", 10) == [
               %{
                 id: rubra.id,
                 name: "Qwebicus rubra",
                 meta: "species · also Qwebicus borealis",
                 group: "Plants"
               },
               %{id: genus.id, name: "Qwebicus", meta: "genus", group: "Genera and sections"}
             ]
    end

    test "nothing for under two letters" do
      plant(%{name: "Qwebicus alba"})

      assert Choices.hosts("q", 10) == []
    end
  end

  describe "places/3" do
    test "each place with the place it is in, grouped" do
      assert [%{name: "Alberta", meta: "Canada", group: "States & Provinces", id: id}] =
               Choices.places("albert", :occurrence, 10)

      assert id == Gallformers.CatalogFixtures.place_id("CA-AB")
    end
  end
end
