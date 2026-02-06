defmodule GallformersWeb.Admin.HostLive.Form do
  @moduledoc """
  Admin form for creating and editing host species.
  Layout mirrors V1 host admin for consistency.
  """
  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers

  alias Gallformers.Places
  alias Gallformers.Plants
  alias Gallformers.Ranges
  alias Gallformers.Repo
  alias Gallformers.Species
  alias Gallformers.Species.Species, as: SpeciesSchema
  alias Gallformers.Taxonomy
  alias GallformersWeb.Admin.DeferredChanges

  import GallformersWeb.Admin.FormComponents, only: [alias_editor: 1, form_actions: 1]

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]
    abundances = Species.list_abundances()
    all_places = Places.list_places()
    families = Taxonomy.list_plant_families_for_select()

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Host")
      |> assign(:abundances, abundances)
      |> assign(:all_places, all_places)
      |> assign(:families, families)
      |> init_form_state()

    {:ok, socket}
  end

  def close_form(socket) do
    push_navigate(socket, to: ~p"/admin/hosts")
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    # New host - start in search mode so user can enter a name
    socket
    |> assign(:page_title, "Add Host")
    |> assign(:mode, :search)
    |> assign(:host, nil)
    |> assign(:form, nil)
    # Deferred changes tracking
    |> assign(DeferredChanges.init(:aliases, []))
    |> assign(:original_places, [])
    |> assign(:places, [])
    |> assign(:taxonomy, nil)
    |> assign(:genus_is_new, false)
    |> assign(:selected_family_id, nil)
    |> assign(:selected_section_id, nil)
    |> assign(:sections_for_family, [])
    |> assign(:new_alias_name, "")
    |> assign(:new_alias_type, "common")
    # Rename modal state
    |> assign(:show_rename_modal, false)
    |> assign(:rename_value, "")
    |> assign(:add_alias_on_rename, false)
    # Genus confirmation modal state
    |> assign(:show_genus_confirm, false)
    |> assign(:pending_genus_info, nil)
    # Genus disambiguation modal state
    |> assign(:show_genus_disambiguation, false)
    |> assign(:possible_families, [])
    # Typeahead search state
    |> assign(:host_search_query, "")
    |> assign(:host_search_results, [])
    |> reset_dirty()
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    host_id = String.to_integer(id)

    case Plants.get_host_species(host_id) do
      nil ->
        socket
        |> put_flash(:error, "Host not found")
        |> push_navigate(to: ~p"/admin/hosts")

      host ->
        if host.taxoncode != "plant" do
          socket
          |> put_flash(:error, "This is not a host. Use the Gall admin for gall species.")
          |> push_navigate(to: ~p"/admin/hosts")
        else
          load_host_for_edit(socket, host)
        end
    end
  end

  defp load_host_for_edit(socket, host) do
    host_id = host.id
    changeset = Plants.change_host(host)
    aliases = Plants.get_aliases_for_host_full(host_id)
    places = Ranges.get_places_for_host(host_id)
    taxonomy = Taxonomy.get_taxonomy_for_species(host_id)

    # Load sections for the host's genus (if genus exists)
    genus_id = taxonomy && taxonomy.genus_id
    family_id = taxonomy && taxonomy.family_id
    sections_for_family = if genus_id, do: Taxonomy.list_sections_for_genus(genus_id), else: []

    socket
    |> assign(:page_title, "Edit Host - #{host.name}")
    |> assign(:host, host)
    |> assign(:form, to_form(changeset))
    |> assign(:mode, :edit)
    # Deferred changes tracking
    |> assign(DeferredChanges.init(:aliases, aliases))
    |> assign(:original_places, places)
    |> assign(:places, places)
    |> assign(:taxonomy, taxonomy)
    |> assign(:genus_is_new, false)
    |> assign(:selected_family_id, family_id)
    |> assign(:selected_section_id, taxonomy && taxonomy.section_id)
    |> assign(:sections_for_family, sections_for_family)
    |> assign(:new_alias_name, "")
    |> assign(:new_alias_type, "common")
    # Rename modal state
    |> assign(:show_rename_modal, false)
    |> assign(:rename_value, host.name)
    |> assign(:add_alias_on_rename, false)
    # Genus confirmation modal state
    |> assign(:show_genus_confirm, false)
    |> assign(:pending_genus_info, nil)
    # Genus disambiguation modal state
    |> assign(:show_genus_disambiguation, false)
    |> assign(:possible_families, [])
    # Typeahead state (cleared in edit mode)
    |> assign(:host_search_query, "")
    |> assign(:host_search_results, [])
    |> reset_dirty()
  end

  # Updates the genus's section if it changed
  defp maybe_update_section(socket) do
    taxonomy = socket.assigns.taxonomy
    selected_section_id = socket.assigns.selected_section_id
    original_section_id = taxonomy && taxonomy.section_id

    # Only update if section changed and genus exists
    if taxonomy && taxonomy.genus_id && selected_section_id != original_section_id do
      # New parent is either the section or the family (if section cleared)
      new_parent_id = selected_section_id || taxonomy.family_id

      if new_parent_id do
        Taxonomy.update_genus_parent(taxonomy.genus_id, new_parent_id)
      end
    end
  end

  # Event handlers

  @impl true
  def handle_event("validate", %{"species" => params}, socket) do
    changeset =
      socket.assigns.host
      |> Plants.change_host(params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form, to_form(changeset)) |> mark_dirty()}
  end

  # Catch-all for validate events that don't match the expected form structure
  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"species" => params}, socket) do
    # Validate that family is selected when genus is new
    if socket.assigns.genus_is_new && is_nil(socket.assigns.selected_family_id) do
      {:noreply, put_flash(socket, :error, "Please select a Family for the new genus")}
    else
      # Name is captured via typeahead (outside the form), so add it from socket assigns
      params =
        params
        |> Map.put("taxoncode", "plant")
        |> Map.put("name", socket.assigns.host.name)

      save_host(socket, socket.assigns.mode, params)
    end
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(request_cancel cancel_discard confirm_discard) do
    handle_form_event(event, params, socket)
  end

  # =================================================================
  # Event handlers - Host search/select/create (typeahead)
  # =================================================================

  @impl true
  def handle_event("search_host", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Species.search_species(query, 10)
        |> Enum.filter(&(&1.taxoncode == "plant"))
      else
        []
      end

    {:noreply,
     socket
     |> assign(:host_search_query, query)
     |> assign(:host_search_results, results)}
  end

  @impl true
  def handle_event("select_host", %{"id" => id}, socket) do
    species_id = String.to_integer(id)
    # Navigate to the edit URL so the URL reflects the selected host
    {:noreply, push_patch(socket, to: ~p"/admin/hosts/#{species_id}")}
  end

  @impl true
  def handle_event("create_host", %{"name" => name}, socket) do
    # User wants to create a new host with this name
    {:noreply, init_new_host_state(socket, name)}
  end

  @impl true
  def handle_event("clear_host", _params, socket) do
    # Clear selection and return to search mode
    {:noreply, close_form(socket)}
  end

  @impl true
  def handle_event("select_family", %{"family_id" => family_id}, socket) do
    family_id = if family_id == "", do: nil, else: String.to_integer(family_id)

    # Load sections for the selected family
    sections_for_family =
      if family_id do
        Taxonomy.list_sections_for_family(family_id)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:selected_family_id, family_id)
     |> assign(:selected_section_id, nil)
     |> assign(:sections_for_family, sections_for_family)
     |> mark_dirty()}
  end

  @impl true
  def handle_event("select_section", %{"section_id" => section_id}, socket) do
    section_id = if section_id == "", do: nil, else: String.to_integer(section_id)
    {:noreply, socket |> assign(:selected_section_id, section_id) |> mark_dirty()}
  end

  @impl true
  def handle_event("select_family_from_disambiguation", %{"family_id" => family_id_str}, socket) do
    family_id = String.to_integer(family_id_str)
    possible_families = socket.assigns.possible_families

    # Find the selected family from the possible families list
    selected = Enum.find(possible_families, &(&1.family_id == family_id))

    if selected do
      # Load sections for this specific genus
      sections_for_family = Taxonomy.list_sections_for_genus(selected.genus_id)

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
       |> assign(:selected_section_id, selected.section_id)
       |> assign(:sections_for_family, sections_for_family)
       |> assign(:possible_families, [])
       |> assign(:show_genus_disambiguation, false)
       |> mark_dirty()}
    else
      {:noreply, put_flash(socket, :error, "Family not found")}
    end
  end

  # Alias events

  @impl true
  def handle_event("update_new_alias", %{"value" => name, "type" => type}, socket) do
    # Name field changed (from phx-keyup on text input)
    {:noreply, assign(socket, new_alias_name: name, new_alias_type: type)}
  end

  @impl true
  def handle_event("update_new_alias", %{"value" => type, "name" => name}, socket) do
    # Type field changed (from phx-change on select)
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

  # Range/Place events

  @impl true
  def handle_event("toggle_region", %{"code" => code}, socket) do
    {:noreply, toggle_region(socket, code)}
  end

  @impl true
  def handle_event("select_all_places", _params, socket) do
    if socket.assigns.mode == :edit do
      # Select all in local state - don't save to DB yet
      all_codes = Enum.map(socket.assigns.all_places, & &1.code)
      {:noreply, socket |> assign(:places, all_codes) |> mark_dirty()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("deselect_all_places", _params, socket) do
    if socket.assigns.mode == :edit do
      # Deselect all in local state - don't save to DB yet
      {:noreply, socket |> assign(:places, []) |> mark_dirty()}
    else
      {:noreply, socket}
    end
  end

  # Rename modal events

  @impl true
  def handle_event("open_rename_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_rename_modal, true)
     |> assign(:rename_value, socket.assigns.host.name)
     |> assign(:add_alias_on_rename, false)}
  end

  @impl true
  def handle_event("close_rename_modal", _params, socket) do
    {:noreply, assign(socket, :show_rename_modal, false)}
  end

  @impl true
  def handle_event("request_close_rename", _params, socket) do
    if socket.assigns.rename_value == socket.assigns.host.name do
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
  def handle_event("delete", _params, socket) do
    case Plants.delete_host(socket.assigns.host.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Host deleted successfully")
         |> push_navigate(to: ~p"/admin/hosts")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete host")}
    end
  end

  @impl true
  def handle_event("do_rename", _params, socket) do
    new_name = String.trim(socket.assigns.rename_value)
    old_name = socket.assigns.host.name

    cond do
      new_name == "" ->
        {:noreply, put_flash(socket, :error, "Name cannot be empty")}

      new_name == old_name ->
        {:noreply, assign(socket, :show_rename_modal, false)}

      not valid_species_name?(new_name) ->
        {:noreply, put_flash(socket, :error, "Name must be a valid species name (Genus species)")}

      true ->
        case Plants.rename_host(
               socket.assigns.host.id,
               new_name,
               socket.assigns.add_alias_on_rename
             ) do
          {:ok, updated_host} ->
            {:noreply, handle_rename_success(socket, updated_host, new_name)}

          {:needs_genus_confirmation, info} ->
            # Genus change requires user confirmation to create new genus
            {:noreply,
             socket
             |> assign(:show_rename_modal, false)
             |> assign(:show_genus_confirm, true)
             |> assign(:pending_genus_info, info)}

          {:error, :name_exists} ->
            {:noreply, put_flash(socket, :error, "That name is already in use")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to rename host")}
        end
    end
  end

  # Genus confirmation modal events

  @impl true
  def handle_event("cancel_genus_confirm", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_genus_confirm, false)
     |> assign(:pending_genus_info, nil)}
  end

  @impl true
  def handle_event("confirm_genus_creation", _params, socket) do
    info = socket.assigns.pending_genus_info

    case Plants.rename_host_with_new_genus(
           info.host_id,
           info.new_name,
           info.new_genus,
           info.family_id,
           info.add_alias
         ) do
      {:ok, updated_host} ->
        {:noreply,
         socket
         |> assign(:show_genus_confirm, false)
         |> assign(:pending_genus_info, nil)
         |> handle_rename_success(updated_host, info.new_name)
         |> put_flash(:info, "Host renamed and new genus \"#{info.new_genus}\" created")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:show_genus_confirm, false)
         |> assign(:pending_genus_info, nil)
         |> put_flash(:error, "Failed to create genus: #{inspect(reason)}")}
    end
  end

  # Helper functions for handle_event

  defp handle_rename_success(socket, updated_host, new_name) do
    # Reload aliases if we added one
    aliases =
      if socket.assigns.add_alias_on_rename do
        Plants.get_aliases_for_host_full(socket.assigns.host.id)
      else
        socket.assigns.aliases
      end

    # Reload taxonomy since genus may have changed
    taxonomy = Taxonomy.get_taxonomy_for_species(updated_host.id)

    socket
    |> assign(:host, updated_host)
    |> assign(:aliases, aliases)
    |> assign(:taxonomy, taxonomy)
    |> assign(:show_rename_modal, false)
    |> assign(:page_title, "Edit Host - #{new_name}")
    |> put_flash(:info, "Host renamed successfully")
  end

  defp toggle_region(%{assigns: %{mode: mode}} = socket, _code) when mode != :edit, do: socket

  defp toggle_region(socket, code) do
    place = Enum.find(socket.assigns.all_places, &(&1.code == code))

    if place do
      new_places = toggle_place_code(socket.assigns.places, code)
      socket |> assign(:places, new_places) |> mark_dirty()
    else
      socket
    end
  end

  defp toggle_place_code(places, code) do
    if code in places, do: Enum.reject(places, &(&1 == code)), else: places ++ [code]
  end

  # Initialize state for a new host (user typed new name in typeahead)
  defp init_new_host_state(socket, name) do
    host = %SpeciesSchema{taxoncode: "plant", name: name}
    changeset = Plants.change_host(host)
    # Look up taxonomy from the genus name - this always returns a result
    # with genus_is_new: true/false to indicate if genus needs to be created
    raw_taxonomy = Taxonomy.lookup_taxonomy_for_new_species(name)

    # Handle genus disambiguation: filter to plant families only
    {taxonomy, genus_is_new, selected_family_id, selected_section_id, possible_families} =
      resolve_taxonomy_for_host(raw_taxonomy, socket.assigns.families)

    # Load sections only for existing genus
    # Sections are specific to a genus, so new genera have no sections
    sections_for_family =
      if !genus_is_new && taxonomy && taxonomy.genus_id do
        Taxonomy.list_sections_for_genus(taxonomy.genus_id)
      else
        []
      end

    socket
    |> assign(:mode, :new)
    |> assign(:page_title, "New Host")
    |> assign(:host, host)
    |> assign(:form, to_form(changeset))
    # Deferred changes tracking
    |> assign(DeferredChanges.init(:aliases, []))
    |> assign(:original_places, [])
    |> assign(:places, [])
    |> assign(:taxonomy, taxonomy)
    |> assign(:genus_is_new, genus_is_new)
    |> assign(:selected_family_id, selected_family_id)
    |> assign(:selected_section_id, selected_section_id)
    |> assign(:sections_for_family, sections_for_family)
    |> assign(:possible_families, possible_families)
    |> assign(:new_alias_name, "")
    |> assign(:new_alias_type, "common")
    # Rename modal state
    |> assign(:show_rename_modal, false)
    |> assign(:rename_value, "")
    |> assign(:add_alias_on_rename, false)
    # Genus disambiguation modal state
    |> assign(:show_genus_disambiguation, false)
    # Clear search state
    |> assign(:host_search_query, "")
    |> assign(:host_search_results, [])
    # Mark form dirty since user entered a name (enables save button)
    |> reset_dirty()
    |> mark_dirty()
  end

  # Resolve taxonomy for hosts: filter to plant families only
  defp resolve_taxonomy_for_host(nil, _families), do: {nil, false, nil, nil, []}

  defp resolve_taxonomy_for_host(taxonomy, families) do
    plant_family_ids = MapSet.new(families, fn {_name, id} -> id end)

    cond do
      # Genus is new - user must select a plant family
      Map.get(taxonomy, :genus_is_new) ->
        {taxonomy, true, nil, nil, []}

      # Genus exists in multiple families - filter to plant families
      Map.get(taxonomy, :requires_disambiguation) ->
        plant_families =
          Enum.filter(taxonomy.possible_families, fn family ->
            MapSet.member?(plant_family_ids, family.family_id)
          end)

        case plant_families do
          [] ->
            # No plant families found - treat as new genus
            {%{genus: taxonomy.genus, genus_id: nil, genus_is_new: true}, true, nil, nil, []}

          [single] ->
            # Only one plant family - auto-select it
            resolved = %{
              genus: taxonomy.genus,
              genus_id: single.genus_id,
              genus_is_new: false,
              section: single.section,
              section_id: single.section_id,
              family: single.family,
              family_id: single.family_id
            }

            {resolved, false, single.family_id, single.section_id, []}

          multiple ->
            # Multiple plant families - needs disambiguation
            {taxonomy, false, nil, nil, multiple}
        end

      # Genus exists in exactly one family - check if it's a plant family
      true ->
        if MapSet.member?(plant_family_ids, taxonomy.family_id) do
          # It's a plant family - use it
          {taxonomy, false, taxonomy.family_id, taxonomy.section_id, []}
        else
          # It's NOT a plant family - treat as new genus
          {%{genus: taxonomy.genus, genus_id: nil, genus_is_new: true}, true, nil, nil, []}
        end
    end
  end

  defp save_host(socket, :new, params) do
    aliases_to_add = socket.assigns.aliases
    taxonomy = socket.assigns.taxonomy
    genus_is_new = socket.assigns.genus_is_new
    selected_family_id = socket.assigns.selected_family_id
    selected_section_id = socket.assigns.selected_section_id

    # Use section as parent if selected, otherwise family
    parent_id = selected_section_id || selected_family_id

    transaction_result =
      Repo.transaction(fn ->
        case Plants.create_host(params) do
          {:ok, host} ->
            # Handle taxonomy: create genus if new, or link to existing
            Taxonomy.link_species_taxonomy(host.id, taxonomy, genus_is_new, parent_id)

            # Add any aliases entered before save
            for a <- aliases_to_add do
              Plants.create_alias_for_host(host.id, %{name: a.name, type: a.type})
            end

            host

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    case transaction_result do
      {:ok, host} ->
        # Redirect to edit mode for the new host so user can add range/aliases
        {:noreply,
         socket
         |> put_flash(:info, "Host created successfully")
         |> push_navigate(to: ~p"/admin/hosts/#{host.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create host. Please try again.")}
    end
  end

  defp save_host(socket, :edit, params) do
    host_id = socket.assigns.host.id

    # Compute changes using DeferredChanges
    {aliases_to_add, aliases_to_remove} = DeferredChanges.compute_changes(socket, :aliases)

    # Wrap all saves in a transaction for atomicity
    transaction_result =
      Repo.transaction(fn ->
        case Plants.update_host(socket.assigns.host, params) do
          {:ok, updated_host} ->
            # Save aliases
            save_alias_changes(host_id, aliases_to_add, aliases_to_remove)

            # Save places - diff original vs current
            save_place_changes(
              host_id,
              socket.assigns.original_places,
              socket.assigns.places,
              socket.assigns.all_places
            )

            # Update section if it changed
            maybe_update_section(socket)

            updated_host

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    case transaction_result do
      {:ok, updated_host} ->
        # Reload data from DB to get actual IDs for new records
        aliases = Plants.get_aliases_for_host_full(host_id)
        places = Ranges.get_places_for_host(host_id)

        # Stay on page, update state to reflect saved data
        {:noreply,
         socket
         |> assign(:host, updated_host)
         |> DeferredChanges.refresh(:aliases, aliases)
         |> assign(:original_places, places)
         |> assign(:places, places)
         |> reset_dirty()
         |> put_flash(:info, "Host saved successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save host. Please try again.")}
    end
  end

  # Helper to save alias changes
  defp save_alias_changes(host_id, to_add, to_remove) do
    # Delete removed aliases
    for alias_id <- to_remove do
      Plants.remove_alias_from_host(host_id, alias_id)
    end

    # Add new aliases
    for alias <- to_add do
      Plants.create_alias_for_host(host_id, %{name: alias.name, type: alias.type})
    end
  end

  # Helper to save place changes
  defp save_place_changes(host_id, original_places, current_places, all_places) do
    # Convert to place_ids
    place_code_to_id = Map.new(all_places, &{&1.code, &1.id})

    original_set = MapSet.new(original_places)
    current_set = MapSet.new(current_places)

    # Only update if there are changes
    if original_set != current_set do
      place_ids =
        Enum.map(current_places, &Map.get(place_code_to_id, &1)) |> Enum.reject(&is_nil/1)

      Ranges.update_host_places(host_id, place_ids)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_user={@current_user}
      page_title={@page_title}
      public_url={if @mode == :edit, do: ~p"/host/#{@host.id}"}
    >
      <Layouts.admin_edit_layout
        back_path={~p"/admin/hosts"}
        back_label="Back to Hosts"
        title={if @mode == :new, do: "Add New Host", else: "Edit Host"}
      >
        <:intro>
          This is for all of the details about a Host. To add a description (which must be referenced to a source) go add <.link
            navigate={~p"/admin/sources"}
            class="hover:underline"
          >Sources</.link>,
          if they do not already exist, then map species to sources with description.
          If you want to assign a
          <.link navigate={~p"/admin/taxonomy"} class="hover:underline">Family</.link>
          or Section then you will need to have created them first if they do not exist.
        </:intro>

        <:quick_links :if={@mode == :edit}>
          <.link
            navigate={~p"/admin/images?species_id=#{@host.id}"}
            class="text-sm hover:underline mr-4"
          >
            Manage Images
          </.link>
          <.link
            navigate={~p"/admin/species-sources/find?species_id=#{@host.id}"}
            class="text-sm hover:underline"
          >
            Species-Source Mappings
          </.link>
        </:quick_links>

        <%!-- Name field with typeahead for search/create --%>
        <div class="mb-3">
          <%= if @mode == :edit do %>
            <%!-- Edit mode: show selected name with rename button --%>
            <label class="gf-label">
              Name (binomial):
              <.info_tip position="right">
                <p class="mb-2">
                  Names must be in binomial form: <mark>Genus species</mark>
                </p>
                <p class="mb-2">
                  Indicate hybrids with 'x' between genus and species, e.g.,
                  <mark>Quercus x leana</mark>
                </p>
                <p>
                  Both genus and species can contain dashes.
                </p>
              </.info_tip>
            </label>
            <div class="flex gap-2">
              <input
                type="text"
                value={@host.name}
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
              id="host-picker"
              label="Name (binomial):"
              placeholder="Search existing hosts or type new name..."
              search_event="search_host"
              select_event="select_host"
              clear_event="clear_host"
              create_event="create_host"
              allow_new={true}
              query={@host_search_query}
              results={@host_search_results}
              selected={@host}
              display_fn={fn host -> host.name end}
            >
              <:label_suffix>
                <.info_tip position="right">
                  <p class="mb-2">
                    Names must be in binomial form: <mark>Genus species</mark>
                  </p>
                  <p class="mb-2">
                    Indicate hybrids with 'x' between genus and species, e.g.,
                    <mark>Quercus x leana</mark>
                  </p>
                  <p>
                    Both genus and species can contain dashes.
                  </p>
                </.info_tip>
              </:label_suffix>
            </.typeahead>
            <p :if={@mode == :search} class="text-gray-500 text-xs mt-1">
              Type to search existing hosts, or enter a new name to create one.
            </p>
          <% end %>
        </div>

        <%!-- Rest of form - disabled until host selected/created --%>
        <fieldset disabled={@mode == :search} class={[@mode == :search && "opacity-50"]}>
          <.form :if={@form} for={@form} id="host-form" phx-change="validate" phx-submit="save">
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
                  class="w-full px-3 py-2 bg-gray-100 border border-gray-300 rounded text-gray-500 text-sm italic"
                />
                <p :if={@genus_is_new} class="text-amber-600 text-xs mt-1">
                  New genus - will be created under selected section/family
                </p>
              </div>
              <div>
                <label class="gf-label">
                  Family:<span :if={@genus_is_new} class="text-red-600 ml-0.5">*</span>
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

            <%!-- Row: Section | Abundance --%>
            <div class="grid grid-cols-2 gap-4 mb-3">
              <div>
                <label class="gf-label">Section:</label>
                <%= if @sections_for_family != [] do %>
                  <select
                    name="section_id"
                    phx-change="select_section"
                    class="w-full px-3 py-2 border border-gray-300 rounded text-sm"
                  >
                    <option value="">-- No Section --</option>
                    <%= for {name, id} <- @sections_for_family do %>
                      <option value={id} selected={@selected_section_id == id}>{name}</option>
                    <% end %>
                  </select>
                <% else %>
                  <input
                    type="text"
                    value=""
                    disabled
                    placeholder="No sections for this family"
                    class="w-full px-3 py-2 bg-gray-100 border border-gray-300 rounded text-gray-500 text-sm"
                  />
                <% end %>
              </div>
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

            <%!-- Range Map Section --%>
            <div class="mb-3 border border-gray-300 rounded">
              <div class="grid grid-cols-6 gap-2 p-3">
                <%!-- Legend --%>
                <div class="col-span-1">
                  <div class="text-sm font-medium text-gray-700 mb-2">Legend:</div>
                  <div class="space-y-1">
                    <div class="flex items-center gap-2">
                      <div class="w-4 h-4 rounded bg-green-700"></div>
                      <span class="text-xs text-gray-600">In Range</span>
                    </div>
                    <div class="flex items-center gap-2">
                      <div class="w-4 h-4 rounded border border-gray-300 bg-white"></div>
                      <span class="text-xs text-gray-600">Out of Range</span>
                    </div>
                  </div>
                  <div class="text-sm font-medium text-gray-700 mt-4 mb-2">Map Actions:</div>
                  <div class="space-y-2">
                    <button
                      type="button"
                      phx-click="select_all_places"
                      class="block w-full px-2 py-1 text-xs bg-gray-100 hover:bg-gray-200 border border-gray-300 rounded"
                      disabled={@mode == :new}
                    >
                      Select All
                    </button>
                    <button
                      type="button"
                      phx-click="deselect_all_places"
                      class="block w-full px-2 py-1 text-xs bg-gray-100 hover:bg-gray-200 border border-gray-300 rounded"
                      disabled={@mode == :new}
                    >
                      De-select All
                    </button>
                  </div>
                </div>
                <%!-- Map --%>
                <div class="col-span-5">
                  <label class="gf-label">Range:</label>
                  <%= if @mode == :edit do %>
                    <.range_map
                      id="host-range-map"
                      in_range={@places}
                      excluded_range={[]}
                      editable
                      class="border border-gray-300 rounded bg-gray-50 min-h-[300px]"
                    />
                  <% else %>
                    <div class="border border-gray-300 rounded bg-gray-100 min-h-[200px] flex items-center justify-center">
                      <p class="text-gray-500 text-sm">Save host first to edit range</p>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>

            <%!-- Aliases Table --%>
            <.alias_editor
              aliases={@aliases}
              new_alias_name={@new_alias_name}
              new_alias_type={@new_alias_type}
            />

            <%!-- Data Complete checkbox --%>
            <div class="space-y-2 mb-4">
              <.input
                type="checkbox"
                field={@form[:datacomplete]}
                label="All galls known to occur on this plant have been added to the database, and can be filtered by Location and Detachable. However, sources and images for galls associated with this host may be incomplete or absent, and other filters may not have been entered comprehensively or at all."
              />
            </div>

            <%!-- Action buttons --%>
            <div class="flex justify-between pt-3 border-t border-gray-200">
              <div>
                <button
                  :if={@mode == :edit}
                  type="button"
                  phx-click="delete"
                  data-confirm="Are you sure you want to delete this host? This will remove all associated gall mappings and range data."
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
            inserted_at={@host.inserted_at}
            updated_at={@host.updated_at}
          />
        </fieldset>

        <%!-- Placeholder when no host selected --%>
        <div :if={@mode == :search} class="text-center py-8 text-gray-500">
          <.icon name="ph-magnifying-glass" class="h-12 w-12 mx-auto mb-3 text-gray-300" />
          <p>Select an existing host or create a new one to edit details.</p>
        </div>

        <.discard_confirm_modal show={@show_discard_confirm} />
      </Layouts.admin_edit_layout>

      <.rename_modal
        show={@show_rename_modal}
        value={@rename_value}
        add_alias_checked={@add_alias_on_rename}
        entity_type="Host"
      />

      <%!-- Genus disambiguation modal --%>
      <.modal
        :if={@possible_families != [] && @taxonomy}
        id="genus-disambiguation-modal"
        show
        on_cancel={JS.push("clear_host")}
      >
        <:header>Select Family for Genus "{Map.get(@taxonomy, :genus, "")}"</:header>
        <:body>
          <p class="text-gray-700 mb-4">
            The genus <strong>{Map.get(@taxonomy, :genus, "")}</strong>
            exists in multiple plant families. Please select which family this host belongs to:
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
            phx-click="clear_host"
            class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
          >
            Cancel
          </button>
        </:footer>
      </.modal>

      <%!-- Genus confirmation modal --%>
      <.modal
        :if={@show_genus_confirm}
        id="genus-confirm-modal"
        show
        on_cancel={JS.push("cancel_genus_confirm")}
      >
        <:header>Create New Genus?</:header>
        <:body>
          <p class="text-gray-700 mb-4">
            Renaming to
            <em class="font-medium">{@pending_genus_info && @pending_genus_info.new_name}</em>
            will create a new genus
            <strong>{@pending_genus_info && @pending_genus_info.new_genus}</strong>
            under the family <strong>{@pending_genus_info && @pending_genus_info.family_name}</strong>.
          </p>
          <p class="text-gray-600 text-sm">
            This will create a new genus entry in the taxonomy. Are you sure you want to continue?
          </p>
        </:body>
        <:footer>
          <button
            type="button"
            phx-click="cancel_genus_confirm"
            class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click="confirm_genus_creation"
            class="px-4 py-2 text-sm font-medium text-white bg-gf-maroon border border-transparent rounded-md hover:bg-gf-maroon/90"
          >
            Create Genus & Rename
          </button>
        </:footer>
      </.modal>
    </Layouts.admin>
    """
  end
end
