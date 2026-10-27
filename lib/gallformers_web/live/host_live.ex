defmodule GallformersWeb.HostLive do
  @moduledoc """
  LiveView for the host plant detail page.

  Displays a host plant from `Gallformers.Taxa.host_page/1` (its names and
  taxonomy) with the Galls on it (`Gallformers.Catalog.list_galls_for_hosts/1`),
  its images and its range map. Citations on plants were not migrated, so
  the page has no Sources (`803b`, decision 1).
  """
  use GallformersWeb, :live_view

  alias Gallformers.{Catalog, Images, Places, Ranges, Taxa}
  alias Gallformers.Images.Image
  alias Gallformers.Taxa.ReadModels.HostPage
  alias GallformersWeb.LineageBreadcrumb
  alias GallformersWeb.SEO

  @page_size 10
  @synonymy_page_size 10

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {host_id, ""} -> load_host(socket, host_id)
      _ -> {:ok, not_found(socket, "Invalid host ID")}
    end
  end

  defp not_found(socket, error) do
    assign(socket,
      page_title: "Host Not Found",
      page_description: "The requested host plant was not found on Gallformers.",
      page_url: nil,
      page_image: nil,
      page_json_ld: nil,
      page_noindex: true,
      host: nil,
      error: error
    )
  end

  defp load_host(socket, host_id) do
    case Taxa.host_page(host_id) do
      :not_found ->
        {:ok, not_found(socket, "Host not found")}

      {:ok, %HostPage{} = host} ->
        galls = Catalog.list_galls_for_hosts([host.id])
        images = host.id |> Images.list_images_for_taxon() |> format_images()
        range_data = Ranges.get_display_range_for_taxa([host.id])
        range = range_data.in_range
        inherited_range = range_data.inherited_range

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
           host: host,
           galls: galls,
           images: images,
           taxonomy: LineageBreadcrumb.from_lineage(host.lineage),
           range: range,
           inherited_range: inherited_range,
           introduced_range: range_data.introduced_range,
           range_bounds: Places.get_bounds_for_codes(range ++ inherited_range),
           current_page: 1,
           page_size: @page_size,
           sort_by: :name,
           sort_dir: :asc,
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
    total_pages = ceil(length(socket.assigns.galls) / socket.assigns.page_size)
    new_page = min(total_pages, socket.assigns.current_page + 1)
    {:noreply, assign(socket, current_page: new_page)}
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
  def handle_event("synonymy_page", %{"page" => page}, socket) do
    total = synonymy_total_pages(socket.assigns.host.synonyms, socket.assigns.synonymy_page_size)
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
                      <.taxon_name name={@host.name} />
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

              <p :if={@host.abundance}><strong>Abundance:</strong> {@host.abundance}</p>

              <%!-- Common Names --%>
              <div :if={@host.common_names != []}>
                <strong>Common Name(s):</strong>
                <span class="text-gray-700">{Enum.join(@host.common_names, ", ")}</span>
              </div>

              <%!-- Galls table --%>
              <div class="pt-2">
                <h3 class="font-semibold text-gray-800 mb-2">
                  Associated Galls ({length(@galls)})
                </h3>
                <%= if @galls != [] do %>
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
                              sorted_galls(@galls, @sort_by, @sort_dir),
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
                            <%= if gall.datacomplete do %>
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
                      :if={total_pages(@galls, @page_size) > 1}
                      class="flex items-center justify-between px-3 py-1 bg-white border-t border-gray-200"
                    >
                      <div class="text-sm">
                        {(@current_page - 1) * @page_size + 1}-{min(
                          @current_page * @page_size,
                          length(@galls)
                        )} of {length(@galls)}
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
                          Page {@current_page} of {total_pages(@galls, @page_size)}
                        </span>
                        <button
                          class="px-2 py-0.5 text-sm border rounded hover:bg-gray-100 disabled:opacity-50 disabled:cursor-not-allowed"
                          disabled={@current_page == total_pages(@galls, @page_size)}
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
            <div :if={@host.synonyms != []}>
              <h3 class="font-semibold text-gray-800 mb-2">
                Synonymy ({length(@host.synonyms)})
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
                    <tr :for={
                      s <- paginated_synonyms(@host.synonyms, @synonymy_page, @synonymy_page_size)
                    }>
                      <td><.taxon_name name={s.name} /></td>
                      <td class="text-gray-600">{s.sensu || "—"}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <.pagination
                :if={synonymy_total_pages(@host.synonyms, @synonymy_page_size) > 1}
                page={@synonymy_page}
                total_pages={synonymy_total_pages(@host.synonyms, @synonymy_page_size)}
                total_items={length(@host.synonyms)}
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

          <.see_also name={@host.name} type={:host} />

          <.record_metadata inserted_at={@host.inserted_at} updated_at={@host.updated_at} />
        <% else %>
          <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
            Host not found
          </div>
        <% end %>
      <% end %>
    </Layouts.app>
    """
  end
end
