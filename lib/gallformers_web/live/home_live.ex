defmodule GallformersWeb.HomeLive do
  @moduledoc """
  LiveView for the home page.

  Quick ID tool design with:
  - Host plant typeahead to jump into ID tool
  - Quick action chips
  - Database stats banner
  - Featured random gall
  """
  use GallformersWeb, :live_view

  alias Gallformers.{Galls, Images, Sources}
  alias Gallformers.Plants

  @impl true
  def mount(_params, _session, socket) do
    # Only fetch data when connected to avoid fetching twice
    {random_gall, stats} =
      if connected?(socket) do
        {Galls.random_gall(), fetch_stats()}
      else
        {nil, %{galls: 0, hosts: 0, sources: 0, images: 0}}
      end

    {:ok,
     assign(socket,
       page_title: "Plant Gall Identification",
       page_description:
         "Gallformers - The place to identify and learn about galls on plants in the US and Canada. A comprehensive database of plant galls and their causative organisms.",
       page_url: "/",
       page_image: nil,
       page_json_ld: build_website_json_ld(),
       random_gall: random_gall,
       stats: stats,
       # Quick ID tool state
       host_query: "",
       host_results: [],
       selected_host: nil
     )}
  end

  defp fetch_stats do
    %{
      galls: Galls.count_galls(),
      hosts: Plants.count_hosts(),
      sources: Sources.count_sources(),
      images: Images.count_images()
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

  # Quick ID tool events
  @impl true
  def handle_event("search_host", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Plants.search_hosts(query, 50)
      else
        []
      end

    {:noreply, assign(socket, host_query: query, host_results: results)}
  end

  @impl true
  def handle_event("select_host", %{"id" => id_str}, socket) do
    host = Plants.get_host(String.to_integer(id_str))

    # On home page, selecting a host immediately navigates to ID page
    {:noreply, push_navigate(socket, to: ~p"/id?h=#{host.name}")}
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

  @impl true
  def handle_event("go_to_id", _params, socket) do
    path =
      if socket.assigns.selected_host do
        ~p"/id?h=#{socket.assigns.selected_host.name}"
      else
        ~p"/id"
      end

    {:noreply, push_navigate(socket, to: path)}
  end

  defp format_host_display(%{name: name, aliases: aliases}) when is_list(aliases) do
    case aliases do
      [] -> name
      alias_list -> "#{name} (#{Enum.join(alias_list, ", ")})"
    end
  end

  defp format_host_display(%{name: name}), do: name

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <%!-- Welcome + Definition --%>
      <div class="text-center mb-8">
        <h1 class="text-3xl font-bold text-gf-maroon mb-4">Welcome to Gallformers</h1>
        <div class="max-w-5xl mx-auto border-2 border-gf-sky-blue rounded-lg bg-white p-4">
          <p class="text-gray-700 leading-relaxed">
            Plant galls are abnormal growths of plant tissues—similar to tumors or warts in
            animals—caused by insects, mites, fungi, bacteria, or other organisms. They're often
            intricate structures that can identify the species that made them, even when that
            organism isn't visible.
            <.link href="/articles/idguide" class="text-gf-maroon hover:underline whitespace-nowrap">
              Learn more →
            </.link>
          </p>
        </div>
      </div>

      <%!-- ID Tool + Random Gall --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
        <%!-- Left column: ID Tool + Quick Links --%>
        <div>
          <%!-- Quick ID Tool --%>
          <.card title="Identify a Gall" icon="ph-crosshair">
            <p class="mb-3">
              If you know the host plant that the gall is on start here.
            </p>
            <div class="mb-3">
              <.typeahead
                id="home-host-picker"
                label="Host Plant:"
                placeholder="Type a host plant (oak, Quercus, willow...)"
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
                  <span :if={!host.datacomplete} class="ml-2 text-xs text-amber-600">
                    (incomplete)
                  </span>
                </:result>
              </.typeahead>
            </div>
            <button
              type="button"
              phx-click="go_to_id"
              class="w-full px-4 py-2 bg-gf-maroon text-white rounded-lg hover:bg-gf-maroon/90 font-medium"
            >
              Find Galls →
            </button>
          </.card>

          <%!-- Things You Can Do --%>
          <div class="mt-4">
            <.card title="Things You Can Do" icon="ph-list">
              <div class="flex flex-wrap gap-2">
                <.link
                  href="/globalsearch"
                  class="inline-flex items-center px-4 py-2 bg-gray-100 text-gray-700 rounded-full hover:bg-gray-200"
                >
                  <.icon name="ph-magnifying-glass" class="size-5 mr-2" /> Search
                </.link>
                <.link
                  href="/id"
                  class="inline-flex items-center px-4 py-2 bg-gray-100 text-gray-700 rounded-full hover:bg-gray-200"
                >
                  <.icon name="ph-crosshair" class="size-5 mr-2" /> Identify
                </.link>
                <.link
                  href="/articles"
                  class="inline-flex items-center px-4 py-2 bg-gray-100 text-gray-700 rounded-full hover:bg-gray-200"
                >
                  <.icon name="ph-article" class="size-5 mr-2" /> Articles
                </.link>
                <.link
                  href="/explore"
                  class="inline-flex items-center px-4 py-2 bg-gray-100 text-gray-700 rounded-full hover:bg-gray-200"
                >
                  <.icon name="ph-compass" class="size-5 mr-2" /> Explore
                </.link>
              </div>
            </.card>
          </div>

          <%!-- Help Us Out --%>
          <div class="mt-4">
            <.card title="Help Us Out" icon="ph-hand-heart">
              <p class="mb-3">
                Gallformers is a community project. Here's how you can contribute:
              </p>
              <div class="flex flex-wrap gap-2">
                <.link
                  href="https://www.patreon.com/gallformers"
                  target="_blank"
                  rel="noreferrer"
                  class="inline-flex items-center px-4 py-2 bg-gray-100 text-gray-700 rounded-full hover:bg-gray-200"
                >
                  <.icon name="ph-heart" class="size-5 mr-2" /> Patreon
                </.link>
                <.link
                  href="/about#administrators"
                  class="inline-flex items-center px-4 py-2 bg-gray-100 text-gray-700 rounded-full hover:bg-gray-200"
                >
                  <.icon name="ph-users" class="size-5 mr-2" /> Become an Admin
                </.link>
                <.link
                  href="https://github.com/jeffdc/gallformers"
                  target="_blank"
                  rel="noreferrer"
                  class="inline-flex items-center px-4 py-2 bg-gray-100 text-gray-700 rounded-full hover:bg-gray-200"
                >
                  <.icon name="ph-code" class="size-5 mr-2" /> Contribute Code
                </.link>
              </div>
            </.card>
          </div>
        </div>

        <%!-- Random Gall --%>
        <.card title="Random Gall" icon="ph-shuffle" class="h-fit">
          <%= if @random_gall do %>
            <.link href={"/gall/#{@random_gall.id}"} class="block -mx-4 -mt-4 mb-4">
              <img
                src={@random_gall.image_url}
                alt={@random_gall.name}
                class="w-full aspect-[4/3] object-cover"
              />
            </.link>
            <.link href={"/gall/#{@random_gall.id}"} class="hover:underline">
              <.taxon_name name={@random_gall.name} class="text-gf-maroon font-medium" />
            </.link>
            <%= if @random_gall.undescribed do %>
              <span class="ml-2 text-xs bg-amber-100 text-amber-800 px-2 py-0.5 rounded">
                Undescribed
              </span>
            <% end %>
            <%= if @random_gall.image_creator do %>
              <p class="text-xs text-gray-500 mt-2">
                Photo:
                <%= if @random_gall.image_sourcelink not in [nil, ""] do %>
                  <a
                    href={@random_gall.image_sourcelink}
                    target="_blank"
                    rel="noreferrer"
                    class="hover:underline"
                  >
                    {@random_gall.image_creator}
                  </a>
                <% else %>
                  {@random_gall.image_creator}
                <% end %>
                <%= if @random_gall.image_license do %>
                  <span class="ml-1">
                    ©
                    <%= if @random_gall.image_licenselink not in [nil, ""] do %>
                      <a
                        href={@random_gall.image_licenselink}
                        target="_blank"
                        rel="noreferrer"
                        class="hover:underline"
                      >
                        {@random_gall.image_license}
                      </a>
                    <% else %>
                      {@random_gall.image_license}
                    <% end %>
                  </span>
                <% end %>
              </p>
            <% end %>
          <% else %>
            <div class="text-center text-gray-600">
              <p>Loading...</p>
            </div>
          <% end %>
        </.card>
      </div>

      <%!-- Stats Banner (bottom) --%>
      <div class="bg-gradient-to-r from-gf-maroon to-gf-maroon/80 text-white rounded-lg p-6">
        <h2 class="text-lg font-semibold text-center mb-4 opacity-90">By the Numbers</h2>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-center">
          <div>
            <.icon name="gf-gall" class="size-8 mx-auto mb-1" />
            <div class="text-3xl font-bold">{format_number(@stats.galls)}</div>
            <div class="text-base opacity-90">Galls</div>
          </div>
          <div>
            <.icon name="gf-host" class="size-8 mx-auto mb-1" />
            <div class="text-3xl font-bold">{format_number(@stats.hosts)}</div>
            <div class="text-base opacity-90">Host Plants</div>
          </div>
          <div>
            <.icon name="gf-source" class="size-8 mx-auto mb-1" />
            <div class="text-3xl font-bold">{format_number(@stats.sources)}</div>
            <div class="text-base opacity-90">Sources</div>
          </div>
          <div>
            <.icon name="ph-image" class="size-8 mx-auto mb-1" />
            <div class="text-3xl font-bold">{format_number(@stats.images)}</div>
            <div class="text-base opacity-90">Images</div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
