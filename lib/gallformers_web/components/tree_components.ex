defmodule GallformersWeb.TreeComponents do
  @moduledoc """
  Reusable tree browser component for displaying hierarchical data.
  """
  use Phoenix.Component
  import GallformersWeb.CoreComponents, only: [icon: 1]
  import GallformersWeb.DataDisplayComponents, only: [taxon_name: 1]
  import GallformersWeb.FormComponents, only: [search_input: 1]

  @doc """
  Renders a tree browser with search, expand/collapse controls, and hierarchical navigation.
  """
  attr :id, :string, required: true
  attr :nodes, :list, required: true
  attr :expanded, :any, required: true
  attr :search_query, :string, default: ""
  attr :show_search, :boolean, default: true
  attr :show_controls, :boolean, default: true
  attr :on_toggle, :string, required: true
  attr :on_expand_all, :string, required: true
  attr :on_collapse_all, :string, required: true
  attr :on_search, :string, required: true

  def tree_browser(assigns) do
    ~H"""
    <div id={@id} class="tree-browser">
      <%!-- Search and controls --%>
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-4">
        <div :if={@show_search} class="flex-1 max-w-md">
          <form phx-change={@on_search} phx-submit={@on_search} id={"#{@id}-search-form"}>
            <.search_input
              id={"#{@id}-search"}
              name="query"
              value={@search_query}
              placeholder="Filter by name..."
              phx-debounce="300"
            />
          </form>
        </div>
        <div :if={@show_controls} class="flex gap-2">
          <button phx-click={@on_expand_all} class="text-sm hover:underline">
            Expand All
          </button>
          <span class="text-gray-300">|</span>
          <button phx-click={@on_collapse_all} class="text-sm hover:underline">
            Collapse All
          </button>
        </div>
      </div>

      <%!-- Tree content --%>
      <div class="bg-white rounded-lg border border-gray-200 p-4">
        <%= if @nodes == [] do %>
          <p class="text-gray-500 italic">
            {if @search_query != "", do: "No matching items found.", else: "No items found."}
          </p>
        <% else %>
          <.tree_menu nodes={@nodes} expanded={@expanded} on_toggle={@on_toggle} level={0} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :nodes, :list, required: true
  attr :expanded, :any, required: true
  attr :on_toggle, :string, required: true
  attr :level, :integer, required: true

  defp tree_menu(assigns) do
    ~H"""
    <ul class={["list-none", if(@level > 0, do: "ml-5", else: "")]}>
      <li :for={node <- @nodes} class="py-1">
        <%= if Map.has_key?(node, :nodes) do %>
          <%!-- Branch node (family or genus) - has children (even if filtered to empty) --%>
          <div class="flex items-center gap-1">
            <button
              phx-click={@on_toggle}
              phx-value-key={node.key}
              class="flex items-center gap-1 text-left hover:text-gf-maroon focus:outline-none focus:text-gf-maroon"
            >
              <span class={[
                "inline-block w-4 h-4 transition-transform",
                if(MapSet.member?(@expanded, node.key), do: "rotate-90", else: "")
              ]}>
                <.icon name="ph-caret-right" class="w-4 h-4" />
              </span>
              <span class={[
                "font-medium",
                if(@level == 0, do: "text-gf-maroon", else: "")
              ]}>
                <.taxon_name name={node.name} rank={node.rank} />
                <span :if={node[:description]} class="font-normal">
                  ({node.description})
                </span>
              </span>
              <span class="text-xs text-gray-400 ml-1">
                ({length(node.nodes)})
              </span>
            </button>
            <.link
              :if={node[:url]}
              href={node.url}
              class="text-gray-400 hover:text-gf-maroon"
              title={"View #{node.label} details"}
            >
              <.icon name="ph-arrow-square-out" class="w-4 h-4" />
            </.link>
          </div>
          <.tree_menu
            :if={MapSet.member?(@expanded, node.key) and node.nodes != []}
            nodes={node.nodes}
            expanded={@expanded}
            on_toggle={@on_toggle}
            level={@level + 1}
          />
        <% else %>
          <%!-- Leaf node (species) --%>
          <.link href={node.url} class="flex items-center gap-1 ml-5 hover:underline">
            <.taxon_name name={node.label} />
          </.link>
        <% end %>
      </li>
    </ul>
    """
  end
end
