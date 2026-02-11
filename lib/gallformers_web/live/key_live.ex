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
  def handle_params(params, _uri, socket) do
    case params["path"] do
      nil ->
        {:noreply, socket}

      path_string ->
        if socket.assigns.key do
          {:noreply, replay_path(socket, path_string)}
        else
          {:noreply, socket}
        end
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

  def handle_event("copy_path", _params, socket) do
    %{key: key, path: path, terminal: terminal} = socket.assigns

    steps =
      Enum.map(path, fn {couplet_num, lead_index, _label} ->
        lead = Enum.at(key.couplets[couplet_num].leads, lead_index)
        "#{couplet_num}. #{lead.text}"
      end)

    result_lines =
      if terminal do
        species_ids = terminal[:species_ids] || []

        species_links =
          Enum.map(species_ids, fn id -> "  {{KEY_URL_ORIGIN}}/gall/#{id}" end)

        ["→ #{terminal.name}" | species_links]
      else
        []
      end

    path_param = encode_path(path)
    url_path = "/keys/#{key.slug}?path=#{path_param}"

    body = Enum.join(steps ++ result_lines, "\n")
    text = "#{key.title}\n{{KEY_URL}}\n\n#{body}"

    {:noreply, push_event(socket, "copy_to_clipboard", %{text: text, url_path: url_path})}
  end

  def handle_event("clipboard_copy_success", _params, socket) do
    {:noreply, put_flash(socket, :info, "Path copied to clipboard")}
  end

  def handle_event("clipboard_copy_error", _params, socket) do
    {:noreply, put_flash(socket, :error, "Failed to copy to clipboard")}
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

  defp encode_path(path) do
    Enum.map_join(path, ",", fn {couplet_num, lead_index, _label} ->
      "#{couplet_num}:#{lead_index}"
    end)
  end

  defp replay_path(socket, path_string) do
    key = socket.assigns.key

    choices =
      path_string
      |> String.split(",", trim: true)
      |> Enum.map(fn pair ->
        case String.split(pair, ":", parts: 2) do
          [couplet_num, lead_idx] -> {couplet_num, String.to_integer(lead_idx)}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    Enum.reduce(choices, socket, fn {couplet_num, lead_index}, acc ->
      replay_choice(key, acc, couplet_num, lead_index)
    end)
  end

  defp replay_choice(key, socket, couplet_num, lead_index) do
    with couplet when not is_nil(couplet) <- key.couplets[couplet_num],
         lead when not is_nil(lead) <- Enum.at(couplet.leads, lead_index) do
      label = lead.destination[:label]
      path_entry = {couplet_num, lead_index, label}
      path = socket.assigns.path ++ [path_entry]

      case lead.destination.type do
        "couplet" ->
          assign(socket, path: path, active_couplet: lead.destination.number, terminal: nil)

        "taxon" ->
          assign(socket, path: path, active_couplet: nil, terminal: lead.destination)
      end
    else
      _ -> socket
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
          <div class="mx-auto max-w-4xl mb-4">
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
          <div class="mx-auto max-w-4xl mt-4 space-y-3">
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
