defmodule GallformersWeb.Admin.PowoDiffReviewTest do
  @moduledoc """
  Tests for the PowoDiffReview LiveComponent.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GallformersWeb.Admin.PowoDiffReview

  # A minimal harness LiveView that renders the PowoDiffReview component
  # and captures messages sent by it.
  defmodule HarnessLive do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <div id="harness">
        <.live_component
          :if={@diff}
          module={PowoDiffReview}
          id="powo-diff"
          diff={@diff}
          place_by_code={@place_by_code}
        />
        <div :if={@last_message} id="last-message">{inspect(@last_message)}</div>
      </div>
      """
    end

    def mount(_params, session, socket) do
      {:ok,
       assign(socket,
         diff: session["diff"],
         place_by_code: session["place_by_code"] || %{},
         last_message: nil
       )}
    end

    def handle_info({PowoDiffReview, msg}, socket) do
      {:noreply, Phoenix.Component.assign(socket, :last_message, msg)}
    end
  end

  @place_by_code %{
    "US" => %{name: "United States"},
    "US-CA" => %{name: "California"},
    "US-NY" => %{name: "New York"},
    "US-TX" => %{name: "Texas"},
    "BR" => %{name: "Brazil"},
    "CA" => %{name: "Canada"},
    "CA-BC" => %{name: "British Columbia"},
    "CA-ON" => %{name: "Ontario"},
    "MX" => %{name: "Mexico"}
  }

  defp diff_with_changes do
    %{
      add_native: ["US-CA", "US-NY", "BR"],
      add_introduced: ["MX"],
      remove: ["CA-BC"],
      reclassify_to_introduced: ["US-TX"],
      reclassify_to_native: ["CA-ON"],
      agree_count: 5,
      has_changes: true
    }
  end

  defp empty_diff do
    %{
      add_native: [],
      add_introduced: [],
      remove: [],
      reclassify_to_introduced: [],
      reclassify_to_native: [],
      agree_count: 10,
      has_changes: false
    }
  end

  defp mount_harness(conn, diff, place_by_code \\ @place_by_code) do
    live_isolated(conn, HarnessLive, session: %{"diff" => diff, "place_by_code" => place_by_code})
  end

  describe "rendering" do
    test "renders all non-empty buckets with correct labels", %{conn: conn} do
      {:ok, _view, html} = mount_harness(conn, diff_with_changes())

      assert html =~ "POWO-WCVP Data Comparison"
      assert html =~ "Native places in WCVP but not in current range"
      assert html =~ "Introduced places in WCVP but not in current range"
      assert html =~ "Places in current range but not in WCVP"
      assert html =~ "WCVP says introduced (currently native)"
      assert html =~ "WCVP says native (currently introduced)"
    end

    test "empty diff shows no differences message", %{conn: conn} do
      {:ok, _view, html} = mount_harness(conn, empty_diff())

      assert html =~ "No differences found"
      refute html =~ "Apply Selected Changes"
    end

    test "agree count is displayed", %{conn: conn} do
      {:ok, _view, html} = mount_harness(conn, diff_with_changes())

      assert html =~ "5 places match"
    end

    test "hides agree count when zero", %{conn: conn} do
      diff = %{diff_with_changes() | agree_count: 0}
      {:ok, _view, html} = mount_harness(conn, diff)

      refute html =~ "places match"
    end

    test "hides buckets that are empty", %{conn: conn} do
      diff = %{diff_with_changes() | add_introduced: [], reclassify_to_native: []}
      {:ok, _view, html} = mount_harness(conn, diff)

      refute html =~ "Introduced places in WCVP but not in current range"
      refute html =~ "WCVP says native (currently introduced)"
      # Others still present
      assert html =~ "Native places in WCVP but not in current range"
    end
  end

  describe "toggle interactions" do
    test "toggle individual item updates selection state", %{conn: conn} do
      {:ok, view, html} = mount_harness(conn, diff_with_changes())

      # add_native has 3 items: US-CA, US-NY (grouped under US), BR (standalone)
      # All start selected. Total: 3/3
      assert html =~ "(3/3)"

      # Expand the BR group first so items are visible
      view
      |> element("#powo-add-native button[phx-click=expand_group_add-native][phx-value-group=BR]")
      |> render_click()

      # Now deselect BR
      view
      |> element("#powo-add-native input[phx-click=toggle_item_add-native][phx-value-id=BR]")
      |> render_click()

      html = render(view)
      # Now 2/3 selected
      assert html =~ "(2/3)"
    end

    test "select all / deselect all per bucket", %{conn: conn} do
      {:ok, view, _html} = mount_harness(conn, diff_with_changes())

      # add_native starts with all 3 selected, so button says "Deselect all"
      # Click deselect all
      view
      |> element("#powo-add-native button", "Deselect all")
      |> render_click()

      html = render(view)
      assert html =~ "(0/3)"

      # Now click Select all
      view
      |> element("#powo-add-native button", "Select all")
      |> render_click()

      html = render(view)
      assert html =~ "(3/3)"
    end
  end

  describe "apply and cancel" do
    test "apply sends correct selections to parent", %{conn: conn} do
      {:ok, view, _html} = mount_harness(conn, diff_with_changes())

      # Deselect BR from add_native by toggling the BR group (single-item group)
      view
      |> element("#powo-add-native input[phx-click=toggle_group_add-native][phx-value-group=BR]")
      |> render_click()

      # Click apply
      view
      |> element("button", "Apply Selected Changes")
      |> render_click()

      html = render(view)
      # The harness renders the last_message
      assert html =~ "last-message"
      assert html =~ ":apply"
    end

    test "cancel sends cancel to parent", %{conn: conn} do
      {:ok, view, _html} = mount_harness(conn, diff_with_changes())

      view
      |> element("button", "Cancel")
      |> render_click()

      html = render(view)
      assert html =~ "last-message"
      assert html =~ ":cancel"
    end
  end
end
