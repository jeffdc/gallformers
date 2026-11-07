defmodule Gallformers.Import.FactsForGallTest do
  @moduledoc """
  A Gall's Facts as the Gall page shows them (matter `ec2c`, finding 5),
  `Gallformers.Import.facts_for_gall/1`: every Fact about the Gall under
  its one header, by category, each with its standing and the Sources
  stating it, oldest first. Facts never shown (`:unsupported`) are left
  out.

  Not async: the vocabularies are loaded (`Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Import

  setup :audit_test_metadata

  setup do
    load_vocab!()
    %{gall: gall_fixture()}
  end

  defp trait!(gall, trait, value, attribution) do
    {:ok, _} =
      Catalog.assert_trait(
        test_actor(),
        %{gall_id: gall.id, trait: trait, value: value},
        attribution
      )
  end

  test "one header for the Gall, its Facts by category with their Sources", %{gall: gall} do
    kinsey = source_fixture("Kinsey", "1959")
    weld = source_fixture("Weld", "2001")
    trait!(gall, "color", "red", confirm(weld))
    trait!(gall, "color", "red", confirm(kinsey))
    trait!(gall, "shape", "globular", confirm(kinsey))
    trait!(gall, "shape", "globular", deny(weld))

    assert [%{gall_id: id, name: name, facts: facts}] = Import.facts_for_gall(gall.id)
    assert id == gall.id
    assert is_binary(name)

    assert [red] = facts.traits["color"]
    assert red.standing == :current

    assert [%{source_id: k, stance: :confirm}, %{source_id: w, stance: :confirm}] = red.sources
    assert {k, w} == {kinsey.id, weld.id}
    assert hd(red.sources).name == "Weld 1959"

    assert [globular] = facts.traits["shape"]
    assert globular.standing == :withdrawn
    assert Enum.map(globular.sources, & &1.stance) == [:confirm, :deny]
  end

  test "a Gall with no Facts has its header and nothing under it", %{gall: gall} do
    assert [%{gall_id: id, facts: facts}] = Import.facts_for_gall(gall.id)
    assert id == gall.id
    assert facts |> Map.values() |> Enum.all?(&(&1 in [[], %{}]))
  end
end
