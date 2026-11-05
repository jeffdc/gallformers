defmodule Gallformers.Import.NameVariantsTest do
  @moduledoc """
  Spelling and ending variants of Latin epithets, for suggestions only
  (queue triage rules C, F and G), and whether two epithets are one name in
  another gender.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Import.NameVariants

  describe "variants/1" do
    test "Latin endings: -us/-a/-um, -er/-ra/-rum, -is/-e, -a/-ae, -i/-ii" do
      assert "rubra" in NameVariants.variants("rubrum")
      assert "nigra" in NameVariants.variants("niger")
      assert "quercusstrobilanus" in NameVariants.variants("quercusstrobilana")
      assert "gemmae" in NameVariants.variants("gemma")
      assert "coccinea" in NameVariants.variants("coccineae")
      assert "douglasi" in NameVariants.variants("douglasii")
      assert "rileyii" in NameVariants.variants("rileyi")
      assert "brevis" in NameVariants.variants("breve")
    end

    test "spellings: ii/i inside the word, ae/a, ae/e and ae/oe" do
      assert "vaccinifoliae" in NameVariants.variants("vacciniifoliae")
      assert "ambrosiacola" in NameVariants.variants("ambrosiaecola")
      assert "coelebs" in NameVariants.variants("caelebs")
    end

    test "never the word itself, and nothing for a word with no known ending" do
      refute "rubrum" in NameVariants.variants("rubrum")
      assert NameVariants.variants("lobt") == []
    end
  end

  describe "same_epithet?/2" do
    test "one epithet in another gender, or ii/i, is the same" do
      assert NameVariants.same_epithet?("sulcatus", "sulcata") == true
      assert NameVariants.same_epithet?("niger", "nigrum") == true
      assert NameVariants.same_epithet?("morrisonii", "morrisoni") == true
      assert NameVariants.same_epithet?("quercuscornigera", "quercuscornigera") == true
    end

    test "a different word, or a genitive for a nominative, is not" do
      refute NameVariants.same_epithet?("vesiculoides", "clarkei")
      refute NameVariants.same_epithet?("nigrae", "nigra")
      refute NameVariants.same_epithet?("smilacis", "smilax")
    end
  end

  describe "epithet/1 and genus/1" do
    test "the words after the genus, joined, as normalized" do
      assert NameVariants.epithet("Cynips quercus cornigera") == "quercuscornigera"
      assert NameVariants.epithet("Callirhytis quercus-cornigera") == "quercuscornigera"
      assert NameVariants.epithet("ANDRICUS IMBRECARIÆ") == "imbrecariae"
      assert NameVariants.epithet("Andricus") == nil
      assert NameVariants.genus("Cynips (Synerges?) lignicola") == "cynips"
    end
  end

  describe "edit_distance/2" do
    test "counts insertions, deletions and substitutions" do
      assert NameVariants.edit_distance("wisliceni", "wislizeni") == 1
      assert NameVariants.edit_distance("allegheliensis", "allegheniensis") == 1
      assert NameVariants.edit_distance("abc", "abc") == 0
      assert NameVariants.edit_distance("abc", "") == 3
      assert NameVariants.edit_distance("kitten", "sitting") == 3
    end
  end
end
