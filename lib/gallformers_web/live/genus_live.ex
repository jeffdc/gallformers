defmodule GallformersWeb.GenusLive do
  @moduledoc """
  LiveView for the taxonomic genus page.

  Displays a genus (`Gallformers.Taxa.get_by_name/2`) with its lineage and
  up to three lists, each shown when it has rows:

    * **Galls** — the Galls whose Inducer is in the genus (its species, the
      genus itself for undescribed Galls, a section in it), with their
      number of Hosts, filterable by the genera of their Hosts;
    * **Hosts** — the plants in the genus, with their number of Galls,
      filterable by the genera of the Inducers of their Galls;
    * **Galls on the genus as a whole** — the Galls whose Host is the genus
      itself (today's "Genus spp." placeholder plants).

  A genus name used more than once (e.g. in two kingdoms) offers each,
  with its family; `?family=` picks one. Data through
  `GallformersWeb.RankPage` and `Gallformers.Catalog`.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog
  alias Gallformers.Taxa
  alias GallformersWeb.LineageBreadcrumb
  alias GallformersWeb.RankPage
  alias GallformersWeb.RankPageComponents
  alias GallformersWeb.TaxonomyURL

  @impl true
  def mount(%{"name" => name} = params, _session, socket) do
    case RankPage.lookup(name, :genus) do
      {:redirect, path} ->
        {:ok, push_navigate(socket, to: path, replace: true)}

      {:ok, []} ->
        {:ok, assign_genus_not_found(socket, "Genus not found")}

      {:ok, [genus]} ->
        {:ok, assign_genus_data(socket, genus.id, name)}

      {:ok, genera} ->
        {:ok, resolve_disambiguation(socket, name, params["family"], genera)}
    end
  end

  defp assign_genus_not_found(socket, error) do
    assign(socket,
      page_title: "Genus Not Found",
      page_description: "The requested taxonomic genus was not found on Gallformers.",
      page_url: nil,
      page_image: nil,
      page_json_ld: nil,
      page_noindex: true,
      genus: nil,
      disambiguation: nil,
      error: error
    )
  end

  defp resolve_disambiguation(socket, name, family_hint, genera) do
    lineages = genera |> Enum.map(& &1.id) |> Taxa.lineages()
    family_of = &Enum.find(Map.get(lineages, &1.id, []), fn t -> t.rank == :family end)

    case Enum.find(genera, &(family_hint != nil && match?(%{name: ^family_hint}, family_of.(&1)))) do
      %{id: id} -> assign_genus_data(socket, id, name)
      nil -> assign_disambiguation(socket, name, genera, family_of)
    end
  end

  defp assign_disambiguation(socket, name, genera, family_of) do
    ids = Enum.map(genera, & &1.id)
    gall_counts = Catalog.count_galls_under(ids)
    host_counts = Taxa.count_plants_under(ids)

    options =
      Enum.map(genera, fn genus ->
        family = family_of.(genus)

        %{
          name: name,
          family_name: (family && family.name) || "Unknown",
          family_description: family && RankPage.description(family.taxon_id),
          species_count: gall_counts[genus.id] + host_counts[genus.id]
        }
      end)

    assign(socket,
      page_title: "Genus #{name} — Disambiguation",
      page_description:
        "Multiple genera named #{name} exist on Gallformers under different families.",
      page_url: nil,
      page_image: nil,
      page_json_ld: nil,
      page_noindex: true,
      genus: nil,
      disambiguation: options,
      error: nil
    )
  end

  defp assign_genus_data(socket, id, name) do
    sections = sections(id)
    total = sections |> Enum.map(&length(&1.rows)) |> Enum.sum()

    assign(socket,
      page_title: "Genus #{name}",
      page_description:
        "#{name} - A taxonomic genus documented on Gallformers with #{total} species.",
      page_url: TaxonomyURL.public_path(%{rank: :genus, name: name}),
      page_image: nil,
      page_json_ld: nil,
      page_noindex: total == 0,
      genus: %{id: id, name: name, description: RankPage.description(id)},
      lineage: id |> Taxa.lineage() |> LineageBreadcrumb.from_lineage(),
      disambiguation: nil,
      sections: sections,
      total_species_count: total,
      search_query: "",
      show_related: %{},
      selected_related: %{},
      sort_by: :name,
      sort_dir: :asc,
      error: nil
    )
  end

  # The lists the page shows, each only when it has rows.
  defp sections(genus_id) do
    inducer_ids = Taxa.subtree_ids([genus_id]) |> Map.get(genus_id, [genus_id])
    galls = RankPage.galls_of_inducers(inducer_ids)
    hosts = RankPage.host_rows(genus_id)
    on_genus = RankPage.galls_on_hosts([genus_id])

    [
      %{
        key: "galls",
        title: "Galls",
        rows: galls,
        url_prefix: "/gall/",
        name_header: "Gall",
        count_header: "Number of Hosts",
        related: related(galls, &Catalog.host_genera_of_galls/1),
        related_heading: "Host genera used by this genus",
        related_filter_label: "host genus"
      },
      %{
        key: "hosts",
        title: "Hosts",
        rows: hosts,
        url_prefix: "/host/",
        name_header: "Species Name",
        count_header: "Number of Galls",
        related: related(hosts, &Catalog.inducer_genera_on_hosts/1),
        related_heading: "Gall-former genera found on this host",
        related_filter_label: "gall-former genus"
      },
      %{
        key: "genus_host",
        title: "Galls on the genus as a whole",
        rows: on_genus,
        url_prefix: "/gall/",
        name_header: "Gall",
        count_header: "Number of Hosts",
        related: [],
        related_heading: nil,
        related_filter_label: nil
      }
    ]
    |> Enum.reject(&(&1.rows == []))
  end

  defp related([], _fun), do: []
  defp related(rows, fun), do: rows |> Enum.map(& &1.id) |> fun.()

  defp format_with_description(name, description) do
    if description && String.trim(description) != "" do
      "#{name} (#{description})"
    else
      name
    end
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  @impl true
  def handle_event("filter_related_genus", %{"section" => key, "id" => id}, socket) do
    selected = if id == "all", do: nil, else: String.to_integer(id)

    {:noreply,
     socket
     |> update(:show_related, &Map.put(&1, key, true))
     |> update(:selected_related, &Map.put(&1, key, selected))}
  end

  @impl true
  def handle_event("toggle_related_genera", %{"section" => key}, socket) do
    {:noreply, update(socket, :show_related, &Map.update(&1, key, true, fn shown -> !shown end))}
  end

  @impl true
  def handle_event("sort", %{"column" => column}, socket)
      when column in ["name", "common_name", "count"] do
    {sort_by, sort_dir} =
      RankPage.toggle_sort(
        socket.assigns.sort_by,
        socket.assigns.sort_dir,
        String.to_existing_atom(column)
      )

    {:noreply, assign(socket, sort_by: sort_by, sort_dir: sort_dir)}
  end

  # A section's rows narrowed by its selected related genus and the search.
  defp visible_rows(section, selected_related, query) do
    rows =
      case Map.get(selected_related, section.key) do
        nil ->
          section.rows

        genus_id ->
          focal =
            section.related
            |> Enum.find(%{focal_ids: []}, &(&1.taxon_id == genus_id))
            |> Map.fetch!(:focal_ids)
            |> MapSet.new()

          Enum.filter(section.rows, &MapSet.member?(focal, &1.id))
      end

    RankPage.filter_rows(rows, query)
  end

  defp related_name(section, genus_id),
    do: Enum.find(section.related, &(&1.taxon_id == genus_id)).name

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-7xl">
        <%= if @error do %>
          <div class="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">{@error}</div>
        <% else %>
          <%= if @disambiguation do %>
            <div class="mb-6">
              <h1 class="text-2xl font-bold text-gf-maroon mb-4">
                Genus <.taxon_name name={hd(@disambiguation).name} rank="genus" />
              </h1>
              <p class="text-gray-600 mb-6">
                This genus name exists under multiple families. Select the one you're looking for:
              </p>
              <div class="grid gap-4 max-w-2xl">
                <.link
                  :for={option <- @disambiguation}
                  navigate={"/genus/#{URI.encode(option.name)}?family=#{URI.encode(option.family_name)}"}
                  class="block p-4 bg-white border border-gray-200 rounded-lg hover:border-gf-maroon hover:bg-gf-cream transition-colors"
                >
                  <div class="font-semibold text-gf-maroon">
                    <.taxon_name name={option.name} rank="genus" />
                    <span class="text-gray-500 font-normal">
                      in Family {option.family_name}
                      <span :if={option.family_description not in [nil, ""]}>
                        ({option.family_description})
                      </span>
                    </span>
                  </div>
                  <div class="text-sm text-gray-500 mt-1">
                    {option.species_count} species
                  </div>
                </.link>
              </div>
            </div>
          <% end %>
          <%= if @genus do %>
            <%!-- Header --%>
            <div class="mb-6">
              <div class="flex items-center justify-between mb-2">
                <div class="flex items-center gap-2">
                  <h1 class="text-2xl font-bold text-gf-maroon">
                    Genus
                    <.taxon_name
                      name={format_with_description(@genus.name, @genus.description)}
                      rank="genus"
                    />
                  </h1>
                </div>
              </div>

              <.taxonomy_breadcrumb
                :if={@lineage}
                family={@lineage.family}
                intermediates={@lineage.intermediates}
                show_genus={false}
              />
            </div>

            <%!-- Species lists --%>
            <div class="mt-6">
              <%= if @total_species_count > 0 do %>
                <%!-- Search box --%>
                <div class="mb-4 max-w-md">
                  <form phx-change="search" phx-submit="search" id="genus-search-form">
                    <.search_input
                      id="genus-search"
                      name="query"
                      value={@search_query}
                      placeholder="Filter by name or common name..."
                      phx-debounce="300"
                    />
                  </form>
                </div>

                <.genus_section
                  :for={section <- @sections}
                  section={section}
                  genus_name={@genus.name}
                  selected={Map.get(@selected_related, section.key)}
                  shown={Map.get(@show_related, section.key, false)}
                  rows={visible_rows(section, @selected_related, @search_query)}
                  search_query={@search_query}
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                />
              <% else %>
                <p class="text-gray-500 italic">No species found for this genus.</p>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :section, :map, required: true
  attr :genus_name, :string, required: true
  attr :selected, :integer, default: nil, doc: "the related genus filtering the list"
  attr :shown, :boolean, default: false, doc: "whether the related-genera filters are open"
  attr :rows, :list, required: true, doc: "the rows left after filtering"
  attr :search_query, :string, required: true
  attr :sort_by, :atom, required: true
  attr :sort_dir, :atom, required: true

  defp genus_section(assigns) do
    ~H"""
    <div class="mb-8">
      <div :if={@section.related != []} class="mb-6">
        <.button
          :if={!@shown}
          type="button"
          variant="secondary"
          phx-click="toggle_related_genera"
          phx-value-section={@section.key}
          aria-expanded="false"
          aria-controls={"related-genera-filters-#{@section.key}"}
          class="w-full text-left shadow-sm"
        >
          <span class="flex w-full items-center justify-between gap-4">
            <span class="flex min-w-0 items-center gap-2">
              <.icon name="ph-arrows-left-right" class="size-5 shrink-0" />
              <span class="font-medium">{@section.related_heading}</span>
              <span class="rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-600">
                {length(@section.related)}
              </span>
              <span :if={@selected} class="truncate text-sm text-gray-600">
                — filtered by <.taxon_name name={related_name(@section, @selected)} rank="genus" />
              </span>
            </span>
            <span class="flex shrink-0 items-center gap-1 text-sm">
              Show filters <.icon name="ph-caret-down" class="size-4" />
            </span>
          </span>
        </.button>

        <.card
          :if={@shown}
          title={"#{@section.related_heading} (#{length(@section.related)})"}
          icon="ph-arrows-left-right"
          id={"related-genera-filters-#{@section.key}"}
        >
          <:actions>
            <.button
              type="button"
              variant="ghost"
              size="sm"
              phx-click="toggle_related_genera"
              phx-value-section={@section.key}
              aria-expanded="true"
              aria-controls={"related-genera-filters-#{@section.key}"}
              class="gap-1 hover:underline"
            >
              Hide <.icon name="ph-caret-up" class="size-4" />
            </.button>
          </:actions>
          <p class="text-sm text-gray-600 mb-4">
            Select a genus to filter the list below. Counts show how many entries
            in <.taxon_name name={@genus_name} rank="genus" /> have that association.
          </p>
          <div
            class="flex flex-wrap gap-2"
            role="group"
            aria-label={"Filter by #{@section.related_filter_label}"}
          >
            <.button
              type="button"
              variant={if is_nil(@selected), do: "primary", else: "secondary"}
              size="sm"
              shape="pill"
              phx-click="filter_related_genus"
              phx-value-section={@section.key}
              phx-value-id="all"
              aria-pressed={is_nil(@selected)}
              class="gap-2"
            >
              All <span class="text-xs opacity-80">{length(@section.rows)}</span>
            </.button>
            <.button
              :for={genus <- @section.related}
              type="button"
              variant={if @selected == genus.taxon_id, do: "primary", else: "secondary"}
              size="sm"
              shape="pill"
              phx-click="filter_related_genus"
              phx-value-section={@section.key}
              phx-value-id={genus.taxon_id}
              aria-pressed={@selected == genus.taxon_id}
              title={"#{genus.association_count} associations"}
              class="gap-2"
            >
              <.taxon_name name={genus.name} rank="genus" />
              <span class={[
                "rounded-full px-1.5 py-0.5 text-xs",
                @selected == genus.taxon_id && "bg-white/20",
                @selected != genus.taxon_id && "bg-gray-100 text-gray-600"
              ]}>
                {length(genus.focal_ids)}
              </span>
            </.button>
          </div>
          <p :if={@selected} class="mt-4 text-sm text-gray-600">
            Showing entries associated with
            <.taxon_name name={related_name(@section, @selected)} rank="genus" />.
            <.button
              type="button"
              variant="ghost"
              size="sm"
              phx-click="filter_related_genus"
              phx-value-section={@section.key}
              phx-value-id="all"
              class="ml-1 underline hover:no-underline"
            >
              Clear filter
            </.button>
          </p>
        </.card>
      </div>

      <h2 class="text-lg font-semibold text-gray-800 mb-3">
        {@section.title} ({length(@section.rows)})
      </h2>

      <%= if @rows == [] do %>
        <div class="bg-gray-50 rounded-lg p-8 text-center text-gray-600">
          <p>No entries found matching "{@search_query}"</p>
        </div>
      <% else %>
        <RankPageComponents.species_table
          id={"genus-#{@section.key}"}
          rows={@rows}
          url_prefix={@section.url_prefix}
          name_header={@section.name_header}
          count_header={@section.count_header}
          sort_by={@sort_by}
          sort_dir={@sort_dir}
        />

        <div class="mt-4 text-sm text-gray-500">
          <%= if @search_query != "" or @selected do %>
            Filtering {length(@rows)} of {length(@section.rows)}
          <% else %>
            Showing {length(@rows)}
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
