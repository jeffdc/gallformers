defmodule GallformersWeb.HomeLive do
  @moduledoc """
  The home page (design system, matter bc0d): a headline in the brand's own
  voice, the Host typeahead that opens the ID tool on a sky band, the counts
  as a sentence with the cynipid mark, a random Gall large with "Show me
  another" (named and summed up by `gall_name` and `gall_summary`), the
  Gallformer groups as photos and the Host genera to start from, and the
  Source changed most recently.
  """
  use GallformersWeb, :live_view

  alias Gallformers.{Catalog, Sources, Taxa}

  @impl true
  def mount(_params, _session, socket) do
    # Only fetch data when connected to avoid fetching twice
    {random_gall, stats, lists} =
      if connected?(socket) do
        {random_gall(), fetch_stats(), fetch_lists()}
      else
        {nil, %{galls: 0, undescribed: 0, hosts: 0, sources: 0},
         %{genera: [], groups: [], newest: nil}}
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
       newest: lists.newest,
       # Quick ID tool state
       host_query: "",
       host_results: [],
       selected_host: nil
     )}
  end

  defp fetch_stats do
    counts = Catalog.gall_counts()

    %{
      galls: counts.galls,
      undescribed: counts.undescribed,
      hosts: Taxa.count_plants(),
      sources: Sources.count_sources()
    }
  end

  defp fetch_lists do
    %{
      genera: Catalog.top_host_genera(8),
      groups:
        Catalog.inducer_groups()
        |> Enum.take(12)
        |> Enum.map(&%{&1 | image_url: medium(&1.image_url)}),
      newest: newest(Sources.list_recently_changed(8))
    }
  end

  # Group photos come small; a photo tile wants the medium size.
  defp medium(nil), do: nil
  defp medium(url), do: String.replace(url, ~r/_small(\.\w+)$/, "_medium\\1")

  # The random Gall with what `gall_summary` says of it.
  defp random_gall do
    case Catalog.random_gall() do
      nil ->
        nil

      gall ->
        details = Map.get(Catalog.gall_search_details([gall.id]), gall.id, %{})

        Map.merge(
          %{hosts: [], plant_part: [], season: []},
          Map.take(details, [:hosts, :plant_part, :season])
        )
        |> Map.merge(gall)
    end
  end

  # The Source changed most recently, and how many others since the eighth.
  defp newest([]), do: nil

  defp newest([source | rest] = sources) do
    %{source: source, others: length(rest), since: List.last(sources).changed_at}
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
    {:noreply, assign(socket, random_gall: random_gall())}
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

  defp present?(value), do: value not in [nil, ""]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <div class="grid items-start gap-section xl:grid-cols-12">
          <div class="flex flex-col gap-6 xl:col-span-5 xl:pt-6">
            <h1 class="font-brand text-display font-semibold text-brand text-balance">
              Found something odd growing on a plant?
            </h1>
            <p class="max-w-text text-lead text-ink-2">
              It's probably a gall: plant tissue that a wasp, midge, mite or fungus has rebuilt
              into a home. Tell Gallformers the plant, and it narrows {format_number(@stats.galls)} galls to the ones yours could be.
              <.link href="/articles/idguide" class="whitespace-nowrap">Learn more →</.link>
            </p>

            <div class="flex flex-col gap-2 rounded-panel bg-sky p-panel">
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
              <p class="text-meta text-ink-2">
                Or <.link href="/globalsearch">search by name</.link>, or <.link navigate="/galls">browse the galls</.link>.
              </p>
            </div>

            <div class="flex items-end gap-4">
              <p id="home-counts" class="max-w-text flex-1 text-body text-ink-2">
                Gallformers knows
                <.link navigate="/galls" class="font-semibold tabular-nums">
                  {format_number(@stats.galls)} galls
                </.link>
                on <.link navigate="/hosts" class="font-semibold tabular-nums">{format_number(@stats.hosts)} host plants</.link>,
                drawn from
                <span class="font-semibold tabular-nums text-ink">
                  {format_number(@stats.sources)}
                </span>
                Sources.
                <span class="font-semibold tabular-nums text-ink">
                  {format_number(@stats.undescribed)}
                </span>
                of them are still undescribed, waiting for someone to rear the maker and name it.
              </p>
              <.cynipid_mark class="hidden h-28 w-44 shrink-0 text-brand sm:block" />
            </div>
          </div>

          <section
            :if={@random_gall}
            id="random-gall"
            class="flex flex-col gap-3 xl:col-span-7"
            aria-label="A gall to meet"
          >
            <div class="relative overflow-hidden rounded-panel bg-surface-2">
              <.link navigate={"/gall/#{@random_gall.id}"} class="block">
                <img
                  src={@random_gall.image_url}
                  alt={"Photo of #{@random_gall.name}"}
                  class="aspect-4/3 w-full object-cover"
                />
              </.link>
              <.button icon="ph-shuffle" phx-click="shuffle" class="absolute bottom-4 right-4">
                Show me another
              </.button>
            </div>

            <div class="flex flex-col gap-1">
              <.link
                navigate={"/gall/#{@random_gall.id}"}
                class="font-brand text-page font-semibold text-ink text-balance"
              >
                <.gall_name name={@random_gall.name} undescribed={@random_gall.undescribed} article />
              </.link>
              <.gall_summary
                hosts={@random_gall.hosts}
                plant_part={@random_gall.plant_part}
                season={@random_gall.season}
                name={@random_gall.name}
                undescribed={@random_gall.undescribed}
                class="text-lead text-ink-2"
              />
              <p
                :if={@random_gall.image_creator || @random_gall.image_license}
                class="text-caption text-muted"
              >
                <span :if={@random_gall.image_creator}>
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
                </span>
                <span :if={@random_gall.image_license}>
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
                </span>
              </p>
            </div>
          </section>
        </div>

        <.section title="The gallformers">
          <:aside><.link navigate="/galls">All galls</.link></:aside>
          <ul id="home-inducer-groups" class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
            <li :for={{group, i} <- Enum.with_index(@groups)} class={i >= 6 && "hidden sm:block"}>
              <.category_tile
                navigate={"/galls#group-#{group.slug}"}
                name={group.name}
                count={group.count}
                image_url={group.image_url}
                layout={:tile}
              />
            </li>
          </ul>
        </.section>

        <.section title="Start from the plant">
          <:aside><.link navigate="/hosts">All host plants</.link></:aside>
          <ul id="home-host-genera" class="grid grid-cols-1 gap-x-6 sm:grid-cols-2 xl:grid-cols-4">
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

        <p :if={@newest} id="newest-source" class="max-w-text text-body text-ink-2">
          Newest in the library: <.link navigate={"/source/#{@newest.source.id}"}>{@newest.source.title}</.link>{newest_after(
            @newest
          )}
        </p>

        <.panel variant={:info}>
          <div class="flex flex-wrap items-baseline gap-x-5 gap-y-1 text-ui">
            <span>Gallformers is made by volunteers who caught the gall bug.</span>
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

  # " (InfluentialPoints, 2026), added Nov 4. 7 more Sources were added or updated since Sep 2."
  defp newest_after(%{source: source, others: others, since: since}) do
    by = [source.authors, source.year] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(", ")
    verb = if source.change == :added, do: "added", else: "updated"

    others_text =
      if others > 0,
        do:
          " #{others} more Sources were added or updated since #{Calendar.strftime(since, "%b %-d")}.",
        else: ""

    "#{if by != "", do: " (#{by})"}, #{verb} #{Calendar.strftime(source.changed_at, "%b %-d")}." <>
      others_text
  end
end
