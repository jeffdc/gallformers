defmodule GallformersWeb.PlacesTabTest do
  @moduledoc """
  Legacy places tab tests — superseded by PlacesBrowseLiveTest.

  The old /explore?tab=places route has been replaced by /places.
  See places_browse_live_test.exs for current tests.
  """
  use GallformersWeb.ConnCase, async: true

  describe "legacy /explore?tab=places redirect" do
    test "redirects /explore?tab=places to /places with 301", %{conn: conn} do
      conn = get(conn, "/explore?tab=places")
      assert redirected_to(conn, 301) == "/places"
    end
  end
end
