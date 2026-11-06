defmodule GallformersWeb.KeyLiveTest do
  @moduledoc """
  A key page (`/keys/:slug`): couplets with lettered leads, the path (a bar
  on narrow screens, the `#key-path` panel beside the key on wide ones),
  Back, Start over, Copy link, Copy as text, and `?path=` replay.

  Uses the seeds' oak parasite key: 1a → 2, 2a → 3, 3a → 4, 4a →
  Ichneumonidae.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Gallformers.CatalogFixtures

  # Reads the seeds' oak parasite key.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  @key "/keys/oak-parasite-key"

  defp choose(view, couplet, lead) do
    view
    |> element("li[phx-value-couplet='#{couplet}'][phx-value-lead='#{lead}']")
    |> render_click()
  end

  defp to_ichneumonidae(view) do
    for couplet <- ~w(1 2 3 4), do: choose(view, couplet, 0)
    view
  end

  describe "the page" do
    test "shows the key's title, scope and couplet count", %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)

      assert has_element?(view, "h1", "Key to parasitic wasps associated with oak gall wasps")
      assert has_element?(view, "[data-part=meta]", "Hymenoptera: Cynipini")
      assert view |> element("[data-part=meta]") |> render() =~ ~r/Couplets.*4/s
      assert page_title(view) =~ "parasitic wasps"
    end

    test "a missing key is a 404", %{conn: conn} do
      assert_raise GallformersWeb.NotFoundError, fn -> live(conn, ~p"/keys/nonexistent") end
    end

    test "couplet 1 is active; the others wait", %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)

      assert has_element?(view, "#couplet-1[data-state=active]")
      assert has_element?(view, "#couplet-2[data-state=unvisited]")
    end

    test "leads are lettered, each a button to choose it", %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)

      assert has_element?(view, "#couplet-1 li[phx-value-lead='0'] [data-part=letter]", "a")
      assert has_element?(view, "#couplet-1 li[phx-value-lead='1'] [data-part=letter]", "b")

      assert has_element?(
               view,
               "#couplet-1 li[phx-value-lead='0'] button",
               "Wings fully developed"
             )
    end

    test "a lead says where it goes", %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)

      assert has_element?(view, "#couplet-1 li[phx-value-lead='0']", "go to 2")
      assert has_element?(view, "#couplet-4 li[phx-value-lead='0']", "Ichneumonidae")
    end

    test "before any choice, the path says where to start", %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)

      assert has_element?(view, "#key-path", "Start at couplet 1")
      refute has_element?(view, "#key-path button", "Back")
      refute has_element?(view, "#key-path [phx-hook=CopyToClipboard]")
    end
  end

  describe "choosing" do
    test "a choice adds a step, marks the lead and moves on", %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)
      choose(view, 1, 0)

      assert has_element?(view, "#key-path li", "1a")
      assert has_element?(view, "#key-path li", "Wings fully developed")
      assert has_element?(view, "#couplet-1[data-state=visited]")
      assert has_element?(view, "#couplet-1 li[phx-value-lead='0'][data-state=chosen]")
      assert has_element?(view, "#couplet-2[data-state=active]")
      assert_push_event(view, "scroll_to_couplet", %{id: "couplet-2"})
    end

    test "a lead to a taxon ends at the result", %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)
      to_ichneumonidae(view)

      assert has_element?(view, "#key-path [data-part=result]", "Ichneumonidae")
      refute has_element?(view, "[data-state=active]")
    end

    test "Start over clears the path", %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)
      choose(view, 1, 0)

      view |> element("#key-path button", "Start over") |> render_click()

      assert has_element?(view, "#key-path", "Start at couplet 1")
      assert has_element?(view, "#couplet-1[data-state=active]")
    end

    test "a step goes back to its couplet, dropping it and what follows", %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)
      choose(view, 1, 0)
      choose(view, 2, 0)

      view
      |> element("#key-path button[phx-click=jump_to][phx-value-index='1']")
      |> render_click()

      assert has_element?(view, "#key-path li", "1a")
      refute has_element?(view, "#key-path li", "2a")
      assert has_element?(view, "#couplet-2[data-state=active]")
    end

    test "Back undoes the last step", %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)
      choose(view, 1, 0)
      choose(view, 2, 0)

      view |> element("#key-path button", "Back") |> render_click()

      refute has_element?(view, "#key-path li", "2a")
      assert_push_event(view, "scroll_to_couplet", %{id: "couplet-2"})
    end

    test "the narrow-screen bar has the same steps and actions", %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)
      choose(view, 1, 0)

      assert has_element?(
               view,
               "#key-path-bar[data-sticky-chrome] button[phx-click=jump_to]",
               "1a"
             )

      assert has_element?(view, "#key-path-bar button", "Back")
      assert has_element?(view, "#key-path-bar button", "Start over")
    end
  end

  describe "copying" do
    test "Copy link copies the link to this point, once there is a path", %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)
      choose(view, 1, 0)
      choose(view, 2, 0)

      assert has_element?(
               view,
               ~s{#key-path [phx-hook=CopyToClipboard][data-copy-url][data-copy-text="/keys/oak-parasite-key?path=1:0,2:0"]},
               "Copy link"
             )
    end

    test "Copy as text shows only at a result", %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)
      choose(view, 1, 0)
      refute has_element?(view, "#key-path button", "Copy as text")

      for couplet <- ~w(2 3 4), do: choose(view, couplet, 0)
      assert has_element?(view, "#key-path button", "Copy as text")
    end

    test "Copy as text copies the title, the link, each step as the page numbers it, and the result",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, @key)
      to_ichneumonidae(view)

      view |> element("#key-path button", "Copy as text") |> render_click()

      assert_push_event(view, "copy_to_clipboard", %{text: text, url_path: url_path})
      assert url_path == "/keys/oak-parasite-key?path=1:0,2:0,3:0,4:0"

      assert [
               "Key to parasitic wasps associated with oak gall wasps",
               "{{KEY_URL}}",
               "",
               "1a. Wings fully developed." | rest
             ] = String.split(text, "\n")

      assert Enum.at(rest, 0) =~ ~r/^2a\. /
      assert Enum.at(rest, 2) =~ ~r/^4a\. /
      assert Enum.at(rest, 3) == "→ Ichneumonidae"
    end
  end

  describe "a result's Galls" do
    defp key_to(destination) do
      couplets =
        Jason.encode!(%{
          "1" => %{
            "leads" => [
              %{"text" => "Pocket on the leaf.", "images" => [], "destination" => destination},
              %{
                "text" => "Not a pocket.",
                "images" => [],
                "destination" => %{"type" => "taxon", "name" => "Something else"}
              }
            ]
          }
        })

      slug = "fixture-key-#{System.unique_integer([:positive])}"

      {:ok, _} =
        Gallformers.Keys.create_key(%{
          title: "Fixture key",
          slug: slug,
          version: "1",
          couplets: couplets
        })

      "/keys/#{slug}"
    end

    test "one Gall: the name links to it", %{conn: conn} do
      gall = gall_fixture()
      path = key_to(%{"type" => "taxon", "name" => "Thecabius affinis", "species_id" => gall.id})

      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, ~s{#couplet-1 a[href="/gall/#{gall.id}"]}, "Thecabius affinis")
    end

    test "several Galls: each is named and linked", %{conn: conn} do
      one = gall_fixture(%{name: "Thecabius lysimachiae"})
      two = gall_fixture(%{name: "Thecabius affinis"})

      path =
        key_to(%{
          "type" => "taxon",
          "name" => "Thecabius lysimachiae / T. affinis",
          "species_id" => [one.id, two.id]
        })

      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, ~s{#couplet-1 a[href="/gall/#{one.id}"]}, "Thecabius lysimachiae")
      assert has_element?(view, ~s{#couplet-1 a[href="/gall/#{two.id}"]}, "Thecabius affinis")
    end
  end

  describe "?path= links" do
    test "replay the path and scroll to where it stops", %{conn: conn} do
      {:ok, view, _html} = live(conn, "#{@key}?path=1:0,2:0")

      assert has_element?(view, "#key-path li", "2a")
      assert has_element?(view, "#couplet-3[data-state=active]")
      assert_push_event(view, "scroll_to_couplet", %{id: "couplet-3"})
    end

    test "ending at a result scrolls to the last couplet", %{conn: conn} do
      {:ok, view, _html} = live(conn, "#{@key}?path=1:0,2:0,3:0,4:0")

      assert has_element?(view, "#key-path [data-part=result]", "Ichneumonidae")
      assert_push_event(view, "scroll_to_couplet", %{id: "couplet-4"})
    end
  end
end
