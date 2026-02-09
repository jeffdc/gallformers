defmodule GallformersWeb.KeyLive do
  @moduledoc """
  LiveView for displaying an interactive dichotomous identification key.

  Renders all couplets with interactive navigation. Users click leads to
  follow the key, with their path highlighted and unvisited couplets dimmed.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Keys

  import GallformersWeb.KeyComponents

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Keys.get_key(slug) do
      {:ok, key} ->
        {:ok,
         assign(socket,
           page_title: key.title,
           page_description: key.description || "Dichotomous identification key",
           page_url: "/keys/#{slug}",
           page_image: nil,
           page_json_ld: nil,
           key: key,
           path: [],
           active_couplet: "1",
           terminal: nil,
           error: nil
         )}

      {:error, :not_found} ->
        {:ok,
         assign(socket,
           page_title: "Key Not Found",
           page_description: "The requested identification key was not found.",
           page_url: nil,
           page_image: nil,
           page_json_ld: nil,
           key: nil,
           path: [],
           active_couplet: nil,
           terminal: nil,
           error: "Key Not Found"
         )}
    end
  end

  @impl true
  def handle_event("select_lead", %{"couplet" => couplet_num, "lead" => lead_idx_str}, socket) do
    lead_index = String.to_integer(lead_idx_str)
    key = socket.assigns.key
    couplet = key.couplets[couplet_num]
    lead = Enum.at(couplet.leads, lead_index)

    # Build label for path tracker
    label = lead.destination[:label]
    path_entry = {couplet_num, lead_index, label}

    # Truncate path if re-selecting from a visited couplet
    path = truncate_path_to(socket.assigns.path, couplet_num) ++ [path_entry]

    case lead.destination.type do
      "couplet" ->
        {:noreply,
         socket
         |> assign(path: path, active_couplet: lead.destination.number, terminal: nil)
         |> push_event("scroll_to_couplet", %{id: "couplet-#{lead.destination.number}"})}

      "taxon" ->
        {:noreply,
         assign(socket,
           path: path,
           active_couplet: nil,
           terminal: lead.destination
         )}
    end
  end

  def handle_event("jump_to", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    # Truncate path to before this step — user wants to go back and re-choose
    {couplet_num, _lead_index, _label} = Enum.at(socket.assigns.path, index)
    path = Enum.take(socket.assigns.path, index)

    {:noreply,
     socket
     |> assign(path: path, active_couplet: couplet_num, terminal: nil)
     |> push_event("scroll_to_couplet", %{id: "couplet-#{couplet_num}"})}
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     socket
     |> assign(path: [], active_couplet: "1", terminal: nil)
     |> push_event("scroll_to_couplet", %{id: "couplet-1"})}
  end

  # Truncate path to just before the given couplet number.
  # This handles re-clicking from a previously visited couplet.
  defp truncate_path_to(path, couplet_num) do
    case Enum.find_index(path, fn {num, _idx, _label} -> num == couplet_num end) do
      nil -> path
      index -> Enum.take(path, index)
    end
  end

  defp couplet_state(number, active_couplet, path) do
    cond do
      number == active_couplet -> :active
      Enum.any?(path, fn {num, _idx, _label} -> num == number end) -> :visited
      true -> :unvisited
    end
  end

  defp chosen_lead_for(number, path) do
    case Enum.find(path, fn {num, _idx, _label} -> num == number end) do
      {_num, lead_index, _label} -> lead_index
      nil -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <%= if @error do %>
        <div class="mx-auto max-w-4xl">
          <div class="bg-gray-50 rounded-lg p-8 text-center">
            <h1 class="text-2xl font-bold text-gray-700 mb-2">{@error}</h1>
            <p class="text-gray-600 mb-4">The requested identification key could not be found.</p>
            <.link href={~p"/keys"} class="hover:underline">
              Browse all keys
            </.link>
          </div>
        </div>
      <% else %>
        <div id="key-display" phx-hook="ScrollToCouplet">
          <%!-- Header --%>
          <div class="mx-auto max-w-4xl mb-6">
            <div class="mb-4">
              <.link href={~p"/keys"} class="hover:underline inline-flex items-center gap-1 text-sm">
                ← Back to Keys
              </.link>
            </div>

            <h1 class="text-3xl font-bold text-gf-maroon">{@key.title}</h1>
            <p :if={@key.subtitle} class="text-xl text-gf-autumn mt-1">{@key.subtitle}</p>

            <div :if={@key.authors != []} class="text-gray-600 mt-2">
              By {Enum.join(@key.authors, ", ")}
            </div>

            <p :if={@key.citation} class="text-sm text-gray-500 mt-2">
              <%= if @key.citation_url do %>
                <a
                  href={@key.citation_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="hover:underline"
                >
                  {@key.citation}
                </a>
              <% else %>
                {@key.citation}
              <% end %>
            </p>

            <p :if={@key.description} class="text-gray-700 mt-4">{@key.description}</p>
          </div>

          <%!-- Path tracker --%>
          <.path_tracker path={@path} terminal={@terminal} />

          <%!-- All couplets --%>
          <div class="mx-auto max-w-4xl mt-6 space-y-4">
            <.couplet
              :for={number <- Keys.couplet_numbers(@key)}
              number={number}
              couplet={@key.couplets[number]}
              key_slug={@key.slug}
              state={couplet_state(number, @active_couplet, @path)}
              chosen_lead_index={chosen_lead_for(number, @path)}
            />
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
