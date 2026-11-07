defmodule GallformersWeb.E2E.PublicPagesTest do
  @moduledoc """
  E2E tests for public-facing pages.
  These verify that core public pages load and display correctly.
  """
  use GallformersWeb.E2ECase

  @moduletag :e2e
  @moduletag :e2e_public

  describe "home page" do
    test "loads and displays welcome content", %{conn: conn} do
      conn
      |> visit("/")
      |> assert_has("h1", text: "Found something odd growing on a plant?")
    end

    test "has navigation to main sections", %{conn: conn} do
      conn
      |> visit("/")
      # Use css selector since mobile and desktop nav may both have these links
      |> assert_has("a", text: "Identify")
      |> assert_has("button", text: "Browse")
    end
  end

  describe "about page" do
    test "loads successfully", %{conn: conn} do
      conn
      |> visit("/about")
      |> assert_has("h1", text: "About Us")
    end
  end

  describe "glossary page" do
    test "loads and displays terms", %{conn: conn} do
      conn
      |> visit("/glossary")
    end
  end

  describe "filter guide page" do
    test "loads successfully", %{conn: conn} do
      conn
      |> visit("/filterguide")
      |> assert_has("h1", text: "ID Tool Filter Guide")
    end
  end

  describe "explore page" do
    test "loads successfully", %{conn: conn} do
      conn
      |> visit("/explore")
    end
  end

  describe "articles page" do
    test "loads successfully", %{conn: conn} do
      conn
      |> visit("/articles")
      |> assert_has("h1", text: "Articles")
    end
  end
end
