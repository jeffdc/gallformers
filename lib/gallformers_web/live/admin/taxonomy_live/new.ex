defmodule GallformersWeb.Admin.TaxonomyLive.New do
  @moduledoc """
  Adding a taxon in the taxonomy admin (matter a856, Task 9), at
  `/admin/taxonomy/new`, two ways:

    * **From POWO-WCVP** (a plant): search WCVP, pick the record — its
      name, family and genus (WCVP is authoritative for a plant's family;
      a missing family or genus is made) and its native range, introduced
      too when asked — and add it, linked to the record.
    * **By name**: a name, a rank and a parent (a root needs a kingdom).
      A rank above species can take some of the parent's children under
      it (an intermediate rank needs at least one); a plant (Plantae at
      species rank or below) needs a Host range, drawn on the map as in
      the old Host admin.

  Both warn of possible duplicates — the same name, a synonym or common
  name, the same WCVP record — as the old Host admin did. Writes go
  through `Gallformers.Import` as the signed-in admin
  (`Gallformers.Import.TaxonomyAdmin`), so they are audited and in the
  replay log, each all or nothing.
  """
  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers

  import GallformersWeb.Admin.FormComponents, only: [duplicate_host_warning: 1]

  alias Gallformers.Import
  alias Gallformers.Ranges.Wcvp
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.Admin.TaxonomyLive.Errors
  alias GallformersWeb.Admin.TaxonomyLive.RangeEditor
  alias Phoenix.HTML.Form, as: HtmlForm

  @intermediate_ranks [:subfamily, :tribe, :subtribe]
  @parent_results 20

  defp wcvp_lookup, do: Application.get_env(:gallformers, :wcvp_lookup, Gallformers.Wcvp.Lookup)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> init_form_state()
     |> RangeEditor.init()
     |> assign(:page_title, "New Taxon")
     |> assign(:wcvp_available, wcvp_lookup().available?())
     |> assign(
       wcvp_search_query: "",
       wcvp_search_results: [],
       wcvp_selected: nil,
       wcvp_searching: false,
       wcvp_loading: false,
       wcvp_prefilled: nil,
       wcvp_warnings: []
     )
     |> assign(parent_query: "", parent_results: [], selected_parent: nil)
     |> assign(:form, taxon_form(%{"name" => "", "rank" => "species", "kingdom" => ""}))
     |> assign(duplicate_warnings: [], children: [], selected_children: MapSet.new())
     |> assign(:plant?, false)}
  end

  def close_form(socket), do: push_navigate(socket, to: ~p"/admin/taxonomy")

  defp taxon_form(params), do: to_form(params, as: :taxon)

  # -- adding from WCVP --------------------------------------------------------

  @impl true
  def handle_event("search_wcvp", %{"value" => query}, socket) do
    socket = assign(socket, :wcvp_search_query, query)

    if String.length(query) >= 3 do
      {:noreply,
       socket
       |> assign(:wcvp_searching, true)
       |> start_async(:wcvp_search, fn ->
         query
         |> wcvp_lookup().search(limit: 10)
         |> Enum.map(&Map.put(&1, :id, &1.plant_name_id))
       end)}
    else
      {:noreply, assign(socket, :wcvp_search_results, [])}
    end
  end

  def handle_event("select_wcvp", %{"id" => plant_name_id}, socket) do
    {:noreply,
     socket
     |> assign(wcvp_loading: true, wcvp_search_results: [])
     |> start_async(:wcvp_select, fn -> wcvp_lookup().get(plant_name_id) end)}
  end

  def handle_event("clear_wcvp", _params, socket) do
    {:noreply,
     assign(socket,
       wcvp_selected: nil,
       wcvp_search_query: "",
       wcvp_search_results: [],
       wcvp_prefilled: nil,
       wcvp_warnings: []
     )}
  end

  def handle_event("toggle_wcvp_introduced", _params, socket) do
    {:noreply,
     update(socket, :wcvp_prefilled, &%{&1 | include_introduced: !&1.include_introduced})}
  end

  def handle_event("add_from_wcvp", _params, socket) do
    case socket.assigns.wcvp_prefilled do
      nil ->
        {:noreply, put_flash(socket, :error, "Pick a WCVP record first")}

      %{entries: []} ->
        {:noreply, put_flash(socket, :error, "Host must have at least one range entry")}

      prefilled ->
        entries = wcvp_entries(prefilled)
        record = prefilled.record

        case Import.record_plant_added_from_wcvp(
               socket.assigns.actor,
               record,
               wcvp_rank(record),
               entries
             ) do
          {:ok, plant} ->
            {:noreply,
             socket
             |> reset_dirty()
             |> put_flash(:info, "#{record.taxon_name} added")
             |> push_navigate(to: ~p"/admin/taxonomy/#{plant.id}")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Not added: #{Errors.text(reason)}")}
        end
    end
  end

  # -- adding by name ----------------------------------------------------------

  def handle_event("validate", %{"taxon" => params}, socket) do
    {:noreply,
     socket
     |> assign(:form, taxon_form(params))
     |> refresh()
     |> mark_dirty()}
  end

  # A change from an input outside the taxon's fields (the parent search).
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("search_parent", %{"value" => query}, socket) do
    results =
      if String.length(String.trim(query)) >= 2 do
        query
        |> Taxa.search(ranks: parent_ranks(rank(socket)))
        |> Enum.take(@parent_results)
      else
        []
      end

    {:noreply, assign(socket, parent_query: query, parent_results: results)}
  end

  def handle_event("select_parent", %{"id" => id}, socket) do
    selected = Enum.find(socket.assigns.parent_results, &(&1.id == String.to_integer(id)))

    {:noreply,
     socket
     |> assign(selected_parent: selected, parent_query: "", parent_results: [])
     |> assign(:selected_children, MapSet.new())
     |> refresh()
     |> mark_dirty()}
  end

  def handle_event("clear_parent", _params, socket) do
    {:noreply,
     socket
     |> assign(selected_parent: nil, parent_query: "", parent_results: [])
     |> assign(:selected_children, MapSet.new())
     |> refresh()}
  end

  def handle_event("toggle_child", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = socket.assigns.selected_children

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, :selected_children, selected)}
  end

  def handle_event("create", %{"taxon" => params}, socket) do
    socket = socket |> assign(:form, taxon_form(params)) |> refresh()

    case validate_create(socket) do
      {:ok, attrs} ->
        entries = if plant?(socket), do: RangeEditor.entries_for_save(socket), else: []
        children = MapSet.to_list(socket.assigns.selected_children)

        case Import.record_taxon_created(socket.assigns.actor, attrs, children, entries) do
          {:ok, taxon} ->
            {:noreply,
             socket
             |> reset_dirty()
             |> put_flash(:info, "#{attrs.name} added")
             |> push_navigate(to: ~p"/admin/taxonomy/#{taxon.id}")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Not added: #{Errors.text(reason)}")}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  # -- the range editor (a plant added by name) --------------------------------

  def handle_event(event, params, socket) when event in ~w(toggle_region toggle_country) do
    if plant?(socket),
      do: {:noreply, RangeEditor.handle_event(event, params, socket)},
      else: {:noreply, socket}
  end

  def handle_event(event, params, socket)
      when event in ~w(request_cancel cancel_discard confirm_discard) do
    handle_form_event(event, params, socket)
  end

  @impl true
  def handle_info(message, socket) do
    if RangeEditor.handles_info?(message),
      do: {:noreply, RangeEditor.handle_info(message, socket)},
      else: {:noreply, socket}
  end

  # -- async WCVP lookups ------------------------------------------------------

  @impl true
  def handle_async(:wcvp_search, {:ok, results}, socket),
    do: {:noreply, assign(socket, wcvp_searching: false, wcvp_search_results: results)}

  def handle_async(:wcvp_search, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, wcvp_searching: false, wcvp_search_results: [])}

  def handle_async(:wcvp_select, {:ok, nil}, socket) do
    {:noreply,
     socket
     |> assign(:wcvp_loading, false)
     |> put_flash(:error, "WCVP species not found")}
  end

  def handle_async(:wcvp_select, {:ok, record}, socket) do
    {entries, _native, _introduced} = Wcvp.range_entries(record)
    native = Enum.count(entries, &(elem(&1, 2) == "native"))
    introduced = length(entries) - native

    introduced_suffix = if introduced > 0, do: " (+ #{introduced} introduced)", else: ""

    {:noreply,
     socket
     |> assign(:wcvp_loading, false)
     |> assign(:wcvp_selected, record)
     |> assign(:wcvp_prefilled, %{
       record: record,
       entries: entries,
       native_count: native,
       introduced_count: introduced,
       include_introduced: false,
       summary: "WCVP matched #{native} native places#{introduced_suffix}."
     })
     |> assign(
       :wcvp_warnings,
       duplicate_warnings(record.taxon_name, "Plantae", record.plant_name_id)
     )
     |> mark_dirty()}
  end

  def handle_async(:wcvp_select, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:wcvp_loading, false)
     |> put_flash(:error, "WCVP lookup failed. Please try again.")}
  end

  # -- helpers -----------------------------------------------------------------

  # The form's derived state: duplicate warnings, the parent's children a
  # new rank could take, and the range editor for a plant.
  defp refresh(socket) do
    name = socket |> field("name") |> String.trim()
    kingdom = kingdom(socket)
    rank = rank(socket)

    warnings = if name == "", do: [], else: duplicate_warnings(name, kingdom, nil)

    children =
      case socket.assigns.selected_parent do
        %{id: parent_id} when not is_nil(rank) ->
          parent_id
          |> Taxa.children_with_ranks()
          |> Enum.filter(&Rank.below?(&1.rank, rank))

        _ ->
          []
      end

    children_ids = MapSet.new(children, & &1.taxon_id)

    socket
    |> assign(:duplicate_warnings, warnings)
    |> assign(:children, children)
    |> update(:selected_children, &MapSet.intersection(&1, children_ids))
    |> assign(:plant?, plant?(socket))
  end

  defp field(socket, key), do: HtmlForm.input_value(socket.assigns.form, key) || ""

  defp rank(socket) do
    value = field(socket, "rank")
    Enum.find(Rank.all(), &(Atom.to_string(&1) == value))
  end

  defp kingdom(socket) do
    case socket.assigns.selected_parent do
      %{kingdom: kingdom} when kingdom not in [nil, ""] -> kingdom
      _ -> socket |> field("kingdom") |> String.trim() |> blank_to_nil()
    end
  end

  defp plant?(socket),
    do: kingdom(socket) == "Plantae" and rank(socket) in Rank.species_and_below()

  defp validate_create(socket) do
    input = %{
      name: socket |> field("name") |> String.trim(),
      rank: rank(socket),
      parent: socket.assigns.selected_parent,
      kingdom: kingdom(socket),
      children?: MapSet.size(socket.assigns.selected_children) > 0,
      missing_range?: plant?(socket) and RangeEditor.empty?(socket)
    }

    case Enum.find_value(create_checks(), & &1.(input)) do
      nil ->
        %{name: name, rank: rank, parent: parent, kingdom: kingdom} = input
        {:ok, %{name: name, rank: rank, parent_id: parent && parent.id, kingdom: kingdom}}

      message ->
        {:error, message}
    end
  end

  # Each check gives the problem with the new taxon, or nil; the first
  # problem found is reported.
  defp create_checks do
    [
      &unnamed/1,
      &unranked/1,
      &orphan/1,
      &kingdomless/1,
      &duplicate/1,
      &childless_intermediate/1,
      &rangeless_plant/1
    ]
  end

  defp unnamed(%{name: ""}), do: "Enter the name"
  defp unnamed(_input), do: nil

  defp unranked(%{rank: nil}), do: "Pick the rank"
  defp unranked(_input), do: nil

  defp orphan(%{parent: nil, rank: rank}),
    do: if(Rank.below?(rank, :family), do: "A #{rank} needs a parent")

  defp orphan(_input), do: nil

  defp kingdomless(%{parent: nil, kingdom: nil}), do: "A taxon without a parent needs a kingdom"
  defp kingdomless(_input), do: nil

  defp duplicate(%{name: name, rank: rank, parent: parent}) do
    if exists_under_parent?(name, rank, parent), do: "#{name} already exists under this parent"
  end

  defp childless_intermediate(%{rank: rank, children?: false}) when rank in @intermediate_ranks,
    do: "Pick at least one child to move under the new #{rank}"

  defp childless_intermediate(_input), do: nil

  defp rangeless_plant(%{missing_range?: true}), do: "Host must have at least one range entry"
  defp rangeless_plant(_input), do: nil

  defp exists_under_parent?(name, rank, parent) do
    parent_id = parent && parent.id

    case Taxa.resolve_name(name, rank: rank) do
      {:ok, taxon} -> taxon.parent_id == parent_id
      {:ambiguous, taxa} -> Enum.any?(taxa, &(&1.parent_id == parent_id))
      :none -> false
    end
  end

  # Taxa whose accepted name, synonym or common name is `name`, and plants
  # linked to the WCVP record `wcvp_id`.
  defp duplicate_warnings(name, kingdom, wcvp_id) do
    opts = if kingdom, do: [kingdom: kingdom], else: []
    names = name_matches(name, opts)
    common = common_name_matches(name, opts)
    linked = if wcvp_id, do: wcvp_matches(wcvp_id), else: []

    names ++ common ++ linked
  end

  defp name_matches(name, opts) do
    taxa =
      case Taxa.resolve_name(name, opts) do
        {:ok, taxon} -> [taxon]
        {:ambiguous, taxa} -> taxa
        :none -> []
      end

    for taxon <- taxa do
      case taxon.matched_name do
        %{status: :accepted} ->
          %{reason: :name_match, taxon_id: taxon.id, name: taxon.matched_name.name}

        _synonym ->
          %{
            reason: :alias_match,
            alias_type: "scientific",
            taxon_id: taxon.id,
            name: Taxa.accepted_name(taxon.id)
          }
      end
    end
  end

  defp common_name_matches(name, opts) do
    hits = Taxa.search(name, opts)
    commons = hits |> Enum.map(& &1.id) |> Taxa.common_names()
    wanted = String.downcase(name)

    for hit <- hits,
        Enum.any?(Map.get(commons, hit.id, []), &(String.downcase(&1) == wanted)),
        do: %{reason: :alias_match, alias_type: "common", taxon_id: hit.id, name: hit.name}
  end

  defp wcvp_matches(wcvp_id) do
    for id <- Wcvp.linked_taxon_ids(wcvp_id),
        do: %{reason: :wcvp_id_match, taxon_id: id, name: Taxa.accepted_name(id)}
  end

  defp wcvp_entries(%{entries: entries, include_introduced: true}), do: entries

  defp wcvp_entries(%{entries: entries}),
    do: Enum.filter(entries, &(elem(&1, 2) == "native"))

  # The rank a WCVP name is at, read from its infraspecific marker.
  defp wcvp_rank(%{taxon_name: name}) do
    words = String.split(name)

    cond do
      "var." in words -> :variety
      "subsp." in words -> :subspecies
      "f." in words -> :form
      true -> :species
    end
  end

  defp parent_ranks(nil), do: Rank.all()
  defp parent_ranks(rank), do: Enum.filter(Rank.all(), &Rank.below?(rank, &1))

  defp rank_options, do: Enum.map(Rank.all(), &{rank_label(&1), Atom.to_string(&1)})

  defp rank_label(rank), do: rank |> Atom.to_string() |> String.capitalize()

  defp name_rank(rank) do
    if rank in Rank.species_and_below(), do: "species", else: Atom.to_string(rank)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # -- rendering ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <:page_title_html>New Taxon</:page_title_html>

      <Layouts.admin_edit_layout back_path={~p"/admin/taxonomy"} back_label="Back to Taxonomy">
        <:intro>
          Add a plant from the POWO World Checklist of Vascular Plants, or any taxon by its name,
          rank and parent.
        </:intro>

        <div class="space-y-6">
          <%!-- From WCVP --%>
          <.card
            :if={@wcvp_available}
            title="Add a plant from POWO-WCVP"
            icon="ph-leaf"
            class="overflow-visible relative"
          >
            <.loading_overlay :if={@wcvp_loading} label="Loading WCVP data..." />
            <p class="text-sm text-gray-600 mb-3">
              Search the
              <a
                href="https://powo.science.kew.org/about-wcvp"
                target="_blank"
                class="text-blue-600 hover:underline"
              >
                POWO World Checklist of Vascular Plants
              </a>
              to add a plant with its name, family, genus and range.
            </p>
            <.typeahead
              id="wcvp-picker"
              label="WCVP Search:"
              placeholder="Search WCVP by species name (min 3 characters)..."
              search_event="search_wcvp"
              select_event="select_wcvp"
              clear_event="clear_wcvp"
              query={@wcvp_search_query}
              results={@wcvp_search_results}
              selected={@wcvp_selected}
              display_fn={fn item -> item.taxon_name end}
            >
              <:result :let={item}>
                <span class="italic">{item.taxon_name}</span>
                <span class="text-gray-500 text-sm ml-1">{item.taxon_authors}</span>
                <span class="text-gray-400 text-xs ml-2">({item.family})</span>
              </:result>
            </.typeahead>
            <div
              :if={@wcvp_searching}
              id="wcvp-search-loading"
              class="flex items-center gap-2 mt-2 text-sm text-gray-500"
            >
              <.loading_spinner size="sm" label="Searching WCVP..." />
              <span>Searching WCVP...</span>
            </div>

            <div :if={@wcvp_prefilled} id="wcvp-prefilled" class="mt-3 space-y-3">
              <.duplicate_host_warning warnings={@wcvp_warnings} />
              <dl class="text-sm grid grid-cols-2 gap-x-4 gap-y-1 max-w-lg">
                <dt class="text-gray-500">Name</dt>
                <dd><.taxon_name name={@wcvp_prefilled.record.taxon_name} /></dd>
                <dt class="text-gray-500">Genus</dt>
                <dd>{@wcvp_prefilled.record.genus}</dd>
                <dt class="text-gray-500">Family</dt>
                <dd>{@wcvp_prefilled.record.family}</dd>
              </dl>
              <div class="text-sm text-green-700 bg-green-50 border border-green-200 rounded px-3 py-2">
                <p>{@wcvp_prefilled.summary}</p>
                <label
                  :if={@wcvp_prefilled.introduced_count > 0}
                  class="mt-2 flex items-center gap-2 cursor-pointer"
                >
                  <input
                    type="checkbox"
                    checked={@wcvp_prefilled.include_introduced}
                    phx-click="toggle_wcvp_introduced"
                    class="rounded border-gray-300 text-green-600 focus:ring-green-500"
                  />
                  <span>Include introduced range</span>
                </label>
              </div>
              <.button id="add-from-wcvp" type="button" variant="primary" phx-click="add_from_wcvp">
                Add plant
              </.button>
            </div>
          </.card>

          <%!-- By name --%>
          <.card title="Add a taxon by name" icon="ph-plus">
            <.form for={@form} id="taxon-form" phx-change="validate" phx-submit="create">
              <div class="grid grid-cols-2 gap-4 mb-3">
                <.input field={@form[:name]} label="Name" placeholder="e.g. Quercus alba" />
                <.input field={@form[:rank]} type="select" label="Rank" options={rank_options()} />
              </div>

              <div class="mb-3">
                <.typeahead
                  id="parent-picker"
                  label="Parent"
                  placeholder="Search for the parent..."
                  search_event="search_parent"
                  select_event="select_parent"
                  clear_event="clear_parent"
                  query={@parent_query}
                  results={@parent_results}
                  selected={@selected_parent}
                  display_fn={fn p -> "#{p.name} (#{p.rank})" end}
                >
                  <:result :let={parent}>
                    <.taxon_name name={parent.name} rank={name_rank(parent.rank)} />
                    <span class="text-xs text-gray-500 ml-1">({parent.rank})</span>
                  </:result>
                </.typeahead>
                <p class="mt-1 text-xs text-gray-500">
                  Below family a parent is required. The new taxon takes its parent's kingdom.
                </p>
              </div>

              <div :if={is_nil(@selected_parent)} class="mb-3 max-w-xs">
                <.input field={@form[:kingdom]} label="Kingdom" placeholder="e.g. Animalia" />
              </div>

              <.duplicate_host_warning warnings={@duplicate_warnings} />

              <div :if={@children != []} id="children-to-move" class="mb-3">
                <p class="gf-label">Children to move under it</p>
                <p class="mb-2 text-xs text-gray-500">
                  The parent's children that rank below the new taxon. Moving one moves its subtree.
                </p>
                <ul class="space-y-1">
                  <li :for={child <- @children}>
                    <label class="flex items-center gap-2 text-sm">
                      <input
                        type="checkbox"
                        checked={MapSet.member?(@selected_children, child.taxon_id)}
                        phx-click="toggle_child"
                        phx-value-id={child.taxon_id}
                        class="rounded border-gray-300 text-gf-maroon focus:ring-gf-maroon"
                      />
                      <.taxon_name name={child.name} rank={name_rank(child.rank)} />
                      <span class="text-xs text-gray-500">({child.rank})</span>
                    </label>
                  </li>
                </ul>
              </div>
            </.form>

            <div :if={@plant?} class="mt-3">
              <p class="gf-label">Host range</p>
              <RangeEditor.editor
                refreshable={false}
                range_taxon_name={@range_taxon_name}
                range_entries={@range_entries}
                all_places={@all_places}
                place_by_code={@place_by_code}
                in_range={@in_range}
                inherited_range={@inherited_range}
                introduced_range={@introduced_range}
                range_bounds={@range_bounds}
              />
            </div>

            <div class="flex justify-end gap-2 pt-3 border-t border-gray-200">
              <button type="button" phx-click="request_cancel" class="gf-btn gf-btn-soft">
                Cancel
              </button>
              <button id="create-taxon" type="submit" form="taxon-form" class="gf-btn gf-btn-primary">
                Create
              </button>
            </div>
          </.card>
        </div>

        <.discard_confirm_modal show={@show_discard_confirm} />
      </Layouts.admin_edit_layout>
    </Layouts.admin>
    """
  end
end
