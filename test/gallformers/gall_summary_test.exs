defmodule Gallformers.Galls.SummaryTest do
  use ExUnit.Case, async: false

  alias Gallformers.Galls.Summary

  describe "from_db_filters/2" do
    test "converts database filter format to summary format" do
      db_filters = %{
        shapes: [%{id: 1, field: "spherical"}],
        colors: [%{id: 2, field: "red"}, %{id: 3, field: "brown"}],
        textures: [%{id: 4, field: "hairy"}],
        plant_parts: [%{id: 5, field: "leaf"}],
        seasons: [%{id: 6, field: "spring"}],
        alignments: [],
        walls: [],
        cells: [],
        forms: [%{id: 7, field: "gall"}]
      }

      # Detachable is stored as integer in gall: 0=unknown, 1=integral, 2=detachable, 3=both
      result = Summary.from_db_filters(db_filters, 2)

      assert result.shapes == ["spherical"]
      assert result.colors == ["red", "brown"]
      assert result.textures == ["hairy"]
      assert result.plant_parts == ["leaf"]
      assert result.seasons == ["spring"]
      assert result.detachable == "detachable"
      assert result.forms == ["gall"]
    end

    test "handles empty filter lists" do
      db_filters = %{
        shapes: [],
        colors: [],
        textures: [],
        plant_parts: [],
        seasons: [],
        alignments: [],
        walls: [],
        cells: [],
        forms: []
      }

      result = Summary.from_db_filters(db_filters, 0)

      assert result.shapes == []
      assert result.colors == []
      assert result.detachable == nil
    end

    test "converts detachable integers correctly" do
      db_filters = %{
        shapes: [],
        colors: [],
        plant_parts: [],
        textures: [],
        forms: [],
        seasons: [],
        alignments: [],
        walls: [],
        cells: []
      }

      assert Summary.from_db_filters(db_filters, 0).detachable == nil
      assert Summary.from_db_filters(db_filters, 1).detachable == "integral"
      assert Summary.from_db_filters(db_filters, 2).detachable == "detachable"
      assert Summary.from_db_filters(db_filters, 3).detachable == "both"
    end

    test "handles nil db_filters" do
      result = Summary.from_db_filters(nil, 2)
      assert result == %{}
    end
  end

  describe "generate/2" do
    test "full data produces complete sentence" do
      filters = %{
        shapes: ["spherical"],
        colors: ["red"],
        textures: ["hairy"],
        plant_parts: ["leaf"],
        seasons: ["spring"],
        detachable: "detachable",
        forms: ["gall"]
      }

      result = Summary.generate(filters)

      assert result == "A spherical, red, hairy gall found on the leaf in spring. Detachable."
    end

    test "sparse data gracefully degrades - no shape" do
      filters = %{
        colors: ["red"],
        textures: ["hairy"],
        plant_parts: ["leaf"],
        seasons: ["spring"],
        detachable: nil,
        forms: []
      }

      result = Summary.generate(filters)

      assert result == "A red, hairy gall found on the leaf in spring."
    end

    test "sparse data gracefully degrades - only location and texture" do
      filters = %{
        textures: ["hairy"],
        plant_parts: ["leaf"]
      }

      result = Summary.generate(filters)

      assert result == "A hairy gall found on the leaf."
    end

    test "sparse data gracefully degrades - only location" do
      filters = %{
        plant_parts: ["leaf"]
      }

      result = Summary.generate(filters)

      assert result == "A gall found on the leaf."
    end

    test "empty input returns minimal fallback" do
      assert Summary.generate(%{}) == "A gall."
    end

    test "nil input returns minimal fallback" do
      assert Summary.generate(nil) == "A gall."
    end

    test "non-gall form uses structure instead of gall" do
      filters = %{
        colors: ["red"],
        plant_parts: ["stem"],
        forms: ["non-gall"]
      }

      result = Summary.generate(filters)

      assert result == "A red structure found on the stem."
    end

    test "erineum form uses erineum with correct article" do
      filters = %{
        colors: ["red"],
        plant_parts: ["leaf"],
        forms: ["erineum"]
      }

      result = Summary.generate(filters)

      assert result == "A red erineum found on the leaf."
    end

    test "proper article selection - a vs an" do
      # "oval" starts with vowel
      filters = %{
        shapes: ["oval"],
        plant_parts: ["leaf"]
      }

      result = Summary.generate(filters)

      assert result == "An oval gall found on the leaf."
    end

    test "multi-value attributes joined with slash" do
      filters = %{
        colors: ["red", "brown"],
        plant_parts: ["leaf", "stem"]
      }

      result = Summary.generate(filters)

      assert result == "A red/brown gall found on the leaf/stem."
    end

    test "multi-value attributes truncated at 3 with ellipsis" do
      filters = %{
        colors: ["red", "brown", "green", "yellow"]
      }

      result = Summary.generate(filters)

      assert result == "A red/brown/green/... gall."
    end

    test "detachable phrase - integral" do
      filters = %{
        plant_parts: ["leaf"],
        detachable: "integral"
      }

      result = Summary.generate(filters)

      assert result == "A gall found on the leaf. Integral to host."
    end

    test "detachable phrase - both" do
      filters = %{
        plant_parts: ["leaf"],
        detachable: "both"
      }

      result = Summary.generate(filters)

      assert result == "A gall found on the leaf. May be detachable or integral."
    end

    test "mode :short truncates to key attributes" do
      filters = %{
        shapes: ["spherical"],
        colors: ["red"],
        textures: ["hairy"],
        plant_parts: ["leaf"],
        seasons: ["spring"],
        detachable: "detachable",
        forms: ["gall"]
      }

      result = Summary.generate(filters, mode: :short)

      # Short mode: location, shape, color only - ~50 chars target
      assert result == "A spherical, red gall on the leaf."
    end

    test "mode :full includes all available data" do
      filters = %{
        shapes: ["spherical"],
        colors: ["red"],
        textures: ["hairy"],
        plant_parts: ["leaf"],
        seasons: ["spring"],
        detachable: "detachable",
        alignments: ["erect"],
        walls: ["thick"],
        cells: ["monothalamous"],
        forms: ["gall"]
      }

      result = Summary.generate(filters, mode: :full)

      # Full mode includes alignment, walls, cells
      assert result =~
               "A spherical, red, hairy, erect gall found on the leaf in spring. Monothalamous with thick walls. Detachable."
    end

    test "empty string attribute treated as nil" do
      filters = %{
        shapes: [""],
        colors: [],
        plant_parts: ["leaf"]
      }

      result = Summary.generate(filters)

      assert result == "A gall found on the leaf."
    end

    test "unknown form value defaults to gall" do
      filters = %{
        plant_parts: ["leaf"],
        forms: ["unknown-form-type"]
      }

      result = Summary.generate(filters)

      assert result == "A gall found on the leaf."
    end
  end

  describe "for_seo/2" do
    test "prefixes with species name" do
      filters = %{
        shapes: ["spherical"],
        colors: ["red"],
        plant_parts: ["leaf"]
      }

      result = Summary.for_seo("Andricus quercuscalifornicus", filters)

      assert result =~ "Andricus quercuscalifornicus"
      assert result =~ "spherical"
      assert result =~ "red"
      assert result =~ "leaf"
    end

    test "stays under 160 chars" do
      filters = %{
        shapes: ["spherical"],
        colors: ["red", "brown", "green"],
        textures: ["hairy", "woolly"],
        plant_parts: ["leaf", "stem", "bud"],
        seasons: ["spring", "summer"],
        detachable: "detachable",
        alignments: ["erect"],
        walls: ["thick"],
        cells: ["monothalamous"],
        forms: ["gall"]
      }

      result = Summary.for_seo("Andricus quercuscalifornicus", filters)

      assert String.length(result) <= 160
    end

    test "handles empty filters gracefully" do
      result = Summary.for_seo("Andricus quercuscalifornicus", %{})

      assert result == "Andricus quercuscalifornicus - A gall species documented on Gallformers."
    end

    test "handles nil filters" do
      result = Summary.for_seo("Unknown Species", nil)

      assert result == "Unknown Species - A gall species documented on Gallformers."
    end
  end
end
