defmodule GallformersWeb.ProdDataE2E.SmokeTest do
  @moduledoc """
  Smoke tests that verify the app loads correctly with real production data.
  """
  use GallformersWeb.ProdDataE2ECase

  @moduletag :prod_data

  describe "home page" do
    test "loads with real data", %{session: session} do
      session
      |> visit("/")
      |> assert_has(css("h1", text: "Welcome to Gallformers"))
    end
  end

  describe "admin access" do
    test "admin dashboard loads with auth bypass", %{session: session} do
      session
      |> visit("/admin")
      |> assert_has(css(".phx-connected"))
    end
  end
end
