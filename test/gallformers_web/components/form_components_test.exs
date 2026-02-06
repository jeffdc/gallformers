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

  describe "cascade_delete_modal/1" do
    test "renders modal with impact summary", %{conn: conn} do
      {:ok, _view, html} = live_isolated(conn, CascadeDeleteTestLive)

      # Check header
      assert html =~ "Delete TestFamily?"

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
