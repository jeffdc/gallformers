defmodule GallformersWeb.Admin.GallLive.Form do
  @moduledoc """
  Admin form for creating and editing galls.

  Features:
  - Typeahead at top to search existing galls or create new ones
  - Form below that enables when a gall is selected/created
  - All changes stored in socket state until save
  - Single transaction saves all changes (gall + hosts + filters)
  """
  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers

  alias Gallformers.GallHosts
  alias Gallformers.Galls
  alias Gallformers.Repo
  alias Gallformers.Species
  alias Gallformers.Species.Species, as: SpeciesSchema
  alias GallformersWeb.Admin.DeferredChanges

  import GallformersWeb.Admin.FormComponents, only: [alias_editor: 1, form_actions: 1]

  @detachable_options [
    {"Unknown", "unknown"},
    {"Integral", "integral"},
    {"Detachable", "detachable"},
    {"Both", "both"}
  ]

  # Valid filter types for String.to_existing_atom safety
  @valid_filter_types ~w(colors shapes textures alignments walls cells plant_parts forms seasons)a

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    if connected?(socket), do: Species.subscribe()

    filter_options = Galls.get_all_filter_options()
    families = Gallformers.Taxonomy.list_gall_families_for_select()

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Galls")
      |> assign(:abundances, Species.list_abundances())
      |> assign(:filter_options, filter_options)
      |> assign(:detachable_options, @detachable_options)
      |> assign(:families, families)
      |> init_form_state()
      |> init_search_state()
      |> init_empty_gall_state()

    {:ok, socket}
  end

  def close_form(socket) do
    push_navigate(socket, to: ~p"/admin/galls")
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    # Edit existing gall
    case Integer.parse(id) do
      {species_id, ""} ->
        load_gall_for_edit(socket, species_id, redirect_on_error: true)

      _ ->
        socket
        |> put_flash(:error, "Invalid gall ID: #{id}")
        |> push_navigate(to: ~p"/admin/galls")
    end
  end

  defp apply_action(socket, :new, params) do
    # Check if this is from the undescribed flow (has species_name param)
    if params["species_name"] do
      init_undescribed_gall_state(socket, params)
    else
      # New gall - start in search mode so user can enter a name
      socket
    end
  end

  # Initialize search state
  defp init_search_state(socket) do
    socket
    |> assign(:gall_search_query, "")
    |> assign(:gall_search_results, [])
  end

  # Initialize empty gall state (no gall selected)
  defp init_empty_gall_state(socket) do
    socket
    |> assign(:mode, :search)
    |> assign(:gall, nil)
    |> assign(:gall_data, nil)
    |> assign(:form, nil)
    |> assign(:gall_id, nil)
    # Deferred changes tracking
    |> assign(DeferredChanges.init(:aliases, []))
    |> assign(DeferredChanges.init(:hosts, []))
    |> assign(:original_filter_values, empty_filter_values())
    |> assign(:original_detachable, "unknown")
    |> assign(:original_undescribed, false)
    # Pending state (what user sees and edits)
    |> assign(:taxonomy, nil)
    |> assign(:genus_is_new, false)
    |> assign(:selected_family_id, nil)
    |> assign(:filter_values, empty_filter_values())
    |> assign(:detachable, "unknown")
    |> assign(:undescribed, false)
    |> assign(:new_alias_name, "")
    |> assign(:new_alias_type, "common")
    |> assign(:host_search_query, "")
    |> assign(:host_search_results, [])
    |> assign(:host_dropdown_open, false)
    |> assign(:filter_search, init_filter_search_state())
    |> assign(:filter_dropdown_open, nil)
    # Rename modal state
    |> assign(:show_rename_modal, false)
    |> assign(:rename_value, "")
    |> assign(:add_alias_on_rename, false)
    # Genus disambiguation modal state
    |> assign(:show_genus_disambiguation, false)
    |> assign(:possible_families, [])
    |> reset_dirty()
  end

  # Initialize state for a new gall (user typed new name)
  defp init_new_gall_state(socket, name) do
    gall = %SpeciesSchema{taxoncode: "gall", name: name}
    changeset = Species.change_species(gall)
    # Look up taxonomy from the genus name - this always returns a result
    # with genus_is_new: true/false to indicate if genus needs to be created
    raw_taxonomy = Gallformers.Taxonomy.lookup_taxonomy_for_new_species(name)

    # Handle genus disambiguation: filter to non-plant families only
    {taxonomy, genus_is_new, selected_family_id, possible_families} =
      resolve_taxonomy_for_gall(raw_taxonomy, socket.assigns.families)

    socket
    |> assign(:mode, :new)
    |> assign(:page_title, "New Gall")
    |> assign(:gall, gall)
    |> assign(:gall_data, nil)
    |> assign(:form, to_form(changeset))
    |> assign(:gall_id, nil)
    # Deferred changes tracking
    |> assign(DeferredChanges.init(:aliases, []))
    |> assign(DeferredChanges.init(:hosts, []))
    |> assign(:original_filter_values, empty_filter_values())
    |> assign(:original_detachable, "unknown")
    |> assign(:original_undescribed, false)
    # Pending state
    |> assign(:taxonomy, taxonomy)
    |> assign(:genus_is_new, genus_is_new)
    |> assign(:selected_family_id, selected_family_id)
    |> assign(:possible_families, possible_families)
    |> assign(:filter_values, empty_filter_values())
    |> assign(:detachable, "unknown")
    |> assign(:undescribed, false)
    |> assign(:new_alias_name, "")
    |> assign(:new_alias_type, "common")
    |> assign(:host_search_query, "")
    |> assign(:host_search_results, [])
    |> assign(:host_dropdown_open, false)
    |> assign(:filter_search, init_filter_search_state())
    |> assign(:filter_dropdown_open, nil)
    |> assign(:show_rename_modal, false)
    |> assign(:rename_value, "")
    |> assign(:add_alias_on_rename, false)
    # Genus disambiguation modal state
    |> assign(:show_genus_disambiguation, false)
    # Clear search
    |> assign(:gall_search_query, "")
    |> assign(:gall_search_results, [])
    # Mark form dirty since user entered a name (enables save button)
    |> reset_dirty()
    |> mark_dirty()
  end

  # Resolve taxonomy for galls: filter to non-plant families only
  defp resolve_taxonomy_for_gall(nil, _families), do: {nil, false, nil, []}

  defp resolve_taxonomy_for_gall(taxonomy, families) do
    gall_family_ids = MapSet.new(families, fn {_name, id} -> id end)

    cond do
      # Genus is new - user must select a gall family
      Map.get(taxonomy, :genus_is_new) ->
        {taxonomy, true, nil, []}

      # Genus exists in multiple families - filter to non-plant families
      Map.get(taxonomy, :requires_disambiguation) ->
        gall_families =
          Enum.filter(taxonomy.possible_families, fn family ->
            MapSet.member?(gall_family_ids, family.family_id)
          end)

        case gall_families do
          [] ->
            # No gall families found - treat as new genus
            {%{genus: taxonomy.genus, genus_id: nil, genus_is_new: true}, true, nil, []}

          [single] ->
            # Only one gall family - auto-select it
            resolved = %{
              genus: taxonomy.genus,
              genus_id: single.genus_id,
              genus_is_new: false,
              section: single.section,
              section_id: single.section_id,
              family: single.family,
              family_id: single.family_id
            }

            {resolved, false, single.family_id, []}

          multiple ->
            # Multiple gall families - needs disambiguation
            {taxonomy, false, nil, multiple}
        end

      # Genus exists in exactly one family - check if it's a gall family
      true ->
        if MapSet.member?(gall_family_ids, taxonomy.family_id) do
          # It's a gall family - use it
          {taxonomy, false, taxonomy.family_id, []}
        else
          # It's NOT a gall family - treat as new genus
          {%{genus: taxonomy.genus, genus_id: nil, genus_is_new: true}, true, nil, []}
        end
    end
  end

  # Initialize state for a new undescribed gall from the undescribed flow modal.
  # Params come from URL query string: species_name, genus_id, family_id, host_id, undescribed
  defp init_undescribed_gall_state(socket, params) do
    name = params["species_name"]
    genus_id = parse_int_param(params["genus_id"])
    family_id = parse_int_param(params["family_id"])
    host_id = parse_int_param(params["host_id"])

    gall = %SpeciesSchema{taxoncode: "gall", name: name}
    changeset = Species.change_species(gall)

    # Build taxonomy info based on whether genus_id is provided
    {taxonomy, genus_is_new, selected_family_id} =
      if genus_id do
        # Known genus - look it up
        genus = Gallformers.Taxonomy.get_taxonomy(genus_id)

        if genus do
          taxonomy = Gallformers.Taxonomy.lookup_taxonomy_for_new_species(name)
          {taxonomy, false, family_id}
        else
          # Genus not found, fall back to family-only
          {%{genus: "Unknown", genus_id: nil, genus_is_new: true, family_id: family_id}, true,
           family_id}
        end
      else
        # Unknown genus - will create "Unknown" genus under the family
        {%{
           genus: "Unknown",
           genus_id: nil,
           genus_is_new: true,
           section: nil,
           section_id: nil,
           family: nil,
           family_id: family_id
         }, true, family_id}
      end

    # Fetch the type host to add to pending hosts
    host = if host_id, do: Species.get_species(host_id)

    socket
    |> assign(:mode, :new)
    |> assign(:page_title, "New Undescribed Gall")
    |> assign(:gall, gall)
    |> assign(:gall_data, nil)
    |> assign(:form, to_form(changeset))
    |> assign(:gall_id, nil)
    # Deferred changes tracking
    |> assign(DeferredChanges.init(:aliases, []))
    |> assign(DeferredChanges.init(:hosts, []))
    |> assign(:original_filter_values, empty_filter_values())
    |> assign(:original_detachable, "unknown")
    |> assign(:original_undescribed, false)
    # Pending state - set undescribed to true
    |> assign(:taxonomy, taxonomy)
    |> assign(:genus_is_new, genus_is_new)
    |> assign(:selected_family_id, selected_family_id)
    |> assign(:filter_values, empty_filter_values())
    |> assign(:detachable, "unknown")
    |> assign(:undescribed, true)
    |> assign(:new_alias_name, "")
    |> assign(:new_alias_type, "common")
    |> assign(:host_search_query, "")
    |> assign(:host_search_results, [])
    |> assign(:host_dropdown_open, false)
    |> assign(:filter_search, init_filter_search_state())
    |> assign(:filter_dropdown_open, nil)
    |> assign(:show_rename_modal, false)
    |> assign(:rename_value, "")
    |> assign(:add_alias_on_rename, false)
    # Genus disambiguation modal state
    |> assign(:show_genus_disambiguation, false)
    |> assign(:possible_families, [])
    # Clear search
    |> assign(:gall_search_query, "")
    |> assign(:gall_search_results, [])
    # Add the type host if provided
    |> maybe_add_initial_host(host)
    # Mark form dirty since coming from undescribed flow
    |> reset_dirty()
    |> mark_dirty()
  end

  defp parse_int_param(nil), do: nil
  defp parse_int_param(""), do: nil

  defp parse_int_param(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp maybe_add_initial_host(socket, nil), do: socket

  defp maybe_add_initial_host(socket, host) do
    DeferredChanges.add_pending(
      socket,
      :hosts,
      %{host_species_id: host.id, host_name: host.name},
      id_field: :host_relation_id
    )
  end

  # Load an existing gall for editing
  # When redirect_on_error is true (URL navigation), redirect to clean URL on error
  # When false (event handlers), stay on page and show error
  defp load_gall_for_edit(socket, species_id, opts \\ []) do
    redirect_on_error = Keyword.get(opts, :redirect_on_error, false)

    case Galls.get_gall_for_admin_edit(species_id) do
      nil ->
        handle_load_error(socket, "Gall not found", redirect_on_error)

      gall_data ->
        species = Species.get_species!(species_id)

        if species.taxoncode != "gall" do
          handle_load_error(
            socket,
            "This is not a gall. Use the Host admin for host species.",
            redirect_on_error
          )
        else
          changeset = Species.change_species(species)
          aliases = Species.get_aliases_for_species(species_id)
          hosts = Gallformers.GallHosts.get_hosts_for_gall(species_id)
          taxonomy = Gallformers.Taxonomy.get_taxonomy_for_species(species_id)
          filter_values = gall_data.filter_values
          detachable = gall_data.detachable || "unknown"
          undescribed = gall_data.undescribed || false

          socket
          |> assign(:mode, :edit)
          |> assign(:page_title, "Edit Gall - #{species.name}")
          |> assign(:gall, species)
          |> assign(:gall_data, gall_data)
          |> assign(:form, to_form(changeset))
          |> assign(:gall_id, gall_data.gall_id)
          # Deferred changes tracking
          |> assign(DeferredChanges.init(:aliases, aliases))
          |> assign(DeferredChanges.init(:hosts, hosts))
          |> assign(:original_filter_values, filter_values)
          |> assign(:original_detachable, detachable)
          |> assign(:original_undescribed, undescribed)
          # Pending state
          |> assign(:taxonomy, taxonomy)
          |> assign(:genus_is_new, false)
          |> assign(:selected_family_id, taxonomy && taxonomy.family_id)
          |> assign(:filter_values, filter_values)
          |> assign(:detachable, detachable)
          |> assign(:undescribed, undescribed)
          |> assign(:new_alias_name, "")
          |> assign(:new_alias_type, "common")
          |> assign(:host_search_query, "")
          |> assign(:host_search_results, [])
          |> assign(:host_dropdown_open, false)
          |> assign(:filter_search, init_filter_search_state())
          |> assign(:filter_dropdown_open, nil)
          |> assign(:show_rename_modal, false)
          |> assign(:rename_value, species.name)
          |> assign(:add_alias_on_rename, false)
          # Genus disambiguation modal state
          |> assign(:show_genus_disambiguation, false)
          |> assign(:possible_families, [])
          # Clear search
          |> assign(:gall_search_query, "")
          |> assign(:gall_search_results, [])
          |> reset_dirty()
        end
    end
  end

  defp empty_filter_values do
    %{
      colors: [],
      shapes: [],
      textures: [],
      alignments: [],
      walls: [],
      cells: [],
      plant_parts: [],
      forms: [],
      seasons: []
    }
  end

  defp init_filter_search_state do
    %{
      colors: "",
      shapes: "",
      textures: "",
      alignments: "",
      walls: "",
      cells: "",
      plant_parts: "",
      forms: "",
      seasons: ""
    }
  end

  defp handle_load_error(socket, message, true = _redirect) do
    socket
    |> put_flash(:error, message)
    |> push_navigate(to: ~p"/admin/galls")
  end

  defp handle_load_error(socket, message, false = _redirect) do
    socket
    |> put_flash(:error, message)
    |> init_empty_gall_state()
  end

  # =================================================================
  # Event handlers - Gall search/select/create
  # =================================================================

  @impl true
  def handle_event("search_gall", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Species.search_species(query, 10)
        |> Enum.filter(&(&1.taxoncode == "gall"))
      else
        []
      end

    {:noreply,
     socket
     |> assign(:gall_search_query, query)
     |> assign(:gall_search_results, results)}
  end

  @impl true
  def handle_event("select_gall", %{"id" => id}, socket) do
    species_id = String.to_integer(id)
    # Navigate to the edit URL so the URL reflects the selected gall
    {:noreply, push_patch(socket, to: ~p"/admin/galls/#{species_id}")}
  end

  @impl true
  def handle_event("create_gall", %{"name" => name}, socket) do
    # User wants to create a new gall with this name
    {:noreply, init_new_gall_state(socket, name)}
  end

  @impl true
  def handle_event("clear_gall", _params, socket) do
    # Clear selection and return to search mode
    {:noreply, close_form(socket)}
  end

  # =================================================================
  # Event handlers - Form validation and save
  # =================================================================

  @impl true
  def handle_event("validate", %{"species" => params}, socket) do
    changeset =
      socket.assigns.gall
      |> Species.change_species(params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form, to_form(changeset)) |> mark_dirty()}
  end

  # Catch-all for validate events from standalone inputs
  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"species" => params}, socket) do
    cond do
      # Validate that family is selected when genus is new
      socket.assigns.genus_is_new && is_nil(socket.assigns.selected_family_id) ->
        {:noreply, put_flash(socket, :error, "Please select a Family for the new genus")}

      # Check for Unknown genus/family without undescribed flag
      has_unknown_taxonomy?(socket) && !socket.assigns.undescribed &&
          !socket.assigns[:unknown_taxonomy_confirmed] ->
        {:noreply,
         socket
         |> put_flash(
           :warning,
           "This gall has an Unknown genus/family but is not marked as undescribed. " <>
             "This is likely an error. Click Save again to confirm, or check the Undescribed box."
         )
         |> assign(:unknown_taxonomy_confirmed, true)}

      true ->
        # Name is captured via typeahead (outside the form), so add it from socket assigns
        params =
          params
          |> Map.put("taxoncode", "gall")
          |> Map.put("name", socket.assigns.gall.name)

        save_gall(socket, socket.assigns.mode, params)
    end
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(request_cancel cancel_discard confirm_discard) do
    handle_form_event(event, params, socket)
  end

  # =================================================================
  # Event handlers - Aliases
  # =================================================================

  @impl true
  def handle_event("update_new_alias", %{"value" => name, "type" => type}, socket) do
    {:noreply, assign(socket, new_alias_name: name, new_alias_type: type)}
  end

  @impl true
  def handle_event("update_new_alias", %{"value" => type, "name" => name}, socket) do
    {:noreply, assign(socket, new_alias_name: name, new_alias_type: type)}
  end

  @impl true
  def handle_event("add_alias", _params, socket) do
    name = String.trim(socket.assigns.new_alias_name)
    type = socket.assigns.new_alias_type

    cond do
      name == "" ->
        {:noreply, put_flash(socket, :error, "Alias name cannot be empty")}

      DeferredChanges.exists?(socket, :aliases, :name, name) ->
        {:noreply, put_flash(socket, :error, "Alias already exists")}

      true ->
        socket =
          socket
          |> DeferredChanges.add_pending(:aliases, %{name: name, type: type})
          |> assign(:new_alias_name, "")
          |> mark_dirty()

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_alias", %{"alias-id" => alias_id}, socket) do
    alias_id = String.to_integer(alias_id)

    socket =
      socket
      |> DeferredChanges.remove_pending(:aliases, alias_id)
      |> mark_dirty()

    {:noreply, socket}
  end

  # =================================================================
  # Event handlers - Hosts
  # =================================================================

  @impl true
  def handle_event("search_hosts", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Species.search_species_by_name(query, "plant", 10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:host_search_query, query)
     |> assign(:host_search_results, results)
     |> assign(:host_dropdown_open, results != [])}
  end

  @impl true
  def handle_event("open_host_dropdown", _params, socket) do
    {:noreply, assign(socket, :host_dropdown_open, true)}
  end

  @impl true
  def handle_event("close_host_dropdown", _params, socket) do
    {:noreply, assign(socket, :host_dropdown_open, false)}
  end

  @impl true
  def handle_event("add_host", %{"id" => host_id}, socket) do
    host_id = String.to_integer(host_id)

    if DeferredChanges.exists?(socket, :hosts, :host_species_id, host_id) do
      {:noreply, put_flash(socket, :error, "Host already associated")}
    else
      add_host_to_pending(socket, host_id)
    end
  end

  @impl true
  def handle_event("remove_host", %{"id" => id}, socket) do
    relation_id = String.to_integer(id)

    socket =
      socket
      |> DeferredChanges.remove_pending(:hosts, relation_id, id_field: :host_relation_id)
      |> mark_dirty()

    {:noreply, socket}
  end

  # =================================================================
  # Event handlers - Gall properties (detachable, undescribed, filters)
  # =================================================================

  @impl true
  def handle_event("update_detachable", %{"value" => value}, socket) do
    {:noreply, socket |> assign(:detachable, value) |> mark_dirty()}
  end

  @impl true
  def handle_event("toggle_undescribed", _params, socket) do
    new_value = !socket.assigns.undescribed

    {:noreply,
     socket
     |> assign(:undescribed, new_value)
     |> assign(:unknown_taxonomy_confirmed, false)
     |> mark_dirty()}
  end

  @impl true
  def handle_event("select_family", %{"family_id" => family_id}, socket) do
    family_id = if family_id == "", do: nil, else: String.to_integer(family_id)
    {:noreply, socket |> assign(:selected_family_id, family_id) |> mark_dirty()}
  end

  @impl true
  def handle_event("select_family_from_disambiguation", %{"family_id" => family_id_str}, socket) do
    family_id = String.to_integer(family_id_str)
    possible_families = socket.assigns.possible_families

    # Find the selected family from the possible families list
    selected = Enum.find(possible_families, &(&1.family_id == family_id))

    if selected do
      # Update taxonomy with the selected family info
      taxonomy = %{
        genus: socket.assigns.taxonomy.genus,
        genus_id: selected.genus_id,
        genus_is_new: false,
        section: selected.section,
        section_id: selected.section_id,
        family: selected.family,
        family_id: selected.family_id
      }

      {:noreply,
       socket
       |> assign(:taxonomy, taxonomy)
       |> assign(:selected_family_id, family_id)
       |> assign(:possible_families, [])
       |> assign(:show_genus_disambiguation, false)
       |> mark_dirty()}
    else
      {:noreply, put_flash(socket, :error, "Family not found")}
    end
  end

  @impl true
  def handle_event("filter_search", %{"type" => type, "value" => query}, socket) do
    filter_type = string_to_filter_type(type)
    filter_search = Map.put(socket.assigns.filter_search, filter_type, query)

    {:noreply,
     socket |> assign(:filter_search, filter_search) |> assign(:filter_dropdown_open, filter_type)}
  end

  @impl true
  def handle_event("open_filter_dropdown", %{"type" => type}, socket) do
    filter_type = string_to_filter_type(type)
    {:noreply, assign(socket, :filter_dropdown_open, filter_type)}
  end

  @impl true
  def handle_event("close_filter_dropdown", _params, socket) do
    {:noreply, assign(socket, :filter_dropdown_open, nil)}
  end

  @impl true
  def handle_event("add_filter", %{"type" => type, "id" => id}, socket) do
    filter_type = string_to_filter_type(type)
    filter_id = String.to_integer(id)

    options = Map.get(socket.assigns.filter_options, filter_type, [])
    option = Enum.find(options, &(&1.id == filter_id))

    if option do
      current_values = Map.get(socket.assigns.filter_values, filter_type, [])

      if Enum.any?(current_values, &(&1.id == filter_id)) do
        {:noreply, put_flash(socket, :error, "Already selected")}
      else
        new_values = current_values ++ [option]
        filter_values = Map.put(socket.assigns.filter_values, filter_type, new_values)
        filter_search = Map.put(socket.assigns.filter_search, filter_type, "")

        {:noreply,
         socket
         |> assign(:filter_values, filter_values)
         |> assign(:filter_search, filter_search)
         |> assign(:filter_dropdown_open, nil)
         |> mark_dirty()}
      end
    else
      {:noreply, put_flash(socket, :error, "Option not found")}
    end
  end

  @impl true
  def handle_event("remove_filter", %{"type" => type, "id" => id}, socket) do
    filter_type = string_to_filter_type(type)
    filter_id = String.to_integer(id)

    current_values = Map.get(socket.assigns.filter_values, filter_type, [])
    new_values = Enum.reject(current_values, &(&1.id == filter_id))
    filter_values = Map.put(socket.assigns.filter_values, filter_type, new_values)

    {:noreply, socket |> assign(:filter_values, filter_values) |> mark_dirty()}
  end

  # =================================================================
  # Event handlers - Rename modal
  # =================================================================

  @impl true
  def handle_event("open_rename_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_rename_modal, true)
     |> assign(:rename_value, socket.assigns.gall.name)
     |> assign(:add_alias_on_rename, false)}
  end

  @impl true
  def handle_event("close_rename_modal", _params, socket) do
    {:noreply, assign(socket, :show_rename_modal, false)}
  end

  @impl true
  def handle_event("request_close_rename", _params, socket) do
    if socket.assigns.rename_value == socket.assigns.gall.name do
      {:noreply, assign(socket, :show_rename_modal, false)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_rename_value", %{"value" => value}, socket) do
    {:noreply, assign(socket, :rename_value, value)}
  end

  @impl true
  def handle_event("toggle_add_alias_on_rename", _params, socket) do
    {:noreply, assign(socket, :add_alias_on_rename, !socket.assigns.add_alias_on_rename)}
  end

  @impl true
  def handle_event("do_rename", _params, socket) do
    new_name = String.trim(socket.assigns.rename_value)
    old_name = socket.assigns.gall.name

    cond do
      new_name == "" ->
        {:noreply, put_flash(socket, :error, "Name cannot be empty")}

      new_name == old_name ->
        {:noreply, assign(socket, :show_rename_modal, false)}

      not valid_species_name?(new_name) ->
        {:noreply, put_flash(socket, :error, "Name must be a valid species name (Genus species)")}

      true ->
        case Species.rename_species(
               socket.assigns.gall.id,
               new_name,
               socket.assigns.add_alias_on_rename
             ) do
          {:ok, updated_species} ->
            aliases =
              if socket.assigns.add_alias_on_rename do
                Species.get_aliases_for_species(socket.assigns.gall.id)
              else
                socket.assigns.aliases
              end

            {:noreply,
             socket
             |> assign(:gall, updated_species)
             |> assign(:aliases, aliases)
             |> assign(:show_rename_modal, false)
             |> assign(:page_title, "Edit Gall - #{new_name}")
             |> put_flash(:info, "Gall renamed successfully")}

          {:error, :name_exists} ->
            {:noreply, put_flash(socket, :error, "That name is already in use")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to rename gall")}
        end
    end
  end

  # =================================================================
  # Event handlers - Delete
  # =================================================================

  @impl true
  def handle_event("delete", _params, socket) do
    case Species.delete_species(socket.assigns.gall) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gall deleted successfully")
         |> init_empty_gall_state()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete gall")}
    end
  end

  # =================================================================
  # PubSub handlers
  # =================================================================

  @impl true
  def handle_info({:species_updated, species}, socket) do
    # If the currently edited gall was updated elsewhere, reload it
    if socket.assigns.gall && socket.assigns.gall.id == species.id do
      {:noreply, load_gall_for_edit(socket, species.id)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:species_deleted, species}, socket) do
    # If the currently edited gall was deleted, clear it
    if socket.assigns.gall && socket.assigns.gall.id == species.id do
      {:noreply,
       socket
       |> put_flash(:warning, "This gall was deleted by another user")
       |> init_empty_gall_state()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:species_created, _species}, socket) do
    # New species created elsewhere - no action needed
    {:noreply, socket}
  end

  # =================================================================
  # Private helper functions
  # =================================================================

  # Checks if genus or family is "Unknown"
  defp has_unknown_taxonomy?(socket) do
    taxonomy = socket.assigns.taxonomy
    genus_name = socket.assigns[:genus] || (taxonomy && taxonomy.genus)

    # Check both the selected genus (if new) and the taxonomy data
    if socket.assigns.genus_is_new do
      # For new genus flow, check the selected family
      family = Gallformers.Taxonomy.get_taxonomy(socket.assigns.selected_family_id)
      family && family.name == "Unknown"
    else
      # Check the taxonomy record for Unknown genus or family
      (genus_name && genus_name == "Unknown") ||
        (taxonomy && taxonomy.family == "Unknown")
    end
  end

  defp add_host_to_pending(socket, host_id) do
    host_result = Enum.find(socket.assigns.host_search_results, &(&1.id == host_id))

    if host_result do
      socket =
        socket
        |> DeferredChanges.add_pending(
          :hosts,
          %{host_species_id: host_id, host_name: host_result.name},
          id_field: :host_relation_id
        )
        |> assign(:host_search_query, "")
        |> assign(:host_search_results, [])
        |> assign(:host_dropdown_open, false)
        |> mark_dirty()

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Host not found")}
    end
  end

  defp save_gall(socket, :new, params) do
    # For new galls, we create everything in one transaction
    hosts_to_add = socket.assigns.hosts
    filter_values = socket.assigns.filter_values
    aliases_to_add = socket.assigns.aliases
    taxonomy = socket.assigns.taxonomy
    genus_is_new = socket.assigns.genus_is_new
    selected_family_id = socket.assigns.selected_family_id

    transaction_result =
      Repo.transaction(fn ->
        case Species.create_species(params) do
          {:ok, species} ->
            # Create gall-specific record
            {:ok, _gall} = Galls.create_gall_traits(species.id)

            # Handle taxonomy: create genus if new, or link to existing
            Gallformers.Taxonomy.link_species_taxonomy(
              species.id,
              taxonomy,
              genus_is_new,
              selected_family_id
            )

            # Add hosts
            for host <- hosts_to_add do
              GallHosts.add_host_to_gall(species.id, host.host_species_id)
            end

            # Add aliases
            for a <- aliases_to_add do
              Species.create_alias_for_species(species.id, %{name: a.name, type: a.type})
            end

            # Add filter values
            save_filter_changes(species.id, empty_filter_values(), filter_values)

            # Save gall properties
            Galls.update_gall_properties(species.id, %{
              detachable: socket.assigns.detachable,
              undescribed: socket.assigns.undescribed
            })

            species

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    case transaction_result do
      {:ok, species} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gall created successfully")
         |> load_gall_for_edit(species.id)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create gall. Please try again.")}
    end
  end

  defp save_gall(socket, :edit, params) do
    gall_id = socket.assigns.gall_id
    species_id = socket.assigns.gall.id

    # Compute changes using DeferredChanges
    {aliases_to_add, aliases_to_remove} = DeferredChanges.compute_changes(socket, :aliases)

    {hosts_to_add, hosts_to_remove} =
      DeferredChanges.compute_changes(socket, :hosts, id_field: :host_relation_id)

    # Wrap all saves in a transaction for atomicity
    transaction_result =
      Repo.transaction(fn ->
        case Species.update_species(socket.assigns.gall, params) do
          {:ok, updated_gall} ->
            save_alias_changes(species_id, aliases_to_add, aliases_to_remove)
            save_host_changes(species_id, hosts_to_add, hosts_to_remove)
            save_gall_specific_data(gall_id, socket.assigns)
            updated_gall

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    case transaction_result do
      {:ok, updated_gall} ->
        # Reload data from DB to get actual IDs for new records
        aliases = Species.get_aliases_for_species(species_id)
        hosts = Gallformers.GallHosts.get_hosts_for_gall(species_id)

        filter_values =
          if gall_id, do: Galls.get_gall_filter_values(gall_id), else: empty_filter_values()

        # Stay on page, update state to reflect saved data
        {:noreply,
         socket
         |> assign(:gall, updated_gall)
         |> DeferredChanges.refresh(:aliases, aliases)
         |> DeferredChanges.refresh(:hosts, hosts)
         |> assign(:original_filter_values, filter_values)
         |> assign(:original_detachable, socket.assigns.detachable)
         |> assign(:original_undescribed, socket.assigns.undescribed)
         |> assign(:filter_values, filter_values)
         |> reset_dirty()
         |> put_flash(:info, "Gall saved successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save gall. Please try again.")}
    end
  end

  defp save_gall_specific_data(nil, _assigns), do: :ok

  defp save_gall_specific_data(gall_id, assigns) do
    save_filter_changes(gall_id, assigns.original_filter_values, assigns.filter_values)

    Galls.update_gall_properties(gall_id, %{
      detachable: assigns.detachable,
      undescribed: assigns.undescribed
    })
  end

  defp save_alias_changes(species_id, to_add, to_remove) do
    for alias_id <- to_remove do
      Species.remove_alias_from_species(species_id, alias_id)
    end

    for a <- to_add do
      Species.create_alias_for_species(species_id, %{name: a.name, type: a.type})
    end
  end

  defp save_host_changes(species_id, to_add, to_remove) do
    for relation_id <- to_remove do
      GallHosts.remove_host_from_gall(relation_id)
    end

    for host <- to_add do
      GallHosts.add_host_to_gall(species_id, host.host_species_id)
    end
  end

  defp save_filter_changes(gall_id, original_values, current_values) do
    filter_types = [
      :colors,
      :shapes,
      :textures,
      :alignments,
      :walls,
      :cells,
      :plant_parts,
      :forms,
      :seasons
    ]

    for filter_type <- filter_types do
      original = Map.get(original_values, filter_type, [])
      current = Map.get(current_values, filter_type, [])

      original_ids = MapSet.new(Enum.map(original, & &1.id))
      current_ids = MapSet.new(Enum.map(current, & &1.id))

      removed_ids = MapSet.difference(original_ids, current_ids)

      for filter_id <- removed_ids do
        Galls.remove_filter_field_from_gall(gall_id, filter_type, filter_id)
      end

      added_ids = MapSet.difference(current_ids, original_ids)

      for filter_id <- added_ids do
        Galls.add_filter_field_to_gall(gall_id, filter_type, filter_id)
      end
    end
  end

  # Convert valid filter type strings to atoms (whitelist strings derived from @valid_filter_types)
  @valid_filter_type_strings Enum.map(@valid_filter_types, &Atom.to_string/1)

  defp string_to_filter_type(type) when type in @valid_filter_type_strings do
    String.to_atom(type)
  end

  defp string_to_filter_type(type) when is_binary(type) do
    raise ArgumentError, "Invalid filter type: #{type}"
  end

  # =================================================================
  # Render
  # =================================================================

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :title, "Add/Edit Galls")

    ~H"""
    <Layouts.admin
      flash={@flash}
      current_user={@current_user}
      page_title={@page_title}
      public_url={if @mode == :edit, do: ~p"/gall/#{@gall.id}"}
    >
      <div class="bg-white shadow rounded-lg">
        <Layouts.admin_edit_layout back_path={~p"/admin"} back_label="Back to Admin" title={@title}>
          <:intro>
            Search for an existing gall to edit, or type a new name to create one.
            To add descriptions, first add <.link
              navigate={~p"/admin/sources"}
              class="hover:underline"
            >Sources</.link>,
            then map species to sources.
          </:intro>

          <:quick_links :if={@mode == :edit}>
            <.link
              navigate={~p"/admin/images?species_id=#{@gall.id}"}
              class="text-sm hover:underline mr-4"
            >
              Manage Images
            </.link>
            <.link
              navigate={~p"/admin/gallhost?id=#{@gall.id}"}
              class="text-sm hover:underline mr-4"
            >
              Gall-Host Mappings
            </.link>
            <.link
              navigate={~p"/admin/species-sources/find?species_id=#{@gall.id}"}
              class="text-sm hover:underline"
            >
              Species-Source Mappings
            </.link>
          </:quick_links>

          <%!-- Name field with typeahead for search/create --%>
          <div class="mb-3">
            <%= if @mode == :edit do %>
              <%!-- Edit mode: show selected name with rename button --%>
              <label class="gf-label">Name (binomial):</label>
              <div class="flex gap-2">
                <input
                  type="text"
                  value={@gall.name}
                  disabled
                  class="flex-1 px-3 py-2 bg-gray-100 border border-gray-300 rounded text-gray-700 text-sm italic"
                />
                <button
                  type="button"
                  phx-click="open_rename_modal"
                  class="px-3 py-2 text-sm bg-gray-200 hover:bg-gray-300 border border-gray-300 rounded"
                >
                  Rename
                </button>
              </div>
            <% else %>
              <%!-- Search/New mode: typeahead for search or create --%>
              <.typeahead
                id="gall-picker"
                label="Name (binomial):"
                placeholder="Search existing galls or type new name..."
                search_event="search_gall"
                select_event="select_gall"
                clear_event="clear_gall"
                create_event="create_gall"
                allow_new={true}
                query={@gall_search_query}
                results={@gall_search_results}
                selected={@gall}
                display_fn={fn gall -> gall.name end}
              />
              <p :if={@mode == :search} class="text-gray-500 text-xs mt-1">
                Type to search existing galls, or enter a new name to create one.
              </p>
            <% end %>
          </div>

          <%!-- Rest of form - disabled until gall selected/created --%>
          <fieldset disabled={@mode == :search} class={[@mode == :search && "opacity-50"]}>
            <.form
              :if={@form}
              for={@form}
              id="gall-form"
              phx-change="validate"
              phx-submit="save"
            >
              <%!-- Row: Genus | Family --%>
              <div class="grid grid-cols-2 gap-4 mb-3">
                <div>
                  <label class="gf-label">
                    Genus (filled automatically):
                  </label>
                  <input
                    type="text"
                    value={if @taxonomy, do: @taxonomy.genus, else: ""}
                    disabled
                    class="w-full px-3 py-2 bg-gray-100 border border-gray-300 rounded text-gray-500 text-sm"
                  />
                  <p :if={@genus_is_new} class="text-amber-600 text-xs mt-1">
                    New genus - will be created under selected family
                  </p>
                </div>
                <div>
                  <label class="gf-label">
                    Family:<span class="text-red-600 ml-0.5">*</span>
                  </label>
                  <%= if @genus_is_new do %>
                    <%!-- Genus is new - user must select a family --%>
                    <select
                      name="family_id"
                      phx-change="select_family"
                      class="w-full px-3 py-2 border border-gray-300 rounded text-sm"
                    >
                      <option value="">-- Select Family --</option>
                      <%= for {name, id} <- @families do %>
                        <option value={id} selected={@selected_family_id == id}>{name}</option>
                      <% end %>
                    </select>
                    <p :if={is_nil(@selected_family_id)} class="text-red-600 text-xs mt-1">
                      Please select a family for the new genus
                    </p>
                  <% else %>
                    <%!-- Genus exists - family is read-only --%>
                    <input
                      type="text"
                      value={if @taxonomy, do: @taxonomy.family, else: ""}
                      disabled
                      class="w-full px-3 py-2 bg-gray-100 border border-gray-300 rounded text-gray-500 text-sm"
                    />
                  <% end %>
                </div>
              </div>

              <%!-- Row: Hosts --%>
              <div class="mb-3">
                <.multi_select_dropdown
                  id="host-picker"
                  label="Hosts:"
                  type={:hosts}
                  search_results={@host_search_results}
                  selected={@hosts}
                  search_query={@host_search_query}
                  dropdown_open={@host_dropdown_open}
                  item_id={:host_relation_id}
                  result_id={:id}
                  selected_match_id={:host_species_id}
                  item_label={:host_name}
                  result_label={:name}
                  placeholder="Search hosts..."
                  on_search="search_hosts"
                  on_add="add_host"
                  on_remove="remove_host"
                  on_open="open_host_dropdown"
                  on_close="close_host_dropdown"
                  required={true}
                />
                <p :if={@hosts == []} class="text-red-600 text-xs mt-1">
                  You must map this gall to at least one host.
                </p>
              </div>

              <%!-- Row: Detachable | Walls | Cells | Alignment --%>
              <div class="grid grid-cols-4 gap-3 mb-3">
                <div>
                  <.input
                    type="select"
                    name="value"
                    label="Detachable:"
                    options={@detachable_options}
                    value={@detachable}
                    phx-change="update_detachable"
                  />
                </div>
                <.multi_select_dropdown
                  id="walls"
                  label="Walls:"
                  type={:walls}
                  options={@filter_options.walls}
                  selected={@filter_values.walls}
                  search_query={@filter_search.walls}
                  dropdown_open={@filter_dropdown_open == :walls}
                  item_label={:field}
                  on_search="filter_search"
                  on_add="add_filter"
                  on_remove="remove_filter"
                  on_open="open_filter_dropdown"
                  on_close="close_filter_dropdown"
                />
                <.multi_select_dropdown
                  id="cells"
                  label="Cells:"
                  type={:cells}
                  options={@filter_options.cells}
                  selected={@filter_values.cells}
                  search_query={@filter_search.cells}
                  dropdown_open={@filter_dropdown_open == :cells}
                  item_label={:field}
                  on_search="filter_search"
                  on_add="add_filter"
                  on_remove="remove_filter"
                  on_open="open_filter_dropdown"
                  on_close="close_filter_dropdown"
                />
                <.multi_select_dropdown
                  id="alignments"
                  label="Alignment(s):"
                  type={:alignments}
                  options={@filter_options.alignments}
                  selected={@filter_values.alignments}
                  search_query={@filter_search.alignments}
                  dropdown_open={@filter_dropdown_open == :alignments}
                  item_label={:field}
                  on_search="filter_search"
                  on_add="add_filter"
                  on_remove="remove_filter"
                  on_open="open_filter_dropdown"
                  on_close="close_filter_dropdown"
                />
              </div>

              <%!-- Row: Color | Shape | Season | Form --%>
              <div class="grid grid-cols-4 gap-3 mb-3">
                <.multi_select_dropdown
                  id="colors"
                  label="Color(s):"
                  type={:colors}
                  options={@filter_options.colors}
                  selected={@filter_values.colors}
                  search_query={@filter_search.colors}
                  dropdown_open={@filter_dropdown_open == :colors}
                  item_label={:field}
                  on_search="filter_search"
                  on_add="add_filter"
                  on_remove="remove_filter"
                  on_open="open_filter_dropdown"
                  on_close="close_filter_dropdown"
                />
                <.multi_select_dropdown
                  id="shapes"
                  label="Shape(s):"
                  type={:shapes}
                  options={@filter_options.shapes}
                  selected={@filter_values.shapes}
                  search_query={@filter_search.shapes}
                  dropdown_open={@filter_dropdown_open == :shapes}
                  item_label={:field}
                  on_search="filter_search"
                  on_add="add_filter"
                  on_remove="remove_filter"
                  on_open="open_filter_dropdown"
                  on_close="close_filter_dropdown"
                />
                <.multi_select_dropdown
                  id="seasons"
                  label="Season(s):"
                  type={:seasons}
                  options={@filter_options.seasons}
                  selected={@filter_values.seasons}
                  search_query={@filter_search.seasons}
                  dropdown_open={@filter_dropdown_open == :seasons}
                  item_label={:field}
                  on_search="filter_search"
                  on_add="add_filter"
                  on_remove="remove_filter"
                  on_open="open_filter_dropdown"
                  on_close="close_filter_dropdown"
                />
                <.multi_select_dropdown
                  id="forms"
                  label="Form(s):"
                  type={:forms}
                  options={@filter_options.forms}
                  selected={@filter_values.forms}
                  search_query={@filter_search.forms}
                  dropdown_open={@filter_dropdown_open == :forms}
                  item_label={:field}
                  on_search="filter_search"
                  on_add="add_filter"
                  on_remove="remove_filter"
                  on_open="open_filter_dropdown"
                  on_close="close_filter_dropdown"
                />
              </div>

              <%!-- Row: Location | Texture | Abundance --%>
              <div class="grid grid-cols-3 gap-3 mb-3">
                <.multi_select_dropdown
                  id="plant_parts"
                  label="Location(s):"
                  type={:plant_parts}
                  options={@filter_options.plant_parts}
                  selected={@filter_values.plant_parts}
                  search_query={@filter_search.plant_parts}
                  dropdown_open={@filter_dropdown_open == :plant_parts}
                  item_label={:field}
                  on_search="filter_search"
                  on_add="add_filter"
                  on_remove="remove_filter"
                  on_open="open_filter_dropdown"
                  on_close="close_filter_dropdown"
                />
                <.multi_select_dropdown
                  id="textures"
                  label="Texture(s):"
                  type={:textures}
                  options={@filter_options.textures}
                  selected={@filter_values.textures}
                  search_query={@filter_search.textures}
                  dropdown_open={@filter_dropdown_open == :textures}
                  item_label={:field}
                  on_search="filter_search"
                  on_add="add_filter"
                  on_remove="remove_filter"
                  on_open="open_filter_dropdown"
                  on_close="close_filter_dropdown"
                />
                <div>
                  <label class="gf-label">Abundance:</label>
                  <.input
                    field={@form[:abundance_id]}
                    type="select"
                    options={Enum.map(@abundances, &{&1.abundance, &1.id})}
                    prompt=""
                    class="gf-select w-full text-sm"
                  />
                </div>
              </div>

              <%!-- Aliases table --%>
              <.alias_editor
                aliases={@aliases}
                new_alias_name={@new_alias_name}
                new_alias_type={@new_alias_type}
              />

              <%!-- Checkboxes --%>
              <div class="space-y-2 mb-4">
                <.input
                  type="checkbox"
                  field={@form[:datacomplete]}
                  label="All sources containing unique information relevant to this gall have been added and are reflected in its associated data. However, filter criteria may not be comprehensive in every field."
                />

                <label class="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={@undescribed}
                    phx-click="toggle_undescribed"
                    class="rounded border-gray-300 text-gf-maroon focus:ring-gf-maroon"
                  />
                  <span class="text-sm text-gray-700">Undescribed?</span>
                </label>
              </div>

              <%!-- Action buttons --%>
              <div class="flex justify-between pt-3 border-t border-gray-200">
                <div>
                  <button
                    :if={@mode == :edit}
                    type="button"
                    phx-click="delete"
                    data-confirm="Are you sure? This will delete the gall and all its associations."
                    class="gf-btn gf-btn-danger"
                  >
                    Delete
                  </button>
                </div>
                <.form_actions form_dirty={@form_dirty} mode={@mode} />
              </div>
            </.form>

            <.record_metadata
              :if={@mode == :edit}
              inserted_at={@gall.inserted_at}
              updated_at={@gall.updated_at}
            />
          </fieldset>

          <%!-- Placeholder when no gall selected --%>
          <div :if={@mode == :search} class="text-center py-8 text-gray-500">
            <.icon name="ph-magnifying-glass" class="h-12 w-12 mx-auto mb-3 text-gray-300" />
            <p>Select an existing gall or create a new one to edit details.</p>
          </div>

          <.discard_confirm_modal show={@show_discard_confirm} />
        </Layouts.admin_edit_layout>

        <.rename_modal
          show={@show_rename_modal}
          value={@rename_value}
          add_alias_checked={@add_alias_on_rename}
          entity_type="Gall"
        />

        <%!-- Genus disambiguation modal --%>
        <.modal
          :if={@possible_families != [] && @taxonomy}
          id="genus-disambiguation-modal"
          show
          on_cancel={JS.push("clear_gall")}
        >
          <:header>Select Family for Genus "{Map.get(@taxonomy, :genus, "")}"</:header>
          <:body>
            <p class="text-gray-700 mb-4">
              The genus <strong>{Map.get(@taxonomy, :genus, "")}</strong>
              exists in multiple gall-forming families. Please select which family this gall belongs to:
            </p>
            <div class="space-y-2">
              <%= for family <- @possible_families do %>
                <button
                  type="button"
                  phx-click="select_family_from_disambiguation"
                  phx-value-family_id={family.family_id}
                  class="block w-full text-left px-4 py-3 border border-gray-300 rounded-md hover:bg-gray-50 hover:border-gf-maroon transition-colors"
                >
                  <div class="font-medium text-gray-900">{family.family}</div>
                  <%= if family.section do %>
                    <div class="text-sm text-gray-500">Section: {family.section}</div>
                  <% end %>
                </button>
              <% end %>
            </div>
          </:body>
          <:footer>
            <button
              type="button"
              phx-click="clear_gall"
              class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
            >
              Cancel
            </button>
          </:footer>
        </.modal>
      </div>
    </Layouts.admin>
    """
  end
end
