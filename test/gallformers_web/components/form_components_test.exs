defmodule GallformersWeb.FormComponentsTest do
  use GallformersWeb.ConnCase
  import Phoenix.LiveViewTest

  alias GallformersWeb.FormComponents

  defmodule CascadeDeleteTestLive do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <FormComponents.cascade_delete_modal
        show={@show}
        impact={@impact}
        confirmation_value={@confirmation_value}
      />
      """
    end

    def mount(_params, _session, socket) do
      {:ok,
       assign(socket,
         show: true,
         impact: %{
           taxonomy: %{name: "TestFamily", type: "family"},
           genera: [%{name: "TestGenus1"}, %{name: "TestGenus2"}],
           genera_count: 2,
           sections: [%{name: "TestSection"}],
           sections_count: 1,
           species_count: 10,
           has_impact: true
         },
         confirmation_value: ""
       )}
    end

    def handle_event("update_delete_confirmation", %{"value" => value}, socket) do
      {:noreply, assign(socket, confirmation_value: value)}
    end

    def handle_event("confirm_cascade_delete", %{"confirmation" => _}, socket) do
      {:noreply, assign(socket, show: false)}
    end

    def handle_event("cancel_cascade_delete", _, socket) do
      {:noreply, assign(socket, show: false)}
    end
  end

  defmodule NoImpactTestLive do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <FormComponents.cascade_delete_modal
        show={@show}
        impact={@impact}
        confirmation_value={@confirmation_value}
      />
      """
    end

    def mount(_params, _session, socket) do
      {:ok,
       assign(socket,
         show: true,
         impact: %{
           taxonomy: %{name: "EmptyGenus", type: "genus"},
           genera: [],
           genera_count: 0,
           sections: [],
           sections_count: 0,
           species_count: 0,
           has_impact: false
         },
         confirmation_value: ""
       )}
    end

    def handle_event("update_delete_confirmation", %{"value" => value}, socket) do
      {:noreply, assign(socket, confirmation_value: value)}
    end

    def handle_event("confirm_cascade_delete", _, socket), do: {:noreply, socket}
    def handle_event("cancel_cascade_delete", _, socket), do: {:noreply, socket}
  end

  defmodule GroupedTypeaheadTestLive do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <FormComponents.typeahead
        id="test-grouped"
        label="Place"
        query={@query}
        results={@results}
        selected={nil}
        search_event="search"
        select_event="select"
        clear_event="clear"
        display_fn={fn item -> item.name end}
        group_key={:group}
      />
      """
    end

    def mount(_params, _session, socket) do
      {:ok,
       assign(socket,
         query: "br",
         results: [
           %{id: 1, name: "Brazil", group: "Countries"},
           %{id: 2, name: "British Columbia", group: "States & Provinces"}
         ]
       )}
    end

    def handle_event("search", _params, socket), do: {:noreply, socket}
    def handle_event("select", _params, socket), do: {:noreply, socket}
    def handle_event("clear", _params, socket), do: {:noreply, socket}
  end

  defmodule UngroupedTypeaheadTestLive do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <FormComponents.typeahead
        id="test-ungrouped"
        label="Place"
        query={@query}
        results={@results}
        selected={nil}
        search_event="search"
        select_event="select"
        clear_event="clear"
        display_fn={fn item -> item.name end}
      />
      """
    end

    def mount(_params, _session, socket) do
      {:ok,
       assign(socket,
         query: "b",
         results: [%{id: 1, name: "Brazil"}, %{id: 2, name: "Canada"}]
       )}
    end

    def handle_event("search", _params, socket), do: {:noreply, socket}
    def handle_event("select", _params, socket), do: {:noreply, socket}
    def handle_event("clear", _params, socket), do: {:noreply, socket}
  end

  describe "typeahead with group_key" do
    test "renders group headers between groups", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, GroupedTypeaheadTestLive)

      assert html =~ "Countries"
      assert html =~ "States &amp; Provinces"
      assert html =~ "Brazil"
      assert html =~ "British Columbia"
    end

    test "group headers have role=presentation", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, GroupedTypeaheadTestLive)

      assert html =~ ~s(role="presentation")
    end

    test "renders without groups when group_key is nil", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, UngroupedTypeaheadTestLive)

      refute html =~ ~s(role="presentation")
      assert html =~ "Brazil"
      assert html =~ "Canada"
    end
  end

  describe "cascade_delete_modal/1" do
    test "renders modal with impact summary", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, CascadeDeleteTestLive)

      # Check header — name is wrapped in .taxon_name component
      assert html =~ "Delete"
      assert html =~ "TestFamily"

      # Check impact summary
      assert html =~ "2"
      assert html =~ "genera"
      assert html =~ "1"
      assert html =~ "sections"
      assert html =~ "10"
      assert html =~ "species"
      assert html =~ "images, aliases, sources, host associations"
    end

    test "renders expandable details with genera and sections", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, CascadeDeleteTestLive)

      # Check details section exists
      assert html =~ "Show details"
      assert html =~ "TestGenus1"
      assert html =~ "TestGenus2"
      assert html =~ "TestSection"
    end

    test "renders type-to-confirm input", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, CascadeDeleteTestLive)

      assert html =~ "Type"
      assert html =~ "TestFamily"
      assert html =~ "to confirm"
      assert html =~ ~s(id="delete-confirmation")
    end

    test "renders cancel and delete buttons", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, CascadeDeleteTestLive)

      assert html =~ "Cancel"
      assert html =~ "Delete Forever"
    end

    test "delete button is disabled when confirmation doesn't match", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, CascadeDeleteTestLive)

      # Button should have disabled attribute when confirmation is empty
      assert html =~ ~s(disabled)
    end

    test "shows safe delete message when no impact", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, NoImpactTestLive)

      assert html =~ "no dependent data"
      assert html =~ "safely deleted"
      refute html =~ "This will delete:"
    end

    test "hides details section when no genera or sections", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, NoImpactTestLive)

      refute html =~ "Show details"
    end

    test "has proper accessibility attributes", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, CascadeDeleteTestLive)

      assert html =~ ~s(role="dialog")
      assert html =~ ~s(aria-modal="true")
      assert html =~ ~s(aria-labelledby="cascade-delete-modal-title")
      assert html =~ ~s(aria-label="close")
    end
  end
end
