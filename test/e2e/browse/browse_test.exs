defmodule GallformersWeb.E2E.BrowseTest do
  @moduledoc """
  E2E tests for browsing Galls and hosts.
  These verify that detail pages load and navigation works.

  Test data comes from `Gallformers.Catalog` and `Gallformers.Taxa`, the
  back-end the public pages read.
  """
  use GallformersWeb.E2ECase

  alias Gallformers.Catalog
  alias Gallformers.Catalog.ReadModels.GallPage
  alias Gallformers.Taxa

  @moduletag :e2e
  @moduletag :e2e_browse

  # How many Galls to look through for one with a species Host.
  @gall_sample 200

  # The Gall page shows the display name without its generation qualifier
  # (" (agamic)"), which becomes a glossary tooltip; every other part of the
  # name comes before the first " (".
  defp base_name(name), do: name |> String.split(" (") |> hd()

  defp first_gall_page do
    [id | _] = Catalog.list_gall_ids()
    {:ok, %GallPage{} = page} = Catalog.gall_page(id)
    page
  end

  # A Gall with a species-rank Host (linked to `/host/:id`) and that Host.
  defp gall_with_species_host do
    Catalog.list_gall_ids()
    |> Enum.take(@gall_sample)
    |> Enum.find_value(fn id ->
      {:ok, page} = Catalog.gall_page(id)

      case Enum.find(page.hosts, &match?(%{link: {:host, _}}, &1)) do
        nil -> nil
        host -> {page, host}
      end
    end)
  end

  describe "gall detail page" do
    test "loads for valid gall ID", %{conn: conn} do
      gall = first_gall_page()

      conn
      |> visit("/gall/#{gall.id}")
      # Page uses h2 for the Gall's name, wrapped in em tags
      |> assert_has("h2 em", text: base_name(gall.name))
    end

    test "shows 404 for invalid gall ID", %{conn: conn} do
      conn
      |> visit("/gall/999999999")
      # Should show not found message
      |> assert_has("body", text: "not found")
    end
  end

  describe "host detail page" do
    test "loads for valid host ID", %{conn: conn} do
      [id | _] = Taxa.list_plant_ids()
      {:ok, host} = Taxa.host_page(id)

      conn
      |> visit("/host/#{id}")
      |> assert_has("h2", text: host.name)
    end

    test "shows 404 for invalid host ID", %{conn: conn} do
      conn
      |> visit("/host/999999999")
      # Should show not found message
      |> assert_has("body", text: "not found")
    end
  end

  describe "navigation between gall and host" do
    test "can navigate from gall to host", %{conn: conn} do
      pair = gall_with_species_host()
      assert pair, "Need a Gall with a species Host among the first #{@gall_sample} Galls"
      {gall, host} = pair

      conn
      |> visit("/gall/#{gall.id}")
      # Find and click link to host
      |> click_link(host.name)
      |> assert_has("h2", text: host.name)
    end
  end
end
