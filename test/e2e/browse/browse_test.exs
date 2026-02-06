defmodule GallformersWeb.E2E.BrowseTest do
  @moduledoc """
  E2E tests for browsing species, hosts, and galls.
  These verify that detail pages load and navigation works.
  """
  use GallformersWeb.E2ECase

  alias Gallformers.Plants

  @moduletag :e2e
  @moduletag :e2e_browse

  describe "gall detail page" do
    test "loads for valid gall ID", %{session: session} do
      # Get a valid gall ID from the database
      galls = Gallformers.Galls.list_galls()

      if length(galls) > 0 do
        gall = hd(galls)

        session
        |> visit("/gall/#{gall.id}")
        |> assert_has(css(".phx-connected"))
        # Page uses h2 for the species name, wrapped in em tags
        |> assert_has(css("h2 em", text: gall.name))
      end
    end

    test "shows 404 for invalid gall ID", %{session: session} do
      session
      |> visit("/gall/999999999")
      |> assert_has(css(".phx-connected"))
      # Should show not found message
      |> assert_has(Query.text("not found"))
    end
  end

  describe "host detail page" do
    test "loads for valid host ID", %{session: session} do
      # Get a valid host ID from the database
      hosts = Plants.list_hosts()

      if length(hosts) > 0 do
        host = hd(hosts)

        session
        |> visit("/host/#{host.id}")
        |> assert_has(css(".phx-connected"))
        # Page uses h2 for the species name, wrapped in em tags
        |> assert_has(css("h2 em", text: host.name))
      end
    end

    test "shows 404 for invalid host ID", %{session: session} do
      session
      |> visit("/host/999999999")
      |> assert_has(css(".phx-connected"))
      # Should show not found message
      |> assert_has(Query.text("not found"))
    end
  end

  describe "navigation between gall and host" do
    test "can navigate from gall to host", %{session: session} do
      # Find a gall that has associated hosts
      galls = Gallformers.Galls.list_galls()

      gall_with_host =
        Enum.find(galls, fn g ->
          length(Gallformers.GallHosts.get_hosts_for_gall(g.id)) > 0
        end)

      if gall_with_host do
        hosts = Gallformers.GallHosts.get_hosts_for_gall(gall_with_host.id)
        host = hd(hosts)
        # Note: get_hosts_for_gall returns maps with :host_name key, not :name
        host_name = host.host_name

        session
        |> visit("/gall/#{gall_with_host.id}")
        |> assert_has(css(".phx-connected"))
        # Find and click link to host
        |> click(link(host_name))
        |> assert_has(css(".phx-connected"))
        |> assert_has(css("h2 em", text: host_name))
      end
    end
  end
end
