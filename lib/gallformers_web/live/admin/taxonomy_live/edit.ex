defmodule GallformersWeb.Admin.TaxonomyLive.Edit do
  @moduledoc """
  A taxon's page in the taxonomy admin (matter a856, Task 9), at
  `/admin/taxonomy/:id`, for a taxon of any rank:

    * rename — the old accepted name stays a synonym; Galls whose derived
      names change get rename proposals in the review queue (`86e7`);
    * move — a new parent, through the tree validator;
    * synonyms and common names, added and removed;
    * section membership: a plant's section within its genus, or a
      section's member plants (all in the section's genus);
    * a plant's editorial flags (`datacomplete`, abundance);
    * a plant's Host range, edited as in the old Host admin
      (`GallformersWeb.Admin.TaxonomyLive.RangeEditor`), saved on Save;
    * a plant's WCVP link: match, sync, ignore;
    * the taxon's images (`GallformersWeb.Admin.ImagesComponent`);
    * delete, only when nothing refers to it (decision 8), with typed-name
      confirmation; otherwise what refers to it is listed.

  Every write goes through `Gallformers.Import` as the signed-in admin (the
  `:admin` live session's actor), so it is audited and in the replay log.
  """
  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers

  alias Gallformers.Import
  alias Gallformers.Ranges
  alias Gallformers.Ranges.Wcvp
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon
  alias GallformersWeb.Admin.ImagesComponent
  alias GallformersWeb.Admin.TaxonomyLive.Errors
  alias GallformersWeb.Admin.TaxonomyLive.RangeEditor
  alias GallformersWeb.TaxonomyURL

  @parent_results 20
  @member_results 10

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    with {taxon_id, ""} <- Integer.parse(id),
         %Taxon{} = taxon <- Taxa.get_taxon(taxon_id) do
      {:ok,
       socket
       |> init_form_state()
       |> RangeEditor.init()
       |> assign(:abundances, Taxa.abundance_options())
       |> assign(parent_query: "", parent_results: [], selected_parent: nil)
       |> assign(member_query: "", member_results: [])
       |> assign(show_delete_modal: false, delete_confirmation: "")
       |> load_taxon(taxon)
       |> load_range()}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Taxon not found")
         |> push_navigate(to: ~p"/admin/taxonomy")}
    end
  end

  def close_form(socket), do: push_navigate(socket, to: ~p"/admin/taxonomy")

  # -- loading -----------------------------------------------------------------

  defp load_taxon(socket, %Taxon{} = taxon) do
    name = Taxa.accepted_name(taxon)
    lineage = Taxa.lineage(taxon)
    plant? = plant?(taxon)

    socket
    |> assign(:taxon, taxon)
    |> assign(:name, name)
    |> assign(:page_title, name)
    |> assign(:lineage, Enum.reject(lineage, &(&1.taxon_id == taxon.id)))
    |> assign(:plant?, plant?)
    |> assign(:public_path, public_path(taxon, name, plant?))
    |> assign(:synonyms, Taxa.list_synonyms(taxon))
    |> assign(:common_names, Taxa.list_common_names(taxon))
    |> assign(:references, Taxa.references(taxon))
    |> assign(:rename_form, to_form(%{"name" => name}, as: :rename))
    |> assign(:synonym_form, to_form(%{"name" => "", "sensu" => ""}, as: :synonym))
    |> assign(:common_name_form, to_form(%{"name" => ""}, as: :common_name))
    |> assign(:editorial_form, editorial_form(taxon))
    |> assign_sections(lineage)
    |> assign_link()
  end

  defp reload(socket), do: load_taxon(socket, Taxa.get_taxon!(socket.assigns.taxon.id))

  defp plant?(%Taxon{kingdom: "Plantae", rank: rank}), do: rank in Rank.species_and_below()
  defp plant?(_taxon), do: false

  defp editorial_form(taxon) do
    to_form(
      %{"datacomplete" => taxon.datacomplete, "abundance_id" => taxon.abundance_id},
      as: :editorial
    )
  end

  # A plant's section choices (the sections of its genus), or a section's
  # member plants.
  defp assign_sections(socket, lineage) do
    %{taxon: taxon, plant?: plant?} = socket.assigns

    genus = lineage |> Enum.reverse() |> Enum.find(&(&1.rank == :genus))

    sections =
      if plant? and genus,
        do: genus.taxon_id |> Taxa.children_with_ranks() |> Enum.filter(&(&1.rank == :section)),
        else: []

    members =
      if taxon.rank == :section,
        do:
          taxon.id
          |> Taxa.children_with_ranks()
          |> Enum.filter(&(&1.rank in Rank.species_and_below())),
        else: []

    assign(socket, genus: genus, sections: sections, members: members)
  end

  defp assign_link(%{assigns: %{plant?: true, taxon: taxon, name: name}} = socket) do
    link = Wcvp.get_link(taxon.id)

    socket
    |> assign(:link, link)
    |> RangeEditor.set_lookup(name, link && link.wcvp_id)
  end

  defp assign_link(socket), do: assign(socket, :link, nil)

  defp load_range(%{assigns: %{plant?: true, taxon: taxon}} = socket) do
    socket
    |> RangeEditor.load(Ranges.get_places_for_taxon_with_precision(taxon.id))
    |> reset_dirty()
  end

  defp load_range(socket), do: socket

  # -- the range editor --------------------------------------------------------

  @impl true
  def handle_event(event, params, socket) when event in ~w(toggle_region toggle_country) do
    if socket.assigns.plant?,
      do: {:noreply, RangeEditor.handle_event(event, params, socket)},
      else: {:noreply, socket}
  end

  def handle_event(event, params, socket)
      when event in ~w(refresh_from_wcvp cancel_wcvp_refresh wcvp_nomatch_search
                       select_wcvp_nomatch cancel_wcvp_search continue_wcvp_search) do
    {:noreply, RangeEditor.handle_event(event, params, socket)}
  end

  def handle_event("save_range", params, socket) do
    if RangeEditor.empty?(socket),
      do: {:noreply, put_flash(socket, :error, "Host must have at least one range entry")},
      else: {:noreply, save_range(socket, params["confirm"] == "true")}
  end

  # -- names -------------------------------------------------------------------

  def handle_event("rename", %{"rename" => %{"name" => new_name}}, socket) do
    new_name = String.trim(new_name)

    cond do
      new_name == "" ->
        {:noreply, put_flash(socket, :error, "Enter the new name")}

      new_name == socket.assigns.name ->
        {:noreply, socket}

      true ->
        socket
        |> edit({:rename, socket.assigns.taxon, new_name}, "Renamed to #{new_name}")
        |> then(&{:noreply, &1})
    end
  end

  def handle_event("add_synonym", %{"synonym" => %{"name" => name} = params}, socket) do
    name = String.trim(name)
    sensu = params |> Map.get("sensu", "") |> String.trim()
    opts = if sensu == "", do: [], else: [sensu: sensu]

    if name == "" do
      {:noreply, put_flash(socket, :error, "Enter the synonym")}
    else
      result = Import.record_synonym_added(socket.assigns.actor, socket.assigns.taxon, name, opts)
      {:noreply, after_write(socket, result, "Synonym #{name} added")}
    end
  end

  def handle_event("remove_synonym", %{"id" => id}, socket) do
    edit = {:remove_synonym, String.to_integer(id)}
    {:noreply, edit(socket, edit, "Synonym removed")}
  end

  def handle_event("add_common_name", %{"common_name" => %{"name" => name}}, socket) do
    name = String.trim(name)

    if name == "" do
      {:noreply, put_flash(socket, :error, "Enter the common name")}
    else
      edit = {:add_common_name, socket.assigns.taxon, name}
      {:noreply, edit(socket, edit, "Common name #{name} added")}
    end
  end

  def handle_event("remove_common_name", %{"id" => id}, socket) do
    edit = {:remove_common_name, String.to_integer(id)}
    {:noreply, edit(socket, edit, "Common name removed")}
  end

  # -- placement ---------------------------------------------------------------

  def handle_event("search_parent", %{"value" => query}, socket) do
    {:noreply,
     assign(socket,
       parent_query: query,
       parent_results: parent_candidates(socket.assigns.taxon, query)
     )}
  end

  def handle_event("select_parent", %{"id" => id}, socket) do
    selected = Enum.find(socket.assigns.parent_results, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, selected_parent: selected, parent_query: "", parent_results: [])}
  end

  def handle_event("clear_parent", _params, socket) do
    {:noreply, assign(socket, selected_parent: nil, parent_query: "", parent_results: [])}
  end

  def handle_event("move", _params, socket) do
    case socket.assigns.selected_parent do
      nil ->
        {:noreply, put_flash(socket, :error, "Pick the new parent")}

      parent ->
        socket
        |> assign(:selected_parent, nil)
        |> edit({:place, socket.assigns.taxon, parent.id}, "Moved under #{parent.name}")
        |> then(&{:noreply, &1})
    end
  end

  def handle_event("set_section", %{"section_id" => section_id}, socket) do
    %{taxon: taxon, genus: genus} = socket.assigns

    parent_id = if section_id == "", do: genus.taxon_id, else: String.to_integer(section_id)

    if parent_id == taxon.parent_id do
      {:noreply, socket}
    else
      {:noreply, edit(socket, {:place, taxon, parent_id}, "Section updated")}
    end
  end

  def handle_event("search_member", %{"value" => query}, socket) do
    results =
      if String.length(String.trim(query)) >= 2,
        do: Taxa.search_plants(query, @member_results),
        else: []

    {:noreply, assign(socket, member_query: query, member_results: results)}
  end

  def handle_event("select_member", %{"id" => id}, socket) do
    socket = assign(socket, member_query: "", member_results: [])
    edit = {:place, String.to_integer(id), socket.assigns.taxon}
    {:noreply, edit(socket, edit, "Added to the section")}
  end

  def handle_event("clear_member", _params, socket),
    do: {:noreply, assign(socket, member_query: "", member_results: [])}

  def handle_event("remove_member", %{"id" => id}, socket) do
    edit = {:place, String.to_integer(id), socket.assigns.taxon.parent_id}
    {:noreply, edit(socket, edit, "Removed from the section")}
  end

  # -- a plant's flags ---------------------------------------------------------

  def handle_event("save_editorial", %{"editorial" => params}, socket) do
    attrs = %{
      datacomplete: params["datacomplete"] == "true",
      abundance_id: parse_id(params["abundance_id"])
    }

    {:noreply,
     edit(socket, {:update_editorial, socket.assigns.taxon, attrs}, "Plant details saved")}
  end

  # -- WCVP --------------------------------------------------------------------

  def handle_event("wcvp_match", _params, socket),
    do: {:noreply, wcvp_edit(socket, {:match, socket.assigns.taxon.id})}

  def handle_event("wcvp_sync", _params, socket) do
    if socket.assigns.form_dirty do
      {:noreply,
       put_flash(socket, :error, "Save or discard the range changes before syncing from WCVP")}
    else
      {:noreply, socket |> wcvp_edit({:sync, socket.assigns.taxon.id}) |> load_range()}
    end
  end

  def handle_event("wcvp_ignore", _params, socket),
    do: {:noreply, wcvp_edit(socket, {:ignore, [socket.assigns.taxon.id]})}

  def handle_event("wcvp_clear_status", _params, socket),
    do: {:noreply, wcvp_edit(socket, {:clear_match_status, [socket.assigns.taxon.id]})}

  # -- delete ------------------------------------------------------------------

  def handle_event("delete", _params, socket) do
    {:noreply, assign(socket, show_delete_modal: true, delete_confirmation: "")}
  end

  def handle_event("update_delete_confirmation", %{"value" => value}, socket),
    do: {:noreply, assign(socket, :delete_confirmation, value)}

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, show_delete_modal: false, delete_confirmation: "")}

  def handle_event("confirm_delete", %{"confirmation" => confirmation}, socket) do
    %{actor: actor, taxon: taxon, name: name} = socket.assigns

    if confirmation != name do
      {:noreply, put_flash(socket, :error, "Name does not match. Type the exact name.")}
    else
      case Import.record_taxonomy_edit(actor, {:delete_taxon, taxon}) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Deleted #{name}")
           |> push_navigate(to: ~p"/admin/taxonomy")}

        {:error, reason} ->
          {:noreply,
           socket
           |> reload()
           |> assign(:show_delete_modal, false)
           |> put_flash(:error, "Could not delete #{name}: #{Errors.text(reason)}")}
      end
    end
  end

  def handle_event(event, params, socket)
      when event in ~w(request_cancel cancel_discard confirm_discard) do
    handle_form_event(event, params, socket)
  end

  # -- messages ----------------------------------------------------------------

  @impl true
  def handle_info(message, socket) do
    if RangeEditor.handles_info?(message),
      do: {:noreply, RangeEditor.handle_info(message, socket)},
      else: {:noreply, socket}
  end

  @impl true
  def handle_async(name, result, socket),
    do: {:noreply, RangeEditor.handle_async(name, result, socket)}

  # -- helpers -----------------------------------------------------------------

  # Saves the edited range with what a WCVP refresh staged, confirmed when
  # asked, then reloads both.
  defp save_range(socket, confirm?) do
    %{actor: actor, taxon: taxon, pending_wcvp_link: staged} = socket.assigns

    link_attrs =
      if confirm?, do: Map.put(staged || %{}, :range_confirmed, true), else: staged || %{}

    entries = RangeEditor.entries_for_save(socket)

    case Import.record_host_range_saved(actor, taxon.id, entries, link_attrs) do
      {:ok, :ok} ->
        socket
        |> assign_link()
        |> load_range()
        |> put_flash(:info, if(confirm?, do: "Range saved and confirmed", else: "Range saved"))

      {:error, reason} ->
        put_flash(socket, :error, "Could not save the range: #{Errors.text(reason)}")
    end
  end

  # One replay-logged edit; on success the taxon is reloaded (its names,
  # placement and what refers to it may have changed).
  defp edit(socket, edit, message) do
    result = Import.record_taxonomy_edit(socket.assigns.actor, edit)
    after_write(socket, result, message)
  end

  defp after_write(socket, {:ok, _}, message),
    do: socket |> reload() |> put_flash(:info, message)

  defp after_write(socket, {:error, reason}, _message),
    do: put_flash(socket, :error, "Not saved: #{Errors.text(reason)}")

  defp wcvp_edit(socket, edit) do
    case Import.record_wcvp_edit(socket.assigns.actor, edit) do
      {:ok, result} ->
        socket |> assign_link() |> put_flash(:info, wcvp_message(edit, result))

      {:error, reason} ->
        socket |> assign_link() |> put_flash(:error, Errors.text(reason))
    end
  end

  defp wcvp_message({:match, _}, :linked), do: "Linked to WCVP"
  defp wcvp_message({:match, _}, :already_linked), do: "Already linked to WCVP"

  defp wcvp_message({:sync, _}, summary),
    do: "Range synced from WCVP: #{summary.total_places} places"

  defp wcvp_message({:ignore, _}, _count), do: "Left out of WCVP matching and sync"
  defp wcvp_message({:clear_match_status, _}, _count), do: "WCVP match status cleared"

  # Taxa of a higher rank in the same kingdom, the taxon itself left out.
  defp parent_candidates(taxon, query) do
    if String.length(String.trim(query)) >= 2 do
      ranks = Enum.filter(Rank.all(), &Rank.below?(taxon.rank, &1))
      opts = if taxon.kingdom, do: [ranks: ranks, kingdom: taxon.kingdom], else: [ranks: ranks]

      query
      |> Taxa.search(opts)
      |> Enum.reject(&(&1.id == taxon.id))
      |> Enum.take(@parent_results)
    else
      []
    end
  end

  defp parse_id(value) when value in [nil, ""], do: nil
  defp parse_id(value), do: String.to_integer(value)

  defp rank_label(rank), do: rank |> Atom.to_string() |> String.capitalize()

  # Names at species rank and below are italicized like a species.
  defp name_rank(rank) do
    if rank in Rank.species_and_below(), do: "species", else: Atom.to_string(rank)
  end

  defp public_path(taxon, _name, true = _plant?), do: ~p"/host/#{taxon.id}"

  defp public_path(taxon, name, false),
    do: TaxonomyURL.public_path(%{rank: taxon.rank, name: name})

  defp reference_text(%{table: "taxa", column: "parent_id", count: count}),
    do: "#{count} child #{if count == 1, do: "taxon", else: "taxa"}"

  defp reference_text(%{table: table, column: column, count: count}),
    do: "#{count} #{if count == 1, do: "row", else: "rows"} of #{table} (#{column})"

  defp format_synced_at(nil), do: nil
  defp format_synced_at(at), do: format_date(at, :short)

  defp stale?(%{wcvp_synced_at: %DateTime{} = synced}, %DateTime{} = built_at),
    do: DateTime.compare(synced, built_at) == :lt

  defp stale?(_link, _built_at), do: false

  # -- rendering ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <:page_title_html>
        Editing {rank_label(@taxon.rank)}
        <.taxon_name name={@name} rank={name_rank(@taxon.rank)} class="font-bold" />
      </:page_title_html>

      <Layouts.admin_edit_layout
        back_path={~p"/admin/taxonomy"}
        back_label="Back to Taxonomy"
        public_url={@public_path}
      >
        <:intro>
          A taxon's names, placement and details. Each change is saved as you make it, except the
          Host range, which is saved with its Save button.
        </:intro>

        <nav :if={@lineage != []} id="taxon-lineage" class="mb-4 text-sm text-gray-600">
          <span :for={{entry, i} <- Enum.with_index(@lineage)}>
            <span :if={i > 0} class="mx-1 text-gray-400">›</span>
            <.link navigate={~p"/admin/taxonomy/#{entry.taxon_id}"} class="hover:underline">
              <.taxon_name name={entry.name} rank={name_rank(entry.rank)} />
            </.link>
          </span>
        </nav>

        <div class="space-y-6">
          <%!-- Name --%>
          <.card title="Name" icon="ph-text-aa">
            <.form
              for={@rename_form}
              id="rename-form"
              phx-submit="rename"
              class="flex gap-2 items-end"
            >
              <div class="flex-1">
                <.input field={@rename_form[:name]} label="Accepted name" />
              </div>
              <.button type="submit" variant="secondary">Rename</.button>
            </.form>
            <p class="mt-2 text-xs text-gray-500">
              The old name is kept as a synonym. Galls whose names it changes get rename proposals in the <.link
                navigate={~p"/admin/queue"}
                class="underline"
              >review queue</.link>.
            </p>
          </.card>

          <%!-- Placement --%>
          <.card title="Placement" icon="ph-tree-structure">
            <p class="text-sm text-gray-600 mb-2">
              Rank: <strong>{rank_label(@taxon.rank)}</strong>
              <span :if={@taxon.kingdom}>· Kingdom: <strong>{@taxon.kingdom}</strong></span>
            </p>
            <div class="flex gap-2 items-end">
              <div class="flex-1">
                <.typeahead
                  id="parent-picker"
                  label="Move under"
                  placeholder="Search for the new parent..."
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
              </div>
              <.button
                id="move-button"
                type="button"
                variant="secondary"
                phx-click="move"
                disabled={is_nil(@selected_parent)}
              >
                Move
              </.button>
            </div>

            <div :if={@plant? and @sections != []} class="mt-4">
              <form id="section-form" phx-change="set_section">
                <.input
                  type="select"
                  name="section_id"
                  label="Section"
                  prompt="-- No Section --"
                  options={Enum.map(@sections, &{&1.name, &1.taxon_id})}
                  value={@taxon.parent_id}
                />
              </form>
            </div>
          </.card>

          <%!-- Section members --%>
          <.card :if={@taxon.rank == :section} title="Plants in this section" icon="ph-leaf">
            <p class="text-sm text-gray-600 mb-3">All of a section's plants are in its genus.</p>
            <ul id="section-members" class="divide-y divide-gray-100 mb-3">
              <li :for={member <- @members} class="flex items-center justify-between py-1">
                <.link navigate={~p"/admin/taxonomy/#{member.taxon_id}"} class="hover:underline">
                  <.taxon_name name={member.name} />
                </.link>
                <button
                  type="button"
                  phx-click="remove_member"
                  phx-value-id={member.taxon_id}
                  class="text-sm text-red-600 hover:underline"
                >
                  Remove
                </button>
              </li>
              <li :if={@members == []} class="py-1 text-sm text-gray-500">No plants yet.</li>
            </ul>
            <.typeahead
              id="member-picker"
              label="Add a plant"
              placeholder="Search plants..."
              search_event="search_member"
              select_event="select_member"
              clear_event="clear_member"
              query={@member_query}
              results={@member_results}
              display_fn={& &1.name}
            >
              <:result :let={plant}><.taxon_name name={plant.name} /></:result>
            </.typeahead>
          </.card>

          <%!-- Synonyms --%>
          <.card title="Synonyms" icon="ph-list">
            <ul id="synonyms" class="divide-y divide-gray-100 mb-3">
              <li :for={synonym <- @synonyms} class="flex items-center justify-between py-1">
                <span>
                  <.taxon_name name={synonym.name} />
                  <span :if={synonym.sensu} class="text-sm text-gray-500">sensu {synonym.sensu}</span>
                </span>
                <button
                  type="button"
                  phx-click="remove_synonym"
                  phx-value-id={synonym.id}
                  data-confirm={"Remove the synonym #{synonym.name}?"}
                  class="text-sm text-red-600 hover:underline"
                >
                  Remove
                </button>
              </li>
              <li :if={@synonyms == []} class="py-1 text-sm text-gray-500">No synonyms.</li>
            </ul>
            <.form
              for={@synonym_form}
              id="synonym-form"
              phx-submit="add_synonym"
              class="flex gap-2 items-end"
            >
              <div class="flex-1"><.input field={@synonym_form[:name]} label="Synonym" /></div>
              <div class="flex-1">
                <.input field={@synonym_form[:sensu]} label="Sensu (misapplied names only)" />
              </div>
              <.button type="submit" variant="secondary">Add</.button>
            </.form>
          </.card>

          <%!-- Common names --%>
          <.card title="Common names" icon="ph-chat-text">
            <ul id="common-names" class="divide-y divide-gray-100 mb-3">
              <li :for={common <- @common_names} class="flex items-center justify-between py-1">
                <span>{common.name}</span>
                <button
                  type="button"
                  phx-click="remove_common_name"
                  phx-value-id={common.id}
                  class="text-sm text-red-600 hover:underline"
                >
                  Remove
                </button>
              </li>
              <li :if={@common_names == []} class="py-1 text-sm text-gray-500">No common names.</li>
            </ul>
            <.form
              for={@common_name_form}
              id="common-name-form"
              phx-submit="add_common_name"
              class="flex gap-2 items-end"
            >
              <div class="flex-1">
                <.input field={@common_name_form[:name]} label="Common name" />
              </div>
              <.button type="submit" variant="secondary">Add</.button>
            </.form>
          </.card>

          <%!-- A plant's details --%>
          <.card :if={@plant?} title="Plant details" icon="ph-leaf">
            <.form for={@editorial_form} id="editorial-form" phx-submit="save_editorial">
              <div class="mb-3 max-w-xs">
                <.input
                  field={@editorial_form[:abundance_id]}
                  type="select"
                  label="Abundance"
                  prompt=""
                  options={@abundances}
                />
              </div>
              <.input
                type="checkbox"
                field={@editorial_form[:datacomplete]}
                label="All galls known to occur on this plant have been added to the database, and can be filtered by Location and Detachable. However, sources and images for galls associated with this host may be incomplete or absent, and other filters may not have been entered comprehensively or at all."
              />
              <div class="mt-3">
                <.button type="submit" variant="secondary">Save details</.button>
              </div>
            </.form>
          </.card>

          <%!-- Host range --%>
          <.card :if={@plant?} title="Host range" icon="ph-map-trifold">
            <div id="range-status" class="mb-4 text-sm">
              <div class="flex items-center gap-2">
                <span
                  :if={@link && @link.range_confirmed}
                  class="inline-flex items-center gap-1 text-green-700"
                >
                  <.icon name="ph-check-circle-fill" class="h-4 w-4" /> Range confirmed
                </span>
                <span
                  :if={!(@link && @link.range_confirmed)}
                  class="inline-flex items-center gap-1 text-amber-600"
                >
                  <.icon name="ph-warning" class="h-4 w-4" /> Range needs review
                </span>
              </div>
              <p class="text-gray-500 mt-1">
                <%= if @link && @link.wcvp_synced_at do %>
                  Last synced with WCVP: {format_synced_at(@link.wcvp_synced_at)}
                  <span :if={stale?(@link, @wcvp_built_at)} class="text-amber-600 font-medium">
                    — WCVP data updated since last sync
                  </span>
                <% else %>
                  Never synced with WCVP
                <% end %>
              </p>
            </div>

            <RangeEditor.editor
              range_taxon_name={@range_taxon_name}
              range_entries={@range_entries}
              all_places={@all_places}
              place_by_code={@place_by_code}
              in_range={@in_range}
              inherited_range={@inherited_range}
              introduced_range={@introduced_range}
              range_bounds={@range_bounds}
              powo_diff={@powo_diff}
              wcvp_nomatch_search={@wcvp_nomatch_search}
              wcvp_available={@wcvp_available}
              wcvp_refreshing={@wcvp_refreshing}
              wcvp_searching={@wcvp_searching}
              wcvp_loading={@wcvp_loading}
            />

            <div class="flex justify-end gap-2 pt-3 border-t border-gray-200">
              <button type="button" phx-click="request_cancel" class="gf-btn gf-btn-soft">
                Cancel
              </button>
              <button
                :if={!(@link && @link.range_confirmed)}
                id="save-confirm-range"
                type="button"
                phx-click="save_range"
                phx-value-confirm="true"
                class="gf-btn bg-green-600 text-white hover:bg-green-700"
              >
                Save &amp; Confirm Range
              </button>
              <button
                id="save-range"
                type="button"
                phx-click="save_range"
                disabled={not @form_dirty}
                class="gf-btn gf-btn-primary"
              >
                Save
              </button>
            </div>
          </.card>

          <%!-- WCVP link --%>
          <.card :if={@plant?} title="POWO-WCVP link" icon="ph-link">
            <dl id="wcvp-link" class="text-sm grid grid-cols-2 gap-x-4 gap-y-1 mb-3 max-w-lg">
              <dt class="text-gray-500">WCVP ID</dt>
              <dd>{(@link && @link.wcvp_id) || "—"}</dd>
              <dt class="text-gray-500">POWO ID</dt>
              <dd>{(@link && @link.powo_id) || "—"}</dd>
              <dt class="text-gray-500">Match status</dt>
              <dd>
                <.badge :if={@link && @link.wcvp_match_status} variant="warning">
                  {String.replace(@link.wcvp_match_status, "_", " ")}
                </.badge>
                <span :if={!(@link && @link.wcvp_match_status)}>—</span>
              </dd>
            </dl>
            <div class="flex flex-wrap gap-2">
              <.button type="button" variant="secondary" size="sm" phx-click="wcvp_match">
                Match to WCVP
              </.button>
              <.button
                type="button"
                variant="secondary"
                size="sm"
                phx-click="wcvp_sync"
                data-confirm="Replace this plant's Host range with WCVP's?"
              >
                Sync range from WCVP
              </.button>
              <.button
                :if={!(@link && @link.wcvp_match_status == "ignored")}
                type="button"
                variant="secondary"
                size="sm"
                phx-click="wcvp_ignore"
              >
                Ignore for WCVP
              </.button>
              <.button
                :if={@link && @link.wcvp_match_status}
                type="button"
                variant="secondary"
                size="sm"
                phx-click="wcvp_clear_status"
              >
                Clear match status
              </.button>
            </div>
          </.card>

          <%!-- Images --%>
          <.card id="images" title="Images" icon="ph-image">
            <.live_component
              module={ImagesComponent}
              id="taxon-images"
              owner={{:taxon, @taxon.id}}
              uploader={@actor.name}
              name={@name}
            />
          </.card>

          <%!-- Delete --%>
          <.card title="Delete" icon="ph-trash">
            <%= if @references == [] do %>
              <p class="text-sm text-gray-600 mb-3">
                Nothing refers to this taxon, so it can be deleted.
              </p>
              <button id="delete-button" type="button" phx-click="delete" class="gf-btn gf-btn-danger">
                Delete
              </button>
            <% else %>
              <p class="text-sm text-gray-600 mb-2">
                This taxon can't be deleted while something refers to it:
              </p>
              <ul id="taxon-references" class="list-disc pl-5 text-sm text-gray-700">
                <li :for={reference <- @references}>{reference_text(reference)}</li>
              </ul>
            <% end %>
          </.card>
        </div>

        <.record_metadata inserted_at={@taxon.inserted_at} updated_at={@taxon.updated_at} />

        <.discard_confirm_modal show={@show_discard_confirm} />

        <.dangerous_delete_modal
          show={@show_delete_modal}
          item_type="taxon"
          item_name={@name}
          consequences={[
            "Its names, common names and WCVP link are deleted with it.",
            "The deletion is recorded in the replay log."
          ]}
          confirmation_value={@delete_confirmation}
        />
      </Layouts.admin_edit_layout>
    </Layouts.admin>
    """
  end
end
