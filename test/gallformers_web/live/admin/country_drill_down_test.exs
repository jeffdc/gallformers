defmodule GallformersWeb.Admin.CountryDrillDownTest do
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GallformersWeb.Admin.CountryDrillDown

  # Wrapper LiveView that hosts the CountryDrillDown component and collects
  # messages it sends via notify_parent. Mirrors how the host form uses it.
  defmodule TestLive do
    use Phoenix.LiveView

    alias Gallformers.Places
    alias GallformersWeb.Admin.CountryDrillDown

    def mount(_params, session, socket) do
      {:ok,
       assign(socket,
         range_entries: session["range_entries"] || %{},
         all_places: Places.list_places(),
         messages: []
       )}
    end

    def render(assigns) do
      ~H"""
      <button
        id="open-us"
        phx-click="open_country"
        phx-value-id="902"
        phx-value-code="US"
        phx-value-name="United States"
      >
        Open US
      </button>
      <button
        id="open-mx"
        phx-click="open_country"
        phx-value-id="904"
        phx-value-code="MX"
        phx-value-name="Mexico"
      >
        Open MX
      </button>
      <.live_component
        module={CountryDrillDown}
        id="test-drill-down"
        range_entries={@range_entries}
        all_places={@all_places}
      />
      <div id="messages">{inspect(@messages)}</div>
      """
    end

    def handle_event("open_country", %{"id" => id, "code" => code, "name" => name}, socket) do
      country = %{id: String.to_integer(id), code: code, name: name}
      send_update(CountryDrillDown, id: "test-drill-down", action: {:open, country})
      {:noreply, socket}
    end

    # Mirror the form's cycle_range_entry so component re-renders with updated state
    def handle_info({CountryDrillDown, {:cycle_entry, code}}, socket) do
      new_entries = cycle_range_entry(socket.assigns.range_entries, code)

      {:noreply,
       socket
       |> assign(range_entries: new_entries)
       |> update(:messages, &[{:cycle_entry, code} | &1])}
    end

    def handle_info({CountryDrillDown, {:set_country_level, code, type}}, socket)
        when type in ["native", "introduced"] do
      new_entries =
        Map.put(socket.assigns.range_entries, code, %{
          precision: "country",
          distribution_type: type
        })

      {:noreply,
       socket
       |> assign(range_entries: new_entries)
       |> update(:messages, &[{:set_country_level, code, type} | &1])}
    end

    def handle_info({CountryDrillDown, {:set_country_level, code, false}}, socket) do
      new_entries = Map.delete(socket.assigns.range_entries, code)

      {:noreply,
       socket
       |> assign(range_entries: new_entries)
       |> update(:messages, &[{:set_country_level, code, false} | &1])}
    end

    def handle_info({CountryDrillDown, {:select_all_exact, codes}}, socket) do
      new_entries =
        Enum.reduce(codes, socket.assigns.range_entries, fn code, acc ->
          Map.put_new(acc, code, %{precision: "exact", distribution_type: "native"})
        end)

      {:noreply,
       socket
       |> assign(range_entries: new_entries)
       |> update(:messages, &[{:select_all_exact, codes} | &1])}
    end

    def handle_info({CountryDrillDown, {:deselect_all_exact, codes}}, socket) do
      new_entries = Map.drop(socket.assigns.range_entries, codes)

      {:noreply,
       socket
       |> assign(range_entries: new_entries)
       |> update(:messages, &[{:deselect_all_exact, codes} | &1])}
    end

    def handle_info({CountryDrillDown, :zoom_out}, socket) do
      {:noreply, update(socket, :messages, &[:zoom_out | &1])}
    end

    defp cycle_range_entry(range_entries, code) do
      case Map.get(range_entries, code) do
        nil ->
          Map.put(range_entries, code, %{precision: "exact", distribution_type: "native"})

        %{distribution_type: "native"} ->
          Map.put(range_entries, code, %{precision: "exact", distribution_type: "introduced"})

        _ ->
          Map.delete(range_entries, code)
      end
    end
  end

  # open_us triggers handle_event which calls send_update (async).
  # The extra render/1 processes the queued send_update message.
  defp open_us(view) do
    view |> element("#open-us") |> render_click()
    render(view)
  end

  # Component events use notify_parent (send to self), which is async.
  # Click the element, then render to process the parent's handle_info.
  defp click_and_sync(view, selector) do
    view |> element(selector) |> render_click()
    render(view)
  end

  defp click_and_sync(view, selector, text) do
    view |> element(selector, text) |> render_click()
    render(view)
  end

  defp get_messages(view) do
    :sys.get_state(view.pid).socket.assigns.messages
  end

  describe "closed state" do
    test "renders nothing when closed", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, TestLive)

      refute html =~ "Country-level range"
      refute html =~ "Select all"
    end
  end

  describe "open state" do
    test "shows country name and subdivisions", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)

      html = open_us(view)

      assert html =~ "United States"
      assert html =~ "California"
      assert html =~ "US-CA"
    end

    test "shows country-level toggle and bulk buttons", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)

      html = open_us(view)

      assert html =~ "Country-level range"
      assert html =~ "Select all"
      assert html =~ "Deselect all"
    end

    test "computes exact_places and introduced_places on open (no race)", %{conn: conn} do
      entries = %{
        "US-CA" => %{precision: "exact", distribution_type: "native"}
      }

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      html = open_us(view)

      # California should show as native (green indicator)
      assert html =~ "bg-green-500"
      assert html =~ "bg-green-50"
    end
  end

  describe "tri-state subdivision indicators" do
    test "not-included subdivision shows empty indicator", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      html = open_us(view)

      # California is not in range — should have gray border indicator
      assert html =~ "border-gray-300"
      refute html =~ "bg-green-500"
      refute html =~ "bg-amber-500"
    end

    test "native subdivision shows green indicator", %{conn: conn} do
      entries = %{"US-CA" => %{precision: "exact", distribution_type: "native"}}

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      html = open_us(view)

      assert html =~ "bg-green-500"
      assert html =~ "bg-green-50"
      refute html =~ "(introduced)"
    end

    test "introduced subdivision shows amber indicator", %{conn: conn} do
      entries = %{"US-CA" => %{precision: "exact", distribution_type: "introduced"}}

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      html = open_us(view)

      assert html =~ "bg-amber-500"
      assert html =~ "bg-amber-50"
      assert html =~ "(introduced)"
    end
  end

  describe "tri-state subdivision cycling" do
    test "clicking subdivision sends cycle_entry", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      click_and_sync(view, "button[phx-value-code='US-CA']")

      assert {:cycle_entry, "US-CA"} in get_messages(view)
    end

    test "cycling through states: none → native → introduced → none", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      # Click 1: none → native
      html = click_and_sync(view, "button[phx-value-code='US-CA']")
      assert html =~ "bg-green-500"
      refute html =~ "(introduced)"

      # Click 2: native → introduced
      html = click_and_sync(view, "button[phx-value-code='US-CA']")
      assert html =~ "bg-amber-500"
      assert html =~ "(introduced)"

      # Click 3: introduced → removed
      html = click_and_sync(view, "button[phx-value-code='US-CA']")
      assert html =~ "border-gray-300"
      refute html =~ "bg-green-500"
      refute html =~ "bg-amber-500"
    end
  end

  describe "country-level toggle" do
    test "toggling on sends set_country_level with native type", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      click_and_sync(view, "#country-level-US")

      assert {:set_country_level, "US", "native"} in get_messages(view)
    end

    test "toggling off sends set_country_level with false", %{conn: conn} do
      entries = %{"US" => %{precision: "country", distribution_type: "native"}}

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      open_us(view)

      click_and_sync(view, "#country-level-US")

      assert {:set_country_level, "US", false} in get_messages(view)
    end

    test "shows inherited background for subdivisions when country-level is on", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      html = click_and_sync(view, "#country-level-US")

      # California should show inherited style
      assert html =~ "bg-emerald-50/50"
    end
  end

  describe "country distribution type selector" do
    test "shows native/introduced pills when country-level is on", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      # Toggle country-level on to see pills
      html = click_and_sync(view, "#country-level-US")

      assert html =~ "Native"
      assert html =~ "Introduced"
      assert html =~ "Type:"
    end

    test "does not show pills when country-level is off", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      html = open_us(view)

      refute html =~ "Type:"
    end

    test "switching to introduced sends set_country_level with introduced type", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      # Turn on country-level first
      click_and_sync(view, "#country-level-US")

      # Switch to introduced
      click_and_sync(view, "button[phx-value-type='introduced']")

      assert {:set_country_level, "US", "introduced"} in get_messages(view)
    end

    test "native pill is highlighted when country is native", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      html = click_and_sync(view, "#country-level-US")

      assert html =~ "bg-green-100"
    end

    test "introduced pill is highlighted after switching", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      click_and_sync(view, "#country-level-US")
      html = click_and_sync(view, "button[phx-value-type='introduced']")

      assert html =~ "bg-amber-100"
    end
  end

  describe "bulk selection" do
    test "select all sends select_all_exact with subdivision codes", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      click_and_sync(view, "button", "Select all")

      messages = get_messages(view)
      assert {:select_all_exact, codes} = List.first(messages)
      assert "US-CA" in codes
    end

    test "deselect all sends deselect_all_exact with subdivision codes", %{conn: conn} do
      entries = %{"US-CA" => %{precision: "exact", distribution_type: "native"}}

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      open_us(view)

      click_and_sync(view, "button", "Deselect all")

      messages = get_messages(view)
      assert {:deselect_all_exact, codes} = List.first(messages)
      assert "US-CA" in codes
    end

    test "select all adds native entries for all subdivisions", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      html = click_and_sync(view, "button", "Select all")

      # California should now show as native
      assert html =~ "bg-green-500"
    end

    test "deselect all removes entries and shows empty indicators", %{conn: conn} do
      entries = %{"US-CA" => %{precision: "exact", distribution_type: "native"}}

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      open_us(view)

      html = click_and_sync(view, "button", "Deselect all")

      assert html =~ "border-gray-300"
      refute html =~ "bg-green-500"
    end
  end

  describe "close" do
    test "close button sends zoom_out", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      click_and_sync(view, "button[aria-label='Close panel']")

      assert :zoom_out in get_messages(view)
    end
  end
end
