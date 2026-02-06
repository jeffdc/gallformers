defmodule GallformersWeb.Admin.TaxonomyLive.Index do
  @moduledoc """
  Admin page for listing and managing taxonomic classifications.

  Displays families, genera, and sections with their hierarchical relationships.
  Supports moving genera between families via selection and modal.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Taxonomy

  @page_size 50
  @valid_sort_columns ~w(name type description parent_name)

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    if connected?(socket), do: Taxonomy.subscribe()

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Taxonomy")
      |> assign(:search_query, "")
      |> assign(:filter_type, nil)
      |> assign(:current_page, 1)
      |> assign(:page_size, @page_size)
      |> assign(:sort_by, :name)
      |> assign(:sort_dir, :asc)
      |> assign(:selected_genera, MapSet.new())
      |> assign(:show_move_modal, false)
      |> assign(:families, [])
      |> assign(:move_target_family_id, nil)
      |> assign(:hide_empty_unknown, true)
      |> load_taxonomies()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Taxonomy")
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> assign(:current_page, 1)
      |> load_taxonomies()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_type", %{"type" => type}, socket) do
    filter_type = if type == "", do: nil, else: type

    socket =
      socket
      |> assign(:filter_type, filter_type)
      |> assign(:current_page, 1)
      |> load_taxonomies()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_empty_unknown", _params, socket) do
    socket =
      socket
      |> assign(:hide_empty_unknown, !socket.assigns.hide_empty_unknown)
      |> assign(:current_page, 1)
      |> load_taxonomies()

    {:noreply, socket}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    page = max(1, min(page, total_pages(socket.assigns.taxonomies, socket.assigns.page_size)))
    {:noreply, assign(socket, current_page: page)}
  end

  @impl true
  def handle_event("sort", %{"column" => column}, socket) when column in @valid_sort_columns do
    column_atom = String.to_atom(column)

    {new_sort_by, new_sort_dir} =
      if socket.assigns.sort_by == column_atom do
        new_dir = if socket.assigns.sort_dir == :asc, do: :desc, else: :asc
        {column_atom, new_dir}
      else
        {column_atom, :asc}
      end

    {:noreply,
     socket
     |> assign(:sort_by, new_sort_by)
     |> assign(:sort_dir, new_sort_dir)
     |> assign(:current_page, 1)}
  end

  @impl true
  def handle_event("delete", %{"id" => _id}, socket) do
    # Taxonomy deletion is disabled until soft delete is implemented
    # Deleting taxonomy entries can cascade to hundreds of downstream records
    {:noreply,
     put_flash(
       socket,
       :error,
       "Taxonomy deletion is temporarily disabled. Deleting a family or genus can cascade to " <>
         "hundreds of species records. This will be re-enabled once soft delete is implemented."
     )}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    selected = socket.assigns.selected_genera

    new_selected =
      if MapSet.member?(selected, id) do
        MapSet.delete(selected, id)
      else
        MapSet.put(selected, id)
      end

    {:noreply, assign(socket, :selected_genera, new_selected)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_genera, MapSet.new())}
  end

  @impl true
  def handle_event("open_move_modal", _params, socket) do
    families = Taxonomy.list_families_for_select()

    {:noreply,
     socket
     |> assign(:show_move_modal, true)
     |> assign(:families, families)
     |> assign(:move_target_family_id, nil)}
  end

  @impl true
  def handle_event("close_move_modal", _params, socket) do
    {:noreply, assign(socket, :show_move_modal, false)}
  end

  @impl true
  def handle_event("select_target_family", %{"family_id" => family_id}, socket) do
    family_id = if family_id == "", do: nil, else: String.to_integer(family_id)
    {:noreply, assign(socket, :move_target_family_id, family_id)}
  end

  @impl true
  def handle_event("move_genera", _params, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_genera)
    target_family_id = socket.assigns.move_target_family_id

    if target_family_id == nil do
      {:noreply, put_flash(socket, :error, "Please select a destination family.")}
    else
      # Get the current family of the first selected genus to use as old_family_id
      first_genus = Taxonomy.get_taxonomy!(hd(selected_ids))
      old_family_id = first_genus.parent_id

      case Taxonomy.move_genera(selected_ids, old_family_id, target_family_id) do
        {:ok, count} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             "Successfully moved #{count} #{if count == 1, do: "genus", else: "genera"}."
           )
           |> assign(:show_move_modal, false)
           |> assign(:selected_genera, MapSet.new())
           |> load_taxonomies()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to move genera: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_info({event, _taxonomy}, socket)
      when event in [:taxonomy_created, :taxonomy_updated, :taxonomy_deleted] do
    {:noreply, load_taxonomies(socket)}
  end

  @impl true
  def handle_info(:genera_moved, socket) do
    {:noreply, load_taxonomies(socket)}
  end

  defp load_taxonomies(socket) do
    hide_empty_unknown = socket.assigns.hide_empty_unknown
    opts = [hide_empty_unknown: hide_empty_unknown]

    taxonomies =
      case {socket.assigns.search_query, socket.assigns.filter_type} do
        {"", nil} -> Taxonomy.list_taxonomies_with_parent(nil, opts)
        {"", type} -> Taxonomy.list_taxonomies_with_parent(type, opts)
        {query, type} -> search_and_filter(query, type, hide_empty_unknown)
      end

    assign(socket, :taxonomies, taxonomies)
  end

  defp search_and_filter(query, type, hide_empty_unknown) do
    taxonomies = Taxonomy.search_taxonomies(query, type, 500)

    # Batch fetch all parent records (1 query instead of up to 500)
    parent_ids =
      taxonomies
      |> Enum.map(& &1.parent_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    parents_map = Taxonomy.get_taxonomies_batch(parent_ids)

    results =
      Enum.map(taxonomies, fn t ->
        parent = Map.get(parents_map, t.parent_id)

        %{
          id: t.id,
          name: t.name,
          description: t.description,
          type: t.type,
          parent_id: t.parent_id,
          parent_name: parent && parent.name,
          parent_type: parent && parent.type
        }
      end)

    if hide_empty_unknown do
      empty_ids = Taxonomy.empty_unknown_genus_ids()
      Enum.reject(results, fn t -> t.id in empty_ids end)
    else
      results
    end
  end

  defp sorted_taxonomies(taxonomies, sort_by, sort_dir) do
    sorted =
      Enum.sort_by(taxonomies, fn t ->
        value =
          case sort_by do
            :name -> t.name
            :type -> t.type
            :description -> t.description
            :parent_name -> t.parent_name
            _ -> t.name
          end

        if is_binary(value), do: String.downcase(value), else: value || ""
      end)

    if sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp paginated_taxonomies(taxonomies, current_page, page_size, sort_by, sort_dir) do
    taxonomies
    |> sorted_taxonomies(sort_by, sort_dir)
    |> Enum.drop((current_page - 1) * page_size)
    |> Enum.take(page_size)
  end

  defp total_pages(taxonomies, page_size) do
    max(1, ceil(length(taxonomies) / page_size))
  end

  defp taxonomy_public_url(%{type: "family", id: id}), do: ~p"/family/#{id}"
  defp taxonomy_public_url(%{type: "genus", id: id}), do: ~p"/genus/#{id}"
  defp taxonomy_public_url(%{type: "section", id: id}), do: ~p"/section/#{id}"
  defp taxonomy_public_url(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Taxonomy">
      <div class="space-y-6">
        <%!-- Header with search, filter, and buttons --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div class="flex items-center gap-4 flex-1 max-w-2xl">
            <form phx-change="search" phx-submit="search" id="taxonomy-search-form" class="flex-1">
              <.search_input
                id="taxonomy-search"
                name="query"
                value={@search_query}
                placeholder="Search taxonomy..."
                phx-debounce="300"
              />
            </form>
            <form phx-change="filter_type">
              <.input
                type="select"
                name="type"
                prompt="All Types"
                options={[{"Families", "family"}, {"Genera", "genus"}, {"Sections", "section"}]}
                value={@filter_type}
              />
            </form>
            <label class="flex items-center gap-2 text-sm text-gray-600 cursor-pointer whitespace-nowrap">
              <input
                type="checkbox"
                checked={@hide_empty_unknown}
                phx-click="toggle_empty_unknown"
                class="h-4 w-4 rounded border-gray-300 text-gf-maroon focus:ring-gf-maroon"
              /> Hide empty Unknown
            </label>
          </div>
          <div class="flex items-center gap-2">
            <button
              :if={MapSet.size(@selected_genera) > 0}
              type="button"
              phx-click="open_move_modal"
              class="gf-btn gf-btn-secondary"
            >
              <.icon name="ph-arrow-right" class="h-4 w-4 mr-1" />
              Move {MapSet.size(@selected_genera)} Selected
            </button>
            <button
              :if={MapSet.size(@selected_genera) > 0}
              type="button"
              phx-click="clear_selection"
              class="gf-btn gf-btn-ghost text-sm"
            >
              Clear
            </button>
            <.link navigate={~p"/admin/taxonomy/new"} class="gf-btn gf-btn-primary">
              New Entry
            </.link>
          </div>
        </div>

        <%!-- Taxonomy list table --%>
        <div class="bg-white shadow rounded-lg overflow-hidden">
          <table class="gf-table gf-table-dark">
            <thead>
              <tr>
                <th class="w-10"></th>
                <th class="sortable" phx-click="sort" phx-value-column="name">
                  Name
                  <span :if={@sort_by == :name} class="ml-1">
                    {if @sort_dir == :asc, do: "↑", else: "↓"}
                  </span>
                </th>
                <th class="sortable" phx-click="sort" phx-value-column="type">
                  Type
                  <span :if={@sort_by == :type} class="ml-1">
                    {if @sort_dir == :asc, do: "↑", else: "↓"}
                  </span>
                </th>
                <th class="sortable" phx-click="sort" phx-value-column="description">
                  Description
                  <span :if={@sort_by == :description} class="ml-1">
                    {if @sort_dir == :asc, do: "↑", else: "↓"}
                  </span>
                </th>
                <th class="sortable" phx-click="sort" phx-value-column="parent_name">
                  Parent
                  <span :if={@sort_by == :parent_name} class="ml-1">
                    {if @sort_dir == :asc, do: "↑", else: "↓"}
                  </span>
                </th>
                <th class="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={
                  taxonomy <-
                    paginated_taxonomies(@taxonomies, @current_page, @page_size, @sort_by, @sort_dir)
                }
                class={if MapSet.member?(@selected_genera, taxonomy.id), do: "bg-canary", else: ""}
              >
                <td class="text-center">
                  <%= if taxonomy.type == "genus" do %>
                    <input
                      type="checkbox"
                      checked={MapSet.member?(@selected_genera, taxonomy.id)}
                      phx-click="toggle_select"
                      phx-value-id={taxonomy.id}
                      class="h-4 w-4 rounded border-gray-300 text-gf-maroon focus:ring-gf-maroon"
                    />
                  <% end %>
                </td>
                <td>
                  <.link
                    navigate={~p"/admin/taxonomy/#{taxonomy.id}"}
                    class="hover:underline font-medium"
                  >
                    {taxonomy.name}
                  </.link>
                </td>
                <td>
                  <.type_badge type={taxonomy.type} />
                </td>
                <td class="text-gray-500">
                  {taxonomy.description || "—"}
                </td>
                <td>
                  <%= if taxonomy.parent_name do %>
                    <span class="text-gray-900">{taxonomy.parent_name}</span>
                    <span class="text-gray-500 text-xs ml-1">({taxonomy.parent_type})</span>
                  <% else %>
                    <span class="text-gray-400">—</span>
                  <% end %>
                </td>
                <td class="text-right">
                  <.table_actions>
                    <.action_button
                      icon="ph-pencil-simple"
                      label="Edit"
                      navigate={~p"/admin/taxonomy/#{taxonomy.id}"}
                      variant="primary"
                    />
                    <.action_button
                      icon="ph-arrow-square-out"
                      label="View"
                      navigate={taxonomy_public_url(taxonomy)}
                    />
                    <.action_button
                      icon="ph-trash"
                      label="Delete"
                      variant="danger"
                      phx-click="delete"
                      phx-value-id={taxonomy.id}
                    />
                  </.table_actions>
                </td>
              </tr>
              <tr :if={@taxonomies == []}>
                <td colspan="6" class="text-center text-gray-500">
                  No taxonomy entries found.
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%= if total_pages(@taxonomies, @page_size) > 1 do %>
          <.pagination
            page={@current_page}
            total_pages={total_pages(@taxonomies, @page_size)}
            total_items={length(@taxonomies)}
            page_size={@page_size}
            on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
          />
        <% else %>
          <p class="text-sm text-gray-500">
            Showing {length(@taxonomies)} entries
          </p>
        <% end %>
      </div>

      <%!-- Move Genera Modal --%>
      <.modal
        :if={@show_move_modal}
        id="move-genera-modal"
        show
        on_cancel={JS.push("close_move_modal")}
      >
        <:header>
          <h3 class="text-lg font-semibold text-gray-900">
            Move {MapSet.size(@selected_genera)} {if MapSet.size(@selected_genera) == 1,
              do: "Genus",
              else: "Genera"}
          </h3>
        </:header>

        <:body>
          <div class="space-y-4">
            <div>
              <p class="text-sm text-gray-600 mb-2">Selected genera:</p>
              <div class="flex flex-wrap gap-2">
                <%= for taxonomy <- Enum.filter(@taxonomies, fn t -> MapSet.member?(@selected_genera, t.id) end) do %>
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-sm font-medium bg-green-100 text-green-800">
                    {taxonomy.name}
                  </span>
                <% end %>
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Destination Family
              </label>
              <select phx-change="select_target_family" name="family_id" class="gf-select w-full">
                <option value="">Select a family...</option>
                <%= for {name, id} <- @families do %>
                  <option value={id} selected={@move_target_family_id == id}>{name}</option>
                <% end %>
              </select>
            </div>

            <div class="bg-amber-50 border border-amber-200 rounded-lg p-3">
              <p class="text-sm text-amber-800">
                <.icon name="ph-warning" class="h-4 w-4 inline mr-1" />
                This will move the selected genera and all their species to the new family.
                This change takes effect immediately.
              </p>
            </div>
          </div>
        </:body>

        <:footer>
          <button type="button" phx-click="close_move_modal" class="gf-btn gf-btn-secondary">
            Cancel
          </button>
          <button
            type="button"
            phx-click="move_genera"
            disabled={@move_target_family_id == nil}
            class="gf-btn gf-btn-primary"
          >
            Move to Selected Family
          </button>
        </:footer>
      </.modal>
    </Layouts.admin>
    """
  end

  defp type_badge(assigns) do
    color_class =
      case assigns.type do
        "family" -> "bg-blue-100 text-blue-800"
        "genus" -> "bg-green-100 text-green-800"
        "section" -> "bg-purple-100 text-purple-800"
        _ -> "bg-gray-100 text-gray-800"
      end

    assigns = assign(assigns, :color_class, color_class)

    ~H"""
    <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{@color_class}"}>
      {@type}
    </span>
    """
  end
end
