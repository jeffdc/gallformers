defmodule GallformersWeb.SectionLive do
  @moduledoc """
  The section page (a subdivision within a plant genus), on the design
  system (matter bc0d; behavior in docs/design-system/inventory/rank-pages.md):
  a section (`Gallformers.Taxa.get_by_name/2`) with its lineage and its
  plants, each with the number of Galls on it, filterable by name and by the
  Gallformer genera with Galls on them (the rail). Data through
  `GallformersWeb.RankPage`.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog
  alias GallformersWeb.RankPage
  alias GallformersWeb.TaxonomyURL

  import GallformersWeb.RankPageComponents

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    case RankPage.lookup(name, :section) do
      {:redirect, path} -> {:ok, push_navigate(socket, to: path, replace: true)}
      {:ok, []} -> raise GallformersWeb.NotFoundError, "No section named #{name}"
      {:ok, [section | _]} -> {:ok, load_section(socket, section.id, name)}
    end
  end

  defp load_section(socket, id, name) do
    species = RankPage.host_rows(id)

    inducers =
      if species == [],
        do: [],
        else: species |> Enum.map(& &1.id) |> Catalog.inducer_genera_on_hosts()

    socket
    |> assign(
      page_title: "Section #{name}",
      page_description:
        "#{name} - A taxonomic section documented on Gallformers with #{length(species)} species.",
      page_url: TaxonomyURL.public_path(%{rank: :section, name: name}),
      page_image: nil,
      page_json_ld: nil,
      page_noindex: false,
      section: %{id: id, name: name, description: RankPage.description(id)},
      crumbs: RankPage.crumbs(id),
      species: species,
      inducers: inducers,
      selected_inducer: nil,
      search_query: "",
      sort: %{field: :name, dir: :asc}
    )
    |> compute()
  end

  defp compute(socket) do
    %{search_query: query, sort: sort, selected_inducer: selected} = socket.assigns

    species =
      case Enum.find(socket.assigns.inducers, &(&1.taxon_id == selected)) do
        nil -> socket.assigns.species
        genus -> Enum.filter(socket.assigns.species, &(&1.id in genus.focal_ids))
      end

    assign(socket,
      shown: species |> RankPage.filter_rows(query) |> RankPage.sort_rows(sort.field, sort.dir)
    )
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(search_query: query) |> compute()}
  end

  def handle_event("sort", %{"field" => field}, socket)
      when field in ["name", "common_name", "count"] do
    %{field: current, dir: dir} = socket.assigns.sort
    {field, dir} = RankPage.toggle_sort(current, dir, String.to_existing_atom(field))
    {:noreply, socket |> assign(sort: %{field: field, dir: dir}) |> compute()}
  end

  def handle_event("plants_filter", %{"id" => id}, socket) do
    selected = if id == "all", do: nil, else: String.to_integer(id)
    {:noreply, socket |> assign(selected_inducer: selected) |> compute()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:crumb :for={c <- @crumbs} navigate={c.path} italic={c.italic}>{c.name}</:crumb>
          <:title name>{@section.name}</:title>
          <:chip variant={:rank}>Section</:chip>
          <:chip>Host plants</:chip>
          <:meta :if={@section.description} label="Common name">{@section.description}</:meta>
          <:action>
            <.button
              navigate={"/id?g=#{URI.encode_www_form(@section.name)}"}
              variant="primary"
              icon="ph-magnifying-glass-plus"
            >
              Identify a gall on {@section.name}
            </.button>
            <.admin_edit_link current_user={@current_user} taxon_id={@section.id} />
          </:action>
        </.page_header>

        <.empty_state :if={@species == []} title="No species found for this section." />

        <div :if={@species != []} class="flex flex-wrap items-end gap-x-10 gap-y-4">
          <.stat value={length(@species)} label="Species" />
          <.stat value={Enum.count(@species, &(&1.count > 0))} label="Species with galls" />
          <.stat value={length(@inducers)} label="Gallformer genera" />
          <form
            id="section-search-form"
            phx-change="search"
            phx-submit="search"
            class="w-full sm:ml-auto sm:w-80"
          >
            <.search_field
              id="section-search"
              name="query"
              value={@search_query}
              label="Filter by species or common name"
              placeholder="Filter by species or common name…"
            />
          </form>
        </div>

        <div :if={@species != []} class="gf-with-rail">
          <div class="min-w-0">
            <.plant_table id="section-species" rows={@shown} total={length(@species)} sort={@sort} />
          </div>
          <.rail width={:narrow} stack={:last}>
            <.inducer_genera_panel
              :if={@inducers != []}
              name={@section.name}
              genera={@inducers}
              selected={@selected_inducer}
            />
          </.rail>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
