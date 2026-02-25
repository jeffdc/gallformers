defmodule GallformersWeb.GallLive do
  @moduledoc """
  LiveView for the gall/species detail page.

  Displays detailed information about a gall species including morphology,
  hosts, images, range map, and sources.
  """
  use GallformersWeb, :live_view

  alias Gallformers.{
    GallHosts,
    Galls,
    Glossaries,
    Markdown,
    Places,
    Ranges,
    Sources,
    Species,
    Taxonomy
  }

  alias Gallformers.Images.Image
  alias GallformersWeb.SEO

  @aliases_page_size 10
  @sources_initial_limit 8

  @detachable_values %{
    "unknown" => "",
    "integral" => "Integral",
    "detachable" => "Detachable",
    "both" => "Both"
  }

  # Gallformers Notes source ID (same as V1)
  @gallformers_notes_source_id 58

  # Regex to extract generation qualifier from species names like "Callirhytis furva (agamic)"
  @generation_re ~r/^(.+?)\s+\((agamic|sexgen|sexual)\)$/

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {gall_id, ""} ->
        load_gall(socket, gall_id)

      _ ->
        {:ok,
         assign(socket,
           page_title: "Gall Not Found",
           page_description: "The requested gall was not found on Gallformers.",
           page_url: nil,
           page_image: nil,
           page_json_ld: nil,
           page_noindex: true,
           gall: nil,
           selected_source: nil,
           error: "Invalid gall ID"
         )}
    end
  end

  @impl true
  def handle_params(%{"source" => source_id_str}, _uri, socket) do
    with {source_id, ""} <- Integer.parse(source_id_str),
         source when not is_nil(source) <-
           Enum.find(socket.assigns[:sources] || [], fn s -> s.id == source_id end) do
      {:noreply, assign(socket, selected_source: source, sources_expanded: true)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp load_gall(socket, gall_id) do
    case Galls.get_gall(gall_id) do
      nil ->
        {:ok,
         assign(socket,
           page_title: "Gall Not Found",
           page_description: "The requested gall was not found on Gallformers.",
           page_url: nil,
           page_image: nil,
           page_json_ld: nil,
           page_noindex: true,
           gall: nil,
           selected_source: nil,
           error: "Gall not found"
         )}

      gall ->
        hosts = GallHosts.get_hosts_for_gall(gall_id) |> Enum.sort_by(& &1.host_name)
        images = Species.get_images_for_species(gall_id) |> format_images()
        sources = Sources.get_sources_for_species(gall_id)
        aliases = Species.get_aliases_for_species(gall_id)
        taxonomy = get_taxonomy_info(gall_id)
        range_data = Ranges.get_display_range_for_gall(gall_id)
        range = range_data.in_range
        inherited_range = range_data.inherited_range
        excluded_range = range_data.excluded_range
        range_bounds = Places.get_bounds_for_codes(range ++ inherited_range)
        gall_filters = Galls.get_gall_filter_values(gall_id)
        related_galls = Galls.get_related_galls(gall)

        # Parse generation qualifier (agamic/sexgen/sexual) and fetch glossary definition
        {base_name, generation_term, glossary_word, generation_definition} =
          parse_generation_term(gall.name)

        # Separate common names from scientific synonyms
        common_names = Enum.filter(aliases, &(&1.type == "common"))
        scientific_aliases = Enum.filter(aliases, &(&1.type != "common"))

        gallformers_code = gall.gallformers_code

        # Check if Gallformers notes exist for this species
        gallformers_notes = Enum.find(sources, fn s -> s.id == @gallformers_notes_source_id end)
        has_gallformers_notes = gallformers_notes != nil

        # Build SEO data
        page_url = "/gall/#{gall_id}"

        # Generate SEO description using gall filter data
        summary_filters = Galls.Summary.from_db_filters(gall_filters, gall.detachable)
        page_description = Galls.Summary.for_seo(gall.name, summary_filters)

        page_image =
          case images do
            [first | _] -> first.url
            [] -> nil
          end

        # Build JSON-LD structured data
        json_ld = build_species_json_ld(gall, page_url, page_description, page_image)

        {:ok,
         assign(socket,
           page_title: gall.name,
           page_description: page_description,
           page_url: page_url,
           page_image: page_image,
           page_json_ld: json_ld,
           page_noindex: false,
           gall: Map.merge(gall, %{hosts: hosts, aliases: aliases}),
           base_name: base_name,
           generation_term: generation_term,
           glossary_word: glossary_word,
           generation_definition: generation_definition,
           gall_filters: gall_filters,
           images: images,
           sources: sources,
           taxonomy: taxonomy,
           range: range,
           inherited_range: inherited_range,
           excluded_range: excluded_range,
           range_bounds: range_bounds,
           related_galls: related_galls,
           common_names: common_names,
           scientific_aliases: scientific_aliases,
           gallformers_code: gallformers_code,
           has_gallformers_notes: has_gallformers_notes,
           notes_alert_dismissed: false,
           aliases_page: 1,
           aliases_page_size: @aliases_page_size,
           selected_source: nil,
           modal_font_size: :base,
           sources_expanded: false,
           error: nil
         )}
    end
  end

  defp build_species_json_ld(gall, url, description, image) do
    json_ld = %{
      "@context" => "https://schema.org",
      "@type" => "Thing",
      "name" => gall.name,
      "description" => description,
      "url" => SEO.base_url() <> url,
      "identifier" => gall.name
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
        alt: "Gall image"
      })
    end)
  end

  defp get_detachable_display(value), do: Map.get(@detachable_values, value, "")
  defp format_fields(fields), do: Enum.map_join(fields, ", ", & &1.field)

  # Parses generation qualifier from species name and fetches glossary definition.
  # Returns {base_name, term, glossary_word, definition} or {full_name, nil, nil, nil}.
  defp parse_generation_term(name) do
    case Regex.run(@generation_re, name) do
      [_full, base_name, term] ->
        # "sexgen" and "sexual" both refer to the glossary entry "sexgen"
        glossary_word = if term == "sexual", do: "sexgen", else: term
        defs = Glossaries.get_definitions([glossary_word])
        {base_name, term, glossary_word, Map.get(defs, glossary_word)}

      _ ->
        {name, nil, nil, nil}
    end
  end

  @impl true
  def handle_event("dismiss_notes_alert", _params, socket) do
    {:noreply, assign(socket, notes_alert_dismissed: true)}
  end

  @impl true
  def handle_event("clipboard_copy_success", _params, socket) do
    {:noreply, put_flash(socket, :info, "Copied to clipboard")}
  end

  @impl true
  def handle_event("clipboard_copy_error", _params, socket) do
    {:noreply, put_flash(socket, :error, "Failed to copy to clipboard")}
  end

  @impl true
  def handle_event("gallery_index_changed", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("aliases_page", %{"page" => page}, socket) do
    aliases = socket.assigns.gall.aliases
    page = max(1, min(page, aliases_total_pages(aliases, socket.assigns.aliases_page_size)))
    {:noreply, assign(socket, aliases_page: page)}
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
  def handle_event("expand_sources", _params, socket) do
    {:noreply, assign(socket, sources_expanded: true)}
  end

  @impl true
  def handle_event("navigate_to_place", %{"code" => code}, socket) do
    {:noreply, push_navigate(socket, to: "/place/#{code}")}
  end

  defp paginated_aliases(aliases, current_page, page_size) do
    aliases
    |> Enum.drop((current_page - 1) * page_size)
    |> Enum.take(page_size)
  end

  defp aliases_total_pages(aliases, page_size) do
    max(1, ceil(length(aliases) / page_size))
  end

  defp prose_size_class(:sm), do: "prose-sm"
  defp prose_size_class(:base), do: "prose-base"
  defp prose_size_class(:lg), do: "prose-lg"
  defp prose_size_class(:xl), do: "prose-xl"

  defp visible_sources(sources, expanded?)
       when expanded? or length(sources) <= @sources_initial_limit do
    sources
  end

  defp visible_sources(sources, _expanded?) do
    # Always include Gallformers Notes (id 58) if it exists
    gallformers_notes = Enum.find(sources, &(&1.id == @gallformers_notes_source_id))

    case gallformers_notes do
      nil ->
        Enum.take(sources, @sources_initial_limit)

      _ ->
        other_sources = Enum.reject(sources, &(&1.id == @gallformers_notes_source_id))
        # Take 7 other sources + Gallformers Notes = 8 total
        limited_sources = Enum.take(other_sources, @sources_initial_limit - 1)
        # Maintain original order by sorting by position in original list
        Enum.sort_by([gallformers_notes | limited_sources], fn s ->
          Enum.find_index(sources, &(&1.id == s.id))
        end)
    end
  end

  defp show_expand_button?(sources, expanded?) do
    !expanded? and length(sources) > @sources_initial_limit
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <%= if @error do %>
        <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">{@error}</div>
      <% else %>
        <%= if @gall do %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <div class="lg:col-span-2 space-y-2">
              <div class="flex items-start justify-between gap-4">
                <div class="flex items-center gap-2">
                  <h2 class="text-2xl font-bold">
                    <em class="taxon-name">
                      {@base_name}
                      <.glossary_tooltip
                        :if={@generation_term}
                        term={@generation_term}
                        glossary_word={@glossary_word}
                        definition={@generation_definition}
                      />
                    </em>
                  </h2>
                  <.link
                    :if={@current_user}
                    href={~p"/admin/galls/#{@gall.id}"}
                    class="text-gray-400 hover:text-gf-maroon"
                    title="Edit in admin"
                  >
                    <.icon name="ph-pencil-simple" class="h-5 w-5" />
                  </.link>
                </div>
                <.data_complete_badge
                  complete={@gall.datacomplete}
                  complete_tooltip="All sources containing unique information relevant to this gall have been added and are reflected in its associated data."
                  incomplete_tooltip="We are still working on this gall so data might be missing."
                />
              </div>

              <div
                :if={@gall.undescribed && @gallformers_code}
                class="bg-amber-50 border border-amber-200 rounded-lg p-4"
              >
                <p class="text-red-600 font-medium mb-2">
                  The inducer of this gall is unknown or undescribed.
                </p>
                <p class="text-sm mb-2">
                  <span class="font-medium text-gray-700">Gallformers Code:</span>
                  <button
                    id="copy-gallformers-code"
                    phx-hook="CopyToClipboard"
                    data-copy-text={@gallformers_code}
                    class="ml-1 cursor-pointer hover:opacity-70"
                  >
                    <code class="px-2 py-0.5 bg-white border border-amber-200 rounded font-mono text-amber-800">
                      {@gallformers_code}
                    </code>
                    <span class="ml-2 text-xs hover:underline">
                      Click to Copy
                    </span>
                  </button>
                </p>
                <p class="text-sm text-gray-600">
                  <a
                    href={"https://www.inaturalist.org/observations?verifiable=any&place_id=any&field:Gallformers%20Code=#{URI.encode(@gallformers_code)}"}
                    target="_blank"
                    rel="noreferrer"
                    class="text-gf-maroon hover:underline"
                  >
                    View observations collected with this code on iNaturalist.
                  </a>
                  <.link href="/articles/link-undescribed-inat" class="text-gf-maroon hover:underline">
                    Learn more about how it works and how you can help.
                  </.link>
                </p>
              </div>

              <div
                :if={!@gall.undescribed && @gallformers_code}
                class="text-sm text-gray-600"
              >
                Formerly tracked as undescribed —
                <a
                  href={"https://www.inaturalist.org/observations?verifiable=any&place_id=any&field:Gallformers%20Code=#{URI.encode(@gallformers_code)}"}
                  target="_blank"
                  rel="noreferrer"
                  class="text-gf-maroon hover:underline"
                >
                  view iNat observations linked under Gallformers Code "{@gallformers_code}"
                </a>
              </div>

              <div class="flex flex-col md:flex-row md:items-start gap-4">
                <div class="flex-1 space-y-2">
                  <p :if={@taxonomy}>
                    <span :if={@taxonomy.family}>
                      <strong>Family:</strong>
                      <.link
                        href={"/family/#{@taxonomy.family.id}"}
                        class="hover:underline"
                      >
                        {@taxonomy.family.name}
                      </.link>
                      <span
                        :if={@taxonomy.family.description not in [nil, ""]}
                        class="text-gray-600"
                      >
                        ({@taxonomy.family.description})
                      </span>
                    </span>
                    <span :if={@taxonomy.family && @taxonomy.genus} class="mx-1">|</span>
                    <span :if={@taxonomy.genus}>
                      <strong>Genus:</strong>
                      <.link
                        href={"/genus/#{@taxonomy.genus.id}"}
                        class="hover:underline"
                      >
                        <.taxon_name name={@taxonomy.genus.name} rank="genus" />
                      </.link>
                      <span
                        :if={@taxonomy.genus.description not in [nil, ""]}
                        class="text-gray-600"
                      >
                        ({@taxonomy.genus.description})
                      </span>
                    </span>
                  </p>

                  <div :if={@gall.hosts && length(@gall.hosts) > 0} class="flex items-center gap-1">
                    <div>
                      <strong>Hosts:</strong>
                      <em class="taxon-name">
                        <span :for={{host, idx} <- Enum.with_index(@gall.hosts)}>
                          {if idx > 0, do: " / "}<.link
                            href={"/host/#{host.host_species_id}"}
                            class="hover:underline"
                          >{host.host_name}</.link>
                        </span>
                      </em>
                    </div>
                    <.link
                      :if={@current_user}
                      href={~p"/admin/gallhost?id=#{@gall.id}"}
                      class="text-gray-400 hover:text-gf-maroon"
                      title="Edit gall-host mappings"
                    >
                      <.icon name="ph-pencil-simple" class="h-4 w-4" />
                    </.link>
                  </div>

                  <div class="grid grid-cols-1 md:grid-cols-2 gap-x-4">
                    <div class="space-y-1">
                      <div>
                        <strong>Detachable:</strong> {get_detachable_display(@gall.detachable)}
                      </div>
                      <div><strong>Color:</strong> {format_fields(@gall_filters.colors)}</div>
                      <div><strong>Texture:</strong> {format_fields(@gall_filters.textures)}</div>
                      <div><strong>Abundance:</strong> {@gall.abundance_name || ""}</div>
                      <div><strong>Shape:</strong> {format_fields(@gall_filters.shapes)}</div>
                      <div><strong>Season:</strong> {format_fields(@gall_filters.seasons)}</div>
                    </div>
                    <div class="space-y-1">
                      <div><strong>Alignment:</strong> {format_fields(@gall_filters.alignments)}</div>
                      <div><strong>Walls:</strong> {format_fields(@gall_filters.walls)}</div>
                      <div><strong>Location:</strong> {format_fields(@gall_filters.plant_parts)}</div>
                      <div><strong>Form:</strong> {format_fields(@gall_filters.forms)}</div>
                      <div><strong>Cells:</strong> {format_fields(@gall_filters.cells)}</div>
                    </div>
                  </div>
                </div>

                <div class="md:w-64 lg:w-80 shrink-0">
                  <div class="flex items-center gap-1">
                    <strong>Possible Range:</strong>
                    <.info_tip content="The gall's range is computed from the range of all hosts that the gall occurs on. In some cases we have evidence that the gall does not occur across the full range of the hosts and we will remove these places from the range. For undescribed species we will show the expected range based on hosts plus where the galls have been observed." />
                  </div>
                  <.range_map
                    id="gall-range-map"
                    in_range={@range}
                    inherited_range={@inherited_range}
                    excluded_range={[]}
                    bounds={@range_bounds}
                    navigable
                  />
                  <div :if={@inherited_range != []} class="mt-1">
                    <.range_map_legend mode={:public} />
                  </div>
                </div>
              </div>

              <div :if={length(@common_names) > 0} class="mt-4">
                <p>
                  <strong>Common Name(s):</strong>
                  {Enum.map_join(@common_names, ", ", & &1.name)}
                </p>
              </div>

              <div :if={length(@scientific_aliases) > 0} class="mt-4">
                <h3 class="font-semibold text-gray-800 mb-2">
                  Synonymy ({length(@scientific_aliases)})
                </h3>
                <div class="bg-white rounded border border-gray-200 overflow-hidden">
                  <table class="gf-table gf-table-compact">
                    <thead>
                      <tr>
                        <th>Name</th>
                        <th>Type</th>
                        <th>Notes</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr :for={
                        a <- paginated_aliases(@scientific_aliases, @aliases_page, @aliases_page_size)
                      }>
                        <td><.taxon_name name={a.name} /></td>
                        <td class="text-gray-600">{a.type || "—"}</td>
                        <td class="text-gray-600">{a.description || "—"}</td>
                      </tr>
                    </tbody>
                  </table>
                </div>
                <.pagination
                  :if={aliases_total_pages(@scientific_aliases, @aliases_page_size) > 1}
                  page={@aliases_page}
                  total_pages={aliases_total_pages(@scientific_aliases, @aliases_page_size)}
                  total_items={length(@scientific_aliases)}
                  page_size={@aliases_page_size}
                  on_page_change={fn page -> JS.push("aliases_page", value: %{page: page}) end}
                  class="mt-4"
                />
              </div>

              <div :if={length(@related_galls) > 0} class="mt-4">
                <h3 class="font-semibold text-gray-800 mb-2">
                  Related Galls ({length(@related_galls)})
                </h3>
                <ul class="list-disc list-inside space-y-1">
                  <li :for={related <- @related_galls}>
                    <.link href={"/gall/#{related.id}"} class="hover:underline">
                      <.taxon_name name={related.name} />
                    </.link>
                  </li>
                </ul>
              </div>
            </div>

            <div class="lg:col-span-1">
              <.image_gallery
                images={@images}
                id="gall-images"
                species_id={@gall.id}
                current_user={@current_user}
              />
            </div>
          </div>

          <hr class="border-gray-200 my-4" />

          <div
            :if={
              @has_gallformers_notes && !@notes_alert_dismissed &&
                !(@selected_source && @selected_source.id == 58)
            }
            class="flex items-center gap-3 p-3 mb-4 bg-gf-sky-blue border border-blue-300 rounded text-sm text-gray-700"
            role="alert"
          >
            <.icon name="ph-info" class="h-5 w-5 text-blue-600 shrink-0" />
            <p class="flex-1">
              Our ID Notes may contain important tips necessary for distinguishing this gall
              from similar galls and/or important information about the taxonomic status of
              this gall inducer.
            </p>
            <button
              type="button"
              phx-click="show_source_detail"
              phx-value-id="58"
              class="px-3 py-1 text-sm bg-white border border-blue-400 text-blue-700 hover:bg-blue-50 rounded whitespace-nowrap"
            >
              Show notes
            </button>
            <button
              type="button"
              class="text-gray-500 hover:text-gray-700"
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
                href={~p"/admin/species-sources/add?species_id=#{@gall.id}"}
                class="text-gray-400 hover:text-gf-maroon"
                title="Add source mapping"
              >
                <.icon name="ph-plus-circle" class="h-5 w-5" />
              </.link>
            </div>
            <div class="space-y-2">
              <div
                :for={source <- visible_sources(@sources, @sources_expanded)}
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
                    data-copy-text={"/gall/#{@gall.id}?source=#{source.id}"}
                    data-copy-url
                    class="ml-2 text-gray-500 hover:text-gf-maroon cursor-pointer"
                    title="Copy link to this description"
                  >
                    <.icon name="ph-link" class="h-4 w-4 inline-block align-text-bottom" />
                  </button>
                  <.link
                    :if={@current_user}
                    href={
                      ~p"/admin/species-sources/find?species_id=#{@gall.id}&source_id=#{source.id}"
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
            <div :if={show_expand_button?(@sources, @sources_expanded)} class="mt-4 text-center">
              <button
                type="button"
                phx-click="expand_sources"
                class="px-4 py-2 bg-white border border-gray-300 rounded hover:bg-gray-50 text-gray-700"
              >
                Show all {length(@sources)} sources
              </button>
            </div>
          <% else %>
            <p class="italic">No further information available for this species.</p>
          <% end %>

          <.see_also name={@gall.name} type={:gall} undescribed={@gall.undescribed} />

          <.record_metadata inserted_at={@gall.inserted_at} updated_at={@gall.updated_at} />
        <% else %>
          <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">
            Gall not found
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
              data-copy-text={"/gall/#{@gall.id}?source=#{@selected_source.id}"}
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
