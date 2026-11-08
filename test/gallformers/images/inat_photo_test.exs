defmodule Gallformers.Images.InatPhotoTest do
  @moduledoc """
  An iNaturalist observation's photo stored as a Gall's or a taxon's image
  (`Gallformers.Images.store_inat_photo/5`, `import_inat_photo/4`): moved
  from the image manager's iNaturalist import so the change tray can apply
  an observation's photos too (matter `87a1`).
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.CatalogFixtures
  alias Gallformers.Images
  alias Gallformers.INaturalist
  alias Gallformers.INaturalist.{Observation, Photo}

  describe "store_inat_photo/5" do
    setup do
      observation = %Observation{
        id: 12_345,
        observer_login: "janedoe",
        observer_name: "Jane Doe",
        url: "https://www.inaturalist.org/observations/12345",
        photos: []
      }

      photo = %Photo{
        id: 1,
        thumbnail_url: "https://static.inaturalist.org/photos/1/medium.png",
        original_url: "https://static.inaturalist.org/photos/1/original.png",
        mapped_license: "CC-BY-NC"
      }

      %{observation: observation, photo: photo}
    end

    test "stores a downloaded photo as the owner's image", %{observation: obs, photo: photo} do
      gall = CatalogFixtures.gall_fixture()

      assert {:ok, image} =
               Images.store_inat_photo("png bytes", photo, obs, {:gall, gall.id}, "Admin")

      assert image.gall_id == gall.id
      assert image.path =~ ~r{^gall/#{gall.id}/#{gall.id}_\d+_\d+_original\.png$}
      assert image.creator == "janedoe - Jane Doe"
      assert image.license == "CC-BY-NC"
      assert image.licenselink == Gallformers.Licenses.url("CC-BY-NC")
      assert image.sourcelink == "https://www.inaturalist.org/observations/12345"
      assert image.uploader == "Admin"
    end

    test "stores a taxon's photo", %{observation: obs, photo: photo} do
      plant = CatalogFixtures.plant_fixture()

      assert {:ok, image} =
               Images.store_inat_photo("bytes", photo, obs, {:taxon, plant.id}, "Admin")

      assert image.taxon_id == plant.id
      assert [_] = Gallformers.Images.list_images_for_taxon(plant.id)
    end
  end

  describe "import_inat_photo/4" do
    test "downloads the photo and stores it as the Gall's image" do
      Req.Test.stub(INaturalist, fn conn -> Plug.Conn.send_resp(conn, 200, "jpeg bytes") end)
      gall = CatalogFixtures.gall_fixture()

      observation = %Observation{
        id: 4242,
        observer_login: "jdoe",
        observer_name: "J. Doe",
        url: "https://www.inaturalist.org/observations/4242",
        photos: []
      }

      photo = %Photo{
        id: 111,
        thumbnail_url: "https://static.inaturalist.org/photos/111/medium.jpg",
        original_url: "https://static.inaturalist.org/photos/111/original.jpg",
        mapped_license: "CC-BY-NC"
      }

      assert {:ok, image} = Images.import_inat_photo(photo, observation, {:gall, gall.id}, "Ada")
      assert image.sourcelink == "https://www.inaturalist.org/observations/4242"
      assert [_] = Images.list_images_for_gall(gall.id)
    end
  end
end
