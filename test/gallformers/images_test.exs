defmodule Gallformers.ImagesTest do
  @moduledoc """
  Unit tests for the Images context.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.CatalogFixtures
  alias Gallformers.Images
  alias Gallformers.Images.Image

  describe "species variant policy" do
    test "defines variant sizes in the images context" do
      assert Images.species_variant_sizes() == [
               small: 300,
               medium: 800,
               large: 1200,
               xlarge: 2000
             ]
    end

    test "includes original plus all generated species variants" do
      assert Images.species_variant_names() == [:original, :small, :medium, :large, :xlarge]
    end
  end

  describe "finalize_upload/4 for an owner" do
    setup do
      %{gall: CatalogFixtures.gall_fixture(), plant: CatalogFixtures.plant_fixture()}
    end

    test "creates a Gall's image with no species", %{gall: gall} do
      path = "gall/#{gall.id}/#{gall.id}_123_456_original.jpg"

      assert {:ok, image} = Images.finalize_upload(path, {:gall, gall.id}, "testuser")
      assert image.path == path
      assert image.gall_id == gall.id
      assert image.taxon_id == nil
      assert image.species_id == nil
      assert image.uploader == "testuser"
      assert image.lastchangedby == "testuser"
      assert [%{id: id}] = Images.list_images_for_gall(gall.id)
      assert id == image.id
    end

    test "creates a taxon's image", %{plant: plant} do
      path = "gall/#{plant.id}/#{plant.id}_123_456_original.jpg"

      assert {:ok, image} = Images.finalize_upload(path, {:taxon, plant.id}, "testuser")
      assert image.taxon_id == plant.id
      assert image.gall_id == nil
      assert [%{id: id}] = Images.list_images_for_taxon(plant.id)
      assert id == image.id
    end

    test "accepts extra metadata attrs", %{gall: gall} do
      path = "gall/#{gall.id}/#{gall.id}_123_456_original.jpg"

      attrs = %{
        creator: "janedoe - Jane Doe",
        license: "CC-BY-NC",
        licenselink: "https://creativecommons.org/licenses/by-nc/4.0/",
        sourcelink: "https://www.inaturalist.org/observations/12345"
      }

      assert {:ok, image} = Images.finalize_upload(path, {:gall, gall.id}, "testuser", attrs)
      assert image.creator == "janedoe - Jane Doe"
      assert image.license == "CC-BY-NC"
      assert image.sourcelink == "https://www.inaturalist.org/observations/12345"
    end

    test "appends to its owner's images only", %{gall: gall, plant: plant} do
      other = CatalogFixtures.gall_fixture()

      {:ok, first} = Images.finalize_upload(unique_path(gall.id), {:gall, gall.id}, "u")
      {:ok, second} = Images.finalize_upload(unique_path(gall.id), {:gall, gall.id}, "u")
      {:ok, other_first} = Images.finalize_upload(unique_path(other.id), {:gall, other.id}, "u")
      {:ok, plant_first} = Images.finalize_upload(unique_path(plant.id), {:taxon, plant.id}, "u")

      assert {first.sort_order, second.sort_order} == {0, 1}
      assert other_first.sort_order == 0
      assert plant_first.sort_order == 0
    end

    test "fails for an owner that does not exist" do
      assert {:error, changeset} =
               Images.finalize_upload(unique_path(1), {:gall, 999_999_999}, "u")

      assert %{gall_id: [_]} = errors_on(changeset)
    end
  end

  describe "an image's owner" do
    setup do
      %{gall: CatalogFixtures.gall_fixture(), plant: CatalogFixtures.plant_fixture()}
    end

    test "create_image/1 takes the owner from gall_id or taxon_id", %{gall: gall, plant: plant} do
      assert {:ok, %{gall_id: gall_id}} =
               Images.create_image(%{gall_id: gall.id, path: unique_path(gall.id)})

      assert {:ok, %{taxon_id: taxon_id}} =
               Images.create_image(%{taxon_id: plant.id, path: unique_path(plant.id)})

      assert {gall_id, taxon_id} == {gall.id, plant.id}
    end

    test "create_image/1 refuses an image with no owner" do
      assert {:error, changeset} = Images.create_image(%{path: unique_path(1)})
      assert %{gall_id: ["must belong to exactly one Gall or taxon"]} = errors_on(changeset)
    end

    test "create_image/1 refuses an image with two owners", %{gall: gall, plant: plant} do
      assert {:error, changeset} =
               Images.create_image(%{
                 gall_id: gall.id,
                 taxon_id: plant.id,
                 path: unique_path(gall.id)
               })

      assert %{gall_id: ["must belong to exactly one Gall or taxon"]} = errors_on(changeset)
    end

    test "Image.changeset/2 requires exactly one owner but no species", %{gall: gall} do
      assert %{valid?: true} = Image.changeset(%Image{}, %{gall_id: gall.id, path: "p"})
      refute Image.changeset(%Image{}, %{path: "p"}).valid?
      refute Image.changeset(%Image{}, %{gall_id: gall.id, taxon_id: gall.id, path: "p"}).valid?
    end

    test "list_images/1 lists by owner", %{gall: gall, plant: plant} do
      {:ok, gall_image} = Images.finalize_upload(unique_path(gall.id), {:gall, gall.id}, "u")
      {:ok, plant_image} = Images.finalize_upload(unique_path(plant.id), {:taxon, plant.id}, "u")

      assert Enum.map(Images.list_images({:gall, gall.id}), & &1.id) == [gall_image.id]
      assert Enum.map(Images.list_images({:taxon, plant.id}), & &1.id) == [plant_image.id]
    end

    test "reorder_images/2 orders the owner's images and leaves others alone", %{gall: gall} do
      other = CatalogFixtures.gall_fixture()
      {:ok, a} = Images.finalize_upload(unique_path(gall.id), {:gall, gall.id}, "u")
      {:ok, b} = Images.finalize_upload(unique_path(gall.id), {:gall, gall.id}, "u")
      {:ok, foreign} = Images.finalize_upload(unique_path(other.id), {:gall, other.id}, "u")

      assert :ok = Images.reorder_images({:gall, gall.id}, [b.id, foreign.id, a.id])

      assert Enum.map(Images.list_images({:gall, gall.id}), &{&1.id, &1.sort_order}) ==
               [{b.id, 0}, {a.id, 2}]

      assert Images.get_image!(foreign.id).sort_order == 0
    end
  end

  defp unique_path(id), do: "gall/#{id}/#{id}_#{System.unique_integer([:positive])}_original.jpg"

  describe "copy_metadata/3" do
    setup do
      gall = CatalogFixtures.gall_fixture()

      # Create source image with full metadata
      {:ok, source} =
        Images.create_image(%{
          gall_id: gall.id,
          path: "gall/#{gall.id}/#{gall.id}_source_original.jpg",
          creator: "Source Creator",
          license: "CC-BY",
          licenselink: "https://creativecommons.org/licenses/by/4.0/",
          sourcelink: "https://example.com/source",
          attribution: "Source attribution notes",
          caption: "Source caption",
          uploader: "test",
          lastchangedby: "test"
        })

      # Create target images with no metadata
      {:ok, target1} =
        Images.create_image(%{
          gall_id: gall.id,
          path: "gall/#{gall.id}/#{gall.id}_target1_original.jpg",
          uploader: "test",
          lastchangedby: "test"
        })

      {:ok, target2} =
        Images.create_image(%{
          gall_id: gall.id,
          path: "gall/#{gall.id}/#{gall.id}_target2_original.jpg",
          uploader: "test",
          lastchangedby: "test"
        })

      %{source: source, target1: target1, target2: target2}
    end

    test "copies metadata from source to targets", %{
      source: source,
      target1: target1,
      target2: target2
    } do
      assert {:ok, 2} = Images.copy_metadata(source.id, [target1.id, target2.id], "admin")

      # Reload targets
      updated1 = Images.get_image!(target1.id)
      updated2 = Images.get_image!(target2.id)

      # Check metadata was copied
      assert updated1.creator == "Source Creator"
      assert updated1.license == "CC-BY"
      assert updated1.licenselink == "https://creativecommons.org/licenses/by/4.0/"
      assert updated1.sourcelink == "https://example.com/source"
      assert updated1.attribution == "Source attribution notes"
      assert updated1.caption == "Source caption"
      assert updated1.lastchangedby == "admin"

      assert updated2.creator == "Source Creator"
      assert updated2.license == "CC-BY"
    end

    test "returns error when source not found", %{target1: target1} do
      assert {:error, :source_not_found} = Images.copy_metadata(999_999, [target1.id], "admin")
    end

    test "returns ok with 0 count when no targets", %{source: source} do
      assert {:ok, 0} = Images.copy_metadata(source.id, [], "admin")
    end

    test "copies source_id when source has one", %{source: source, target1: target1} do
      # First, we need a source record to link
      {:ok, pub_source} =
        Gallformers.Sources.create_source(%{
          title: "Test Publication",
          author: "Test Author",
          pubyear: "2024",
          citation: "Test citation",
          link: "https://example.com",
          license: "CC-BY",
          licenselink: "https://creativecommons.org/licenses/by/4.0/"
        })

      # Update source image to have source_id
      {:ok, source} = Images.update_image(source, %{source_id: pub_source.id})

      assert {:ok, 1} = Images.copy_metadata(source.id, [target1.id], "admin")

      updated = Images.get_image!(target1.id)
      assert updated.source_id == pub_source.id
    end
  end

  # Seeds converted by the catalog migration: image 1 is Gall 300's, image 2
  # plant taxon 10's (`image.gall_id` / `image.taxon_id`).
  describe "images by their typed reference" do
    defp image!(attrs) do
      defaults = %{path: "gall/x/#{System.unique_integer([:positive])}_original.jpg"}
      {1, [%{id: id}]} = Repo.insert_all("image", [Map.merge(defaults, attrs)], returning: [:id])
      id
    end

    test "list_images_for_gall/1 reads image.gall_id, by sort order" do
      later = image!(%{species_id: 300, gall_id: 300, sort_order: 5})

      assert Enum.map(Images.list_images_for_gall(300), & &1.id) == [1, later]
      assert Images.list_images_for_gall(301) == []
    end

    test "list_images_for_gall/1 ignores an image of the species ID with no Gall reference" do
      image!(%{species_id: 301})

      assert Images.list_images_for_gall(301) == []
    end

    test "default_image_ids_for_galls/1 gives each Gall's first image by sort order" do
      earlier = image!(%{species_id: 301, gall_id: 301, sort_order: 2})
      _later = image!(%{species_id: 301, gall_id: 301, sort_order: 3})
      _tied_later_id = image!(%{species_id: 301, gall_id: 301, sort_order: 2})

      assert Images.default_image_ids_for_galls([300, 301, 302]) == %{300 => 1, 301 => earlier}
      assert Images.default_image_ids_for_galls([]) == %{}
    end

    test "count_images/0 counts the images of Galls and taxa only" do
      before = Images.count_images()

      image!(%{species_id: 300, gall_id: 300})
      image!(%{species_id: 10, taxon_id: 10})
      # An image left on an excluded non-gall: no Gall, no taxon.
      image!(%{species_id: 301})

      assert Images.count_images() == before + 2
    end

    test "list_images_for_taxon/1 reads image.taxon_id" do
      assert [%{id: 2, gall_id: nil, taxon_id: 10}] = Images.list_images_for_taxon(10)
      assert Images.list_images_for_taxon(1) == []
    end

    test "list_images_for_source/1 orders by Gall display name and taxon name" do
      # Its species row (301) sorts after 300's; its Gall's shown name first.
      first = Gallformers.CatalogFixtures.gall_fixture(name: "Zzz", name_override: "Aaa gall")

      taxon = image!(%{species_id: 10, taxon_id: 10, source_id: 59})
      agamic = image!(%{species_id: 300, gall_id: 300, source_id: 59})
      overridden = image!(%{species_id: 301, gall_id: first.id, source_id: 59})

      assert Enum.map(Images.list_images_for_source(59), & &1.id) == [overridden, agamic, taxon]
    end
  end
end
