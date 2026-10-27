defmodule Gallformers.Catalog.SiteCountsTest do
  @moduledoc """
  The site-wide reads of the home, about and sitemap pages (`803b` Task 12):
  counts of Galls and plants and the groups they fall in, a random Gall
  with an image, and the IDs and rank pages the sitemap lists.
  """
  use Gallformers.DataCase, async: true

  # The rank pages and random Gall read the converted seeds too.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Taxa

  defp relate!(type, taxon, gall) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: type, subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source_fixture("Weld", "1959"))
      )

    :ok
  end

  describe "Catalog.gall_counts/0" do
    test "every Gall; the undescribed; the families and genera of their Inducers" do
      before = Catalog.gall_counts()

      family = taxon_fixture(rank: :family, kingdom: "Animalia", name: "Fixturcountidae")
      genus = taxon_fixture(rank: :genus, parent: family, name: "Fixturcountus")
      species = taxon_fixture(parent: genus, name: "Fixturcountus primus")
      other_genus = taxon_fixture(rank: :genus, parent: family, name: "Fixturcountella")

      relate!("inducer_of", species, gall_fixture())
      relate!("inducer_of", species, gall_fixture())
      relate!("inducer_of", other_genus, gall_fixture())
      _no_inducer = gall_fixture()

      assert Catalog.gall_counts() == %{
               galls: before.galls + 4,
               undescribed: before.undescribed + 2,
               families: before.families + 1,
               genera: before.genera + 2
             }

      assert Catalog.count_galls() == before.galls + 4
    end
  end

  describe "Taxa.plant_counts/0" do
    test "plants, and the plant families and genera holding them" do
      before = Taxa.plant_counts()

      family = plant_fixture(rank: :family, name: "Fixturcountaceae")
      genus = plant_fixture(rank: :genus, parent: family, name: "Fixturcountia")
      _empty_genus = plant_fixture(rank: :genus, parent: family, name: "Fixturvacua")
      plant_fixture(parent: genus, name: "Fixturcountia alba")
      plant_fixture(parent: genus, name: "Fixturcountia rubra", rank: :species)

      assert Taxa.plant_counts() == %{
               plants: before.plants + 2,
               families: before.families + 1,
               genera: before.genera + 1
             }

      assert Taxa.count_plants() == before.plants + 2
    end
  end

  describe "Catalog.random_gall/0" do
    test "a Gall with an image, its name, undescribed flag and image credits" do
      with_image =
        Repo.all(from(r in "gall_index", where: not is_nil(r.image_id), select: r.gall_id))

      assert %{id: id, name: name, undescribed: undescribed, image_url: url} =
               Catalog.random_gall()

      assert id in with_image
      assert name == Gall.display_name(Catalog.get_gall!(id))
      assert is_boolean(undescribed)
      assert url =~ ~r{^https?://}
    end

    test "nil when no Gall has an image" do
      Repo.query!("UPDATE gall_index SET image_id = NULL")

      assert Catalog.random_gall() == nil
    end
  end

  describe "sitemap reads" do
    test "Catalog.list_gall_ids/0: every Gall" do
      gall = gall_fixture()
      ids = Catalog.list_gall_ids()

      assert gall.id in ids
      assert 300 in ids
      assert length(ids) == Catalog.count_galls()
    end

    test "Taxa.list_plant_ids/0: every plant, not higher plant taxa" do
      genus = plant_fixture(rank: :genus, name: "Fixtursitemapia")
      plant = plant_fixture(parent: genus, name: "Fixtursitemapia alba")
      ids = Taxa.list_plant_ids()

      assert plant.id in ids
      refute genus.id in ids
      assert length(ids) == Taxa.count_plants()
    end

    test "Taxa.list_rank_pages/0: the taxa at ranks with a page, each name and rank once" do
      section =
        plant_fixture(
          rank: :section,
          parent: plant_fixture(rank: :genus, name: "Fixtursectia"),
          name: "Fixtursectia sect. Fixturae"
        )

      pages = Taxa.list_rank_pages()

      assert %{rank: :family, name: "Cynipidae"} in pages
      assert %{rank: :subfamily, name: "Cynipinae"} in pages
      assert %{rank: :tribe, name: "Cynipini"} in pages
      assert %{rank: :genus, name: "Andricus"} in pages
      assert %{rank: :section, name: Taxa.accepted_name(section)} in pages
      refute Enum.any?(pages, &(&1.rank == :species))
      assert pages == Enum.uniq(pages)
    end
  end
end
