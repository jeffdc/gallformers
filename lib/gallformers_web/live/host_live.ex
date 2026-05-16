defmodule GallformersWeb.HostLive do
  @moduledoc """
  LiveView for the host plant detail page.

  Displays detailed information about a host plant species including
  associated galls, images, range map, and sources.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Images
  alias Gallformers.Images.Image
  alias Gallformers.{Markdown, Places, Plants, Ranges, Sources, Species, Taxonomy}
  alias GallformersWeb.SEO

  @page_size 10
  @synonymy_page_size 10
  # Gallformers Notes source ID (same as V1)
  @gallformers_notes_source_id 58

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {host_id, ""} ->
        load_host(socket, host_id)

      _ ->
        {:ok,
         assign(socket,
           page_title: "Host Not Found",
           page_description: "The requested host plant was not found on Gallformers.",
           page_url: nil,
           page_image: nil,
           page_json_ld: nil,
           page_noindex: true,
           host: nil,
           selected_source: nil,
           error: "Invalid host ID"
         )}
    end
  end

  @impl true
  def handle_params(%{"source" => source_id_str}, _uri, socket) do
    with {source_id, ""} <- Integer.parse(source_id_str),
         source when not is_nil(source) <-
           Enum.find(socket.assigns[:sources] || [], fn s -> s.id == source_id end) do
      {:noreply, assign(socket, selected_source: source)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp load_host(socket, host_id) do
    case Plants.get_host(host_id) do
      nil ->
        {:ok,
         assign(socket,
           page_title: "Host Not Found",
           page_description: "The requested host plant was not found on Gallformers.",
           page_url: nil,
           page_image: nil,
           page_json_ld: nil,
           page_noindex: true,
           host: nil,
           selected_source: nil,
           error: "Host not found"
         )}

      host ->
        galls = Plants.get_galls_for_host(host_id) |> Enum.sort_by(& &1.name)
        images = Images.list_images_for_species(host_id) |> format_images()
        sources = Sources.get_sources_for_species(host_id)
        aliases = Species.get_aliases_for_species(host_id)
        taxonomy = get_taxonomy_info(host_id)
        range_data = Ranges.get_display_range_for_host(host_id)
        range = range_data.in_range
        inherited_range = range_data.inherited_range
        introduced_range = range_data.introduced_range
        range_bounds = Places.get_bounds_for_codes(range ++ inherited_range)

        # Check if Gallformers notes exist for this species
        gallformers_notes = Enum.find(sources, fn s -> s.id == @gallformers_notes_source_id end)
        has_gallformers_notes = gallformers_notes != nil

        # Build SEO data
        page_url = "/host/#{host_id}"

        page_description =
          "#{host.name} - A host plant species documented on Gallformers with #{length(galls)} associated galls."

        page_image =
          case images do
            [first | _] -> first.url
            [] -> nil
          end

        # Build JSON-LD structured data
        json_ld = build_host_json_ld(host, page_url, page_description, page_image)

        {:ok,
         assign(socket,
           page_title: host.name,
           page_description: page_description,
           page_url: page_url,
           page_image: page_image,
           page_json_ld: json_ld,
           page_noindex: false,
           host: Map.merge(host, %{galls: galls, aliases: aliases}),
           images: images,
           sources: sources,
           taxonomy: taxonomy,
           range: range,
           inherited_range: inherited_range,
           introduced_range: introduced_range,
           range_bounds: range_bounds,
           has_gallformers_notes: has_gallformers_notes,
           notes_alert_dismissed: false,
           current_page: 1,
           page_size: @page_size,
           sort_by: :name,
           sort_dir: :asc,
           selected_source: nil,
           modal_font_size: :base,
           synonymy_page: 1,
           synonymy_page_size: @synonymy_page_size,
           error: nil
         )}
    end
  end

  defp build_host_json_ld(host, url, description, image) do
    json_ld = %{
      "@context" => "https://schema.org",
      "@type" => "Thing",
      "name" => host.name,
      "description" => description,
      "url" => SEO.base_url() <> url,
      "identifier" => host.name
    }

    json_ld = if image, do: Map.put(json_ld, "image", image), else: json_ld

    Jason.encode!(json_ld)
  end

  defp get_taxonomy_info(species_id) do
    Taxonomy.get_taxonomy_for_species(species_id)
  end

  defp format_images(images) do
    base_url = Image.base_url()

    Enum.map(images, fn img ->
      # Replace "original" with size name in the path
      small_path = String.replace(img.path, "original", "small")
      full_url = "#{base_url}/#{img.path}"

      Map.merge(img, %{
        url: full_url,
        src: full_url,
        small_url: "#{base_url}/#{small_path}",
        alt: "Host plant image"
      })
    end)
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    new_page = max(1, socket.assigns.current_page - 1)
    {:noreply, assign(socket, current_page: new_page)}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    total_pages = ceil(length(socket.assigns.host.galls) / socket.assigns.page_size)
    new_page = min(total_pages, socket.assigns.current_page + 1)
    {:noreply, assign(socket, current_page: new_page)}
  end

  @impl true
  def handle_event("dismiss_notes_alert", _params, socket) do
    {:noreply, assign(socket, notes_alert_dismissed: true)}
  end

  @impl true
  def handle_event("gallery_index_changed", _params, socket) do
    {:noreply, socket}
  end

  @valid_sort_fields ~w(name datacomplete)

  @impl true
  def handle_event("sort", %{"field" => field}, socket) when field in @valid_sort_fields do
    field = String.to_atom(field)

    {sort_by, sort_dir} =
      if socket.assigns.sort_by == field do
        # Toggle direction if same field
        new_dir = if socket.assigns.sort_dir == :asc, do: :desc, else: :asc
        {field, new_dir}
      else
        # New field, default to ascending
        {field, :asc}
      end

    {:noreply, assign(socket, sort_by: sort_by, sort_dir: sort_dir, current_page: 1)}
  end

  @impl true
  def handle_event("show_source_detail", %{"id" => id_str}, socket) do
    source_id = String.to_integer(id_str)
    source = Enum.find(socket.assigns.sources, fn s -> s.id == source_id end)
    {:noreply, assign(socket, selected_source: source)}
  end

  @impl true
  def handle_event("close_source_modal", _params, socket) do
    {:noreply, assign(socket, selected_source: nil, modal_font_size: :base)}
  end

  @impl true
  def handle_event("clipboard_copy_success", _params, socket) do
    {:noreply, put_flash(socket, :info, "Copied to clipboard")}
  end

  @impl true
  def handle_event("clipboard_copy_error", _params, socket) do
    {:noreply, put_flash(socket, :error, "Failed to copy to clipboard")}
  end

  @font_sizes [:sm, :base, :lg, :xl]

  @impl true
  def handle_event("increase_font_size", _params, socket) do
    current = socket.assigns.modal_font_size
    current_idx = Enum.find_index(@font_sizes, &(&1 == current))
    new_size = Enum.at(@font_sizes, min(current_idx + 1, length(@font_sizes) - 1))
    {:noreply, assign(socket, modal_font_size: new_size)}
  end

  @impl true
  def handle_event("decrease_font_size", _params, socket) do
    current = socket.assigns.modal_font_size
    current_idx = Enum.find_index(@font_sizes, &(&1 == current))
    new_size = Enum.at(@font_sizes, max(current_idx - 1, 0))
    {:noreply, assign(socket, modal_font_size: new_size)}
  end

  @impl true
  def handle_event("synonymy_page", %{"page" => page}, socket) do
    synonyms = get_scientific_synonyms(socket.assigns.host.aliases)
    total = synonymy_total_pages(synonyms, socket.assigns.synonymy_page_size)
    page = max(1, min(page, total))
    {:noreply, assign(socket, synonymy_page: page)}
  end

  @impl true
  def handle_event("navigate_to_place", %{"code" => code}, socket) do
    {:noreply, push_navigate(socket, to: "/place/#{code}")}
  end

  defp sorted_galls(galls, sort_by, sort_dir) do
    sorted =
      case sort_by do
        :name -> Enum.sort_by(galls, & &1.name)
        :datacomplete -> Enum.sort_by(galls, & &1.datacomplete)
        _ -> galls
      end

    if sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp paginated_galls(galls, current_page, page_size) do
    galls
    |> Enum.drop((current_page - 1) * page_size)
    |> Enum.take(page_size)
  end

  defp total_pages(galls, page_size) do
    ceil(length(galls) / page_size)
  end

  defp prose_size_class(:sm), do: "prose-sm"
  defp prose_size_class(:base), do: "prose-base"
  defp prose_size_class(:lg), do: "prose-lg"
  defp prose_size_class(:xl), do: "prose-xl"

  # Filter aliases by type
  defp get_common_names(aliases) do
    aliases
    |> Enum.filter(&(&1.type == "common"))
    |> Enum.sort_by(& &1.name)
  end

  defp get_scientific_synonyms(aliases) do
    aliases
    |> Enum.filter(&(&1.type == "scientific"))
    |> Enum.sort_by(& &1.name)
  end

  defp paginated_synonyms(synonyms, page, page_size) do
    synonyms
    |> Enum.drop((page - 1) * page_size)
    |> Enum.take(page_size)
  end

  defp synonymy_total_pages(synonyms, page_size) do
    max(1, ceil(length(synonyms) / page_size))
  end

  attr :field, :atom, required: true
  attr :sort_by, :atom, required: true
  attr :sort_dir, :atom, required: true

  defp sort_indicator(assigns) do
    ~H"""
    <span :if={@sort_by == @field} class="text-gray-400 text-xs">
      {if @sort_dir == :asc, do: "▲", else: "▼"}
    </span>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <%= if @error do %>
        <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">{@error}</div>
      <% else %>
        <%= if @host do %>
          <%!-- Main grid: left column (header + galls), right column (map) --%>
          <div class="grid grid-cols-1 lg:grid-cols-5 gap-6">
            <%!-- Left column: header info + galls table --%>
            <div class="lg:col-span-2 space-y-3">
              <div class="flex items-start justify-between gap-4">
                <div class="flex items-center gap-2">
                  <h2 class="text-2xl font-bold">
                    <.link
                      href={"/id?h=#{URI.encode(@host.name)}"}
                      class="hover:underline"
                    >
                      <.taxon_name
                        name={@host.name}
                        genus_placeholder={@host[:genus_placeholder] == true}
                      />
                    </.link>
                  </h2>
                  <.link
                    :if={@current_user}
                    href={~p"/admin/hosts/#{@host.id}"}
                    class="text-gray-400 hover:text-gf-maroon"
                    title="Edit in admin"
                  >
                    <.icon name="ph-pencil-simple" class="h-5 w-5" />
                  </.link>
                </div>
                <.data_complete_badge
                  complete={@host.datacomplete}
                  complete_tooltip="All galls known to occur on this plant have been added to the database. However, sources and images may be incomplete."
                  incomplete_tooltip="We are still working on this species so data might be missing."
                />
              </div>

              <.taxonomy_breadcrumb
                :if={@taxonomy}
                family={@taxonomy.family}
                intermediates={@taxonomy.intermediates}
                genus={@taxonomy.genus}
                section={@taxonomy.section}
              />

              <p :if={@host.abundance_name}><strong>Abundance:</strong> {@host.abundance_name}</p>

              <%!-- Common Names --%>
              <% common_names = get_common_names(@host.aliases) %>
              <div :if={length(common_names) > 0}>
                <strong>Common Name(s):</strong>
                <span class="text-gray-700">
                  {common_names |> Enum.map(& &1.name) |> Enum.join(", ")}
                </span>
              </div>

              <%!-- Galls table --%>
              <div class="pt-2">
                <h3 class="font-semibold text-gray-800 mb-2">
                  Associated Galls ({length(@host.galls)})
                </h3>
                <%= if length(@host.galls) > 0 do %>
                  <div class="overflow-hidden rounded border border-gray-200">
                    <table class="gf-table gf-table-compact">
                      <thead>
                        <tr>
                          <th
                            class="sortable"
                            phx-click="sort"
                            phx-value-field="name"
                          >
                            <div class="flex items-center gap-1">
                              Gall
                              <.sort_indicator field={:name} sort_by={@sort_by} sort_dir={@sort_dir} />
                            </div>
                          </th>
                          <th
                            class="sortable w-24 text-center"
                            phx-click="sort"
                            phx-value-field="datacomplete"
                          >
                            <div class="flex items-center justify-center gap-1">
                              Complete
                              <.sort_indicator
                                field={:datacomplete}
                                sort_by={@sort_by}
                                sort_dir={@sort_dir}
                              />
                            </div>
                          </th>
                          <th :if={@current_user} class="w-10"></th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={
                          gall <-
                            paginated_galls(
                              sorted_galls(@host.galls, @sort_by, @sort_dir),
                              @current_page,
                              @page_size
                            )
                        }>
                          <td>
                            <.link
                              href={"/gall/#{gall.id}"}
                              class="hover:underline"
                            >
                              <.taxon_name name={gall.name} />
                            </.link>
                          </td>
                          <td class="text-center">
                            <%= if gall.datacomplete in [true, 1] do %>
                              <span class="text-green-600">
                                <.icon name="ph-check" class="size-5 inline-block" />
                              </span>
                            <% else %>
                              <span class="text-red-500">
                                <.icon name="ph-x" class="size-5 inline-block" />
                              </span>
                            <% end %>
                          </td>
                          <td :if={@current_user} class="text-center">
                            <.link
                              href={~p"/admin/gallhost?id=#{gall.id}"}
                              class="text-gray-400 hover:text-gf-maroon"
                              title="Edit gall-host mappings"
                            >
                              <.icon name="ph-pencil-simple" class="h-4 w-4" />
                            </.link>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                    <div
                      :if={total_pages(@host.galls, @page_size) > 1}
                      class="flex items-center justify-between px-3 py-1 bg-white border-t border-gray-200"
                    >
                      <div class="text-sm">
                        {(@current_page - 1) * @page_size + 1}-{min(
                          @current_page * @page_size,
                          length(@host.galls)
                        )} of {length(@host.galls)}
                      </div>
                      <div class="flex items-center gap-2">
                        <button
                          class="px-2 py-0.5 text-sm border rounded hover:bg-gray-100 disabled:opacity-50 disabled:cursor-not-allowed"
                          disabled={@current_page == 1}
                          phx-click="prev_page"
                        >
                          Previous
                        </button>
                        <span class="text-sm">
                          Page {@current_page} of {total_pages(@host.galls, @page_size)}
                        </span>
                        <button
                          class="px-2 py-0.5 text-sm border rounded hover:bg-gray-100 disabled:opacity-50 disabled:cursor-not-allowed"
                          disabled={@current_page == total_pages(@host.galls, @page_size)}
                          phx-click="next_page"
                        >
                          Next
                        </button>
                      </div>
                    </div>
                  </div>
                <% else %>
                  <p class="italic">No galls recorded for this host.</p>
                <% end %>
              </div>
            </div>

            <%!-- Right column: range map --%>
            <div class="lg:col-span-3 flex flex-col min-h-0">
              <h3 class="font-semibold text-gray-800 mb-2">Range</h3>
              <.range_map
                id="host-range-map"
                class="flex-1"
                in_range={@range}
                inherited_range={@inherited_range}
                introduced_range={@introduced_range}
                bounds={@range_bounds}
                navigable
              />
              <div :if={@inherited_range != [] or @introduced_range != []} class="mt-1">
                <.range_map_legend mode={:public} />
              </div>
            </div>
          </div>

          <%!-- Synonymy and photos row --%>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
            <%!-- Synonymy --%>
            <% synonyms = get_scientific_synonyms(@host.aliases) %>
            <div :if={length(synonyms) > 0}>
              <h3 class="font-semibold text-gray-800 mb-2">
                Synonymy ({length(synonyms)})
              </h3>
              <div class="bg-white rounded border border-gray-200 overflow-hidden">
                <table class="gf-table gf-table-compact">
                  <thead>
                    <tr>
                      <th>Name</th>
                      <th>Notes</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={s <- paginated_synonyms(synonyms, @synonymy_page, @synonymy_page_size)}>
                      <td><.taxon_name name={s.name} /></td>
                      <td class="text-gray-600">{s.description || "—"}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <.pagination
                :if={synonymy_total_pages(synonyms, @synonymy_page_size) > 1}
                page={@synonymy_page}
                total_pages={synonymy_total_pages(synonyms, @synonymy_page_size)}
                total_items={length(synonyms)}
                page_size={@synonymy_page_size}
                on_page_change={fn page -> JS.push("synonymy_page", value: %{page: page}) end}
                class="mt-4"
              />
            </div>

            <%!-- Photos (compact) --%>
            <div :if={length(@images) > 0}>
              <h3 class="font-semibold text-gray-800 mb-2">
                Photos ({length(@images)})
              </h3>
              <.image_gallery
                images={@images}
                id="host-images"
                species_id={@host.id}
                current_user={@current_user}
                no_image_src="/images/noimagehost.jpg"
              />
            </div>
          </div>

          <hr class="border-gray-200 my-4" />

          <div
            :if={@has_gallformers_notes && !@notes_alert_dismissed}
            class="flex items-center gap-3 p-3 mb-4 bg-white border border-blue-200 border-l-4 border-l-blue-400 rounded text-sm text-gray-700"
            role="alert"
          >
            <.icon name="ph-info" class="h-5 w-5 text-blue-500 shrink-0" />
            <p class="flex-1">
              Our ID Notes may contain important tips necessary for distinguishing this host
              from similar plants and/or important information about its taxonomy.
            </p>
            <button
              type="button"
              class="text-gray-400 hover:text-gray-600"
              phx-click="dismiss_notes_alert"
              aria-label="Dismiss"
            >
              <.icon name="ph-x" class="h-4 w-4" />
            </button>
          </div>

          <%= if length(@sources) > 0 do %>
            <div class="flex items-center gap-2 mb-2">
              <h3 class="font-semibold">Further Information ({length(@sources)})</h3>
              <.link
                :if={@current_user}
                href={~p"/admin/species-sources/add?species_id=#{@host.id}"}
                class="text-gray-400 hover:text-gf-maroon"
                title="Add source mapping"
              >
                <.icon name="ph-plus-circle" class="h-5 w-5" />
              </.link>
            </div>
            <div class="space-y-2">
              <div
                :for={source <- @sources}
                class={"p-3 rounded border bg-white #{if source.id == 58, do: "border-blue-200 border-l-4 border-l-blue-400", else: "border-gray-200"}"}
              >
                <div>
                  <.icon
                    :if={source.id == 58}
                    name="ph-info"
                    class="h-5 w-5 text-blue-500 inline-block align-text-bottom mr-1"
                  />
                  <.link
                    href={"/source/#{source.id}"}
                    class="font-medium hover:underline"
                  >
                    {source.title}
                  </.link>
                  {if source.author, do: " - #{source.author}"}
                  {if source.pubyear, do: " (#{source.pubyear})"}
                  <.link
                    :if={valid_url?(source.externallink)}
                    href={source.externallink}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="ml-2 text-gray-500 hover:text-gf-maroon"
                    title="View external source"
                  >
                    <.icon name="ph-arrow-square-out" class="h-4 w-4 inline-block align-text-bottom" />
                  </.link>
                  <button
                    id={"copy-source-link-#{source.id}"}
                    phx-hook="CopyToClipboard"
                    data-copy-text={"/host/#{@host.id}?source=#{source.id}"}
                    data-copy-url
                    class="ml-2 text-gray-500 hover:text-gf-maroon cursor-pointer"
                    title="Copy link to this description"
                  >
                    <.icon name="ph-link" class="h-4 w-4 inline-block align-text-bottom" />
                  </button>
                  <.link
                    :if={@current_user}
                    href={
                      ~p"/admin/species-sources/find?species_id=#{@host.id}&source_id=#{source.id}"
                    }
                    class="ml-2 text-gray-400 hover:text-gf-maroon"
                    title="Edit species-source mapping"
                  >
                    <.icon name="ph-pencil-simple" class="h-4 w-4 inline-block align-text-bottom" />
                  </.link>
                </div>
                <button
                  :if={source.description}
                  type="button"
                  phx-click="show_source_detail"
                  phx-value-id={source.id}
                  class="mt-1 text-left w-full group cursor-pointer"
                >
                  <div class="prose prose-sm max-w-none line-clamp-3 [&_p]:mb-0">
                    {Phoenix.HTML.raw(Markdown.render!(source.description))}
                  </div>
                  <span class="text-sm text-gf-maroon group-hover:underline">Read more...</span>
                </button>
                <p :if={source.license} class="mt-1 text-sm text-gray-500">
                  License:
                  <%= if valid_url?(source.licenselink) do %>
                    <.link
                      href={source.licenselink}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="hover:underline"
                    >
                      {source.license}
                    </.link>
                  <% else %>
                    {source.license}
                  <% end %>
                </p>
              </div>
            </div>
          <% else %>
            <p class="italic">No further information available for this species.</p>
          <% end %>

          <.see_also name={@host.name} type={:host} />

          <.record_metadata inserted_at={@host.inserted_at} updated_at={@host.updated_at} />
        <% else %>
          <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
            Host not found
          </div>
        <% end %>
      <% end %>

      <.modal
        :if={@selected_source}
        id="source-detail-modal"
        show={true}
        on_cancel={JS.push("close_source_modal")}
        class="max-w-3xl"
      >
        <:header>
          <div class="flex items-center justify-between w-full pr-8">
            <span>{@selected_source.title}</span>
            <div class="flex items-center gap-1 ml-4">
              <button
                type="button"
                phx-click="decrease_font_size"
                class="px-2 py-1 text-sm border border-gray-300 rounded hover:bg-gray-100 disabled:opacity-50"
                disabled={@modal_font_size == :sm}
                title="Decrease font size"
              >
                A-
              </button>
              <button
                type="button"
                phx-click="increase_font_size"
                class="px-2 py-1 text-sm border border-gray-300 rounded hover:bg-gray-100 disabled:opacity-50"
                disabled={@modal_font_size == :xl}
                title="Increase font size"
              >
                A+
              </button>
            </div>
          </div>
        </:header>
        <:body>
          <div class="space-y-4">
            <div class="text-sm text-gray-600">
              {if @selected_source.author, do: @selected_source.author}
              {if @selected_source.pubyear, do: " (#{@selected_source.pubyear})"}
            </div>
            <div
              :if={@selected_source.description}
              class={"prose #{prose_size_class(@modal_font_size)} max-w-none"}
            >
              {Phoenix.HTML.raw(Markdown.render!(@selected_source.description))}
            </div>
            <div :if={@selected_source.license} class="text-sm text-gray-500 pt-2 border-t">
              License:
              <%= if valid_url?(@selected_source.licenselink) do %>
                <.link
                  href={@selected_source.licenselink}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="hover:underline"
                >
                  {@selected_source.license}
                </.link>
              <% else %>
                {@selected_source.license}
              <% end %>
            </div>
          </div>
        </:body>
        <:footer>
          <div class="flex items-center justify-between w-full">
            <div class="flex items-center gap-4">
              <.link
                :if={valid_url?(@selected_source.externallink)}
                href={@selected_source.externallink}
                target="_blank"
                rel="noopener noreferrer"
                class="text-gf-maroon hover:underline"
              >
                View external link →
              </.link>
              <.link
                href={"/source/#{@selected_source.id}"}
                class="text-gf-maroon hover:underline"
              >
                View source page →
              </.link>
            </div>
            <button
              id="copy-source-link"
              phx-hook="CopyToClipboard"
              data-copy-text={"/host/#{@host.id}?source=#{@selected_source.id}"}
              data-copy-url
              class="flex items-center gap-1 text-sm text-gray-500 hover:text-gf-maroon cursor-pointer"
              title="Copy link to this description"
            >
              <.icon name="ph-copy" class="h-4 w-4" /> Copy link
            </button>
          </div>
        </:footer>
      </.modal>
    </Layouts.app>
    """
  end
end
