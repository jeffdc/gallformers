defmodule GallformersWeb.HomeLiveTest do
  use GallformersWeb.ConnCase
  import Phoenix.LiveViewTest
  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Repo
  alias Gallformers.Taxa

  describe "Home page" do
    test "welcomes, says what galls are, then opens on identifying one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "h1", "Welcome to Gallformers")
      assert has_element?(view, "p", "Plant galls are abnormal growths of plant tissues")
      assert has_element?(view, ~s(p a[href="/articles/idguide"]), "Learn more")
      assert has_element?(view, "h2", "Identify a plant gall")
      assert has_element?(view, "label", "What plant is it on?")
    end

    test "links to search and browse, and to ways to help", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s(a[href="/globalsearch"]), "search by name")
      assert has_element?(view, ~s(a[href="/galls"]), "browse the galls")
      assert has_element?(view, ~s(a[href="https://www.patreon.com/gallformers"]))
      assert has_element?(view, ~s(a[href="https://github.com/jeffdc/gallformers"]))
    end

    test "Host genera to start from, each opening the ID tool on the genus", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(
               view,
               ~s(#home-host-genera a[href="/id?g=Notholithocarpus"]),
               "Notholithocarpus"
             )
    end

    test "the Gallformer groups, with their Gall counts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#home-inducer-groups [data-part=name]", "Gall wasps")
    end

    test "the Sources changed most recently, each linking to its page", %{conn: conn} do
      [source | _] = Gallformers.Sources.list_recently_changed(1)
      {:ok, view, _html} = live(conn, ~p"/")

      assert view |> element("#changed-sources") |> render() =~ "/source/#{source.id}"
      assert has_element?(view, "#changed-sources", source.title)
    end
  end

  defp format(n), do: GallformersWeb.Helpers.format_number(n)

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

      assert has_element?(view, "#random-gall a[href='/gall/#{gall.id}']", "Fixturhomeia randomi")
      assert has_element?(view, "#random-gall", "Fixture Photographer")
    end

    test "Show me another draws a random Gall again", %{conn: conn} do
      first = gall_fixture(name: "Fixturhomeia primi")
      second = gall_fixture(name: "Fixturhomeia secundi")
      Repo.query!("UPDATE gall_index SET image_id = NULL")

      Repo.insert_all("image", [
        %{species_id: 300, path: "gall/x/first_original.jpg", gall_id: first.id}
      ])

      :ok = Catalog.refresh_gall_index([first.id])
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#random-gall", "Fixturhomeia primi")

      # Only the second Gall has an image now, so the next draw is it.
      Repo.query!("DELETE FROM image WHERE gall_id = $1", [first.id])

      Repo.insert_all("image", [
        %{species_id: 300, path: "gall/x/second_original.jpg", gall_id: second.id}
      ])

      :ok = Catalog.refresh_gall_index([first.id, second.id])

      view |> element("#random-gall button", "Show me another") |> render_click()
      assert has_element?(view, "#random-gall", "Fixturhomeia secundi")
    end

    test "the counts are the new back-end's Galls and plants", %{conn: conn} do
      gall_fixture()
      plant_fixture()

      {:ok, view, _html} = live(conn, ~p"/")
      html = render(view)

      stat = fn label ->
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("a:has([data-part=label])")
        |> Enum.find(fn stat ->
          stat |> LazyHTML.query("[data-part=label]") |> LazyHTML.text() |> String.trim() == label
        end)
        |> LazyHTML.query("[data-part=value]")
        |> LazyHTML.text()
        |> String.trim()
      end

      assert stat.("Galls") == format(Catalog.count_galls())
      assert stat.("Host plants") == format(Taxa.count_plants())
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
