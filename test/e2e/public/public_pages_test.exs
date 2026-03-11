defmodule GallformersWeb.E2E.PublicPagesTest do
  @moduledoc """
  E2E tests for public-facing pages.
  These verify that core public pages load and display correctly.
  """
  use GallformersWeb.E2ECase

  @moduletag :e2e
  @moduletag :e2e_public

  describe "home page" do
    test "loads and displays welcome content", %{session: session} do
      session
      |> visit("/")
      |> assert_has(css(".phx-connected"))
      |> assert_has(css("h1", text: "Welcome"))
    end

    test "has navigation to main sections", %{session: session} do
      session
      |> visit("/")
      |> assert_has(css(".phx-connected"))
      # Use css selector since mobile and desktop nav may both have these links
      |> assert_has(css("a", text: "Identify", count: :any))
      |> assert_has(css("button", text: "Browse", count: :any))
    end
  end

  describe "about page" do
    test "loads successfully", %{session: session} do
      session
      |> visit("/about")
      |> assert_has(css("h1", text: "About Us"))
    end
  end

  describe "glossary page" do
    test "loads and displays terms", %{session: session} do
      session
      |> visit("/glossary")
      |> assert_has(css(".phx-connected"))
    end
  end

  describe "filter guide page" do
    test "loads successfully", %{session: session} do
      session
      |> visit("/filterguide")
      |> assert_has(css("h1", text: "ID Tool Filter Guide"))
    end
  end

  describe "explore page" do
    test "loads successfully", %{session: session} do
      session
      |> visit("/explore")
      |> assert_has(css(".phx-connected"))
    end
  end

  describe "articles page" do
    test "loads successfully", %{session: session} do
      session
      |> visit("/articles")
      |> assert_has(css("h1", text: "Gallformers Articles"))
    end
  end
end
