defmodule GallformersWeb.Admin.TaxonomyLive.Index do
  @moduledoc """
  The taxonomy admin's list (matter a856, Task 9), at `/admin/taxonomy`:
  search taxa of every rank by accepted name, synonym or common name
  (`?q=`), or browse the tree from its roots down (`?parent=ID`). Each taxon
  links to its page (`GallformersWeb.Admin.TaxonomyLive.Edit`).

  Browsing a taxon's children, several can be selected and moved under
  another parent at once (the old "move genera"), each move through
  `Gallformers.Import.record_taxonomy_edit/2` as the signed-in admin. Taxa
  outside Plantae move by a Source's word (matter `f923`): the move asks
  "Based on which Source?" (`GallformersWeb.Admin.TaxonomyLive.BasisPicker`)
  and is made as that Source's accepted placements
  (`Gallformers.Import.record_taxonomy_change/3`).
  """
  use GallformersWeb, :live_view

  alias Gallformers.Import
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon
  alias GallformersWeb.Admin.TaxonomyLive.BasisPicker
  alias GallformersWeb.Admin.TaxonomyLive.Errors

  @search_limit 200
  @parent_results 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> BasisPicker.init()
     |> assign(
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
    %{selected: selected, move_target: target} = socket.assigns

    cond do
      is_nil(target) ->
        {:noreply, put_flash(socket, :error, "Pick where to move them")}

      MapSet.size(selected) == 0 ->
        {:noreply, put_flash(socket, :error, "Select the taxa to move")}

      true ->
        move(socket, MapSet.to_list(selected), target)
    end
  end

  def handle_event("cancel_basis", _params, socket),
    do: {:noreply, BasisPicker.cancel(socket)}

  @impl true
  def handle_info({BasisPicker, {:chosen, basis}}, socket) do
    case BasisPicker.run(socket, basis) do
      {:ok, socket, _count, done} ->
        {:noreply, socket |> assign(:selected, MapSet.new()) |> load() |> put_flash(:info, done)}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  # Taxa outside Plantae move by a Source's placement statements (`f923`):
  # ask which Source first. Plants move directly.
  defp move(socket, ids, target) do
    %{actor: actor} = socket.assigns
    count = length(ids)

    case Enum.split_with(ids, &Taxa.follows_facts?(Taxa.get_taxon!(&1))) do
      {[], _plants} ->
        move_directly(socket, actor, ids, target)

      {_followed, []} ->
        {:noreply,
         socket
         |> assign(show_move_modal: false)
         |> BasisPicker.ask(
           {:move_all, ids, target.id},
           "Move #{count} #{taxa_word(count)} under #{target.name}.",
           "Move",
           "Moved #{count} #{taxa_word(count)} under #{target.name}"
         )}

      _mixed ->
        {:noreply, put_flash(socket, :error, "Move plants and other taxa separately")}
    end
  end

  defp move_directly(socket, actor, ids, target) do
    case Import.record_taxa_moved(actor, ids, target.id) do
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
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:title>Taxonomy</:title>
          <:description>
            Every rank, from kingdoms to species: search by accepted name, synonym or common name, or browse down from the roots.
          </:description>
          <:action>
            <.button navigate={~p"/admin/host-range"}>Host range review</.button>
          </:action>
          <:action>
            <.button navigate={~p"/admin/taxonomy/new"} variant="primary" icon="ph-plus">
              New taxon
            </.button>
          </:action>
        </.page_header>

        <div class="flex flex-col gap-block">
          <form
            id="taxonomy-search-form"
            phx-change="search"
            phx-submit="search"
            class="max-w-xl"
          >
            <.search_field
              id="taxonomy-search"
              name="q"
              value={@query}
              label="Search taxa"
              placeholder="Search taxa by name, synonym or common name"
            />
          </form>

          <nav
            :if={@mode == :browse}
            id="browse-trail"
            aria-label="Where you are in the tree"
            class="flex flex-wrap items-center gap-x-1.5 text-meta text-muted"
          >
            <.link patch={~p"/admin/taxonomy"}>All roots</.link>
            <span :for={entry <- @lineage} class="flex items-center gap-x-1.5">
              <span aria-hidden="true">›</span>
              <.link patch={~p"/admin/taxonomy?#{%{parent: entry.taxon_id}}"}>
                <.taxon_name name={entry.name} rank={name_rank(entry.rank)} />
              </.link>
            </span>
          </nav>

          <div
            :if={@mode == :browse and MapSet.size(@selected) > 0}
            class="flex items-center gap-2"
          >
            <.button phx-click="open_move_modal" icon="ph-arrow-right">
              Move {MapSet.size(@selected)} selected
            </.button>
            <.button variant="ghost" phx-click="clear_selection">Clear</.button>
          </div>

          <.data_table id="taxa-table" rows={@rows} row_id={&"taxon-#{&1.id}"}>
            <:col :let={row} :if={@mode == :browse} label="">
              <input
                type="checkbox"
                checked={MapSet.member?(@selected, row.id)}
                phx-click="toggle_select"
                phx-value-id={row.id}
                aria-label={"Select #{row.name}"}
                class="size-4 align-middle"
              />
            </:col>
            <:col :let={row} label="Name" grow>
              <.link navigate={~p"/admin/taxonomy/#{row.id}"} class="font-semibold">
                <.taxon_name name={row.name} rank={name_rank(row.rank)} />
              </.link>
            </:col>
            <:col :let={row} label="Rank">{rank_label(row.rank)}</:col>
            <:col :let={row} :if={@mode == :search} label="Kingdom">{row.kingdom || "—"}</:col>
            <:col
              :let={row}
              label={if @mode == :search, do: "Also known as", else: "Common names"}
              hide_below={:md}
            >
              <span class="text-ink-2">{Enum.join(row.aliases, ", ")}</span>
            </:col>
            <:col :let={row} :if={@mode == :browse} label="Children" numeric>
              <.link
                :if={row.child_count > 0}
                patch={~p"/admin/taxonomy?#{%{parent: row.id}}"}
              >
                {row.child_count} ›
              </.link>
              <span :if={row.child_count == 0} class="text-muted">—</span>
            </:col>
            <:empty>No taxa found.</:empty>
          </.data_table>

          <p class="text-meta text-muted">
            <%= if @mode == :search and @total > length(@rows) do %>
              Showing the first {length(@rows)} of {@total} taxa. Narrow the search to see the rest.
            <% else %>
              Showing {@total} {taxa_word(@total)}
            <% end %>
          </p>
        </div>
      </div>

      <.dialog
        :if={@show_move_modal}
        id="move-taxa-modal"
        title={"Move #{MapSet.size(@selected)} #{taxa_word(MapSet.size(@selected))}"}
        show
        on_cancel={JS.push("close_move_modal")}
      >
        <div class="flex flex-col gap-block">
          <div class="flex flex-wrap gap-2">
            <.chip :for={row <- Enum.filter(@rows, &MapSet.member?(@selected, &1.id))}>
              <.taxon_name name={row.name} rank={name_rank(row.rank)} />
            </.chip>
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
          <.notice kind={:warn}>
            Each selected taxon moves with everything below it. This takes effect immediately.
          </.notice>
        </div>
        <:actions>
          <.button phx-click="close_move_modal">Cancel</.button>
          <.button
            id="move-selected"
            variant="primary"
            phx-click="move_selected"
            disabled={is_nil(@move_target)}
          >
            Move
          </.button>
        </:actions>
      </.dialog>

      <.live_component
        :if={@pending}
        module={BasisPicker}
        id="basis-picker"
        change={@pending.summary}
        confirm_label={@pending.confirm}
        error={@basis_error}
        error_kind={@basis_error_kind}
        remembered={@last_source}
        cancel_event="cancel_basis"
      />
    </Layouts.admin>
    """
  end
end
