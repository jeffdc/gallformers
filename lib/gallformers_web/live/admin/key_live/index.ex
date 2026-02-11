defmodule GallformersWeb.Admin.KeyLive.Index do
  @moduledoc """
  Admin index page for identification keys.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Keys

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:current_user, session["current_user"])
      |> assign(:page_title, "Keys")
      |> load_keys()

    {:ok, socket}
  end

  defp load_keys(socket) do
    keys =
      Keys.list_keys()
      |> Enum.map(fn key ->
        # Get couplet count from the full key
        {:ok, full_key} = Keys.get_key(key.slug)
        Map.put(key, :couplet_count, map_size(full_key.couplets))
      end)

    assign(socket, :keys, keys)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    key = Keys.get_key!(String.to_integer(id))

    case Keys.delete_key(key) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Key deleted successfully")
         |> load_keys()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete key")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <div class="max-w-7xl mx-auto">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-xl font-bold text-gf-maroon">Identification Keys</h2>
          <.link navigate={~p"/admin/keys/new"} class="gf-btn gf-btn-primary">
            New Key
          </.link>
        </div>

        <div class="bg-white rounded-lg border border-gray-200 overflow-hidden">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-cadet-blue text-white">
              <tr>
                <th class="px-4 py-2 text-left text-sm font-semibold">Title</th>
                <th class="px-4 py-2 text-left text-sm font-semibold">Slug</th>
                <th class="px-4 py-2 text-left text-sm font-semibold">Version</th>
                <th class="px-4 py-2 text-center text-sm font-semibold">Couplets</th>
                <th class="px-4 py-2 text-right text-sm font-semibold">Actions</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200">
              <%= if @keys == [] do %>
                <tr>
                  <td colspan="5" class="px-4 py-8 text-center text-gray-500">
                    No keys yet. Create one to get started.
                  </td>
                </tr>
              <% else %>
                <tr :for={key <- @keys} class="hover:bg-gray-50">
                  <td class="px-4 py-2">
                    <.link
                      navigate={~p"/admin/keys/#{key.id}"}
                      class="text-gf-maroon hover:underline font-medium"
                    >
                      {key.title}
                    </.link>
                    <p :if={key.subtitle} class="text-sm text-gray-500">{key.subtitle}</p>
                  </td>
                  <td class="px-4 py-2 text-sm text-gray-600 font-mono">{key.slug}</td>
                  <td class="px-4 py-2 text-sm text-gray-600">{key.version}</td>
                  <td class="px-4 py-2 text-center text-sm text-gray-600">{key.couplet_count}</td>
                  <td class="text-right">
                    <.table_actions>
                      <.action_button
                        icon="ph-pencil-simple"
                        label="Edit"
                        navigate={~p"/admin/keys/#{key.id}"}
                        variant="primary"
                      />
                      <.action_button
                        icon="ph-arrow-square-out"
                        label="View"
                        href={~p"/keys/#{key.slug}"}
                      />
                      <.action_button
                        icon="ph-trash"
                        label="Delete"
                        variant="danger"
                        phx-click="delete"
                        phx-value-id={key.id}
                        confirm="Are you sure you want to delete this key?"
                      />
                    </.table_actions>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <p class="mt-2 text-sm text-gray-500">{length(@keys)} key(s)</p>
      </div>
    </Layouts.admin>
    """
  end
end
