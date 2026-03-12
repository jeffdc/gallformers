defmodule GallformersWeb.KeyLiveTest do
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "Key display page" do
    test "page loads with valid slug", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/keys/oak-parasite-key")
      assert html =~ "parasitic wasps"
    end

    test "displays couplet 1", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/keys/oak-parasite-key")
      assert html =~ "Wings fully developed"
    end

    test "shows 404 for invalid slug", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/keys/nonexistent")
      assert html =~ "Key Not Found"
    end

    test "couplet 1 is active on load", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/keys/oak-parasite-key")
      assert has_element?(view, "#couplet-1")
    end
  end

  describe "Key navigation" do
    test "clicking a lead updates the path", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/keys/oak-parasite-key")

      # Click the first lead of couplet 1 (leads to couplet 2)
      html =
        view
        |> element("[phx-value-couplet='1'][phx-value-lead='0']")
        |> render_click()

      # Path tracker should appear
      assert html =~ "Path:"
      # Couplet 2 should now be active
      assert html =~ "complex venation"
    end

    test "clicking a taxon lead shows terminal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/keys/oak-parasite-key")

      # Navigate: 1 -> 2 (first lead), 2 -> 3 (first lead), 3 -> 4 (first lead), 4 -> Ichneumonidae (first lead)
      view |> element("[phx-value-couplet='1'][phx-value-lead='0']") |> render_click()
      view |> element("[phx-value-couplet='2'][phx-value-lead='0']") |> render_click()
      view |> element("[phx-value-couplet='3'][phx-value-lead='0']") |> render_click()

      html =
        view
        |> element("[phx-value-couplet='4'][phx-value-lead='0']")
        |> render_click()

      assert html =~ "Ichneumonidae"
    end

    test "reset clears the path", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/keys/oak-parasite-key")

      # Make a selection
      view |> element("[phx-value-couplet='1'][phx-value-lead='0']") |> render_click()

      # Reset
      html = view |> element("button", "Start over") |> render_click()

      # Path should be gone
      refute html =~ "Path:"
    end

    test "jump_to truncates path", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/keys/oak-parasite-key")

      # Navigate 1 -> 2 -> 3
      view |> element("[phx-value-couplet='1'][phx-value-lead='0']") |> render_click()
      view |> element("[phx-value-couplet='2'][phx-value-lead='0']") |> render_click()

      # Jump back to step 0 (couplet 1) — goes back to re-choose, clears path before it
      html =
        view
        |> element("button[phx-click='jump_to'][phx-value-index='0']")
        |> render_click()

      # Path should be empty (jumped back to the first step)
      refute html =~ "Path:"
      # Couplet 1 should be active again
      assert has_element?(view, "#couplet-1")
    end

    test "jump_to mid-path keeps earlier steps", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/keys/oak-parasite-key")

      # Navigate 1 -> 2 -> 3
      view |> element("[phx-value-couplet='1'][phx-value-lead='0']") |> render_click()
      view |> element("[phx-value-couplet='2'][phx-value-lead='0']") |> render_click()

      # Jump back to step 1 (couplet 2) — keeps step 0, removes step 1
      html =
        view
        |> element("button[phx-click='jump_to'][phx-value-index='1']")
        |> render_click()

      # Path should still show (step 0 remains)
      assert html =~ "Path:"
    end
  end
end
