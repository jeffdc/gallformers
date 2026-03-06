defmodule GallformersWeb.Admin.GallRangeLive do
  @moduledoc """
  Admin triage page for gall range confirmation.

  Shows galls that need range review and allows bulk confirmation.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Galls

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Gall Range Review")
      |> assign(:show_all, false)
      |> assign(:selected_ids, MapSet.new())
      |> load_galls()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_show_all", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_all, !socket.assigns.show_all)
     |> assign(:selected_ids, MapSet.new())
     |> load_galls()}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id_str}, socket) do
    case Integer.parse(id_str) do
      {id, ""} ->
        selected = socket.assigns.selected_ids

        new_selected =
          if MapSet.member?(selected, id),
            do: MapSet.delete(selected, id),
            else: MapSet.put(selected, id)

        {:noreply, assign(socket, :selected_ids, new_selected)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    all_ids = MapSet.new(socket.assigns.galls, & &1.id)
    {:noreply, assign(socket, :selected_ids, all_ids)}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  @impl true
  def handle_event("confirm_selected", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)

    if ids != [] do
      {count, _} = Galls.bulk_confirm_gall_ranges(ids)

      socket =
        socket
        |> assign(:selected_ids, MapSet.new())
        |> load_galls()
        |> put_flash(:info, "Confirmed range for #{count} gall(s)")

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "No galls selected")}
    end
  end

  defp load_galls(socket) do
    galls = Galls.list_galls_for_range_review(unconfirmed_only: !socket.assigns.show_all)
    assign(socket, :galls, galls)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <div class="max-w-7xl mx-auto">
        <div class="mb-4">
          <.link navigate={~p"/admin"} class="hover:underline text-sm">
            <.icon name="ph-arrow-left" class="h-4 w-4 inline" /> Back to Admin
          </.link>
        </div>

        <div class="bg-white border border-gray-200 rounded shadow-sm">
          <div class="px-4 py-3 border-b border-gray-200 bg-gray-50 flex items-center justify-between">
            <h4 class="text-lg font-semibold text-gf-maroon">Gall Range Review</h4>
            <div class="flex items-center gap-4">
              <label class="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={@show_all}
                  phx-click="toggle_show_all"
                  class="rounded border-gray-300"
                /> Show all galls
              </label>
              <span class="text-sm text-gray-500">
                {length(@galls)} gall(s)
              </span>
            </div>
          </div>

          <div class="p-4">
            <p class="text-sm text-gray-600 mb-4">
              Galls whose range has not been confirmed are listed below. Click a gall name to
              curate its range, or select multiple galls and confirm them in bulk.
            </p>

            <%!-- Bulk actions --%>
            <div :if={MapSet.size(@selected_ids) > 0} class="mb-4 flex items-center gap-3">
              <button
                type="button"
                phx-click="confirm_selected"
                class="gf-btn gf-btn-primary text-sm"
              >
                Confirm Selected ({MapSet.size(@selected_ids)})
              </button>
              <button
                type="button"
                phx-click="deselect_all"
                class="text-sm text-gray-600 hover:underline"
              >
                Clear selection
              </button>
            </div>

            <%!-- Table --%>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-gray-200 text-left">
                    <th class="pb-2 pr-4 w-8">
                      <input
                        type="checkbox"
                        checked={MapSet.size(@selected_ids) == length(@galls) and length(@galls) > 0}
                        phx-click={
                          if MapSet.size(@selected_ids) == length(@galls),
                            do: "deselect_all",
                            else: "select_all"
                        }
                        class="rounded border-gray-300"
                      />
                    </th>
                    <th class="pb-2 pr-4">Gall</th>
                    <th class="pb-2 pr-4 text-center">Hosts</th>
                    <th class="pb-2 pr-4 text-center">Range Places</th>
                    <th class="pb-2 pr-4 text-center">Status</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={gall <- @galls} class="border-b border-gray-100 hover:bg-gray-50">
                    <td class="py-2 pr-4">
                      <input
                        type="checkbox"
                        checked={MapSet.member?(@selected_ids, gall.id)}
                        phx-click="toggle_select"
                        phx-value-id={gall.id}
                        class="rounded border-gray-300"
                      />
                    </td>
                    <td class="py-2 pr-4">
                      <.link navigate={~p"/admin/gallhost?id=#{gall.id}"} class="hover:underline">
                        <.taxon_name name={gall.name} />
                      </.link>
                      <.badge :if={gall.undescribed} variant="warning">
                        undescribed
                      </.badge>
                    </td>
                    <td class="py-2 pr-4 text-center text-gray-600">{gall.host_count}</td>
                    <td class="py-2 pr-4 text-center text-gray-600">{gall.range_count}</td>
                    <td class="py-2 pr-4 text-center">
                      <.badge :if={gall.range_confirmed} variant="success">Confirmed</.badge>
                      <.badge :if={!gall.range_confirmed} variant="warning">Needs Review</.badge>
                    </td>
                  </tr>
                  <tr :if={@galls == []}>
                    <td colspan="5" class="py-8 text-center text-gray-500">
                      {if @show_all, do: "No galls found", else: "All gall ranges confirmed!"}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
