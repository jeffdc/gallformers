defmodule GallformersWeb.FormComponentsTest do
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]

  alias GallformersWeb.FormComponents
  alias Phoenix.LiveView.JS

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()
  defp attr(html, selector, name), do: html |> query(selector) |> LazyHTML.attribute(name)

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

  describe "toggle/1" do
    test "a switch: a checkbox with role switch, its label, on or off" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <FormComponents.toggle id="t1" name="on" checked label="Show on About" />
        """)

      assert attr(html, "input[type=checkbox]#t1", "role") == ["switch"]
      assert attr(html, "input#t1", "checked") == [""]
      assert text(html, "label") =~ "Show on About"
      assert count(html, "label .gf-toggle-track") == 1
    end

    test "with no visible label: its events and accessible name go on the input" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <FormComponents.toggle
          id="t2"
          name="on"
          aria-label="Show Ada on About"
          phx-click="flip"
          phx-value-id="7"
        />
        """)

      assert attr(html, "input#t2", "aria-label") == ["Show Ada on About"]
      assert attr(html, "input#t2", "phx-click") == ["flip"]
      assert attr(html, "input#t2", "phx-value-id") == ["7"]
      assert attr(html, "input#t2", "checked") == []
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

    test "is a dialog: titled, its confirmation a form the Delete button submits", %{conn: conn} do
      {:ok, view, _html} = live_isolated(conn, DangerousDeleteTestLive)

      assert has_element?(
               view,
               "#dangerous-delete-modal-panel[role=dialog][aria-labelledby=dangerous-delete-modal-title]"
             )

      assert has_element?(view, "#dangerous-delete-modal-title", "Permanently delete this gall?")

      assert has_element?(
               view,
               "#dangerous-delete-submit[type=submit][form=dangerous-delete-modal-form]"
             )

      view
      |> element("#dangerous-delete-modal [data-part=actions] button", "Cancel")
      |> render_click()

      refute has_element?(view, "#dangerous-delete-modal")
    end
  end

  describe "typeahead with no results" do
    test "shows no matches message when query is present but results are empty", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, EmptyTypeaheadTestLive)

      assert html =~ "No matches found"
    end
  end

  describe "field/1" do
    test "labels the control and renders help and errors under ids from `for`" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <FormComponents.field
          label="Name"
          for="taxon-name"
          help="The old name is kept as a synonym."
          errors={["can't be blank", "is too short"]}
        >
          <input id="taxon-name" aria-describedby="taxon-name-help taxon-name-errors" />
        </FormComponents.field>
        """)

      assert attr(html, "label", "for") == ["taxon-name"]
      assert text(html, "label") == "Name"
      assert count(html, "input#taxon-name") == 1

      assert text(html, "#taxon-name-help") == "The old name is kept as a synonym."
      # Each error is its own line, with the warning icon
      assert count(html, "#taxon-name-errors > p") == 2
      assert count(html, "#taxon-name-errors > p .ph-warning-circle") == 2
      assert text(html, "#taxon-name-errors") =~ "can't be blank"
      assert text(html, "#taxon-name-errors") =~ "is too short"
    end

    test "renders no help or error elements when there are none" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <FormComponents.field label="Name" for="taxon-name">
          <input id="taxon-name" />
        </FormComponents.field>
        """)

      assert count(html, "#taxon-name-help") == 0
      assert count(html, "#taxon-name-errors") == 0
    end

    test "marks a required field for sight and for screen readers" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <FormComponents.field label="Name" for="n" required><input id="n" /></FormComponents.field>
        """)

      assert count(html, ~s(label [aria-hidden="true"])) == 1
      assert text(html, "label .sr-only") == "(required)"
    end

    test "keeps a polite live region beside the control and says Saved in it" do
      assigns = %{}

      unsaved =
        rendered_to_string(~H"""
        <FormComponents.field label="Name" for="n"><input id="n" /></FormComponents.field>
        """)

      saved =
        rendered_to_string(~H"""
        <FormComponents.field label="Name" for="n" saved><input id="n" /></FormComponents.field>
        """)

      # The region exists before saving, so the announcement is heard
      assert count(unsaved, ~s([aria-live="polite"])) == 1
      assert text(unsaved, ~s([aria-live="polite"])) == ""
      assert text(saved, ~s([aria-live="polite"])) == "Saved"
    end

    test "the row layout puts help and errors in the control's column, not under the label" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <FormComponents.field label="Name" for="n" layout={:row} help="Help" errors={["Bad"]}>
          <input id="n" />
        </FormComponents.field>
        """)

      assert attr(html, "[data-layout]", "data-layout") == ["row"]
      assert count(html, "[data-part=control] input#n") == 1
      assert count(html, "[data-part=control] #n-help") == 1
      assert count(html, "[data-part=control] #n-errors") == 1
      assert count(html, "[data-part=control] label") == 0
    end

    test "stacks by default" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <FormComponents.field label="Name" for="n"><input id="n" /></FormComponents.field>
        """)

      assert attr(html, "[data-layout]", "data-layout") == ["stacked"]
    end
  end

  describe "search_field/1" do
    test "a labelled search input with the icon, debounce and the caller's attributes" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <FormComponents.search_field
          id="gall-search"
          name="q"
          value=""
          label="Search Galls"
          placeholder="Name or Host"
          phx-change="search"
        />
        """)

      input = "input#gall-search"
      assert attr(html, input, "type") == ["search"]
      assert attr(html, input, "name") == ["q"]
      assert attr(html, input, "aria-label") == ["Search Galls"]
      assert attr(html, input, "placeholder") == ["Name or Host"]
      assert attr(html, input, "phx-debounce") == ["300"]
      assert attr(html, input, "phx-change") == ["search"]
      assert count(html, ".ph-magnifying-glass") == 1
    end

    test "shows the shortcut hint only while the field is empty" do
      assigns = %{}

      empty =
        rendered_to_string(~H"""
        <FormComponents.search_field name="q" label="Search" shortcut="/" />
        """)

      filled =
        rendered_to_string(~H"""
        <FormComponents.search_field name="q" value="andricus" label="Search" shortcut="/" />
        """)

      assert text(empty, "kbd") == "/"
      assert attr(empty, "input", "data-shortcut") == ["/"]
      assert attr(empty, "input", "aria-keyshortcuts") == ["/"]
      assert count(filled, "kbd") == 0
    end

    test "offers a clear button only when on_clear is given and there is a value" do
      assigns = %{clear: JS.push("clear_search")}

      filled =
        rendered_to_string(~H"""
        <FormComponents.search_field name="q" value="andricus" label="Search" on_clear={@clear} />
        """)

      empty =
        rendered_to_string(~H"""
        <FormComponents.search_field name="q" value="" label="Search" on_clear={@clear} />
        """)

      no_handler =
        rendered_to_string(~H"""
        <FormComponents.search_field name="q" value="andricus" label="Search" />
        """)

      assert count(filled, ~s(button[aria-label="Clear search"][type="button"])) == 1
      assert [click] = attr(filled, ~s(button[aria-label="Clear search"]), "phx-click")
      assert click =~ "clear_search"
      assert count(empty, "button") == 0
      assert count(no_handler, "button") == 0
    end
  end

  describe "facet_group/1" do
    defp parts(n, opts \\ []) do
      selected = Keyword.get(opts, :selected, [])

      for i <- 1..n do
        %{value: "p#{i}", label: "Part #{i}", count: 10 - i, selected: "p#{i}" in selected}
      end
    end

    test "a fieldset with its legend, one checkbox per option, named for a list" do
      assigns = %{options: parts(3, selected: ["p2"])}

      html =
        rendered_to_string(~H"""
        <FormComponents.facet_group id="facet-part" title="Plant part" name="lo" options={@options} />
        """)

      assert text(html, "fieldset#facet-part > legend") == "Plant part"
      assert count(html, ~s(input[type="checkbox"][name="lo[]"])) == 3
      assert attr(html, ~s(input[type="checkbox"]), "value") == ["p1", "p2", "p3"]
      assert attr(html, ~s(input[type="checkbox"][checked]), "value") == ["p2"]
      # Clearing every box still sends the param, so the server sees the change
      assert attr(html, ~s(input[type="hidden"][name="lo[]"]), "value") == [""]
      # Each option's label holds its input, its text and its count
      assert count(html, "label input[type=checkbox]") == 3
      assert text(html, "label:nth-of-type(1) [data-part=count]") == "9"
    end

    test "single choice uses radios named for one value" do
      assigns = %{options: parts(2, selected: ["p1"])}

      html =
        rendered_to_string(~H"""
        <FormComponents.facet_group
          id="facet-shape"
          title="Shape"
          name="sh"
          options={@options}
          multiple={false}
        />
        """)

      assert count(html, ~s(input[type="radio"][name="sh"])) == 2
      assert attr(html, ~s(input[type="radio"][checked]), "value") == ["p1"]
      assert count(html, ~s(input[type="checkbox"])) == 0
      assert count(html, ~s(input[type="hidden"])) == 0
    end

    test "options with no results stay visible, dimmed and selectable" do
      assigns = %{
        options: [
          %{value: "leaf", label: "leaf", count: 41, selected: false},
          %{value: "bud", label: "bud", count: 0, selected: true}
        ]
      }

      html =
        rendered_to_string(~H"""
        <FormComponents.facet_group id="f" title="Plant part" name="lo" options={@options} />
        """)

      assert count(html, ~s(input[value="bud"])) == 1
      assert count(html, ~s(input[value="bud"][disabled])) == 0
      assert attr(html, ~s(input[value="bud"]), "checked") != [nil]
      assert count(html, ~s([data-zero] input[value="bud"])) == 1
      assert count(html, ~s([data-zero] input[value="leaf"])) == 0
      assert text(html, ~s([data-zero] [data-part=count])) == "0"
    end

    test "counts use thousands separators" do
      assigns = %{options: [%{value: "a", label: "a", count: 3976, selected: false}]}

      html =
        rendered_to_string(~H"""
        <FormComponents.facet_group id="f" title="T" name="t" options={@options} />
        """)

      assert text(html, "[data-part=count]") == "3,976"
    end

    test "hides options past the limit behind a Show N more toggle, never a selected one" do
      assigns = %{options: parts(6, selected: ["p5"])}

      html =
        rendered_to_string(~H"""
        <FormComponents.facet_group
          id="facet-part"
          title="Plant part"
          name="lo"
          options={@options}
          limit={3}
        />
        """)

      # p4 and p6 are hidden; p5 is past the limit but selected
      assert attr(html, "[data-overflow] input", "value") == ["p4", "p6"]
      assert count(html, "[data-overflow].hidden") == 2

      button = "button#facet-part-more"
      assert text(html, button) =~ "Show 2 more"
      assert attr(html, button, "aria-expanded") == ["false"]
      assert [click] = attr(html, button, "phx-click")
      assert click =~ "#facet-part [data-overflow]"
      assert click =~ "toggle_class"
    end

    test "no toggle when every option fits" do
      assigns = %{options: parts(3)}

      html =
        rendered_to_string(~H"""
        <FormComponents.facet_group id="f" title="T" name="t" options={@options} />
        """)

      assert count(html, "[data-overflow]") == 0
      assert count(html, "button") == 0
    end

    test "italic labels for scientific names" do
      assigns = %{options: [%{value: "1", label: "Quercus alba", count: 4, selected: false}]}

      html =
        rendered_to_string(~H"""
        <FormComponents.facet_group id="f" title="Host" name="h" options={@options} italic />
        """)

      assert text(html, "label .italic") == "Quercus alba"
    end

    test "sits inside the caller's form without a phx-change of its own" do
      assigns = %{options: parts(2)}

      html =
        rendered_to_string(~H"""
        <form phx-change="change_filter">
          <FormComponents.facet_group id="f" title="T" name="t" options={@options} />
        </form>
        """)

      assert count(html, "[phx-change]") == 1
      assert count(html, "form [phx-change]") == 0
    end
  end

  describe "filter_select" do
    defp filter(attrs) do
      assigns = Map.merge(%{value: nil, counts: %{}}, attrs)

      rendered_to_string(~H"""
      <FormComponents.filter_select
        id="filter-season"
        name="value"
        label="Season"
        prompt="Any"
        options={[{"Spring", "Spring"}, {"Fall", "Fall"}]}
        value={@value}
        counts={@counts}
        phx-change="change_filter"
        phx-value-filter="season"
      />
      """)
    end

    test "is its own form, carrying the page's change event and values" do
      html = filter(%{})
      assert count(html, ~s(form[phx-change="change_filter"][phx-value-filter="season"])) == 1
      assert count(html, ~s(form select#filter-season[name="value"])) == 1
      assert text(html, ~s(label[for="filter-season"])) == "Season"
    end

    test "offers the prompt as an empty choice, then each option" do
      html = filter(%{})
      assert attr(html, "option", "value") == ["", "Spring", "Fall"]
      assert text(html, ~s(option[value=""])) == "Any"
    end

    test "while unset, each option shows how many results it would leave" do
      html = filter(%{counts: %{"Spring" => 12}})
      assert text(html, ~s(option[value="Spring"])) == "Spring (12)"
      assert text(html, ~s(option[value="Fall"])) == "Fall"
    end

    test "once set, the choice is selected, marked, and counts are hidden" do
      html = filter(%{value: "Fall", counts: %{"Spring" => 12, "Fall" => 3}})
      assert count(html, ~s(option[value="Fall"][selected])) == 1
      assert text(html, ~s(option[value="Spring"])) == "Spring"
      assert count(html, "select[data-set]") == 1
    end

    test "matches a value given as a number against string options" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <FormComponents.filter_select
          id="filter-family"
          name="value"
          label="Family"
          prompt="Any Family"
          options={[{"Cynipidae", 30}]}
          value={30}
        />
        """)

      assert count(html, ~s(option[value="30"][selected])) == 1
    end
  end
end
