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

    def handle_info({CountryDrillDown, {:set_exact_type, code, type}}, socket)
        when type in ["native", "introduced"] do
      new_entries = set_exact_entry_type(socket.assigns.range_entries, code, type)

      {:noreply,
       socket
       |> assign(range_entries: new_entries)
       |> update(:messages, &[{:set_exact_type, code, type} | &1])}
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

    def handle_info({CountryDrillDown, {:set_all_exact_type, codes, type}}, socket)
        when type in ["native", "introduced"] do
      new_entries =
        Enum.reduce(codes, socket.assigns.range_entries, fn code, acc ->
          Map.put(acc, code, %{precision: "exact", distribution_type: type})
        end)

      {:noreply,
       socket
       |> assign(range_entries: new_entries)
       |> update(:messages, &[{:set_all_exact_type, codes, type} | &1])}
    end

    def handle_info({CountryDrillDown, {:deselect_all_exact, codes}}, socket) do
      new_entries = Map.drop(socket.assigns.range_entries, codes)

      {:noreply,
       socket
       |> assign(range_entries: new_entries)
       |> update(:messages, &[{:deselect_all_exact, codes} | &1])}
    end

    def handle_info({CountryDrillDown, {:replace_with_country_baseline, code, type}}, socket)
        when type in ["native", "introduced"] do
      new_entries =
        socket.assigns.range_entries
        |> Enum.reject(fn {entry_code, %{precision: precision}} ->
          precision == "exact" and String.starts_with?(entry_code, "#{code}-")
        end)
        |> Enum.into(%{})
        |> Map.put(code, %{precision: "country", distribution_type: type})

      {:noreply,
       socket
       |> assign(range_entries: new_entries)
       |> update(:messages, &[{:replace_with_country_baseline, code, type} | &1])}
    end

    def handle_info({CountryDrillDown, :zoom_out}, socket) do
      {:noreply, update(socket, :messages, &[:zoom_out | &1])}
    end

    defp set_exact_entry_type(range_entries, code, distribution_type) do
      case Map.get(range_entries, code) do
        %{precision: "exact", distribution_type: ^distribution_type} ->
          Map.delete(range_entries, code)

        _ ->
          Map.put(range_entries, code, %{precision: "exact", distribution_type: distribution_type})
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
      refute html =~ "All native"
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
      assert html =~ "All native"
      assert html =~ "All introduced"
      assert html =~ "Clear all"
    end

    test "computes exact_places and introduced_places on open (no race)", %{conn: conn} do
      entries = %{
        "US-CA" => %{precision: "exact", distribution_type: "native"}
      }

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      open_us(view)

      # California should show as native (green indicator)
      assert has_element?(view, "button[phx-value-code='US-CA'][data-state=native]")
    end
  end

  describe "tri-state subdivision indicators" do
    test "not-included subdivision shows empty indicator", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      # California is not in range — should have gray border indicator
      assert has_element?(view, "button[phx-value-code='US-CA'][data-state=none]")
    end

    test "native subdivision shows green indicator", %{conn: conn} do
      entries = %{"US-CA" => %{precision: "exact", distribution_type: "native"}}

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      html = open_us(view)

      assert has_element?(view, "button[phx-value-code='US-CA'][data-state=native]")
      refute html =~ "(introduced)"
    end

    test "introduced subdivision shows amber indicator", %{conn: conn} do
      entries = %{"US-CA" => %{precision: "exact", distribution_type: "introduced"}}

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      html = open_us(view)

      assert has_element?(view, "button[phx-value-code='US-CA'][data-state=introduced]")
      assert html =~ "(introduced)"
    end
  end

  describe "exact subdivision editing" do
    test "clicking subdivision sends selected exact type", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      click_and_sync(view, "button[phx-value-code='US-CA']")

      assert {:set_exact_type, "US-CA", "native"} in get_messages(view)
    end

    test "clicking with native selected adds native then removes on second click", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      html = click_and_sync(view, "button[phx-value-code='US-CA']")
      assert has_element?(view, "button[phx-value-code='US-CA'][data-state=native]")
      refute html =~ "(introduced)"

      click_and_sync(view, "button[phx-value-code='US-CA']")
      assert has_element?(view, "button[phx-value-code='US-CA'][data-state=none]")
    end

    test "switching exact type converts subdivision in one click", %{conn: conn} do
      entries = %{"US-CA" => %{precision: "exact", distribution_type: "introduced"}}

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      open_us(view)
      click_and_sync(view, "#exact-type-native-US")
      assert has_element?(view, "#exact-type-native-US[aria-pressed=true]")

      html = click_and_sync(view, "button[phx-value-code='US-CA']")
      assert has_element?(view, "button[phx-value-code='US-CA'][data-state=native]")
      refute html =~ "(introduced)"
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

      click_and_sync(view, "#country-level-US")

      # California should show inherited style
      assert has_element?(view, "button[phx-value-code='US-CA'][data-state=inherited]")
    end
  end

  describe "country distribution type selector" do
    test "shows native/introduced pills for exact editing", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      html = render(view)

      assert html =~ "Native"
      assert html =~ "Introduced"
      assert html =~ "Click counties as:"
    end

    test "switching exact click mode does not create a country row", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      click_and_sync(view, "#exact-type-introduced-US")
      assert has_element?(view, "#exact-type-introduced-US[aria-pressed=true]")

      click_and_sync(view, "button[phx-value-code='US-CA']")

      refute {:set_country_level, "US", "introduced"} in get_messages(view)
      assert {:set_exact_type, "US-CA", "introduced"} in get_messages(view)
    end

    test "native pill is highlighted when country is native", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      click_and_sync(view, "#country-level-US")

      assert has_element?(view, "#country-type-native-US[aria-pressed=true]")
    end

    test "introduced pill is highlighted after switching", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      click_and_sync(view, "#country-level-US")
      click_and_sync(view, "#country-type-introduced-US")

      assert has_element?(view, "#country-type-introduced-US[aria-pressed=true]")
    end

    test "replace baseline button sends replace_with_country_baseline", %{conn: conn} do
      entries = %{"US-CA" => %{precision: "exact", distribution_type: "native"}}

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      open_us(view)
      click_and_sync(view, "#country-level-US")
      click_and_sync(view, "#country-type-introduced-US")
      click_and_sync(view, "button", "Replace subdivisions with Introduced baseline")

      assert {:replace_with_country_baseline, "US", "introduced"} in get_messages(view)
    end
  end

  describe "bulk selection" do
    test "all native sends set_all_exact_type with native", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      click_and_sync(view, "button", "All native")

      messages = get_messages(view)
      assert {:set_all_exact_type, codes, "native"} = List.first(messages)
      assert "US-CA" in codes
    end

    test "all introduced sends set_all_exact_type with introduced", %{conn: conn} do
      entries = %{"US-CA" => %{precision: "exact", distribution_type: "native"}}

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      open_us(view)

      click_and_sync(view, "button", "All introduced")

      messages = get_messages(view)
      assert {:set_all_exact_type, codes, "introduced"} = List.first(messages)
      assert "US-CA" in codes
    end

    test "all native adds native entries for all subdivisions", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      click_and_sync(view, "button", "All native")

      assert has_element?(view, "button[phx-value-code][data-state=native]")
    end

    test "clear all removes entries and shows empty indicators", %{conn: conn} do
      entries = %{"US-CA" => %{precision: "exact", distribution_type: "native"}}

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      open_us(view)

      click_and_sync(view, "button", "Clear all")

      assert has_element?(view, "button[phx-value-code='US-CA'][data-state=none]")
      refute has_element?(view, "button[phx-value-code][data-state=native]")
    end

    test "all introduced marks exact entries introduced", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, TestLive)
      open_us(view)

      html = click_and_sync(view, "button", "All introduced")

      assert has_element?(view, "button[phx-value-code][data-state=introduced]")
      assert html =~ "(introduced)"
    end

    test "replace baseline removes exact rows and keeps country row", %{conn: conn} do
      entries = %{"US-CA" => %{precision: "exact", distribution_type: "native"}}

      {:ok, view, _html} =
        live_isolated(conn, TestLive, session: %{"range_entries" => entries})

      open_us(view)
      click_and_sync(view, "#country-level-US")
      click_and_sync(view, "#country-type-introduced-US")
      click_and_sync(view, "button", "Replace subdivisions with Introduced baseline")

      assert has_element?(view, "button[phx-value-code='US-CA'][data-state=inherited]")
      refute has_element?(view, "button[phx-value-code][data-state=native]")
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
