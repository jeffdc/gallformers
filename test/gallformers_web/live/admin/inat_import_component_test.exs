defmodule GallformersWeb.Admin.InatImportComponentTest do
  @moduledoc """
  Tests for the iNaturalist import component of the image component
  (`GallformersWeb.Admin.ImagesComponent`), hosted by a minimal LiveView.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gallformers.CatalogFixtures
  alias Gallformers.INaturalist.{Observation, Photo}
  alias GallformersWeb.Admin.InatImportComponent

  defmodule HostLive do
    use Phoenix.LiveView

    def mount(_params, %{"owner" => owner}, socket),
      do: {:ok, Phoenix.Component.assign(socket, :owner, owner)}

    def render(assigns) do
      ~H"""
      <.live_component module={InatImportComponent} id="inat" owner={@owner} uploader="Admin" />
      """
    end
  end

  describe "inat import component" do
    setup %{conn: conn} do
      gall = CatalogFixtures.gall_fixture()
      {:ok, view, _html} = live_isolated(conn, HostLive, session: %{"owner" => {:gall, gall.id}})
      %{view: view}
    end

    test "renders the observation URL input and fetch button", %{view: view} do
      assert render(view) =~ "Import from iNaturalist"
      assert has_element?(view, "[data-role=inat-url-input]")
      assert has_element?(view, "[data-role=inat-fetch-button]")
    end

    test "fetch button is disabled when input is empty", %{view: view} do
      assert has_element?(view, "[data-role=inat-fetch-button][disabled]")
    end

    test "shows error for invalid input", %{view: view} do
      view
      |> element("form[phx-submit=inat_fetch]")
      |> render_submit(%{url: "not-a-valid-url"})

      assert render(view) =~ "valid iNaturalist observation URL"
    end
  end

  describe "store_photo/5" do
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
               InatImportComponent.store_photo("png bytes", photo, obs, {:gall, gall.id}, "Admin")

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
               InatImportComponent.store_photo("bytes", photo, obs, {:taxon, plant.id}, "Admin")

      assert image.taxon_id == plant.id
      assert [_] = Gallformers.Images.list_images_for_taxon(plant.id)
    end
  end
end
