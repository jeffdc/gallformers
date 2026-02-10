defmodule Gallformers.Taxonomy.TaxonNameTest do
  use ExUnit.Case, async: true

  alias Gallformers.Taxonomy.TaxonName

  describe "genus_display/1" do
    test "extracts genus from simple species name" do
      assert TaxonName.genus_display("Andricus quercuslanigera") == "Andricus"
    end

    test "extracts Unknown (Family) from placeholder name" do
      assert TaxonName.genus_display("Unknown (Cynipidae) oak-apple") == "Unknown (Cynipidae)"
    end

    test "returns single-word name as-is" do
      assert TaxonName.genus_display("Andricus") == "Andricus"
    end

    test "handles empty string" do
      assert TaxonName.genus_display("") == ""
    end

    test "handles multi-word epithet" do
      assert TaxonName.genus_display("Quercus sect. Lobatae") == "Quercus"
    end
  end

  describe "epithet/1" do
    test "extracts epithet from simple species name" do
      assert TaxonName.epithet("Andricus quercuslanigera") == "quercuslanigera"
    end

    test "extracts epithet from Unknown (Family) name" do
      assert TaxonName.epithet("Unknown (Cynipidae) oak-apple") == "oak-apple"
    end

    test "returns empty string for genus-only name" do
      assert TaxonName.epithet("Andricus") == ""
    end

    test "returns empty string for empty input" do
      assert TaxonName.epithet("") == ""
    end

    test "extracts multi-word epithet" do
      assert TaxonName.epithet("Callirhytis furva (agamic)") == "furva (agamic)"
    end

    test "extracts epithet after Unknown (Family) with no trailing space" do
      assert TaxonName.epithet("Unknown (Cecidomyiidae)") == ""
    end
  end

  describe "replace_genus/3" do
    test "replaces genus in simple species name" do
      assert TaxonName.replace_genus("Andricus quercuslanigera", "Andricus", "Callirhytis") ==
               "Callirhytis quercuslanigera"
    end

    test "replaces Unknown (Family) with a genus" do
      assert TaxonName.replace_genus(
               "Unknown (Cynipidae) oak-apple",
               "Unknown (Cynipidae)",
               "Andricus"
             ) ==
               "Andricus oak-apple"
    end

    test "replaces genus-only name" do
      assert TaxonName.replace_genus("Andricus", "Andricus", "Callirhytis") == "Callirhytis"
    end

    test "falls back to first-word replacement when old_genus doesn't match prefix" do
      assert TaxonName.replace_genus("Quercus alba", "Fagus", "Oakus") == "Oakus alba"
    end

    test "returns original when single word doesn't match" do
      assert TaxonName.replace_genus("Andricus", "Quercus", "Oakus") == "Andricus"
    end
  end

  describe "build/2" do
    test "combines genus and epithet" do
      assert TaxonName.build("Andricus", "quercuslanigera") == "Andricus quercuslanigera"
    end

    test "returns genus when epithet is empty" do
      assert TaxonName.build("Andricus", "") == "Andricus"
    end

    test "combines Unknown (Family) and epithet" do
      assert TaxonName.build("Unknown (Cynipidae)", "oak-apple") ==
               "Unknown (Cynipidae) oak-apple"
    end
  end

  describe "unknown_genus?/1" do
    test "returns true for bare Unknown" do
      assert TaxonName.unknown_genus?("Unknown")
    end

    test "returns true for Unknown (Family)" do
      assert TaxonName.unknown_genus?("Unknown (Cynipidae)")
    end

    test "returns false for regular genus" do
      refute TaxonName.unknown_genus?("Andricus")
    end

    test "returns false for nil" do
      refute TaxonName.unknown_genus?(nil)
    end
  end

  describe "italicize_rank?/1" do
    test "species is italic" do
      assert TaxonName.italicize_rank?("species")
    end

    test "genus is italic" do
      assert TaxonName.italicize_rank?("genus")
    end

    test "section is italic" do
      assert TaxonName.italicize_rank?("section")
    end

    test "family is not italic" do
      refute TaxonName.italicize_rank?("family")
    end

    test "order is not italic" do
      refute TaxonName.italicize_rank?("order")
    end
  end

  describe "italicize_name?/1" do
    test "genus name is italic" do
      assert TaxonName.italicize_name?("Andricus")
    end

    test "species name is italic" do
      assert TaxonName.italicize_name?("Andricus quercuslanigera")
    end

    test "family name (-idae) is not italic" do
      refute TaxonName.italicize_name?("Cynipidae")
    end

    test "subfamily name (-inae) is not italic" do
      refute TaxonName.italicize_name?("Eurytominae")
    end

    test "superfamily name (-oidea) is not italic" do
      refute TaxonName.italicize_name?("Ichneumonoidea")
    end

    test "tribe name (-ini) is not italic" do
      refute TaxonName.italicize_name?("Cynipini")
    end

    test "tribe name (-ina) is not italic" do
      refute TaxonName.italicize_name?("Diplolepidina")
    end

    test "name with parenthetical uses first word only" do
      assert TaxonName.italicize_name?("Andricus (subgenus)")
    end
  end
end
