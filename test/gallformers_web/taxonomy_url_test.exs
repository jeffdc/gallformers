defmodule GallformersWeb.TaxonomyURLTest do
  use ExUnit.Case, async: true

  alias GallformersWeb.TaxonomyURL

  describe "taxon_path/1" do
    test "a plant species, subspecies or variety: its Host page" do
      for rank <- ~w(species subspecies variety) do
        assert TaxonomyURL.taxon_path(%{
                 id: 7,
                 name: "Quercus alba",
                 rank: rank,
                 kingdom: "Plantae"
               }) ==
                 "/host/7"
      end
    end

    test "a rank with a page: that page, by name" do
      assert TaxonomyURL.taxon_path(%{
               id: 1,
               name: "Andricus",
               rank: "genus",
               kingdom: "Animalia"
             }) ==
               "/genus/Andricus"

      assert TaxonomyURL.taxon_path(%{
               id: 2,
               name: "Cynipini",
               rank: "tribe",
               kingdom: "Animalia"
             }) ==
               "/tribe/Cynipini"
    end

    test "an organism at species rank or below: its species page" do
      for rank <- ~w(species subspecies variety form), kingdom <- ["Animalia", nil] do
        assert TaxonomyURL.taxon_path(%{
                 id: 3,
                 name: "Andricus quercuscalifornicus",
                 rank: rank,
                 kingdom: kingdom
               }) ==
                 "/species/3"
      end
    end

    test "a rank with no page (an order) has none" do
      assert TaxonomyURL.taxon_path(%{
               id: 4,
               name: "Hymenoptera",
               rank: "order",
               kingdom: "Animalia"
             }) ==
               nil
    end
  end

  describe "public_path/1" do
    test "family" do
      assert TaxonomyURL.public_path(%{type: "family", name: "Cynipidae"}) == "/family/Cynipidae"
    end

    test "genus" do
      assert TaxonomyURL.public_path(%{type: "genus", name: "Andricus"}) == "/genus/Andricus"
    end

    test "section" do
      assert TaxonomyURL.public_path(%{type: "section", name: "Quercus"}) == "/section/Quercus"
    end

    test "intermediate with rank" do
      assert TaxonomyURL.public_path(%{
               type: "intermediate",
               rank: "Subfamily",
               name: "Cynipinae"
             }) ==
               "/subfamily/Cynipinae"
    end

    test "intermediate with nil rank returns nil" do
      assert TaxonomyURL.public_path(%{type: "intermediate", rank: nil, name: "Cynipinae"}) == nil
    end

    test "intermediate with empty rank returns nil" do
      assert TaxonomyURL.public_path(%{type: "intermediate", rank: "", name: "Cynipinae"}) == nil
    end

    test "unknown type returns nil" do
      assert TaxonomyURL.public_path(%{type: "unknown", name: "Foo"}) == nil
    end

    test "works with structs (any map with type/name)" do
      assert TaxonomyURL.public_path(%{type: "family", name: "Eriophyidae", extra: true}) ==
               "/family/Eriophyidae"
    end

    test "encodes names with spaces and special characters" do
      assert TaxonomyURL.public_path(%{type: "family", name: "Santalaceae (gall)"}) ==
               "/family/Santalaceae%20(gall)"

      assert TaxonomyURL.public_path(%{type: "genus", name: "Unknown (Cynipidae)"}) ==
               "/genus/Unknown%20(Cynipidae)"
    end
  end

  describe "numeric?/1" do
    test "pure digits" do
      assert TaxonomyURL.numeric?("123") == true
      assert TaxonomyURL.numeric?("0") == true
    end

    test "non-numeric strings" do
      refute TaxonomyURL.numeric?("Cynipidae")
      refute TaxonomyURL.numeric?("12a")
      refute TaxonomyURL.numeric?("")
    end

    test "strings with spaces or symbols" do
      refute TaxonomyURL.numeric?("12 34")
      refute TaxonomyURL.numeric?("-1")
    end
  end
end
