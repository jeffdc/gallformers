defmodule Gallformers.Import.ResolveHostNamesTest do
  @moduledoc """
  `Gallformers.Import.resolve_host_names/2`: plant names outside a package
  (an iNaturalist observation's Host) resolved as intake resolves a batch's
  Hosts.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Import

  setup do
    :ok = put_test_actor(test_actor())
    genus = plant_fixture(name: "Hostresia", rank: :genus)
    plant = plant_fixture(name: "Hostresia alba", parent: genus)
    wasp = taxon_fixture(name: "Hostresia wasp", kingdom: "Animalia")
    %{plant: plant, wasp: wasp}
  end

  test "names resolve to plants, abbreviations expanded by the texts' genera", ctx do
    assert [exact, abbreviated, missing] =
             Import.resolve_host_names(["Hostresia alba", "H. alba", "Hostresia nowhere"],
               document_texts: ["On Hostresia."]
             )

    assert %{resolution: :resolved, taxon_id: id, method: "exact"} = exact
    assert id == ctx.plant.id
    assert %{resolution: :resolved, method: "abbreviation"} = abbreviated
    assert abbreviated.taxon_id == ctx.plant.id
    assert %{resolution: :unresolved, taxon_id: nil} = missing
  end

  test "only plants: an animal of that name is no Host", _ctx do
    assert [%{resolution: :unresolved}] = Import.resolve_host_names(["Hostresia wasp"])
  end
end
