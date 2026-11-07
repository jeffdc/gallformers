defmodule GallformersWeb.HomeLive do
  @moduledoc """
  The home page (design system, matter bc0d): the Host typeahead that opens
  the ID tool, a random Gall with "Show me another", the counts, the Host
  genera and Gallformer groups to start from, and the Sources changed most
  recently.
  """
  use GallformersWeb, :live_view

  alias Gallformers.{Catalog, Images, Sources, Taxa}

  @impl true
  def mount(_params, _session, socket) do
    # Only fetch data when connected to avoid fetching twice
    {random_gall, stats, lists} =
      if connected?(socket) do
        {Catalog.random_gall(), fetch_stats(), fetch_lists()}
      else
        {nil, %{galls: 0, hosts: 0, sources: 0, images: 0},
         %{genera: [], groups: [], sources: []}}
      end

    {:ok,
     assign(socket,
       page_title: "Plant Gall Identification",
       page_description:
         "Gallformers - The place to identify and learn about plant galls. A comprehensive database of plant galls and their causative organisms.",
       page_url: "/",
       page_image: nil,
       page_json_ld: build_website_json_ld(),
       random_gall: random_gall,
       stats: stats,
       genera: lists.genera,
       groups: lists.groups,
       sources: lists.sources,
       # Quick ID tool state
       host_query: "",
       host_results: [],
       selected_host: nil
     )}
  end

  defp fetch_stats do
    %{
      galls: Catalog.count_galls(),
      hosts: Taxa.count_plants(),
      sources: Sources.count_sources(),
      images: Images.count_images()
    }
  end

  defp fetch_lists do
    %{
      genera: Catalog.top_host_genera(12),
      groups: Enum.take(Catalog.inducer_groups(), 12),
      sources: Sources.list_recently_changed(8)
    }
  end

  defp build_website_json_ld do
    json_ld = %{
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => "Gallformers",
      "url" => "https://gallformers.org",
      "description" => "A comprehensive database of plant galls and their causative organisms",
      "potentialAction" => %{
        "@type" => "SearchAction",
        "target" => %{
          "@type" => "EntryPoint",
          "urlTemplate" => "https://gallformers.org/globalsearch?q={search_term_string}"
        },
        "query-input" => "required name=search_term_string"
      }
    }

    Jason.encode!(json_ld)
  end

  @impl true
  def handle_event("shuffle", _params, socket) do
    {:noreply, assign(socket, random_gall: Catalog.random_gall())}
  end

  # Quick ID tool events
  @impl true
  def handle_event("search_host", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Taxa.search_plants(query, 50)
      else
        []
      end

    {:noreply, assign(socket, host_query: query, host_results: results)}
  end

  @impl true
  def handle_event("select_host", %{"id" => id_str}, socket) do
    # On home page, selecting a host immediately navigates to ID page
    case host_name(socket.assigns.host_results, String.to_integer(id_str)) do
      nil -> {:noreply, socket}
      name -> {:noreply, push_navigate(socket, to: ~p"/id?h=#{name}")}
    end
  end

  @impl true
  def handle_event("clear_host", _params, socket) do
    {:noreply,
     assign(socket,
       selected_host: nil,
       host_query: "",
       host_results: []
     )}
  end

  # The chosen plant's accepted name, from the results shown.
  defp host_name(results, id) do
    case Enum.find(results, &(&1.id == id)) do
      %{name: name} -> name
      nil -> nil
    end
  end

  defp format_host_display(%{name: name, aliases: aliases}) when is_list(aliases) do
    case aliases do
      [] -> name
      alias_list -> "#{name} (#{Enum.join(alias_list, ", ")})"
    end
  end

  defp format_host_display(%{name: name}), do: name

  defp change_label(:added), do: "Added"
  defp change_label(:updated), do: "Updated"

  defp present?(value), do: value not in [nil, ""]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <div class="grid items-start gap-section xl:grid-cols-12">
          <div class="flex flex-col gap-4 xl:col-span-5 xl:pt-4">
            <.page_header>
              <:title>Welcome to Gallformers</:title>
              <:description>
                Plant galls are abnormal growths of plant tissues—similar to tumors or warts in
                animals—caused by insects, mites, fungi, bacteria, or other organisms. They're often
                intricate structures that can identify the species that made them, even when that
                organism isn't visible.
                <.link href="/articles/idguide" class="whitespace-nowrap">Learn more →</.link>
              </:description>
            </.page_header>
            <div class="flex flex-col gap-1 pt-2">
              <h2 class="text-section">Identify a plant gall</h2>
              <p class="max-w-text text-body text-ink-2">
                Start with the plant it's on, and Gallformers narrows {format_number(@stats.galls)} galls
                to the ones it could be.
              </p>
            </div>
            <div class="max-w-xl">
              <.typeahead
                id="home-host-picker"
                label="What plant is it on?"
                placeholder="Oak, Quercus alba, goldenrod…"
                query={@host_query}
                results={@host_results}
                selected={@selected_host}
                search_event="search_host"
                select_event="select_host"
                clear_event="clear_host"
                display_fn={&format_host_display/1}
              >
                <:result :let={host}>
                  <.taxon_name name={format_host_display(host)} />
                  <.chip :if={!host.datacomplete} variant={:warn} size="sm" class="ml-2">
                    incomplete
                  </.chip>
                </:result>
              </.typeahead>
            </div>
            <p class="text-meta text-muted">
              Or <.link href="/globalsearch">search by name</.link>, or <.link navigate="/galls">browse the galls</.link>.
            </p>
            <div class="flex flex-wrap gap-x-10 gap-y-3 pt-2">
              <.stat value={@stats.galls} label="Galls" navigate="/galls" />
              <.stat value={@stats.hosts} label="Host plants" navigate="/hosts" />
              <.stat value={@stats.sources} label="Sources" />
              <.stat value={@stats.images} label="Photos" />
            </div>
          </div>

          <section
            :if={@random_gall}
            id="random-gall"
            class="flex flex-col gap-3 xl:col-span-7"
            aria-label="A gall to meet"
          >
            <.link
              navigate={"/gall/#{@random_gall.id}"}
              class="flex h-120 items-center justify-center overflow-hidden rounded-panel bg-surface-2"
            >
              <img
                src={@random_gall.image_url}
                alt={"Photo of #{@random_gall.name}"}
                class="mx-auto max-h-120 w-full object-contain"
              />
            </.link>
            <div class="flex flex-wrap items-start gap-x-4 gap-y-2">
              <div class="flex min-w-0 flex-col gap-0.5">
                <.link
                  navigate={"/gall/#{@random_gall.id}"}
                  class="text-section font-semibold text-ink"
                >
                  <.taxon_name name={@random_gall.name} />
                </.link>
                <span :if={@random_gall.image_creator} class="text-caption text-muted">
                  Photo:
                  <a
                    :if={present?(@random_gall.image_sourcelink)}
                    href={@random_gall.image_sourcelink}
                    target="_blank"
                    rel="noreferrer"
                  >
                    {@random_gall.image_creator}
                  </a>
                  <span :if={!present?(@random_gall.image_sourcelink)}>
                    {@random_gall.image_creator}
                  </span>
                  <%= if @random_gall.image_license do %>
                    ·
                    <a
                      :if={present?(@random_gall.image_licenselink)}
                      href={@random_gall.image_licenselink}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {@random_gall.image_license}
                    </a>
                    <span :if={!present?(@random_gall.image_licenselink)}>
                      {@random_gall.image_license}
                    </span>
                  <% end %>
                </span>
              </div>
              <div class="ml-auto flex flex-wrap items-center gap-2">
                <.chip :if={@random_gall.undescribed} variant={:info}>Undescribed</.chip>
                <.button navigate={"/gall/#{@random_gall.id}"}>See this gall</.button>
                <.button variant="ghost" icon="ph-shuffle" phx-click="shuffle">
                  Show me another
                </.button>
              </div>
            </div>
          </section>
        </div>

        <div class="grid gap-section lg:grid-cols-2">
          <.section title="Start from the plant">
            <:aside><.link navigate="/hosts">All host plants</.link></:aside>
            <ul id="home-host-genera" class="grid grid-cols-1 gap-x-6 sm:grid-cols-2">
              <li :for={genus <- @genera}>
                <.category_tile
                  navigate={~p"/id?g=#{genus.name}"}
                  name={genus.name}
                  count={genus.count}
                  image_url={genus.image_url}
                  icon="gf-host"
                  italic
                />
              </li>
            </ul>
          </.section>
          <.section title="Browse by what causes them">
            <:aside><.link navigate="/galls">All galls</.link></:aside>
            <ul id="home-inducer-groups" class="grid grid-cols-1 gap-x-6 sm:grid-cols-2">
              <li :for={group <- @groups}>
                <.category_tile
                  navigate={"/galls#group-#{group.slug}"}
                  name={group.name}
                  count={group.count}
                  image_url={group.image_url}
                />
              </li>
            </ul>
          </.section>
        </div>

        <.section title="Recently changed">
          <:aside>Sources added or updated</:aside>
          <.data_table id="changed-sources" rows={@sources} row_navigate={&"/source/#{&1.id}"}>
            <:col :let={s} label="Date">{Calendar.strftime(s.changed_at, "%b %-d, %Y")}</:col>
            <:col :let={s} label="Change">
              <.chip variant={if s.change == :added, do: :ok, else: :info}>
                {change_label(s.change)}
              </.chip>
            </:col>
            <:col :let={s} label="Source" field={:title} grow>{s.title}</:col>
            <:col :let={s} label="Authors" field={:authors} hide_below={:md}>{s.authors}</:col>
            <:col :let={s} label="Year" field={:year} numeric hide_below={:md}>{s.year}</:col>
          </.data_table>
        </.section>

        <.panel variant={:info}>
          <div class="flex flex-wrap items-baseline gap-x-5 gap-y-1 text-ui">
            <span>Gallformers is made by volunteers.</span>
            <a href="https://www.patreon.com/gallformers" target="_blank" rel="noreferrer">
              Support it on Patreon ↗
            </a>
            <.link href="/about#administrators">Become a curator</.link>
            <a href="https://github.com/jeffdc/gallformers" target="_blank" rel="noreferrer">
              Contribute code ↗
            </a>
          </div>
        </.panel>
      </div>
    </Layouts.app>
    """
  end
end
