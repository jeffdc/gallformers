defmodule GallformersWeb.HostLiveTest do
  @moduledoc """
  LiveView tests for the host plant detail page.
  """
  use GallformersWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "Source deep-linking via ?source= param" do
    setup do
      # Create a source linked to host 1 (Quercus alba) with a description
      source =
        Gallformers.Repo.insert!(%Gallformers.Sources.Source{
          title: "Test Host Source for Deep Link",
          author: "Test Author",
          pubyear: "2024",
          link: "https://example.com",
          citation: "Test citation",
          license: "Public Domain"
        })

      Gallformers.Repo.insert!(%Gallformers.Species.SpeciesSource{
        species_id: 1,
        source_id: source.id,
        description: "Host deep link test description",
        useasdefault: false
      })

      %{source: source}
    end

    test "opens source modal when ?source= param matches", %{conn: conn, source: source} do
      {:ok, view, _html} = live(conn, "/host/1?source=#{source.id}")

      # The modal should be open with the source's description
      assert has_element?(view, "#source-detail-modal")
      assert render(view) =~ "Host deep link test description"
    end

    test "ignores invalid source param", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/host/1?source=invalid")

      refute has_element?(view, "#source-detail-modal")
    end

    test "ignores non-existent source param", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/host/1?source=999999")

      refute has_element?(view, "#source-detail-modal")
    end

    test "page loads normally without source param", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/host/1")

      refute has_element?(view, "#source-detail-modal")
    end
  end
end
