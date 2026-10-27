defmodule GallformersWeb.GallLive do
  @moduledoc """
  LiveView for the Gall detail page.

  Displays a Gall from `Gallformers.Catalog.gall_page/1`: its Inducer's
  taxonomy, Hosts, Traits, images, range map, names and Sources (the
  Gallformers note and the legacy citations).
  """
  use GallformersWeb, :live_view

  alias Gallformers.{
    Accounts,
    Catalog,
    Galls,
    Glossaries,
    Markdown,
    Places
  }

  alias Gallformers.Catalog.ReadModels.GallPage
  alias Gallformers.Images.Image
  alias GallformersWeb.LineageBreadcrumb
  alias GallformersWeb.SEO

  @aliases_page_size 10
  @sources_initial_limit 8

  @detachable_values %{
    "unknown" => "",
    "integral" => "Integral",
    "detachable" => "Detachable",
    "both" => "Both"
  }

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
    case Catalog.gall_page(gall_id) do
      :not_found ->
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

      {:ok, %GallPage{} = gall} ->
        images = format_images(gall.images)

        {range, inherited_range, introduced_range} =
          case gall.display_range do
            :everywhere -> {[], [], []}
            range -> {range.in_range, range.inherited_range, range.introduced_range}
          end

        # Parse the generation qualifier off the name and fetch its definition
        {base_name, generation_term, glossary_word, generation_definition} =
          parse_generation_term(gall.name, gall.generation)

        note = Enum.find(gall.sources, & &1.note?)

        # Build SEO data
        page_url = "/gall/#{gall_id}"

        page_description =
          Galls.Summary.for_seo(gall.name, Galls.Summary.from_traits(gall.traits))

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
           gall: gall,
           base_name: base_name,
           generation_term: generation_term,
           glossary_word: glossary_word,
           generation_definition: generation_definition,
           images: images,
           sources: gall.sources,
           taxonomy: breadcrumb(gall.inducers),
           range: range,
           inherited_range: inherited_range,
           introduced_range: introduced_range,
           range_bounds: Places.get_bounds_for_codes(range ++ inherited_range),
           range_unknown?: gall.display_range == :everywhere,
           related_galls: gall.related_galls,
           common_names: gall.common_names,
           name_rows: name_rows(gall),
           gallformers_code: gall.gallformers_code,
           has_gallformers_notes: note != nil,
           note_source_id: note && note.id,
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

  # The taxonomy breadcrumb from the (first) Inducer's lineage.
  defp breadcrumb([]), do: nil
  defp breadcrumb([%{lineage: lineage} | _]), do: LineageBreadcrumb.from_lineage(lineage)

  # The names table: the Inducer's synonyms, then the Gall's former labels
  # and codes (never common names, which are listed apart).
  defp name_rows(gall) do
    synonyms =
      for s <- gall.synonyms do
        type = if s.sensu, do: "misapplied", else: "synonym"
        %{name: s.name, type: type, notes: s.sensu, label?: false}
      end

    labels =
      for l <- gall.labels do
        %{name: l.name, type: label_type(l.kind), notes: nil, label?: true}
      end

    synonyms ++ labels
  end

  defp label_type(:former_label), do: "former label"
  defp label_type(:code), do: "code"

  defp host_href(%{link: {:host, id}}), do: "/host/#{id}"
  defp host_href(%{link: {rank, name}}), do: "/#{rank}/#{name}"

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

  defp detachable_display(traits) do
    case Map.get(traits, "detachable", []) do
      [value | _] -> Map.get(@detachable_values, value, "")
      [] -> ""
    end
  end

  defp trait_display(traits, trait), do: traits |> Map.get(trait, []) |> Enum.join(", ")

  # Splits the generation qualifier (e.g. "agamic", "sexgen") off the Gall's
  # name and gives its definition: the vocabulary's, else the glossary entry
  # named by the qualifier. Returns {base_name, term, glossary_word,
  # definition}, or {name, nil, nil, nil} when the name carries none.
  defp parse_generation_term(name, %{name_qualifier: qualifier} = generation)
       when is_binary(qualifier) do
    suffix = " (#{qualifier})"

    if String.ends_with?(name, suffix) do
      definition =
        generation.definition || Map.get(Glossaries.get_definitions([qualifier]), qualifier)

      {String.replace_suffix(name, suffix, ""), qualifier, qualifier, definition}
    else
      {name, nil, nil, nil}
    end
  end

  defp parse_generation_term(name, _generation), do: {name, nil, nil, nil}

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
    aliases = socket.assigns.name_rows
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
    # Always include the Gallformers note if there is one
    gallformers_notes = Enum.find(sources, & &1.note?)

    case gallformers_notes do
      nil ->
        Enum.take(sources, @sources_initial_limit)

      _ ->
        other_sources = Enum.reject(sources, & &1.note?)
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
                    :if={Accounts.admin?(@current_user)}
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
                :if={@gall.undescribed? && @gallformers_code}
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
                :if={!@gall.undescribed? && @gallformers_code}
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

              <div class="space-y-2">
                <.taxonomy_breadcrumb
                  :if={@taxonomy}
                  family={@taxonomy.family}
                  intermediates={@taxonomy.intermediates}
                  genus={@taxonomy.genus}
                />

                <div :if={@gall.hosts != []} class="flex items-center gap-1">
                  <div>
                    <strong>Hosts:</strong>
                    <span :for={{host, idx} <- Enum.with_index(@gall.hosts)}>
                      {if idx > 0, do: " / "}<.link
                        href={host_href(host)}
                        class="hover:underline"
                      ><.taxon_name
                          name={host.name}
                          genus_placeholder={host.rank == :genus}
                        /></.link>
                    </span>
                  </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-3 gap-x-4">
                  <div class="space-y-1">
                    <div>
                      <strong>Detachable:</strong> {detachable_display(@gall.traits)}
                    </div>
                    <div><strong>Color:</strong> {trait_display(@gall.traits, "color")}</div>
                    <div><strong>Texture:</strong> {trait_display(@gall.traits, "texture")}</div>
                    <div><strong>Abundance:</strong> {@gall.abundance || ""}</div>
                  </div>
                  <div class="space-y-1">
                    <div><strong>Shape:</strong> {trait_display(@gall.traits, "shape")}</div>
                    <div><strong>Season:</strong> {trait_display(@gall.traits, "season")}</div>
                    <div>
                      <strong>Alignment:</strong> {trait_display(@gall.traits, "alignment")}
                    </div>
                    <div><strong>Walls:</strong> {trait_display(@gall.traits, "walls")}</div>
                  </div>
                  <div class="space-y-1">
                    <div>
                      <strong>Location:</strong> {trait_display(@gall.traits, "plant_part")}
                    </div>
                    <div><strong>Form:</strong> {trait_display(@gall.traits, "form")}</div>
                    <div><strong>Cells:</strong> {trait_display(@gall.traits, "cells")}</div>
                  </div>
                </div>
              </div>

              <div>
                <div class="flex items-center gap-1">
                  <strong>Possible Range:</strong>
                  <.info_tip content="The gall's range is computed from the range of all hosts that the gall occurs on. In some cases we have evidence that the gall does not occur across the full range of the hosts and we will remove these places from the range. For undescribed species we will show the expected range based on hosts plus where the galls have been observed." />
                </div>
                <p
                  :if={@range_unknown?}
                  class="text-sm text-gray-600 italic mt-1"
                >
                  Range unknown — no host range data available.
                </p>
                <.alert :if={not @range_unknown?} variant="info" class="mt-1 mb-2">
                  Not an occurrence map: this shows where this gall's hosts grow. In most cases the
                  gall has not been documented throughout this area.
                </.alert>
                <.range_map
                  :if={not @range_unknown?}
                  id="gall-range-map"
                  class="min-h-[250px] h-[300px]"
                  in_range={@range}
                  inherited_range={@inherited_range}
                  introduced_range={@introduced_range}
                  bounds={@range_bounds}
                  navigable
                />
                <div
                  :if={not @range_unknown? and (@inherited_range != [] or @introduced_range != [])}
                  class="mt-1"
                >
                  <.range_map_legend mode={:public} />
                </div>
              </div>

              <div :if={length(@common_names) > 0} class="mt-4">
                <p>
                  <strong>Common Name(s):</strong>
                  {Enum.join(@common_names, ", ")}
                </p>
              </div>

              <div :if={length(@name_rows) > 0} class="mt-4">
                <h3 class="font-semibold text-gray-800 mb-2">
                  Synonymy ({length(@name_rows)})
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
                      <tr :for={a <- paginated_aliases(@name_rows, @aliases_page, @aliases_page_size)}>
                        <td>
                          <span :if={a.label?}>{a.name}</span>
                          <.taxon_name :if={not a.label?} name={a.name} />
                        </td>
                        <td class="text-gray-600">{a.type}</td>
                        <td class="text-gray-600">{a.notes || "—"}</td>
                      </tr>
                    </tbody>
                  </table>
                </div>
                <.pagination
                  :if={aliases_total_pages(@name_rows, @aliases_page_size) > 1}
                  page={@aliases_page}
                  total_pages={aliases_total_pages(@name_rows, @aliases_page_size)}
                  total_items={length(@name_rows)}
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
                edit_href={~p"/admin/galls/#{@gall.id}" <> "#images"}
                current_user={@current_user}
              />
            </div>
          </div>

          <hr class="border-gray-200 my-4" />

          <div
            :if={
              @has_gallformers_notes && !@notes_alert_dismissed &&
                !(@selected_source && @selected_source.note?)
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
              phx-value-id={@note_source_id}
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
            </div>
            <div class="space-y-2">
              <div
                :for={source <- visible_sources(@sources, @sources_expanded)}
                class={"p-3 rounded border bg-white #{if source.note?, do: "border-blue-200 border-l-4 border-l-blue-400", else: "border-gray-200"}"}
              >
                <div>
                  <.icon
                    :if={source.note?}
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
                </div>
                <button
                  :if={source.description not in [nil, ""]}
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

          <.see_also name={@gall.name} type={:gall} undescribed={@gall.undescribed?} />

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
              :if={@selected_source.description not in [nil, ""]}
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
