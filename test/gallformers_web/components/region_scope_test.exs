defmodule GallformersWeb.RegionScopeTest do
  @moduledoc """
  Tests for the region scope widget component.
  """
  use GallformersWeb.ConnCase
  import Phoenix.LiveViewTest

  alias GallformersWeb.UIComponents

  defmodule RegionScopeTestLive do
    use Phoenix.LiveView
    alias GallformersWeb.Live.ContinentScope

    def render(assigns) do
      ~H"""
      <UIComponents.region_scope
        continent_code={@continent_code}
        continent_name={@continent_name}
        default_continent_code={@default_continent_code}
      />
      """
    end

    def mount(_params, _session, socket) do
      {:ok,
       assign(socket,
         continent_code: nil,
         continent_name: nil,
         default_continent_code: nil
       )}
    end

    def handle_info({:set_default, code}, socket) do
      continent_name =
        if code, do: ContinentScope.continent_names()[code]

      {:noreply,
       assign(socket,
         default_continent_code: code,
         continent_code: code,
         continent_name: continent_name
       )}
    end

    def handle_event("change_region", %{"code" => code}, socket) do
      continent_name =
        if code != "",
          do: ContinentScope.continent_names()[code]

      {:noreply,
       assign(socket,
         continent_code: if(code == "", do: nil, else: code),
         continent_name: continent_name
       )}
    end
  end

  describe "region_scope component" do
    test "renders with 'All Regions' when no continent selected", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, RegionScopeTestLive)

      assert html =~ "All Regions"
      assert html =~ "ph-globe"
    end

    test "renders with continent name when selected", %{conn: conn} do
      {:ok, view, _html} =
        live_isolated(conn, RegionScopeTestLive)

      html =
        view
        |> element("[data-region-code=\"XN\"]")
        |> render_click()

      assert html =~ "North America"
    end

    test "shows all 8 continents plus 'All Regions' in dropdown", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, RegionScopeTestLive)

      # 8 continents + All Regions = 9 selectable options
      assert html =~ "Africa"
      assert html =~ "Asia"
      assert html =~ "Caribbean"
      assert html =~ "Central America"
      assert html =~ "Europe"
      assert html =~ "North America"
      assert html =~ "Oceania"
      assert html =~ "South America"
      assert html =~ "All Regions"
    end

    test "shows 'Set as default' and 'Reset' after changing from default", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, RegionScopeTestLive)

      # Change region — should show override controls
      html =
        view
        |> element("[data-region-code=\"XE\"]")
        |> render_click()

      assert html =~ "Set as default"
      assert html =~ "Reset"
    end

    test "does not show override controls when at default", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, RegionScopeTestLive)

      # At default (All Regions), no override controls
      refute html =~ "Set as default"
      refute html =~ "Reset"
    end

    test "Reset reverts to default region", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, RegionScopeTestLive)

      # Change to Europe (override)
      view |> element("[data-region-code=\"XE\"]") |> render_click()

      # Click Reset — should revert to All Regions (the default)
      html = view |> element("[data-region-reset]") |> render_click()

      assert html =~ "All Regions"
      refute html =~ "Set as default"
    end

    test "highlights active region in dropdown", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, RegionScopeTestLive)

      # Change to Asia
      html = view |> element("[data-region-code=\"XA\"]") |> render_click()

      # Asia button should have font-bold
      assert html =~
               ~r/data-region-code="XA"[^>]*class="[^"]*font-bold/
    end
  end

  describe "region scope first-visit modal" do
    test "renders modal markup when no default is set", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, RegionScopeTestLive)

      # Modal should be in the DOM (JS hook controls visibility)
      assert html =~ "region-prompt"
      assert html =~ "Welcome to Gallformers"
      assert html =~ "filterable pages"
    end

    test "does not render modal when a default is already saved", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, RegionScopeTestLive)

      # Simulate having a saved default by setting the default_continent_code
      send(view.pid, {:set_default, "XN"})
      html = render(view)

      refute html =~ "region-prompt"
    end
  end
end
