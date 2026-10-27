defmodule Mix.Tasks.Gallformers.Catalog.IdParityTest do
  @moduledoc """
  `mix gallformers.catalog.id_parity` (`803b` Task 9) on the converted
  seeds, which hold the old tables and the new ones made from them by the
  catalog migration (`make test-db`), `gall_index` included.

  Seeds used: plant 10 (Notholithocarpus densiflorus: US-CA native, RO-B
  introduced) hosts galls 300–304; gall 304 also sits on the genus
  placeholder 11 (MX), the genus Notholithocarpus (old taxonomy 41).

  Not async: loads the vocabularies (`Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  # Comparing the converted seeds is what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import ExUnit.CaptureIO
  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Taxa
  alias Mix.Tasks.Gallformers.Catalog.IdParity

  setup do
    load_vocab!()
    :ok
  end

  defp classes(report),
    do: Enum.map(report.differences, &{&1.gall_id, &1.direction, &1.class})

  test "the same Host finds the same galls in both tools" do
    report = IdParity.compare([%{host: 10}, %{genus: 41}])

    assert report.compared == 2
    assert report.differences == []
  end

  test "galls gaining a Host's introduced range are expected" do
    report = IdParity.compare([%{host: 10, place: "RO-B"}])

    assert classes(report) == for(id <- [300, 301, 302, 303, 304], do: {id, :gained, :introduced})
  end

  test "a gall on a genus Host gaining another species' introduced range is expected" do
    # Gall 304's genus Host Notholithocarpus now reads its species' ranges
    # (`803b` decision 8): a second species, introduced in the Bahamas.
    genus = Taxa.get_by_legacy_id(:taxonomy, 41)
    other = plant_fixture(name: "Notholithocarpus fixtura", parent: genus)
    host_range_fixture(other, [{"BS", "exact", "introduced"}])
    :ok = Catalog.refresh_gall_index([304])

    report = IdParity.compare([%{host: 10, place: "BS"}])

    assert classes(report) == [{304, :gained, :introduced}]
  end

  test "the old genus-placeholder waiver is explained where no species of the genus grows" do
    # The old tool let gall 304 (on placeholder 11) through any place with
    # its genus selected; Notholithocarpus grows nowhere in Canada.
    report = IdParity.compare([%{genus: 41, place: "CA-AB"}, %{genus: 41, place: "MX-JAL"}])

    assert classes(report) == [{304, :lost, :placeholder_waiver}]
  end

  test "a gall with no Inducer counted undescribed is explained" do
    # Seed gall 100 has no genus link (no Inducer) and was not flagged undescribed.
    report = IdParity.compare([%{host: 6, undescribed: true}])

    assert classes(report) == [{100, :gained, :no_inducer}]
  end

  test "a Gall that lost its Host in the new tables is unexpected" do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: 10, object_gall_id: 300},
        deny(source_fixture("Revision", "2030"))
      )

    report = IdParity.compare([%{host: 10}])

    assert classes(report) == [{300, :lost, :unexpected}]
  end

  test "a filter set the new tool cannot translate is skipped, not compared" do
    report = IdParity.compare([%{genus: 999_999}, %{host: 10, trait: {"color", 999_999}}])

    assert report.compared == 0

    assert [
             {%{genus: 999_999}, "taxonomy 999999 has no taxon"},
             {_, "color 999999 is no Trait value"}
           ] =
             report.skipped
  end

  test "the task samples filter sets, compares them and prints the classes" do
    output = capture_io(fn -> IdParity.run(["--hosts", "3", "--seed", "1"]) end)

    assert output =~ ~r/ID tool parity: \d+ filter sets compared/
    assert output =~ "Expected: introduced:"
    assert output =~ "Unexpected: unexpected:"
  end

  test "sample/2 is repeatable and every set has a Host or a Host genus" do
    sets = IdParity.sample(5, 3)

    assert sets == IdParity.sample(5, 3)
    assert sets != []
    assert Enum.reject(sets, &(Map.has_key?(&1, :host) or Map.has_key?(&1, :genus))) == []
  end
end
