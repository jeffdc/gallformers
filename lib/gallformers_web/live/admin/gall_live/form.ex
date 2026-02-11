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

  alias Gallformers.Galls
  alias Gallformers.Species
  alias Gallformers.Species.Species, as: SpeciesSchema
  alias Gallformers.Taxonomy.TaxonName
  alias GallformersWeb.Admin.AliasHandlers
  alias GallformersWeb.Admin.DeferredChanges

  import GallformersWeb.Admin.FormComponents,
    only: [alias_collision_warning: 1, alias_editor: 1, form_actions: 1]

  import GallformersWeb.Admin.ReclassifyHelpers

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
    families = Gallformers.Taxonomy.list_families_for_select(:gall)

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Galls")
      |> assign(:abundances, Species.list_abundances())
      |> assign(:filter_options, filter_options)
      |> assign(:detachable_options, @detachable_options)
      |> assign(:families, families)
      |> init_form_state()
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

  # Initialize empty gall state (no gall selected)
  defp init_empty_gall_state(socket), do: build_default_assigns(socket)

  # Sets ALL gall form assigns to their default/empty values.
  # Each init path calls this first, then overrides only what differs.
  defp build_default_assigns(socket) do
    socket
    |> assign(:mode, :search)
    |> assign(:from_undescribed_flow, false)
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
    |> assign(:undescribed_locked, false)
    |> assign(:undescribed_lock_reason, nil)
    |> assign(:new_alias_name, "")
    |> assign(:new_alias_type, "common")
    |> assign(:host_search_query, "")
    |> assign(:host_search_results, [])
    |> assign(:host_dropdown_open, false)
    |> assign(:filter_search, init_filter_search_state())
    |> assign(:filter_dropdown_open, nil)
    # Alias collision warnings
    |> assign(:alias_collisions, [])
    # Genus disambiguation modal state
    |> assign(:show_genus_disambiguation, false)
    |> assign(:possible_families, [])
    # Search state
    |> assign(:gall_search_query, "")
    |> assign(:gall_search_results, [])
    |> reset_dirty()
  end

  # Initialize state for a new gall (user typed new name)
  # If the genus is a placeholder (Unknown), redirect to the undescribed naming flow instead.
  defp init_new_gall_state(socket, name) do
    lookup_result = Gallformers.Taxonomy.lookup_taxonomy_for_new_species(name)

    genus_name = lookup_genus_name(lookup_result)

    if genus_name && Gallformers.Taxonomy.placeholder_genus_name?(genus_name) do
      redirect_to_undescribed_flow(socket, name)
    else
      init_new_gall_form(socket, name, lookup_result)
    end
  end

  defp lookup_genus_name({:ok, %{genus: genus}}), do: genus.name
  defp lookup_genus_name({:new_genus, %{genus: genus}}), do: genus.name
  defp lookup_genus_name({:ambiguous, genus_name, _}), do: genus_name
  defp lookup_genus_name(nil), do: nil

  defp redirect_to_undescribed_flow(socket, name) do
    description = TaxonName.parse(name).full_epithet || ""

    query = URI.encode_query(%{description: description})

    socket
    |> put_flash(:info, "Undescribed galls should be created through the guided naming flow.")
    |> push_navigate(to: "/admin/galls/undescribed?#{query}")
  end

  defp init_new_gall_form(socket, name, raw_taxonomy) do
    gall = %SpeciesSchema{taxoncode: "gall", name: name}

    # Handle genus disambiguation: filter to non-plant families only
    gall_family_ids = MapSet.new(socket.assigns.families, fn {_name, id} -> id end)

    %{
      taxonomy: taxonomy,
      genus_is_new: genus_is_new,
      family_id: selected_family_id,
      possible_families: possible_families
    } =
      Gallformers.Taxonomy.resolve_taxonomy_for_species(raw_taxonomy, gall_family_ids)

    socket
    |> build_default_assigns()
    |> assign(:mode, :new)
    |> assign(:page_title, "New Gall")
    |> assign(:gall, gall)
    |> assign(:form, to_form(Species.change_species(gall)))
    |> assign(:taxonomy, taxonomy)
    |> assign(:genus_is_new, genus_is_new)
    |> assign(:selected_family_id, selected_family_id)
    |> assign(:possible_families, possible_families)
    |> assign(:alias_collisions, Species.find_species_with_alias(name))
    |> apply_undescribed_lock(taxonomy)
    |> mark_dirty()
  end

  # Initialize state for a new undescribed gall from the undescribed naming flow.
  # Params: species_name, host_id, undescribed. Taxonomy is resolved from the name
  # by the backend (Taxonomy.resolve_taxonomy_from_name/1).
  defp init_undescribed_gall_state(socket, params) do
    name = params["species_name"]
    host_id = parse_int_param(params["host_id"])

    case Gallformers.Taxonomy.resolve_taxonomy_from_name(name) do
      {:ok, taxonomy} ->
        init_undescribed_gall_with_taxonomy(socket, name, taxonomy, host_id)

      {:error, reason} ->
        socket
        |> put_flash(:error, "Could not resolve taxonomy: #{reason}")
        |> push_navigate(to: ~p"/admin/galls/undescribed")
    end
  end

  defp init_undescribed_gall_with_taxonomy(socket, name, taxonomy, host_id) do
    gall = %SpeciesSchema{taxoncode: "gall", name: name}
    host = if host_id, do: Species.get_species(host_id)

    socket
    |> build_default_assigns()
    |> assign(:mode, :new)
    |> assign(:page_title, "New Undescribed Gall")
    |> assign(:from_undescribed_flow, true)
    |> assign(:gall, gall)
    |> assign(:form, to_form(Species.change_species(gall)))
    |> assign(:taxonomy, taxonomy)
    |> assign(:selected_family_id, taxonomy.family && taxonomy.family.id)
    |> assign(:undescribed, true)
    |> maybe_add_initial_host(host)
    |> apply_undescribed_lock(taxonomy)
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
          aliases = Species.get_aliases_for_species(species_id)
          hosts = Gallformers.GallHosts.get_hosts_for_gall(species_id)
          taxonomy = Gallformers.Taxonomy.get_taxonomy_for_species(species_id)
          filter_values = gall_data.filter_values
          detachable = gall_data.detachable || "unknown"
          undescribed = gall_data.undescribed || false

          socket
          |> build_default_assigns()
          |> assign(:mode, :edit)
          |> assign(:page_title, "Edit Gall - #{species.name}")
          |> assign(:gall, species)
          |> assign(:gall_data, gall_data)
          |> assign(:form, to_form(Species.change_species(species)))
          |> assign(:gall_id, gall_data.gall_id)
          # Deferred changes tracking (override defaults with loaded data)
          |> assign(DeferredChanges.init(:aliases, aliases))
          |> assign(DeferredChanges.init(:hosts, hosts))
          |> assign(:original_filter_values, filter_values)
          |> assign(:original_detachable, detachable)
          |> assign(:original_undescribed, undescribed)
          # Pending state (loaded from DB)
          |> assign(:taxonomy, taxonomy)
          |> assign(:selected_family_id, taxonomy && taxonomy.family && taxonomy.family.id)
          |> assign(:filter_values, filter_values)
          |> assign(:detachable, detachable)
          |> assign(:undescribed, undescribed)
          |> apply_undescribed_lock(taxonomy, species_id)
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
        Species.search_species_by_name(query, "gall", 10)
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
    if socket.assigns.genus_is_new && is_nil(socket.assigns.selected_family_id) do
      {:noreply, put_flash(socket, :error, "Please select a Family for the new genus")}
    else
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
  def handle_event("update_new_alias", params, socket),
    do: {:noreply, AliasHandlers.handle_update_new_alias(socket, params)}

  @impl true
  def handle_event("add_alias", _params, socket),
    do: {:noreply, AliasHandlers.handle_add_alias(socket)}

  @impl true
  def handle_event("remove_alias", %{"alias-id" => alias_id}, socket),
    do: {:noreply, AliasHandlers.handle_remove_alias(socket, alias_id)}

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
    if socket.assigns.undescribed_locked do
      {:noreply, put_flash(socket, :warning, socket.assigns.undescribed_lock_reason)}
    else
      new_value = !socket.assigns.undescribed
      {:noreply, socket |> assign(:undescribed, new_value) |> mark_dirty()}
    end
  end

  @impl true
  def handle_event("select_family", %{"family_id" => family_id}, socket) do
    family_id = if family_id == "", do: nil, else: String.to_integer(family_id)
    {:noreply, socket |> assign(:selected_family_id, family_id) |> mark_dirty()}
  end

  @impl true
  def handle_event("select_family_from_disambiguation", %{"family_id" => family_id_str}, socket) do
    case apply_family_disambiguation(socket, family_id_str) do
      {:ok, socket, _selected} ->
        {:noreply, mark_dirty(socket)}

      {:error, socket} ->
        {:noreply, socket}
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
  # Reclassify callbacks (from ReclassifyLive component)
  # =================================================================

  @impl true
  def handle_info({:reclassify_complete, result}, socket) do
    species_id = result.species.id
    taxonomy = Gallformers.Taxonomy.get_taxonomy_for_species(species_id)

    aliases =
      if result.add_alias? and result.name_changed?,
        do: Species.get_aliases_for_species(species_id),
        else: socket.assigns.aliases

    {:noreply,
     socket
     |> assign(:gall, result.species)
     |> assign(:aliases, aliases)
     |> assign(:taxonomy, taxonomy)
     |> assign(:selected_family_id, taxonomy && taxonomy.family && taxonomy.family.id)
     |> assign(:page_title, "Edit Gall - #{result.species.name}")
     |> apply_undescribed_lock(taxonomy, species_id)
     |> put_flash(:info, "Gall updated successfully")}
  end

  @impl true
  def handle_info({:reclassify_flash, level, message}, socket) do
    {:noreply, put_flash(socket, level, message)}
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

  # Applies the undescribed lock result from Galls.compute_undescribed_lock/2 to the socket.
  defp apply_undescribed_lock(socket, taxonomy, species_id \\ nil) do
    {locked?, reason} = Galls.compute_undescribed_lock(taxonomy, species_id)

    socket
    |> assign(:undescribed_locked, locked?)
    |> assign(:undescribed_lock_reason, reason)
    |> then(fn s -> if locked?, do: assign(s, :undescribed, true), else: s end)
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
    create_params = %{
      species_attrs: params,
      taxonomy: socket.assigns.taxonomy,
      genus_is_new: socket.assigns.genus_is_new,
      parent_id: socket.assigns.selected_family_id,
      hosts: socket.assigns.hosts,
      aliases: socket.assigns.aliases,
      filter_values: socket.assigns.filter_values,
      detachable: socket.assigns.detachable,
      undescribed: socket.assigns.undescribed
    }

    case Galls.create_gall_with_associations(create_params) do
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

    update_params = %{
      species_attrs: params,
      alias_changes: DeferredChanges.compute_changes(socket, :aliases),
      host_changes: DeferredChanges.compute_changes(socket, :hosts, id_field: :host_relation_id),
      original_filter_values: socket.assigns.original_filter_values,
      filter_values: socket.assigns.filter_values,
      detachable: socket.assigns.detachable,
      undescribed: socket.assigns.undescribed
    }

    case Galls.update_gall_with_associations(socket.assigns.gall, update_params) do
      {:ok, updated_gall} ->
        # Reload data from DB to get actual IDs for new records
        aliases = Species.get_aliases_for_species(species_id)
        hosts = Gallformers.GallHosts.get_hosts_for_gall(species_id)
        filter_values = Galls.get_gall_filter_values(gall_id)

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
            then map species to sources. <br />
            To add an undescribed gall, you must use the <.link
              navigate={~p"/admin/galls/undescribed"}
              class="text-gf-maroon hover:underline"
            >
              Undescribed Gall guided naming flow</.link>.
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
            <%= cond do %>
              <% @mode == :edit -> %>
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
                    phx-click="open_reclassify_modal"
                    phx-target="#reclassify"
                    class="px-3 py-2 text-sm bg-gray-200 hover:bg-gray-300 border border-gray-300 rounded whitespace-nowrap"
                  >
                    Rename/Reclassify
                  </button>
                </div>
              <% @from_undescribed_flow -> %>
                <%!-- Undescribed flow: read-only name with link back to naming flow --%>
                <label class="gf-label">Name (binomial):</label>
                <div class="flex gap-2">
                  <input
                    type="text"
                    value={@gall.name}
                    disabled
                    class="flex-1 px-3 py-2 bg-gray-100 border border-gray-300 rounded text-gray-700 text-sm italic"
                  />
                  <.link
                    navigate={~p"/admin/galls/undescribed"}
                    class="px-3 py-2 text-sm bg-gray-200 hover:bg-gray-300 border border-gray-300 rounded whitespace-nowrap"
                  >
                    Edit Name
                  </.link>
                </div>
              <% true -> %>
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

          <.alias_collision_warning collisions={@alias_collisions} />

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
              <.taxonomy_genus_family_row
                taxonomy={@taxonomy}
                genus_is_new={@genus_is_new}
                selected_family_id={@selected_family_id}
                families={@families}
                new_genus_hint="selected family"
                family_required_always={true}
              />

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

                <div>
                  <label class={[
                    "flex items-center gap-2",
                    if(@undescribed_locked, do: "cursor-not-allowed", else: "cursor-pointer")
                  ]}>
                    <input
                      type="checkbox"
                      name="undescribed"
                      value="true"
                      checked={@undescribed}
                      phx-change="toggle_undescribed"
                      disabled={@undescribed_locked}
                      class="rounded border-gray-300 text-gf-maroon focus:ring-gf-maroon disabled:opacity-50"
                    />
                    <span class="text-sm text-gray-700">Undescribed?</span>
                  </label>
                  <p :if={@undescribed_lock_reason} class="text-amber-600 text-xs mt-1 ml-6">
                    {@undescribed_lock_reason}
                  </p>
                </div>
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

        <.live_component
          module={GallformersWeb.Admin.ReclassifyLive}
          id="reclassify"
          species_id={@gall && @gall.id}
          species_name={@gall && @gall.name}
          current_family={@taxonomy && @taxonomy.family}
          current_genus={@taxonomy && @taxonomy.genus}
          entity_type="Gall"
          is_gall={true}
          undescribed={@undescribed}
        />

        <%!-- Genus disambiguation modal --%>
        <.genus_disambiguation_modal
          possible_families={@possible_families}
          taxonomy={@taxonomy}
          entity_description="gall-forming"
          select_event="select_family_from_disambiguation"
          clear_event="clear_gall"
        />
      </div>
    </Layouts.admin>
    """
  end
end
