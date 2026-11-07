defmodule Gallformers.Catalog.GallNameUndescribedTest do
  @moduledoc """
  An undescribed Gall's name read back into what it says
  (`Gallformers.Catalog.GallName.undescribed/1`, the inverse of `derive/1`):
  the Inducer's genus or family, the descriptor in words, the qualifiers.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Catalog.GallName

  describe "undescribed/1" do
    test "a family Inducer: the family, its Gallformer group and the descriptor in words" do
      assert GallName.undescribed("Unknown (Cynipidae) q-stellata-red-bud-gall") == %{
               genus: nil,
               family: "Cynipidae",
               group: "Gall wasps",
               description: "red bud gall",
               qualifiers: nil
             }
    end

    test "no Inducer: no family and no group" do
      assert %{family: nil, group: nil, description: "contorted stem swelling"} =
               GallName.undescribed("Unknown (Unknown) s-hartwegii-contorted-stem-swelling")
    end

    test "a genus Inducer: the genus, and no family to name" do
      assert GallName.undescribed("Neuroterus q-gambelii-new-growth-swelling (sexgen)") == %{
               genus: "Neuroterus",
               family: nil,
               group: nil,
               description: "new growth swelling",
               qualifiers: "(sexgen)"
             }
    end

    test "the qualifiers are kept as written, in order" do
      assert %{description: "red oak fringed gall", qualifiers: "(agamic) (on Quercus rubra)"} =
               GallName.undescribed(
                 "Unknown (Cynipidae) red-oak-fringed-gall (agamic) (on Quercus rubra)"
               )
    end

    test "a descriptor without a Host code is put in words as it is" do
      assert %{description: "red oak fuzzy red globs"} =
               GallName.undescribed("Unknown (Cynipidae) red-oak-fuzzy-red-globs")

      assert %{genus: "Macrodiplosis", description: "lobe fold mine"} =
               GallName.undescribed("Macrodiplosis lobe-fold-mine")
    end

    test "a descriptor likening it to another gall says so" do
      assert %{description: "gall like p nigra"} =
               GallName.undescribed("Unknown (Cynipidae) q-arizonica-like-p-nigra")

      assert %{genus: "Rabdophaga", description: "gall like rosaria"} =
               GallName.undescribed("Rabdophaga like-rosaria")

      assert %{description: "gall near campestricola"} =
               GallName.undescribed("Aceria near-campestricola")

      assert %{description: "gall on smilax"} = GallName.undescribed("Meunieriella on-smilax")
    end

    test "a family no group names has no group" do
      assert %{family: "Fixturnamidae", group: nil} =
               GallName.undescribed("Unknown (Fixturnamidae) q-alba-bead")
    end

    test "a name not derived from a descriptor gives nil" do
      assert GallName.undescribed("Andricus") == nil
      assert GallName.undescribed("") == nil
    end
  end
end
