defmodule GallformersWeb.FormComponentsTest do
  use GallformersWeb.ConnCase, async: true
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

  defmodule DangerousDeleteTestLive do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <FormComponents.dangerous_delete_modal
        show={@show}
        item_type="gall"
        item_name="Andricus testus"
        consequences={[
          "All host and source associations will be removed.",
          "All images and range data will be permanently deleted."
        ]}
        confirmation_value={@confirmation_value}
      />
      """
    end

    def mount(_params, _session, socket) do
      {:ok, assign(socket, show: true, confirmation_value: "")}
    end

    def handle_event("update_delete_confirmation", %{"value" => value}, socket) do
      {:noreply, assign(socket, confirmation_value: value)}
    end

    def handle_event("confirm_delete", %{"confirmation" => _}, socket) do
      {:noreply, assign(socket, show: false)}
    end

    def handle_event("cancel_delete", _, socket) do
      {:noreply, assign(socket, show: false)}
    end
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

  defmodule EmptyTypeaheadTestLive do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <FormComponents.typeahead
        id="test-empty"
        label="Host"
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
      {:ok, assign(socket, query: "Pappostipa", results: [])}
    end

    def handle_event("search", _params, socket), do: {:noreply, socket}
    def handle_event("select", _params, socket), do: {:noreply, socket}
    def handle_event("clear", _params, socket), do: {:noreply, socket}
  end

  defmodule SelectableTreeTestLive do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <FormComponents.selectable_tree
        id="test-tree"
        label="Places"
        groups={@groups}
        selected={@selected}
        expanded={@expanded}
        toggle_item_event="toggle_item"
        toggle_group_event="toggle_group"
        expand_group_event="expand_group"
        select_all_event="select_all"
        deselect_all_event="deselect_all"
      />
      """
    end

    def mount(_params, _session, socket) do
      groups = [
        %{
          id: "US",
          label: "United States",
          items: [
            %{id: "US-CA", label: "California (US-CA)"},
            %{id: "US-NY", label: "New York (US-NY)"},
            %{id: "US-TX", label: "Texas (US-TX)"}
          ]
        },
        %{
          id: "CA",
          label: "Canada",
          items: [
            %{id: "CA-BC", label: "British Columbia (CA-BC)"},
            %{id: "CA-ON", label: "Ontario (CA-ON)"}
          ]
        }
      ]

      {:ok,
       assign(socket,
         groups: groups,
         selected: MapSet.new(["US-CA", "US-NY"]),
         expanded: MapSet.new(["US"])
       )}
    end

    def handle_event("toggle_item", %{"id" => id}, socket) do
      import GallformersWeb.BrowseHelpers, only: [toggle_set: 2]
      {:noreply, assign(socket, selected: toggle_set(socket.assigns.selected, id))}
    end

    def handle_event("toggle_group", %{"group" => group_id}, socket) do
      import GallformersWeb.BrowseHelpers, only: [toggle_group_selection: 3]

      selected =
        toggle_group_selection(socket.assigns.groups, socket.assigns.selected, group_id)

      {:noreply, assign(socket, selected: selected)}
    end

    def handle_event("expand_group", %{"group" => group_id}, socket) do
      import GallformersWeb.BrowseHelpers, only: [toggle_set: 2]
      {:noreply, assign(socket, expanded: toggle_set(socket.assigns.expanded, group_id))}
    end

    def handle_event("select_all", _params, socket) do
      all_ids =
        socket.assigns.groups
        |> Enum.flat_map(& &1.items)
        |> MapSet.new(& &1.id)

      {:noreply, assign(socket, selected: all_ids)}
    end

    def handle_event("deselect_all", _params, socket) do
      {:noreply, assign(socket, selected: MapSet.new())}
    end
  end

  defmodule SelectableTreeWithFooterTestLive do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <FormComponents.selectable_tree
        id="footer-tree"
        label="Items"
        groups={@groups}
        selected={@selected}
        expanded={@expanded}
        toggle_item_event="toggle_item"
        toggle_group_event="toggle_group"
        expand_group_event="expand_group"
        select_all_event="select_all"
        deselect_all_event="deselect_all"
      >
        <:group_footer :let={group}>
          <p :if={group.id == "special"} class="footer-note">Special note for this group</p>
        </:group_footer>
      </FormComponents.selectable_tree>
      """
    end

    def mount(_params, _session, socket) do
      {:ok,
       assign(socket,
         groups: [
           %{id: "special", label: "Special Group", items: [%{id: "a", label: "Item A"}]},
           %{id: "normal", label: "Normal Group", items: [%{id: "b", label: "Item B"}]}
         ],
         selected: MapSet.new(),
         expanded: MapSet.new(["special", "normal"])
       )}
    end

    def handle_event("toggle_item", _params, socket), do: {:noreply, socket}
    def handle_event("toggle_group", _params, socket), do: {:noreply, socket}
    def handle_event("expand_group", _params, socket), do: {:noreply, socket}
    def handle_event("select_all", _params, socket), do: {:noreply, socket}
    def handle_event("deselect_all", _params, socket), do: {:noreply, socket}
  end

  describe "selectable_tree/1" do
    test "renders label with selected/total item count", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, SelectableTreeTestLive)

      # 2 selected out of 5 total items across both groups
      assert html =~ "Places (2/5)"
    end

    test "renders group headers with selected/total counts", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, SelectableTreeTestLive)

      # US is expanded, has 2/3 selected
      assert html =~ "United States"
      assert html =~ "(2/3)"

      # Canada is collapsed, has 0/2 selected
      assert html =~ "Canada"
      assert html =~ "(0/2)"
    end

    test "shows items in expanded groups", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, SelectableTreeTestLive)

      # US is expanded — its items should be visible
      assert html =~ "California (US-CA)"
      assert html =~ "New York (US-NY)"
      assert html =~ "Texas (US-TX)"

      # Canada is collapsed — its items should not be visible
      refute html =~ "British Columbia (CA-BC)"
      refute html =~ "Ontario (CA-ON)"
    end

    test "expand_group event toggles group visibility", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, SelectableTreeTestLive)

      # Expand Canada
      html = render_click(view, "expand_group", %{"group" => "CA"})
      assert html =~ "British Columbia (CA-BC)"
      assert html =~ "Ontario (CA-ON)"

      # Collapse US
      html = render_click(view, "expand_group", %{"group" => "US"})
      refute html =~ "California (US-CA)"
    end

    test "toggle_item event toggles individual selection", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, SelectableTreeTestLive)

      # Deselect US-CA (was selected)
      html = render_click(view, "toggle_item", %{"id" => "US-CA"})
      # Now 1/3 selected in US
      assert html =~ "(1/3)"

      # Select US-TX (was not selected)
      html = render_click(view, "toggle_item", %{"id" => "US-TX"})
      # Now 2/3 selected in US
      assert html =~ "(2/3)"
    end

    test "toggle_group event selects all items when not all selected", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, SelectableTreeTestLive)

      # Toggle US group (2/3 selected → should select all 3)
      html = render_click(view, "toggle_group", %{"group" => "US"})
      assert html =~ "(3/3)"
    end

    test "toggle_group event deselects all items when all selected", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, SelectableTreeTestLive)

      # First select all US
      render_click(view, "toggle_group", %{"group" => "US"})
      # Then toggle again — should deselect all
      html = render_click(view, "toggle_group", %{"group" => "US"})
      assert html =~ "(0/3)"
    end

    test "select_all selects everything", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, SelectableTreeTestLive)

      html = render_click(view, "select_all")
      assert html =~ "(3/3)"
      assert html =~ "(2/2)"
      assert html =~ "Deselect all"
    end

    test "deselect_all clears everything", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, SelectableTreeTestLive)

      html = render_click(view, "deselect_all")
      assert html =~ "(0/3)"
      assert html =~ "(0/2)"
      assert html =~ "Select all"
    end

    test "tristate checkbox uses IndeterminateCheckbox hook", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, SelectableTreeTestLive)

      # US group has 2/3 selected — should be indeterminate
      assert html =~ ~s(phx-hook="IndeterminateCheckbox")
      assert html =~ ~s(data-indeterminate="true")
    end

    test "group_footer slot renders per-group content", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, SelectableTreeWithFooterTestLive)

      assert html =~ "Special note for this group"
    end

    test "shows select all when not all selected, deselect all when all selected", %{conn: conn} do
      {:ok, view, html} = live_isolated(conn, SelectableTreeTestLive)

      # Initially not all selected
      assert html =~ "Select all"

      # Select everything
      html = render_click(view, "select_all")
      assert html =~ "Deselect all"
    end
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

  describe "dangerous_delete_modal/1" do
    test "makes permanent impact explicit and requires the exact record name", %{conn: conn} do
      {:ok, view, html} = live_isolated(conn, DangerousDeleteTestLive)

      assert html =~ "Permanently delete this gall?"
      assert html =~ "This cannot be undone"
      assert html =~ "All host and source associations will be removed."
      assert html =~ "All images and range data will be permanently deleted."
      assert html =~ "Andricus testus"
      assert html =~ ~s(id="dangerous-delete-confirmation")
      assert has_element?(view, "#dangerous-delete-submit[disabled]")

      render_hook(view, "update_delete_confirmation", %{"value" => " Andricus testus "})

      assert has_element?(view, "#dangerous-delete-submit[disabled]")

      render_hook(view, "update_delete_confirmation", %{"value" => "Andricus testus"})

      refute has_element?(view, "#dangerous-delete-submit[disabled]")
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

  describe "typeahead with no results" do
    test "shows no matches message when query is present but results are empty", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, EmptyTypeaheadTestLive)

      assert html =~ "No matches found"
    end
  end
end
