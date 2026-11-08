defmodule GallformersWeb.Admin.InatImportComponentTest do
  @moduledoc """
  Tests for the iNaturalist import component of the image component
  (`GallformersWeb.Admin.ImagesComponent`), hosted by a minimal LiveView.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gallformers.CatalogFixtures
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
end
