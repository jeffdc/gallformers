defmodule Gallformers.Catalog.HostGallsTest do
  @moduledoc """
  The Galls on a Host (`Gallformers.Catalog.list_galls_for_hosts/1`), for
  the Host page.

  Mostly the converted seeds (`priv/repo/test_seeds.sql`): plant 10 is the
  Host of Galls 300–304; Gall 304 also has the genus Notholithocarpus as a
  Host (today's genus placeholder).
  """
  use Gallformers.DataCase, async: true

  # Reading the seeds, converted, is most of what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Taxa

  defp host!(plant, gall, attribution) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
        attribution
      )

    :ok
  end

  test "lists the Galls on a host by display name, with their completeness" do
    assert Catalog.list_galls_for_hosts([10]) == [
             %{id: 304, name: "Andricus n-densiflorus-seed-gall", datacomplete: false},
             %{id: 300, name: "Andricus seedii (agamic)", datacomplete: true},
             %{id: 301, name: "Andricus seedii (sexgen)", datacomplete: false},
             %{id: 302, name: "Neuroterus seedatorius (australis) (agamic)", datacomplete: false},
             %{id: 303, name: "Neuroterus seedatorius (sexgen)", datacomplete: false}
           ]
  end

  test "a genus Host's Galls are the genus's, not its species'" do
    genus = Taxa.get_by_legacy_id(:taxonomy, 41)

    assert Enum.map(Catalog.list_galls_for_hosts([genus.id]), & &1.id) == [304]
  end

  test "a Gall on several of the hosts is listed once" do
    genus = Taxa.get_by_legacy_id(:taxonomy, 41)

    assert Enum.count(Catalog.list_galls_for_hosts([10, genus.id]), &(&1.id == 304)) == 1
  end

  test "only current Host Facts count; the name shown is the override" do
    plant = plant_fixture()
    source = source_fixture("Weld", "1959")
    shown = gall_fixture(name: "Derived name", name_override: "Shown name")
    withdrawn = gall_fixture()

    host!(plant, shown, confirm(source))
    host!(plant, withdrawn, confirm(source))
    host!(plant, withdrawn, deny(source_fixture("Revision", "1990")))

    assert [%{id: id, name: "Shown name"}] = Catalog.list_galls_for_hosts([plant.id])
    assert id == shown.id
  end

  test "no hosts, no Galls" do
    assert Catalog.list_galls_for_hosts([]) == []
  end
end
