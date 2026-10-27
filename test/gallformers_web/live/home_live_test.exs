defmodule GallformersWeb.HomeLiveTest do
  use GallformersWeb.ConnCase
  import Phoenix.LiveViewTest
  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Repo
  alias Gallformers.Taxa

  describe "Home page" do
    test "renders welcome message", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Welcome to Gallformers"
      assert html =~ "Plant galls are abnormal growths"
      assert html =~ "Things You Can Do"
      assert html =~ "Help Us Out"
    end

    test "displays random gall section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # Should show the Random Gall card (may show "Loading..." before connected)
      assert html =~ "Random Gall"
    end

    test "contains navigation links", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(href="/id")
      assert html =~ ~s(href="/articles")
      assert html =~ ~s(href="/galls")
    end

    test "contains external links", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "patreon.com/gallformers"
      assert html =~ "github.com/jeffdc/gallformers"
    end
  end

  describe "read from the new back-end" do
    test "the random Gall is one with an image in the ID tool's lookup table", %{conn: conn} do
      gall = gall_fixture(name: "Fixturhomeia randomi")
      Repo.query!("UPDATE gall_index SET image_id = NULL")

      Repo.insert_all("image", [
        %{
          species_id: 300,
          path: "gall/x/fixture_original.jpg",
          gall_id: gall.id,
          creator: "Fixture Photographer"
        }
      ])

      :ok = Catalog.refresh_gall_index([gall.id])

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "a[href='/gall/#{gall.id}']", "Fixturhomeia randomi")
      assert render(view) =~ "Fixture Photographer"
    end

    test "the counts are the new back-end's Galls and plants", %{conn: conn} do
      gall_fixture()
      plant_fixture()

      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      assert html =~ ~r{>\s*#{Catalog.count_galls()}\s*</div>\s*<div[^>]*>Galls}
      assert html =~ ~r{>\s*#{Taxa.count_plants()}\s*</div>\s*<div[^>]*>Host Plants}
    end

    test "the host picker searches plants and opens the ID tool on the chosen one", %{conn: conn} do
      plant = plant_fixture(name: "Fixturhomus pickeri")
      {:ok, view, _html} = live(conn, ~p"/")

      assert render_click(view, "search_host", %{"value" => "Fixturhomus"}) =~
               "Fixturhomus pickeri"

      assert {:error, {:live_redirect, %{to: to}}} =
               render_click(view, "select_host", %{"id" => to_string(plant.id)})

      assert to == "/id?h=Fixturhomus+pickeri"
    end
  end
end
