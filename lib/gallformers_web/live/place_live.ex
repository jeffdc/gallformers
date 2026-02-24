defmodule GallformersWeb.PlaceLive do
  @moduledoc """
  LiveView for the geographic place detail page.

  Displays a place with breadcrumb ancestors, children links, and a range map
  showing the place and its descendants highlighted.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Places

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    place = Places.get_place_by_code!(code)
    ancestors = Places.get_ancestors(place.id)
    children = Places.get_children(place.id)
    descendant_codes = Places.get_descendant_codes(place.id)
    bounds = Places.get_bounds_for_codes(descendant_codes)

    {:ok,
     assign(socket,
       page_title: place.name,
       page_description:
         "#{place.name} (#{place.code}) — geographic place in the Gallformers database.",
       page_url: "/place/#{place.code}",
       page_image: nil,
       page_json_ld: nil,
       place: place,
       ancestors: ancestors,
       children: children,
       descendant_codes: descendant_codes,
       bounds: bounds
     )}
  end

  @impl true
  def handle_event("navigate_to_place", %{"code" => code}, socket) do
    {:noreply, push_navigate(socket, to: "/place/#{code}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-7xl">
        <%!-- Breadcrumb --%>
        <nav class="mb-4 text-sm text-gray-500" aria-label="Breadcrumb">
          <ol class="flex items-center gap-1">
            <li>
              <.link navigate="/places" class="hover:underline hover:text-gf-maroon">
                Places
              </.link>
              <span class="mx-1 text-gray-400">&rsaquo;</span>
            </li>
            <li :for={ancestor <- @ancestors}>
              <.link navigate={"/place/#{ancestor.code}"} class="hover:underline hover:text-gf-maroon">
                {ancestor.name}
              </.link>
              <span class="mx-1 text-gray-400">&rsaquo;</span>
            </li>
            <li class="text-gray-700 font-medium">{@place.name}</li>
          </ol>
        </nav>

        <%!-- Header --%>
        <div class="mb-6">
          <h1 class="text-2xl font-bold text-gf-maroon">{@place.name}</h1>
          <div class="flex items-center gap-2 mt-1">
            <span class="text-gray-600 capitalize">{@place.type}</span>
            <.badge>{@place.code}</.badge>
          </div>
        </div>

        <%!-- Content: map + children --%>
        <div class={[
          "grid gap-6",
          if(@children != [], do: "grid-cols-1 md:grid-cols-3", else: "grid-cols-1 max-w-2xl")
        ]}>
          <%!-- Range map --%>
          <div class={if @children != [], do: "md:col-span-2"}>
            <.range_map
              id="place-range-map"
              in_range={@descendant_codes}
              bounds={@bounds}
              navigable
              place_mode
              class="h-[60vh] min-h-[400px]"
            />
          </div>

          <%!-- Children sidebar --%>
          <div :if={@children != []} class="md:col-span-1">
            <h2 class="text-lg font-semibold text-gray-800 mb-3">
              {children_label(@place.type)}
            </h2>
            <ul class="space-y-1">
              <li :for={child <- @children}>
                <.link
                  navigate={"/place/#{child.code}"}
                  class="text-gf-maroon hover:underline"
                >
                  {child.name}
                </.link>
              </li>
            </ul>
          </div>
        </div>

        <%!-- Back to browse --%>
        <div class="mt-8">
          <.link navigate="/places" class="text-sm text-gray-500 hover:underline">
            &larr; Browse all places
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp children_label("region"), do: "Continents"
  defp children_label("continent"), do: "Countries"
  defp children_label("country"), do: "Subdivisions"
  defp children_label(_), do: "Children"
end
