defmodule Gallformers.Catalog.DisplayRangeTest do
  @moduledoc """
  A Gall's display range (`Gallformers.Catalog.display_range/1`): the map's
  presentation of its potential range, split for colouring into exact,
  country-level (inherited) and introduced places. Its places are always
  the potential range's (`Gallformers.Catalog.potential_range/1`), which
  stays the one definition of a Gall's range.

  Seeded places (`priv/repo/test_seeds.sql`): US (subdivision US-CA), CA
  (CA-AB), MX (MX-JAL), RO (RO-B), and BS, a country with no subdivisions.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Ranges.DisplayRange

  defp host!(plant, gall, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
        confirm(source)
      )

    :ok
  end

  defp range!(gall, adjustment, code, source) do
    {:ok, _} =
      Catalog.assert_range(
        test_actor(),
        %{gall_id: gall.id, adjustment: adjustment, place_id: place_id(code)},
        confirm(source)
      )

    :ok
  end

  defp sorted(%DisplayRange{} = range) do
    %{
      in_range: Enum.sort(range.in_range),
      inherited_range: Enum.sort(range.inherited_range),
      introduced_range: Enum.sort(range.introduced_range)
    }
  end

  # The display range shows exactly the potential range's places.
  defp assert_same_places(gall) do
    case Catalog.potential_range(gall.id) do
      :everywhere ->
        assert Catalog.display_range(gall.id) == :everywhere

      places ->
        display = Catalog.display_range(gall.id)
        shown = MapSet.new(display.in_range ++ display.inherited_range)

        assert shown == MapSet.new(places, & &1.code)
        assert MapSet.difference(MapSet.new(display.introduced_range), shown) == MapSet.new()

        assert MapSet.intersection(
                 MapSet.new(display.in_range),
                 MapSet.new(display.inherited_range)
               ) ==
                 MapSet.new()
    end
  end

  setup do
    california_oak = plant_fixture()
    host_range_fixture(california_oak, [{"US-CA", "exact"}])

    canadian_oak = plant_fixture()
    host_range_fixture(canadian_oak, [{"CA", "country"}])

    %{
      source: source_fixture("Weld", "1959"),
      gall: gall_fixture(),
      california_oak: california_oak,
      canadian_oak: canadian_oak
    }
  end

  test "Hosts' exact rows are in range", ctx do
    host!(ctx.california_oak, ctx.gall, ctx.source)

    assert sorted(Catalog.display_range(ctx.gall.id)) ==
             %{in_range: ["US-CA"], inherited_range: [], introduced_range: []}

    assert_same_places(ctx.gall)
  end

  test "a country-level row is inherited by the country's subdivisions", ctx do
    host!(ctx.california_oak, ctx.gall, ctx.source)
    host!(ctx.canadian_oak, ctx.gall, ctx.source)

    assert sorted(Catalog.display_range(ctx.gall.id)) ==
             %{in_range: ["US-CA"], inherited_range: ["CA-AB"], introduced_range: []}

    assert_same_places(ctx.gall)
  end

  test "a Host's introduced range is in range and marked introduced", ctx do
    plant = plant_fixture()
    host_range_fixture(plant, [{"US-CA", "exact"}, {"RO-B", "exact", "introduced"}])
    host!(plant, ctx.gall, ctx.source)

    assert sorted(Catalog.display_range(ctx.gall.id)) ==
             %{in_range: ["RO-B", "US-CA"], inherited_range: [], introduced_range: ["RO-B"]}

    assert_same_places(ctx.gall)
  end

  test "an exclude removes its places", ctx do
    host!(ctx.california_oak, ctx.gall, ctx.source)
    host!(ctx.canadian_oak, ctx.gall, ctx.source)
    range!(ctx.gall, :exclude, "CA", ctx.source)

    assert sorted(Catalog.display_range(ctx.gall.id)) ==
             %{in_range: ["US-CA"], inherited_range: [], introduced_range: []}

    assert_same_places(ctx.gall)
  end

  test "an only restricts the range to its places", ctx do
    host!(ctx.california_oak, ctx.gall, ctx.source)
    host!(ctx.canadian_oak, ctx.gall, ctx.source)
    range!(ctx.gall, :only, "CA-AB", ctx.source)

    assert sorted(Catalog.display_range(ctx.gall.id)) ==
             %{in_range: [], inherited_range: ["CA-AB"], introduced_range: []}

    assert_same_places(ctx.gall)
  end

  test "an only on a Gall with no Host range data is its range", ctx do
    range!(ctx.gall, :only, "MX-JAL", ctx.source)

    assert sorted(Catalog.display_range(ctx.gall.id)) ==
             %{in_range: ["MX-JAL"], inherited_range: [], introduced_range: []}

    assert_same_places(ctx.gall)
  end

  test "a Gall with no Host range data is everywhere", ctx do
    assert Catalog.display_range(ctx.gall.id) == :everywhere

    host!(plant_fixture(), ctx.gall, ctx.source)
    assert Catalog.display_range(ctx.gall.id) == :everywhere
    assert_same_places(ctx.gall)
  end

  test "a genus Host shows its species' ranges, introduced places marked", ctx do
    genus = plant_fixture(rank: :genus, name: "Fixturquercus")
    alba = plant_fixture(name: "Fixturquercus alba", parent: genus)
    rubra = plant_fixture(name: "Fixturquercus rubra", parent: genus)
    host_range_fixture(alba, [{"US-CA", "exact"}, {"RO-B", "exact", "introduced"}])
    host_range_fixture(rubra, [{"CA", "country"}])
    host!(genus, ctx.gall, ctx.source)

    assert sorted(Catalog.display_range(ctx.gall.id)) ==
             %{
               in_range: ["RO-B", "US-CA"],
               inherited_range: ["CA-AB"],
               introduced_range: ["RO-B"]
             }

    assert_same_places(ctx.gall)
  end

  test "a genus Host's own rows count, as in the seeds (Gall 304)" do
    gall = Catalog.get_gall!(304)

    assert sorted(Catalog.display_range(gall.id)) ==
             %{
               in_range: ["RO-B", "US-CA"],
               inherited_range: ["MX-JAL"],
               introduced_range: ["RO-B"]
             }

    assert_same_places(gall)
  end
end
