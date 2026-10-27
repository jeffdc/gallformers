defmodule Gallformers.Catalog.GallsByIdTest do
  @moduledoc """
  Galls fetched by a list of IDs (`Gallformers.Catalog.list_galls_by_id/1`),
  as the review queue shows the Galls its items name.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog

  test "the Galls with the given IDs, by name, unknown IDs left out" do
    b = gall_fixture(name: "Byid beta gall")
    a = gall_fixture(name: "Byid alpha gall")

    assert Enum.map(Catalog.list_galls_by_id([b.id, a.id, -1, b.id]), & &1.id) == [a.id, b.id]
  end

  test "no IDs, no Galls" do
    assert Catalog.list_galls_by_id([]) == []
  end
end
