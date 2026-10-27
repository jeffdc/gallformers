defmodule GallformersWeb.Admin.TaxonomyLive.Index do
  @moduledoc """
  The taxonomy admin's list (matter a856, Task 9), at `/admin/taxonomy`:
  search taxa of every rank by accepted name, synonym or common name
  (`?q=`), or browse the tree from its roots down (`?parent=ID`). Each taxon
  links to its page (`GallformersWeb.Admin.TaxonomyLive.Edit`).

  Browsing a taxon's children, several can be selected and moved under
  another parent at once (the old "move genera"), each move through
  `Gallformers.Import.record_taxonomy_edit/2` as the signed-in admin.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Import
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon
  alias GallformersWeb.Admin.TaxonomyLive.Errors

  @search_limit 200
  @parent_results 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Taxonomy",
       selected: MapSet.new(),
       show_move_modal: false,
       move_query: "",
       move_results: [],
       move_target: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params |> Map.get("q", "") |> String.trim()

    socket =
      socket
      |> assign(:query, query)
      |> assign(:selected, MapSet.new())
      |> assign(:parent, parent(params["parent"]))
      |> load()

    {:noreply, socket}
  end

  defp parent(nil), do: nil

  defp parent(id) do
    with {id, ""} <- Integer.parse(id),
         %Taxon{} = taxon <- Taxa.get_taxon(id),
         do: taxon,
         else: (_ -> nil)
  end

  defp load(%{assigns: %{query: query}} = socket) when query != "" do
    hits = Taxa.search(query)

    socket
    |> assign(:mode, :search)
    |> assign(:total, length(hits))
    |> assign(:rows, hits |> Enum.take(@search_limit) |> Enum.map(&search_row/1))
    |> assign(:lineage, [])
  end

  defp load(%{assigns: %{parent: nil}} = socket) do
    socket
    |> assign(:mode, :browse)
    |> assign(:lineage, [])
    |> assign_children(Taxa.root_taxa())
  end

  defp load(%{assigns: %{parent: parent}} = socket) do
    socket
    |> assign(:mode, :browse)
    |> assign(:lineage, Taxa.lineage(parent))
    |> assign_children(Taxa.children_with_ranks(parent.id))
  end

  defp search_row(hit) do
    %{
      id: hit.id,
      name: hit.name,
      rank: hit.rank,
      kingdom: hit.kingdom,
      aliases: hit.aliases,
      child_count: nil
    }
  end

  defp assign_children(socket, children) do
    counts =
      children
      |> Enum.map(& &1.taxon_id)
      |> Taxa.children_by_parent()
      |> Map.new(fn {id, kids} -> {id, length(kids)} end)

    rows =
      for child <- children do
        %{
          id: child.taxon_id,
          name: child.name,
          rank: child.rank,
          kingdom: nil,
          aliases: child.common_names,
          child_count: Map.get(counts, child.taxon_id, 0)
        }
      end

    socket
    |> assign(:rows, rows)
    |> assign(:total, length(rows))
  end

  # -- search ------------------------------------------------------------------

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, push_patch(socket, to: index_path(%{"q" => String.trim(query)}))}
  end

  # -- moving the selected children --------------------------------------------

  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = socket.assigns.selected

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("clear_selection", _params, socket),
    do: {:noreply, assign(socket, :selected, MapSet.new())}

  def handle_event("open_move_modal", _params, socket) do
    {:noreply,
     assign(socket, show_move_modal: true, move_query: "", move_results: [], move_target: nil)}
  end

  def handle_event("close_move_modal", _params, socket),
    do: {:noreply, assign(socket, :show_move_modal, false)}

  def handle_event("search_move_target", %{"value" => query}, socket) do
    results =
      if String.length(String.trim(query)) >= 2 do
        ranks = target_ranks(socket)

        query
        |> Taxa.search(ranks: ranks)
        |> Enum.reject(&MapSet.member?(socket.assigns.selected, &1.id))
        |> Enum.take(@parent_results)
      else
        []
      end

    {:noreply, assign(socket, move_query: query, move_results: results)}
  end

  def handle_event("select_move_target", %{"id" => id}, socket) do
    target = Enum.find(socket.assigns.move_results, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, move_target: target, move_query: "", move_results: [])}
  end

  def handle_event("clear_move_target", _params, socket),
    do: {:noreply, assign(socket, move_target: nil, move_query: "", move_results: [])}

  def handle_event("move_selected", _params, socket) do
    %{selected: selected, move_target: target, actor: actor} = socket.assigns

    cond do
      is_nil(target) ->
        {:noreply, put_flash(socket, :error, "Pick where to move them")}

      MapSet.size(selected) == 0 ->
        {:noreply, put_flash(socket, :error, "Select the taxa to move")}

      true ->
        case Import.record_taxa_moved(actor, MapSet.to_list(selected), target.id) do
          {:ok, count} ->
            {:noreply,
             socket
             |> assign(show_move_modal: false, selected: MapSet.new())
             |> load()
             |> put_flash(:info, "Moved #{count} #{taxa_word(count)} under #{target.name}")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Not moved: #{Errors.text(reason)}")}
        end
    end
  end

  # A new parent must rank above every selected taxon.
  defp target_ranks(socket) do
    ranks =
      for row <- socket.assigns.rows,
          MapSet.member?(socket.assigns.selected, row.id),
          do: row.rank

    Enum.filter(Rank.all(), fn rank -> Enum.all?(ranks, &Rank.below?(&1, rank)) end)
  end

  defp taxa_word(1), do: "taxon"
  defp taxa_word(_count), do: "taxa"

  defp index_path(params) do
    params = Map.reject(params, fn {_key, value} -> value in [nil, ""] end)
    if params == %{}, do: ~p"/admin/taxonomy", else: ~p"/admin/taxonomy?#{params}"
  end

  defp rank_label(rank), do: rank |> Atom.to_string() |> String.capitalize()

  defp name_rank(rank) do
    if rank in Rank.species_and_below(), do: "species", else: Atom.to_string(rank)
  end

  # -- rendering ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Taxonomy">
      <div class="space-y-6">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <form
            id="taxonomy-search-form"
            phx-change="search"
            phx-submit="search"
            class="flex-1 max-w-2xl"
          >
            <.search_input
              id="taxonomy-search"
              name="q"
              value={@query}
              placeholder="Search taxa by name, synonym or common name..."
              phx-debounce="300"
            />
          </form>
          <div class="flex items-center gap-2">
            <.link navigate={~p"/admin/host-range"} class="gf-btn gf-btn-secondary">
              Host Range Review
            </.link>
            <.link navigate={~p"/admin/taxonomy/new"} class="gf-btn gf-btn-primary">
              New Taxon
            </.link>
          </div>
        </div>

        <nav :if={@mode == :browse} id="browse-trail" class="text-sm text-gray-600">
          <.link patch={~p"/admin/taxonomy"} class="hover:underline">All roots</.link>
          <span :for={entry <- @lineage}>
            <span class="mx-1 text-gray-400">›</span>
            <.link patch={~p"/admin/taxonomy?#{%{parent: entry.taxon_id}}"} class="hover:underline">
              <.taxon_name name={entry.name} rank={name_rank(entry.rank)} />
            </.link>
          </span>
        </nav>

        <div
          :if={@mode == :browse and MapSet.size(@selected) > 0}
          class="flex items-center gap-2"
        >
          <button type="button" phx-click="open_move_modal" class="gf-btn gf-btn-secondary">
            <.icon name="ph-arrow-right" class="h-4 w-4 mr-1" />
            Move {MapSet.size(@selected)} Selected
          </button>
          <button type="button" phx-click="clear_selection" class="gf-btn gf-btn-ghost text-sm">
            Clear
          </button>
        </div>

        <div class="bg-white shadow rounded-lg overflow-hidden">
          <table id="taxa-table" class="gf-table gf-table-dark">
            <thead>
              <tr>
                <th :if={@mode == :browse} class="w-10"></th>
                <th>Name</th>
                <th>Rank</th>
                <th :if={@mode == :search}>Kingdom</th>
                <th>{if @mode == :search, do: "Also known as", else: "Common names"}</th>
                <th :if={@mode == :browse} class="text-right">Children</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @rows} id={"taxon-#{row.id}"}>
                <td :if={@mode == :browse} class="text-center">
                  <input
                    type="checkbox"
                    checked={MapSet.member?(@selected, row.id)}
                    phx-click="toggle_select"
                    phx-value-id={row.id}
                    class="h-4 w-4 rounded border-gray-300 text-gf-maroon focus:ring-gf-maroon"
                  />
                </td>
                <td>
                  <.link navigate={~p"/admin/taxonomy/#{row.id}"} class="hover:underline font-medium">
                    <.taxon_name name={row.name} rank={name_rank(row.rank)} />
                  </.link>
                </td>
                <td>{rank_label(row.rank)}</td>
                <td :if={@mode == :search}>{row.kingdom || "—"}</td>
                <td class="text-gray-500">{Enum.join(row.aliases, ", ")}</td>
                <td :if={@mode == :browse} class="text-right">
                  <.link
                    :if={row.child_count > 0}
                    patch={~p"/admin/taxonomy?#{%{parent: row.id}}"}
                    class="hover:underline"
                  >
                    {row.child_count} ›
                  </.link>
                  <span :if={row.child_count == 0} class="text-gray-400">—</span>
                </td>
              </tr>
              <tr :if={@rows == []}>
                <td colspan="6" class="text-center text-gray-500">No taxa found.</td>
              </tr>
            </tbody>
          </table>
        </div>

        <p class="text-sm text-gray-500">
          <%= if @mode == :search and @total > length(@rows) do %>
            Showing the first {length(@rows)} of {@total} taxa. Narrow the search to see the rest.
          <% else %>
            Showing {@total} {taxa_word(@total)}
          <% end %>
        </p>
      </div>

      <.modal :if={@show_move_modal} id="move-taxa-modal" show on_cancel={JS.push("close_move_modal")}>
        <:header>Move {MapSet.size(@selected)} {taxa_word(MapSet.size(@selected))}</:header>
        <:body>
          <div class="space-y-4">
            <div class="flex flex-wrap gap-2">
              <span
                :for={row <- Enum.filter(@rows, &MapSet.member?(@selected, &1.id))}
                class="inline-flex items-center px-2.5 py-0.5 rounded-full text-sm font-medium bg-green-100 text-green-800"
              >
                <.taxon_name name={row.name} rank={name_rank(row.rank)} />
              </span>
            </div>
            <.typeahead
              id="move-target-picker"
              label="Move under"
              placeholder="Search for the new parent..."
              search_event="search_move_target"
              select_event="select_move_target"
              clear_event="clear_move_target"
              query={@move_query}
              results={@move_results}
              selected={@move_target}
              display_fn={fn t -> "#{t.name} (#{t.rank})" end}
            />
            <div class="bg-amber-50 border border-amber-200 rounded-lg p-3">
              <p class="text-sm text-amber-800">
                <.icon name="ph-warning" class="h-4 w-4 inline mr-1" />
                Each selected taxon moves with everything below it. This takes effect immediately.
              </p>
            </div>
          </div>
        </:body>
        <:footer>
          <button type="button" phx-click="close_move_modal" class="gf-btn gf-btn-secondary">
            Cancel
          </button>
          <button
            id="move-selected"
            type="button"
            phx-click="move_selected"
            disabled={is_nil(@move_target)}
            class="gf-btn gf-btn-primary"
          >
            Move
          </button>
        </:footer>
      </.modal>
    </Layouts.admin>
    """
  end
end
