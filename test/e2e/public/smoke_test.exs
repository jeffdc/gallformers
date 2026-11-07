defmodule GallformersWeb.E2E.SmokeTest do
  @moduledoc """
  Smoke tests that verify the app loads correctly with real production data.
  """
  use GallformersWeb.E2ECase

  @moduletag :e2e
  @moduletag :e2e_public

  describe "home page" do
    test "loads with real data", %{conn: conn} do
      conn
      |> visit("/")
      |> assert_has("h1", text: "Found something odd growing on a plant?")
    end
  end

  describe "admin access" do
    test "admin dashboard loads with auth bypass", %{conn: conn} do
      conn
      |> visit("/admin")
      |> assert_has("body")
    end
  end
end
