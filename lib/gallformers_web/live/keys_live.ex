defmodule GallformersWeb.KeysLive do
  @moduledoc """
  LiveView for the identification keys index page.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Keys

  @impl true
  def mount(_params, _session, socket) do
    keys = Keys.list_keys()

    {:ok,
     assign(socket,
       page_title: "Identification Keys",
       page_description: "Dichotomous identification keys for gall-associated organisms.",
       page_url: "/keys",
       page_image: nil,
       page_json_ld: nil,
       keys: keys
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-4xl">
        <h1 class="text-3xl font-bold text-gf-maroon mb-4">Identification Keys</h1>

        <p class="text-gray-700 mb-6">
          Dichotomous identification keys for parasitoids, inquilines, and other organisms
          associated with galls.
        </p>

        <%= if @keys == [] do %>
          <div class="bg-gray-50 rounded-lg p-8 text-center">
            <p class="text-gray-600">No keys available yet.</p>
          </div>
        <% else %>
          <div class="space-y-6">
            <article
              :for={key <- @keys}
              class="bg-white rounded-lg shadow-md p-6 hover:shadow-lg transition-shadow"
            >
              <h2 class="text-xl font-semibold mb-2">
                <.link
                  navigate={~p"/keys/#{key.slug}"}
                  class="text-gf-maroon hover:underline"
                >
                  {key.title}
                </.link>
              </h2>
              <p :if={key.subtitle} class="text-gf-autumn text-sm mb-2">{key.subtitle}</p>
              <p :if={key.description} class="text-gray-600">
                {String.slice(key.description || "", 0, 200)}{if String.length(key.description || "") >
                                                                   200,
                                                                 do: "..."}
              </p>
              <div :if={key.authors != []} class="text-sm text-gray-500 mt-3">
                By {Enum.join(key.authors, ", ")}
              </div>
            </article>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
