defmodule Gallformers.ImagesTest do
  @moduledoc """
  Unit tests for the Images context.
  """
  use Gallformers.DataCase, async: true

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

  describe "requires_attribution?/1" do
    test "returns false for Public Domain / CC0" do
      refute Images.requires_attribution?("Public Domain / CC0")
    end

    test "returns false for nil" do
      refute Images.requires_attribution?(nil)
    end

    test "returns true for CC-BY licenses" do
      assert Images.requires_attribution?("CC-BY") == true
      assert Images.requires_attribution?("CC-BY-SA") == true
      assert Images.requires_attribution?("CC-BY-NC") == true
      assert Images.requires_attribution?("CC-BY-NC-SA") == true
      assert Images.requires_attribution?("CC-BY-ND") == true
      assert Images.requires_attribution?("CC-BY-NC-ND") == true
    end

    test "returns true for All Rights Reserved" do
      assert Images.requires_attribution?("All Rights Reserved") == true
    end

    test "returns false for invalid license strings" do
      refute Images.requires_attribution?("invalid")
      refute Images.requires_attribution?("cc-by")
    end
  end

  describe "image_attributed?/1" do
    test "returns true for Public Domain / CC0 without creator" do
      image = %Image{
        license: "Public Domain / CC0",
        creator: nil,
        source_id: nil,
        source: nil
      }

      assert Images.image_attributed?(image) == true
    end

    test "returns true for CC-BY with creator" do
      image = %Image{
        license: "CC-BY",
        creator: "John Doe",
        source_id: nil,
        source: nil
      }

      assert Images.image_attributed?(image) == true
    end

    test "returns false for CC-BY without creator" do
      image = %Image{
        license: "CC-BY",
        creator: nil,
        source_id: nil,
        source: nil
      }

      refute Images.image_attributed?(image)
    end

    test "returns false for CC-BY with empty creator" do
      image = %Image{
        license: "CC-BY",
        creator: "",
        source_id: nil,
        source: nil
      }

      refute Images.image_attributed?(image)
    end

    test "returns false for CC-BY with whitespace-only creator" do
      image = %Image{
        license: "CC-BY",
        creator: "   ",
        source_id: nil,
        source: nil
      }

      refute Images.image_attributed?(image)
    end

    test "returns false for no license" do
      image = %Image{
        license: nil,
        creator: "John Doe",
        source_id: nil,
        source: nil
      }

      refute Images.image_attributed?(image)
    end

    test "returns true for image with source that has license" do
      source = %Gallformers.Sources.Source{
        id: 1,
        license: "CC-BY"
      }

      image = %Image{
        license: nil,
        creator: nil,
        source_id: 1,
        source: source
      }

      assert Images.image_attributed?(image) == true
    end
  end

  describe "list_unattributed_images/1" do
    test "returns empty list and zero count with no images seeded" do
      {images, count} = Images.list_unattributed_images()
      assert images == []
      assert count == 0
    end

    test "respects pagination options" do
      {images, _count} = Images.list_unattributed_images(page: 1, per_page: 5)
      assert length(images) <= 5
    end
  end

  describe "count_unattributed_images/0" do
    test "returns zero with no images seeded" do
      assert Images.count_unattributed_images() == 0
    end
  end

  describe "finalize_upload/3,4" do
    setup do
      species = Gallformers.Repo.one!(from s in Gallformers.Species.Species, limit: 1)
      %{species: species}
    end

    test "creates image record with correct attributes", %{species: species} do
      path = "gall/#{species.id}/#{species.id}_123_456_original.jpg"

      assert {:ok, image} = Images.finalize_upload(path, species.id, "testuser")
      assert image.path == path
      assert image.species_id == species.id
      assert image.uploader == "testuser"
      assert image.lastchangedby == "testuser"
    end

    test "accepts extra metadata attrs", %{species: species} do
      path = "gall/#{species.id}/#{species.id}_123_456_original.jpg"

      attrs = %{
        creator: "janedoe - Jane Doe",
        license: "CC-BY-NC",
        licenselink: "https://creativecommons.org/licenses/by-nc/4.0/",
        sourcelink: "https://www.inaturalist.org/observations/12345"
      }

      assert {:ok, image} = Images.finalize_upload(path, species.id, "testuser", attrs)
      assert image.creator == "janedoe - Jane Doe"
      assert image.license == "CC-BY-NC"
      assert image.sourcelink == "https://www.inaturalist.org/observations/12345"
    end

    test "assigns next sort_order", %{species: species} do
      path1 = "gall/#{species.id}/#{species.id}_1_1_original.jpg"
      path2 = "gall/#{species.id}/#{species.id}_2_2_original.jpg"

      {:ok, img1} = Images.finalize_upload(path1, species.id, "testuser")
      {:ok, img2} = Images.finalize_upload(path2, species.id, "testuser")

      assert img2.sort_order > img1.sort_order
    end
  end

  describe "copy_metadata/3" do
    setup do
      # Get a real species from test seeds
      species = Gallformers.Repo.one!(from s in Gallformers.Species.Species, limit: 1)

      # Create source image with full metadata
      {:ok, source} =
        Images.create_image(%{
          species_id: species.id,
          path: "gall/#{species.id}/#{species.id}_source_original.jpg",
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
          species_id: species.id,
          path: "gall/#{species.id}/#{species.id}_target1_original.jpg",
          uploader: "test",
          lastchangedby: "test"
        })

      {:ok, target2} =
        Images.create_image(%{
          species_id: species.id,
          path: "gall/#{species.id}/#{species.id}_target2_original.jpg",
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
