defmodule Gallformers.Catalog.GallIndexTest do
  @moduledoc """
  The ID tool's stored per-Gall lookup table (`803b` Task 8,
  `Gallformers.Catalog.ReadModels.GallIndex`): one row per Gall, computed
  from the read models (`GallSummary`, `PotentialRange`), refreshed by an
  Oban job when the Gall's current Facts or its taxa change.

  In tests Oban runs jobs inline (`config/test.exs`): an enqueued refresh
  runs at once, inside the Facts or taxonomy transaction that enqueued it,
  reading that transaction's own writes — what it will commit, or roll back
  with. Outside tests the job row is inserted in the transaction and runs
  after it commits.

  Not async: loads the vocabularies (see `Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false
  use Oban.Testing, repo: Gallformers.Repo

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.ReadModels.GallIndex
  alias Gallformers.Catalog.ReadModels.GallIndexWorker
  alias Gallformers.Taxa

  setup do
    load_vocab!()
    %{source: source_fixture("Weld", "1959")}
  end

  defp row(gall), do: Repo.get(GallIndex, gall.id)

  defp host!(plant, gall, attribution) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
        attribution
      )

    :ok
  end

  defp inducer!(taxon, gall, source) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source)
      )

    :ok
  end

  defp trait!(gall, trait, value, attribution) do
    {:ok, _} =
      Catalog.assert_trait(
        test_actor(),
        %{gall_id: gall.id, trait: trait, value: value},
        attribution
      )

    :ok
  end

  defp trait_value_id(trait, value), do: Catalog.get_trait_value(trait, value).id

  defp image!(gall, sort_order) do
    {1, [%{id: id}]} =
      Repo.insert_all(
        "image",
        [
          %{
            species_id: 300,
            gall_id: gall.id,
            path: "gall/#{gall.id}/#{sort_order}_original.jpg",
            sort_order: sort_order
          }
        ],
        returning: [:id]
      )

    id
  end

  # An Inducer species in a genus in a family; a plant species in a genus.
  defp tree do
    family = taxon_fixture(rank: :family, name: "Fixturidae", kingdom: "Animalia")
    genus = taxon_fixture(rank: :genus, name: "Fixtura", parent: family)
    wasp = taxon_fixture(rank: :species, name: "Fixtura foo", parent: genus)
    plant_family = plant_fixture(rank: :family, name: "Fixturaceae")
    plant_genus = plant_fixture(rank: :genus, name: "Fixturquercus", parent: plant_family)
    oak = plant_fixture(name: "Fixturquercus alba", parent: plant_genus)
    host_range_fixture(oak, [{"US-CA", "exact"}, {"CA", "country"}])

    %{
      family: family,
      genus: genus,
      wasp: wasp,
      plant_family: plant_family,
      plant_genus: plant_genus,
      oak: oak
    }
  end

  describe "a Gall's row" do
    test "holds its Inducer, Hosts, Traits, image and potential range", %{source: source} do
      t = tree()
      gall = gall_fixture(name: "Fixtura foo gall", name_override: "Fixtura foo (agamic)")
      inducer!(t.wasp, gall, source)
      host!(t.oak, gall, confirm(source))
      trait!(gall, "color", "red", confirm(source))
      trait!(gall, "plant_part", "upper leaf", confirm(source))
      trait!(gall, "detachable", "detachable", confirm(source))
      _second = image!(gall, 2)
      first = image!(gall, 1)

      :ok = Catalog.refresh_gall_index([gall.id])
      row = row(gall)

      assert row.name == "Fixtura foo (agamic)"
      assert row.inducer_taxon_id == t.wasp.id
      assert row.inducer_ancestor_ids == Enum.sort([t.family.id, t.genus.id, t.wasp.id])
      assert row.host_taxon_ids == [t.oak.id]
      assert row.host_ancestor_ids == Enum.sort([t.plant_family.id, t.plant_genus.id, t.oak.id])

      assert row.trait_value_ids ==
               Enum.sort([
                 trait_value_id("color", "red"),
                 trait_value_id("plant_part", "upper leaf"),
                 trait_value_id("detachable", "detachable")
               ])

      assert row.detachable == "detachable"
      refute row.undescribed
      assert row.image_id == first
      refute row.everywhere

      assert row.place_ids ==
               gall.id |> Catalog.potential_range() |> Enum.map(& &1.place_id) |> Enum.sort()

      assert place_id("US-CA") in row.place_ids
      assert place_id("CA-AB") in row.place_ids
    end

    test "a Gall without Host range data is everywhere, with no places", %{source: source} do
      gall = gall_fixture()
      host!(plant_fixture(), gall, confirm(source))

      :ok = Catalog.refresh_gall_index([gall.id])

      assert %GallIndex{everywhere: true, place_ids: [], image_id: nil} = row(gall)
    end

    test "a genus Host's places are its species' ranges", %{source: source} do
      t = tree()
      gall = gall_fixture()
      host!(t.plant_genus, gall, confirm(source))

      :ok = Catalog.refresh_gall_index([gall.id])
      row = row(gall)

      refute row.everywhere
      assert row.host_taxon_ids == [t.plant_genus.id]

      assert row.place_ids ==
               gall.id |> Catalog.potential_range() |> Enum.map(& &1.place_id) |> Enum.sort()

      assert place_id("US-CA") in row.place_ids
      assert place_id("CA-AB") in row.place_ids
    end

    test "a Gall with no Inducer, or one above species, is undescribed", %{source: source} do
      none = gall_fixture()
      at_genus = gall_fixture()
      inducer!(taxon_fixture(rank: :genus, name: "Fixturgenus"), at_genus, source)

      :ok = Catalog.refresh_gall_index([none.id, at_genus.id])

      assert %GallIndex{undescribed: true, inducer_taxon_id: nil, inducer_ancestor_ids: []} =
               row(none)

      assert %GallIndex{undescribed: true} = row(at_genus)
    end

    test "rebuild_gall_index/0 gives every Gall a row" do
      no_facts = gall_fixture()
      refute row(no_facts)

      :ok = Catalog.rebuild_gall_index()

      assert %GallIndex{everywhere: true, undescribed: true} = row(no_facts)

      assert Repo.aggregate(GallIndex, :count) ==
               Repo.aggregate(Gallformers.Catalog.Gall, :count)
    end
  end

  describe "refreshed on change" do
    test "asserting a Host enqueues a refresh of its Gall", %{source: source} do
      t = tree()
      gall = gall_fixture()

      Oban.Testing.with_testing_mode(:manual, fn ->
        host!(t.oak, gall, confirm(source))
        assert_enqueued(worker: GallIndexWorker, args: %{gall_id: gall.id}, queue: :catalog)
      end)
    end

    test "Facts the table does not read enqueue nothing", %{source: source} do
      gall = gall_fixture()

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _} =
          Catalog.assert_alias(
            test_actor(),
            %{gall_id: gall.id, name: "oak bead"},
            confirm(source)
          )

        {:ok, _} =
          Catalog.assert_occurrence(
            test_actor(),
            %{gall_id: gall.id, place_id: place_id("RO-B")},
            confirm(source)
          )

        refute_enqueued(worker: GallIndexWorker)
      end)
    end

    test "the refresh job rebuilds the Gall's row", %{source: source} do
      t = tree()
      gall = gall_fixture()

      Oban.Testing.with_testing_mode(:manual, fn -> host!(t.oak, gall, confirm(source)) end)
      refute row(gall)

      assert :ok = perform_job(GallIndexWorker, %{gall_id: gall.id})
      assert row(gall).host_taxon_ids == [t.oak.id]
    end

    test "a change to a Gall's images refreshes its default image" do
      gall = gall_fixture()
      first = image!(gall, 0)
      refute row(gall)

      assert :ok = Catalog.gall_images_changed(gall.id)
      assert row(gall).image_id == first

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = Catalog.gall_images_changed(gall.id)
        assert_enqueued(worker: GallIndexWorker, args: %{gall_id: gall.id}, queue: :catalog)
      end)
    end

    test "a Host made current, then denied, comes and goes", %{source: source} do
      t = tree()
      gall = gall_fixture()

      host!(t.oak, gall, confirm(source))
      assert row(gall).host_taxon_ids == [t.oak.id]
      assert row(gall).everywhere == false

      host!(t.oak, gall, deny(source_fixture("Revision", "1990")))
      assert %GallIndex{host_taxon_ids: [], everywhere: true} = row(gall)
    end

    test "a Trait value superseded in its slot is replaced", %{source: source} do
      gall = gall_fixture()
      trait!(gall, "detachable", "integral", confirm(source))
      assert row(gall).detachable == "integral"

      trait!(gall, "detachable", "detachable", confirm(source_fixture("Revision", "1990")))

      assert row(gall).detachable == "detachable"
      assert row(gall).trait_value_ids == [trait_value_id("detachable", "detachable")]
    end

    test "a range adjustment narrows the places", %{source: source} do
      t = tree()
      gall = gall_fixture()
      host!(t.oak, gall, confirm(source))

      {:ok, _} =
        Catalog.assert_range(
          test_actor(),
          %{gall_id: gall.id, adjustment: :exclude, place_id: place_id("CA")},
          confirm(source)
        )

      assert row(gall).place_ids == [place_id("US-CA")]
    end

    test "moving the Inducer's genus updates the Inducer's ancestors", %{source: source} do
      t = tree()
      gall = gall_fixture()
      inducer!(t.wasp, gall, source)
      other = taxon_fixture(rank: :family, name: "Fixturinae", kingdom: "Animalia")

      {:ok, _} = Taxa.place(test_actor(), t.genus, other)

      assert row(gall).inducer_ancestor_ids == Enum.sort([other.id, t.genus.id, t.wasp.id])
    end

    test "moving a Host's genus updates the Hosts' ancestors", %{source: source} do
      t = tree()
      gall = gall_fixture()
      host!(t.oak, gall, confirm(source))
      other = plant_fixture(rank: :family, name: "Fixturbetulaceae")

      {:ok, _} = Taxa.place(test_actor(), t.plant_genus, other)

      assert row(gall).host_ancestor_ids == Enum.sort([other.id, t.plant_genus.id, t.oak.id])
    end

    test "moving a plant into or out of a genus Host refreshes that Gall's places", %{
      source: source
    } do
      t = tree()
      gall = gall_fixture()
      host!(t.plant_genus, gall, confirm(source))
      other_genus = plant_fixture(rank: :genus, name: "Fixturbetula", parent: t.plant_family)
      birch = plant_fixture(name: "Fixturbetula fixtura", parent: other_genus)
      host_range_fixture(birch, [{"MX-JAL", "exact"}])
      :ok = Catalog.refresh_gall_index([gall.id])
      refute place_id("MX-JAL") in row(gall).place_ids

      {:ok, _} = Taxa.place(test_actor(), birch, t.plant_genus)
      assert place_id("MX-JAL") in row(gall).place_ids

      {:ok, _} = Taxa.place(test_actor(), t.oak, other_genus)
      assert row(gall).place_ids == [place_id("MX-JAL")]
    end

    test "renaming a Gall's Inducer enqueues a refresh of the Gall", %{source: source} do
      t = tree()
      gall = gall_fixture()
      inducer!(t.wasp, gall, source)

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _} = Taxa.rename(test_actor(), t.genus, "Fixturella")
        assert_enqueued(worker: GallIndexWorker, args: %{gall_id: gall.id})
      end)
    end

    test "a write rolled back leaves the row as it was", %{source: source} do
      t = tree()
      gall = gall_fixture()
      :ok = Catalog.refresh_gall_index([gall.id])

      {:error, :undone} =
        Repo.transaction(fn ->
          host!(t.oak, gall, confirm(source))
          assert row(gall).host_taxon_ids == [t.oak.id]
          Repo.rollback(:undone)
        end)

      assert row(gall).host_taxon_ids == []
    end

    test "without Oban running, the refresh runs at once", %{source: source} do
      t = tree()
      gall = gall_fixture()

      Gallformers.Catalog.without_gall_index_refresh(fn ->
        host!(t.oak, gall, confirm(source))
      end)

      refute row(gall)

      :ok = GallIndex.enqueue_refresh([gall.id], __MODULE__.NoOban)

      assert row(gall).host_taxon_ids == [t.oak.id]
    end

    test "inside without_gall_index_refresh/1 nothing is refreshed or enqueued", %{source: source} do
      t = tree()
      gall = gall_fixture()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :done =
                 Catalog.without_gall_index_refresh(fn ->
                   host!(t.oak, gall, confirm(source))
                   :done
                 end)

        refute_enqueued(worker: GallIndexWorker)
      end)

      refute row(gall)

      # Refreshes resume afterwards.
      host!(plant_fixture(), gall, confirm(source))
      assert length(row(gall).host_taxon_ids) == 2
    end
  end
end
