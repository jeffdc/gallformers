defmodule Gallformers.Taxa.HostChoicesTest do
  @moduledoc """
  The one plant search for a Host (matter `87a1`, task 6;
  `Gallformers.Taxa.host_choices/2`): the plants a Gall's Host may be, of
  any rank a Host can have, as the review, a Source's corrections and the
  Fact inspector all offer them.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.TaxaFixtures

  alias Gallformers.Taxa

  defp plant(attrs), do: taxon_fixture(Map.merge(%{kingdom: "Plantae", origin: :powo}, attrs))

  setup do
    genus = plant(%{rank: :genus, name: "Qhoicus"})
    section = plant(%{rank: :section, name: "Qhoicus sect. Lobatae", parent: genus})
    alba = plant(%{name: "Qhoicus alba", parent: genus})
    rubra = plant(%{name: "Qhoicus rubra", parent: genus})
    variety = plant(%{rank: :variety, name: "Qhoicus rubra var. qhoa", parent: rubra})
    {:ok, _} = Taxa.add_synonym(test_actor(), rubra, "Qhoicus borealis")
    _wasp = taxon_fixture(name: "Qhoicus alba wasp", kingdom: "Animalia")

    %{genus: genus, section: section, alba: alba, rubra: rubra, variety: variety}
  end

  test "species and below, then genera and sections, each with its rank and aliases", ctx do
    choices = Taxa.host_choices("qhoicus", 10)

    plants = for %{group: :plants} = c <- choices, do: c.id
    higher = for %{group: :genera_and_sections} = c <- choices, do: c.id

    assert Enum.sort(plants) == Enum.sort([ctx.alba.id, ctx.rubra.id, ctx.variety.id])
    assert Enum.sort(higher) == Enum.sort([ctx.genus.id, ctx.section.id])
    assert Enum.take_while(choices, &(&1.group == :plants)) |> length() == 3

    rubra = Enum.find(choices, &(&1.id == ctx.rubra.id))
    assert %{name: "Qhoicus rubra", rank: :species, aliases: ["Qhoicus borealis"]} = rubra
    assert %{rank: :genus, aliases: []} = Enum.find(choices, &(&1.id == ctx.genus.id))
  end

  test "a synonym finds its accepted plant", ctx do
    assert [%{id: id, name: "Qhoicus rubra"}] = Taxa.host_choices("borealis", 10)
    assert id == ctx.rubra.id
  end

  test "an animal is never a Host choice" do
    refute Enum.any?(Taxa.host_choices("qhoicus alba", 10), &(&1.name =~ "wasp"))
  end

  test "up to the limit of each group" do
    choices = Taxa.host_choices("qhoicus", 1)

    assert Enum.count(choices, &(&1.group == :plants)) == 1
    assert Enum.count(choices, &(&1.group == :genera_and_sections)) == 1
  end
end
