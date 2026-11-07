defmodule GallformersWeb.HomeLiveTest do
  use GallformersWeb.ConnCase
  import Phoenix.LiveViewTest
  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog
  alias Gallformers.Repo
  alias Gallformers.Taxa

  describe "Home page" do
    test "asks about the odd thing on a plant, says what galls are, then opens on identifying one",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "h1", "Found something odd growing on a plant?")
      assert has_element?(view, "p", "It's probably a gall")
      assert has_element?(view, ~s(p a[href="/articles/idguide"]), "Learn more")
      assert has_element?(view, "label", "What plant is it on?")
      assert has_element?(view, "[data-part=cynipid-mark]")
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

    test "the Source changed most recently, linking to its page", %{conn: conn} do
      [source | _] = Gallformers.Sources.list_recently_changed(1)
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s(#newest-source a[href="/source/#{source.id}"]), source.title)
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

    test "the counts are the new back-end's Galls, plants and undescribed Galls", %{conn: conn} do
      gall_fixture()
      plant_fixture()

      {:ok, view, _html} = live(conn, ~p"/")
      counts = Catalog.gall_counts()

      assert has_element?(
               view,
               ~s(#home-counts a[href="/galls"]),
               "#{format(counts.galls)} galls"
             )

      assert has_element?(
               view,
               ~s(#home-counts a[href="/hosts"]),
               "#{format(Taxa.count_plants())} host plants"
             )

      assert has_element?(
               view,
               "#home-counts",
               "#{format(counts.undescribed)} of them are still undescribed"
             )
    end

    test "an undescribed random Gall is named by what it is", %{conn: conn} do
      gall = gall_fixture(name: "Unknown (Cynipidae) q-alba-fixture-bead-gall")
      Repo.query!("UPDATE gall_index SET image_id = NULL")

      Repo.insert_all("image", [
        %{species_id: 300, path: "gall/x/bead_original.jpg", gall_id: gall.id}
      ])

      :ok = Catalog.refresh_gall_index([gall.id])

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(
               view,
               "#random-gall a[href='/gall/#{gall.id}'] [data-part=gall-name]",
               "An undescribed fixture bead gall"
             )
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
