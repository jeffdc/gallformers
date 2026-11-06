defmodule GallformersWeb.KeyLive do
  @moduledoc """
  An interactive dichotomous key (design system, matter bc0d): every
  couplet as a `key_couplet`, the path as a `key_path` (a bar on narrow
  screens, a panel beside the key on wide ones). Choosing a lead follows
  the key; `?path=1:0,2:3` replays a path (couplet:lead index). A missing
  key is a 404.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog
  alias Gallformers.ContentImages
  alias Gallformers.Keys
  alias Gallformers.Keys.Key

  import GallformersWeb.KeyComponents

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Keys.get_key(slug) do
      {:ok, key} ->
        image_url_map = build_content_image_url_map(key)

        {:ok,
         assign(socket,
           page_title: key.title,
           page_description: key.description || "Dichotomous identification key",
           page_url: "/keys/#{slug}",
           page_image: nil,
           page_json_ld: nil,
           key: key,
           image_url_map: image_url_map,
           gall_names: gall_names(key),
           pdf_urls: Keys.pdf_urls(key),
           key_has_images: Key.key_has_images?(key),
           path: [],
           active_couplet: "1",
           terminal: nil
         )}

      {:error, :not_found} ->
        raise GallformersWeb.NotFoundError, "No key #{slug}"
    end
  end

  @impl true
  def handle_params(%{"path" => path_string}, _uri, %{assigns: %{key: key}} = socket)
      when not is_nil(key) and is_binary(path_string) do
    socket = replay_path(socket, path_string)

    case scroll_target(socket) do
      nil -> {:noreply, socket}
      id -> {:noreply, push_event(socket, "scroll_to_couplet", %{id: id})}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # After replay, scroll to the active couplet if any, else to the last
  # couplet visited (when a terminal taxon was reached).
  defp scroll_target(%{assigns: %{active_couplet: number}}) when is_binary(number),
    do: "couplet-#{number}"

  defp scroll_target(%{assigns: %{path: [_ | _] = path}}) do
    {couplet_num, _idx, _label} = List.last(path)
    "couplet-#{couplet_num}"
  end

  defp scroll_target(_), do: nil

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
      Enum.map(path, fn {couplet_num, lead_index, _label} = step ->
        lead = Enum.at(key.couplets[couplet_num].leads, lead_index)
        "#{step_name(step)}. #{lead.text}"
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

    url_path = path_link(key, path)

    body = Enum.join(steps ++ result_lines, "\n")
    text = "#{key.title}\n{{KEY_URL}}\n\n#{body}"

    {:noreply, push_event(socket, "copy_to_clipboard", %{text: text, url_path: url_path})}
  end

  def handle_event("clipboard_copy_success", _params, socket) do
    {:noreply, put_flash(socket, :info, "Copied")}
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

  def handle_event("back", _params, socket) do
    case socket.assigns.path do
      [] ->
        {:noreply, socket}

      path ->
        {couplet_num, _lead_index, _label} = List.last(path)

        {:noreply,
         socket
         |> assign(path: Enum.drop(path, -1), active_couplet: couplet_num, terminal: nil)
         |> push_event("scroll_to_couplet", %{id: "couplet-#{couplet_num}"})}
    end
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

  defp path_link(key, path), do: "/keys/#{key.slug}?path=#{encode_path(path)}"

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

  # The names of the Galls the key's results point to, for results that
  # cover several Galls.
  defp gall_names(key) do
    key.couplets
    |> Enum.flat_map(fn {_number, couplet} ->
      Enum.flat_map(couplet.leads, &(&1.destination[:species_ids] || []))
    end)
    |> Catalog.list_galls_by_id()
    |> Map.new(&{&1.id, &1.name})
  end

  # Collect all content_image_ids from couplet images and resolve to CDN URLs
  defp build_content_image_url_map(key) do
    key.couplets
    |> Enum.flat_map(fn {_number, couplet} ->
      Enum.flat_map(couplet.leads, fn lead ->
        (lead.images || [])
        |> Enum.map(& &1[:content_image_id])
        |> Enum.reject(&is_nil/1)
      end)
    end)
    |> Enum.uniq()
    |> ContentImages.build_image_url_map()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="key-display" phx-hook="ScrollToCouplet" class="flex flex-col gap-section">
        <.page_header>
          <:crumb navigate={~p"/keys"}>Keys</:crumb>
          <:title>{@key.title}</:title>
          <:meta :if={@key.subtitle} label="Covers">{@key.subtitle}</:meta>
          <:meta :if={@key.authors != []} label="By">{Enum.join(@key.authors, ", ")}</:meta>
          <:meta label="Couplets">{length(Keys.couplet_numbers(@key))}</:meta>
          <:meta :if={@key.citation} label="Source">
            <.link
              :if={@key.citation_url}
              href={@key.citation_url}
              target="_blank"
              rel="noopener noreferrer"
            >
              {@key.citation}
            </.link>
            <span :if={!@key.citation_url}>{@key.citation}</span>
          </:meta>
          <:action>
            <.button
              href={@pdf_urls.text_only}
              target="_blank"
              rel="noopener noreferrer"
              variant="secondary"
              size="sm"
              icon="ph-file-pdf"
            >
              PDF
            </.button>
          </:action>
          <:action :if={@key_has_images}>
            <.button
              href={@pdf_urls.with_images}
              target="_blank"
              rel="noopener noreferrer"
              variant="secondary"
              size="sm"
              icon="ph-file-pdf"
            >
              PDF with images
            </.button>
          </:action>
          <:description :if={@key.description}>{@key.description}</:description>
        </.page_header>

        <div class="gf-with-rail max-w-7xl">
          <div class="min-w-0">
            <.key_path
              layout={:bar}
              key={@key}
              path={@path}
              terminal={@terminal}
              link={path_link(@key, @path)}
              gall_names={@gall_names}
              class="lg:hidden"
            />
            <ol class="mt-block flex flex-col gap-1 lg:mt-0">
              <.key_couplet
                :for={number <- Keys.couplet_numbers(@key)}
                number={number}
                couplet={@key.couplets[number]}
                key_slug={@key.slug}
                state={couplet_state(number, @active_couplet, @path)}
                chosen={chosen_lead_for(number, @path)}
                image_url_map={@image_url_map}
                gall_names={@gall_names}
              />
            </ol>
          </div>

          <.rail width={:narrow} class="max-lg:hidden lg:sticky lg:top-header lg:self-start lg:pt-2">
            <.key_path
              layout={:panel}
              key={@key}
              path={@path}
              terminal={@terminal}
              link={path_link(@key, @path)}
              gall_names={@gall_names}
            />
          </.rail>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
