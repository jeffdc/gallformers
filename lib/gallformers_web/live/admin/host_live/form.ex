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
  alias Gallformers.Species
  alias Gallformers.Species.Species, as: SpeciesSchema
  alias Gallformers.Taxonomy
  alias GallformersWeb.Admin.AliasHandlers
  alias GallformersWeb.Admin.CountryDrillDown
  alias GallformersWeb.Admin.DeferredChanges

  import GallformersWeb.Admin.FormComponents,
    only: [alias_collision_warning: 1, alias_editor: 1, form_actions: 1]

  import GallformersWeb.Admin.ReclassifyHelpers

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    if connected?(socket), do: Species.subscribe()

    abundances = Species.list_abundances()
    all_places = Places.list_all_places()
    families = Taxonomy.list_families_for_select(:plant)

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
    socket
    |> build_default_assigns()
    |> assign(:page_title, "Add Host")
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
    aliases = Plants.get_aliases_for_host_full(host_id)
    place_entries = Ranges.get_places_for_host_with_precision(host_id)

    exact_places =
      place_entries |> Enum.filter(&(&1.precision == "exact")) |> Enum.map(& &1.code)

    country_places =
      place_entries |> Enum.filter(&(&1.precision == "country")) |> Enum.map(& &1.code)

    taxonomy = Taxonomy.get_taxonomy_for_species(host_id)

    socket
    |> build_default_assigns()
    |> assign(:mode, :edit)
    |> assign(:page_title, "Edit Host - #{host.name}")
    |> assign(:host, host)
    |> assign(:form, to_form(Plants.change_host(host)))
    |> assign(:host_traits, Plants.get_host_traits(host_id))
    # Deferred changes tracking (override defaults with loaded data)
    |> assign(DeferredChanges.init(:aliases, aliases))
    |> assign(:original_exact_places, exact_places)
    |> assign(:original_country_places, country_places)
    |> assign(:exact_places, exact_places)
    |> assign(:country_places, country_places)
    |> compute_map_range()
    |> assign_taxonomy_fields(taxonomy)
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
        Species.search_species_by_name(query, "plant", 10)
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

  # =================================================================
  # Event handlers - WCVP search/select (typeahead)
  # =================================================================

  @impl true
  def handle_event("search_wcvp", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 3 do
        Gallformers.Wcvp.Lookup.search(query, limit: 10)
        |> Enum.map(fn r -> Map.put(r, :id, r.plant_name_id) end)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:wcvp_search_query, query)
     |> assign(:wcvp_search_results, results)}
  end

  @impl true
  def handle_event("select_wcvp", %{"id" => plant_name_id}, socket) do
    case Gallformers.Wcvp.Lookup.get(plant_name_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "WCVP species not found")}

      wcvp_data ->
        {:noreply,
         socket
         |> assign(:wcvp_selected, wcvp_data)
         |> assign(:wcvp_search_results, [])
         |> init_new_host_from_wcvp(wcvp_data)}
    end
  end

  @impl true
  def handle_event("clear_wcvp", _params, socket) do
    {:noreply,
     socket
     |> assign(:wcvp_selected, nil)
     |> assign(:wcvp_search_query, "")
     |> assign(:wcvp_search_results, [])}
  end

  # =================================================================
  # Event handlers - WCVP refresh (edit mode)
  # =================================================================

  @impl true
  def handle_event("refresh_from_wcvp", _params, socket) do
    host_traits = socket.assigns[:host_traits]
    host = socket.assigns.host

    # Look up by wcvp_id if available, otherwise by name
    wcvp_data =
      cond do
        host_traits && host_traits.wcvp_id not in [nil, ""] ->
          Gallformers.Wcvp.Lookup.get(host_traits.wcvp_id)

        true ->
          case Gallformers.Wcvp.Lookup.search(host.name, limit: 1) do
            [match] -> Gallformers.Wcvp.Lookup.get(match.plant_name_id)
            [] -> nil
          end
      end

    case wcvp_data do
      nil ->
        {:noreply, put_flash(socket, :error, "No matching species found in WCVP")}

      data ->
        diff = build_wcvp_diff(socket, data)
        {:noreply, assign(socket, :wcvp_diff, diff)}
    end
  end

  @impl true
  def handle_event("apply_wcvp_updates", _params, socket) do
    diff = socket.assigns.wcvp_diff

    with {:ok, _} <- apply_wcvp_range_updates(socket, diff),
         {:ok, _} <-
           Plants.upsert_host_traits(socket.assigns.host.id, %{
             wcvp_id: diff.wcvp_data.plant_name_id,
             powo_id: diff.wcvp_data.powo_id
           }) do
      {:noreply,
       socket
       |> assign(:wcvp_diff, nil)
       |> put_flash(:info, "Host updated from WCVP")
       |> push_navigate(to: ~p"/admin/hosts/#{socket.assigns.host.id}")}
    else
      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to apply WCVP updates: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("cancel_wcvp_refresh", _params, socket) do
    {:noreply, assign(socket, :wcvp_diff, nil)}
  end

  @impl true
  def handle_event("select_family", %{"family_id" => family_id}, socket) do
    family_id = if family_id == "", do: nil, else: String.to_integer(family_id)

    # Sections belong to a genus, not a family. When the family changes on a new genus,
    # there are no sections to show. For existing genera, sections were loaded at init.
    {:noreply,
     socket
     |> assign(:selected_family_id, family_id)
     |> assign(:selected_section_id, nil)
     |> assign(:sections_for_family, [])
     |> mark_dirty()}
  end

  @impl true
  def handle_event("select_section", %{"section_id" => section_id}, socket) do
    section_id = if section_id == "", do: nil, else: String.to_integer(section_id)
    {:noreply, socket |> assign(:selected_section_id, section_id) |> mark_dirty()}
  end

  @impl true
  def handle_event("select_family_from_disambiguation", %{"family_id" => family_id_str}, socket) do
    case apply_family_disambiguation(socket, family_id_str) do
      {:ok, socket, selected} ->
        sections_for_family = Taxonomy.list_sections_for_genus(selected.genus_id)
        section_id = selected.section && selected.section.id

        {:noreply,
         socket
         |> assign(:selected_section_id, section_id)
         |> assign(:sections_for_family, sections_for_family)
         |> mark_dirty()}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  # Alias events

  @impl true
  def handle_event("update_new_alias", params, socket),
    do: {:noreply, AliasHandlers.handle_update_new_alias(socket, params)}

  @impl true
  def handle_event("add_alias", _params, socket),
    do: {:noreply, AliasHandlers.handle_add_alias(socket)}

  @impl true
  def handle_event("remove_alias", %{"alias-id" => alias_id}, socket),
    do: {:noreply, AliasHandlers.handle_remove_alias(socket, alias_id)}

  # Range/Place events

  @impl true
  def handle_event("toggle_region", %{"code" => code}, socket) do
    {:noreply, toggle_region(socket, code)}
  end

  @impl true
  def handle_event("toggle_country", %{"code" => code}, socket) do
    {:noreply, toggle_country(socket, code)}
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

  defp toggle_country(%{assigns: %{mode: mode}} = socket, _code) when mode != :edit, do: socket

  defp toggle_country(socket, code) do
    case Places.get_place_by_code(code) do
      nil ->
        socket

      place ->
        leaf_ids = Places.leaf_descendant_ids(place.id)

        if leaf_ids == [place.id] do
          # Leaf country (no subdivisions): toggle directly as exact
          new_exact = toggle_place_code(socket.assigns.exact_places, code)

          socket
          |> assign(:exact_places, new_exact)
          |> compute_map_range()
          |> mark_dirty()
        else
          # Country with subdivisions: open drill-down panel
          send_update(CountryDrillDown,
            id: "country-drill-down",
            action: {:open, place}
          )

          push_event(socket, "range-zoom-to-country", %{code: code})
        end
    end
  end

  defp toggle_region(%{assigns: %{mode: mode}} = socket, _code) when mode != :edit, do: socket

  defp toggle_region(socket, code) do
    place = Enum.find(socket.assigns.all_places, &(&1.code == code))

    if place do
      new_exact = toggle_place_code(socket.assigns.exact_places, code)

      socket
      |> assign(:exact_places, new_exact)
      |> compute_map_range()
      |> mark_dirty()
    else
      socket
    end
  end

  defp toggle_place_code(places, code) do
    if code in places, do: Enum.reject(places, &(&1 == code)), else: places ++ [code]
  end

  # Computes @in_range (exact codes) and @inherited_range (expanded country codes)
  # for the map display. Called after every change to exact_places or country_places.
  defp compute_map_range(socket) do
    exact = socket.assigns.exact_places
    country_codes = socket.assigns.country_places
    all_places = socket.assigns.all_places
    place_by_code = Map.new(all_places, &{&1.code, &1})

    inherited =
      country_codes
      |> Enum.flat_map(fn code ->
        case Map.get(place_by_code, code) do
          %{id: id} ->
            leaf_ids = Places.leaf_descendant_ids(id)
            id_to_code = Map.new(all_places, &{&1.id, &1.code})
            Enum.map(leaf_ids, &Map.get(id_to_code, &1)) |> Enum.reject(&is_nil/1)

          nil ->
            []
        end
      end)
      |> Enum.uniq()
      |> Enum.reject(&(&1 in exact))

    socket
    |> assign(:in_range, exact)
    |> assign(:inherited_range, inherited)
  end

  # Sets ALL host form assigns to their default/empty values.
  # Each init path calls this first, then overrides only what differs.
  defp build_default_assigns(socket) do
    socket
    |> assign(:mode, :search)
    |> assign(:host, nil)
    |> assign(:form, nil)
    # Deferred changes tracking
    |> assign(DeferredChanges.init(:aliases, []))
    |> assign(:original_exact_places, [])
    |> assign(:original_country_places, [])
    |> assign(:exact_places, [])
    |> assign(:country_places, [])
    |> assign(:in_range, [])
    |> assign(:inherited_range, [])
    |> assign(:taxonomy, nil)
    |> assign(:genus_is_new, false)
    |> assign(:selected_family_id, nil)
    |> assign(:selected_section_id, nil)
    |> assign(:sections_for_family, [])
    |> assign(:new_alias_name, "")
    |> assign(:new_alias_type, "common")
    # Alias collision warnings
    |> assign(:alias_collisions, [])
    # Genus disambiguation modal state
    |> assign(:show_genus_disambiguation, false)
    |> assign(:possible_families, [])
    # Typeahead search state
    |> assign(:host_search_query, "")
    |> assign(:host_search_results, [])
    # WCVP search state
    |> assign(:wcvp_search_query, "")
    |> assign(:wcvp_search_results, [])
    |> assign(:wcvp_selected, nil)
    |> assign(:wcvp_available, Gallformers.Wcvp.Lookup.available?())
    |> assign(:wcvp_prefilled, nil)
    |> assign(:wcvp_diff, nil)
    |> assign(:host_traits, nil)
    |> reset_dirty()
  end

  # Initialize state for a new host (user typed new name in typeahead)
  defp init_new_host_state(socket, name) do
    host = %SpeciesSchema{taxoncode: "plant", name: name}
    raw_taxonomy = Taxonomy.lookup_taxonomy_for_new_species(name)

    # Handle genus disambiguation: filter to plant families only
    plant_family_ids = MapSet.new(socket.assigns.families, fn {_name, id} -> id end)

    %{
      taxonomy: taxonomy,
      genus_is_new: genus_is_new,
      family_id: selected_family_id,
      section_id: selected_section_id,
      possible_families: possible_families
    } =
      Taxonomy.resolve_taxonomy_for_species(raw_taxonomy, plant_family_ids)

    # Load sections only for existing genus
    sections_for_family =
      if !genus_is_new && taxonomy && taxonomy.genus && taxonomy.genus.id do
        Taxonomy.list_sections_for_genus(taxonomy.genus.id)
      else
        []
      end

    socket
    |> build_default_assigns()
    |> assign(:mode, :new)
    |> assign(:page_title, "New Host")
    |> assign(:host, host)
    |> assign(:form, to_form(Plants.change_host(host)))
    |> assign(:taxonomy, taxonomy)
    |> assign(:genus_is_new, genus_is_new)
    |> assign(:selected_family_id, selected_family_id)
    |> assign(:selected_section_id, selected_section_id)
    |> assign(:sections_for_family, sections_for_family)
    |> assign(:possible_families, possible_families)
    |> assign(:alias_collisions, Species.find_species_with_alias(name))
    |> mark_dirty()
  end

  defp init_new_host_from_wcvp(socket, wcvp_data) do
    # Use the existing init_new_host_state flow but with WCVP name
    socket = init_new_host_state(socket, wcvp_data.taxon_name)

    # WCVP is authoritative for plant taxonomy — always use the WCVP family,
    # overriding whatever taxonomy resolution may have guessed.
    socket =
      case Enum.find(socket.assigns.families, fn {name, _id} -> name == wcvp_data.family end) do
        {_name, family_id} ->
          assign(socket, :selected_family_id, family_id)

        nil ->
          # Family doesn't exist yet — create it from WCVP data
          case Taxonomy.create_taxonomy(%{
                 name: wcvp_data.family,
                 type: "family",
                 description: "Plant"
               }) do
            {:ok, family} ->
              families = Taxonomy.list_families_for_select(:plant)

              socket
              |> assign(:families, families)
              |> assign(:selected_family_id, family.id)

            {:error, _} ->
              socket
          end
      end

    # Resolve WCVP distribution to gallformers place codes for saving after create
    tdwg_lookup = Gallformers.Wcvp.Tdwg.load()
    wcvp_places = Gallformers.Wcvp.Tdwg.convert_tdwg_codes(wcvp_data.distribution, tdwg_lookup)
    wcvp_place_codes = Enum.map(wcvp_places, & &1.code)

    wcvp_place_ids =
      socket.assigns.all_places
      |> Enum.filter(fn p -> p.code in wcvp_place_codes end)
      |> Enum.map(& &1.id)

    socket
    |> assign(:wcvp_prefilled, %{
      wcvp_id: wcvp_data.plant_name_id,
      powo_id: wcvp_data.powo_id,
      place_ids: wcvp_place_ids
    })
  end

  # =================================================================
  # WCVP diff helpers
  # =================================================================

  defp build_wcvp_diff(socket, wcvp_data) do
    tdwg_lookup = Gallformers.Wcvp.Tdwg.load()
    wcvp_places = Gallformers.Wcvp.Tdwg.convert_tdwg_codes(wcvp_data.distribution, tdwg_lookup)
    wcvp_place_codes = MapSet.new(wcvp_places, & &1.code)

    # Current places are stored as codes in exact_places and country_places
    current_place_codes =
      MapSet.new(socket.assigns.exact_places ++ socket.assigns.country_places)

    added = MapSet.difference(wcvp_place_codes, current_place_codes)
    removed = MapSet.difference(current_place_codes, wcvp_place_codes)

    %{
      wcvp_data: wcvp_data,
      places_added: MapSet.to_list(added),
      places_removed: MapSet.to_list(removed),
      has_changes: MapSet.size(added) > 0 or MapSet.size(removed) > 0
    }
  end

  defp apply_wcvp_range_updates(socket, diff) do
    host_id = socket.assigns.host.id
    tdwg_lookup = Gallformers.Wcvp.Tdwg.load()
    wcvp_places = Gallformers.Wcvp.Tdwg.convert_tdwg_codes(diff.wcvp_data.distribution, tdwg_lookup)
    wcvp_place_codes = Enum.map(wcvp_places, & &1.code)

    new_place_ids =
      socket.assigns.all_places
      |> Enum.filter(fn p -> p.code in wcvp_place_codes end)
      |> Enum.map(& &1.id)

    Ranges.update_host_places(host_id, new_place_ids)
  end

  defp assign_taxonomy_fields(socket, nil) do
    socket
    |> assign(:taxonomy, nil)
    |> assign(:selected_family_id, nil)
    |> assign(:selected_section_id, nil)
    |> assign(:sections_for_family, [])
  end

  defp assign_taxonomy_fields(socket, taxonomy) do
    genus_id = taxonomy.genus.id
    sections_for_family = if genus_id, do: Taxonomy.list_sections_for_genus(genus_id), else: []

    socket
    |> assign(:taxonomy, taxonomy)
    |> assign(:selected_family_id, taxonomy.family && taxonomy.family.id)
    |> assign(:selected_section_id, taxonomy.section && taxonomy.section.id)
    |> assign(:sections_for_family, sections_for_family)
  end

  defp save_host(socket, :new, params) do
    create_params = %{
      species_attrs: params,
      taxonomy: socket.assigns.taxonomy,
      genus_is_new: socket.assigns.genus_is_new,
      parent_id: socket.assigns.selected_section_id || socket.assigns.selected_family_id,
      aliases: socket.assigns.aliases
    }

    case Plants.create_host_with_associations(create_params) do
      {:ok, host} ->
        # Save WCVP IDs and places if this host was pre-filled from WCVP
        if wcvp = socket.assigns[:wcvp_prefilled] do
          Plants.upsert_host_traits(host.id, %{wcvp_id: wcvp.wcvp_id, powo_id: wcvp.powo_id})

          if place_ids = wcvp[:place_ids] do
            Ranges.update_host_places(host.id, place_ids)
          end
        end

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
    taxonomy = socket.assigns.taxonomy

    update_params = %{
      species_attrs: params,
      alias_changes: DeferredChanges.compute_changes(socket, :aliases),
      place_changes: %{
        original_exact_places: socket.assigns.original_exact_places,
        original_country_places: socket.assigns.original_country_places,
        exact_places: socket.assigns.exact_places,
        country_places: socket.assigns.country_places,
        all_places: socket.assigns.all_places
      },
      section_update: %{
        species_id: host_id,
        genus_id: taxonomy && taxonomy.genus && taxonomy.genus.id,
        selected_section_id: socket.assigns.selected_section_id,
        section_id: taxonomy && taxonomy.section && taxonomy.section.id
      }
    }

    case Plants.update_host_with_associations(socket.assigns.host, update_params) do
      {:ok, updated_host} ->
        aliases = Plants.get_aliases_for_host_full(host_id)
        place_entries = Ranges.get_places_for_host_with_precision(host_id)

        exact_places =
          place_entries |> Enum.filter(&(&1.precision == "exact")) |> Enum.map(& &1.code)

        country_places =
          place_entries |> Enum.filter(&(&1.precision == "country")) |> Enum.map(& &1.code)

        taxonomy = Taxonomy.get_taxonomy_for_species(host_id)

        {:noreply,
         socket
         |> assign(:host, updated_host)
         |> assign(:taxonomy, taxonomy)
         |> DeferredChanges.refresh(:aliases, aliases)
         |> assign(:original_exact_places, exact_places)
         |> assign(:original_country_places, country_places)
         |> assign(:exact_places, exact_places)
         |> assign(:country_places, country_places)
         |> compute_map_range()
         |> reset_dirty()
         |> put_flash(:info, "Host saved successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save host. Please try again.")}
    end
  end

  # =================================================================
  # Reclassify callbacks (from ReclassifyLive component)
  # =================================================================

  @impl true
  def handle_info({:reclassify_complete, result}, socket) do
    species_id = result.species.id
    taxonomy = Taxonomy.get_taxonomy_for_species(species_id)

    aliases =
      if result.add_alias? and result.name_changed?,
        do: Plants.get_aliases_for_host_full(species_id),
        else: socket.assigns.aliases

    {:noreply,
     socket
     |> assign(:host, result.species)
     |> assign(:aliases, aliases)
     |> assign(:page_title, "Edit Host - #{result.species.name}")
     |> assign_taxonomy_fields(taxonomy)
     |> put_flash(:info, "Host updated successfully")}
  end

  @impl true
  def handle_info({:reclassify_flash, level, message}, socket) do
    {:noreply, put_flash(socket, level, message)}
  end

  # =================================================================
  # CountryDrillDown callbacks
  # =================================================================

  @impl true
  def handle_info({CountryDrillDown, {:set_country_level, code, true}}, socket) do
    new_country = Enum.uniq([code | socket.assigns.country_places])

    {:noreply,
     socket
     |> assign(:country_places, new_country)
     |> compute_map_range()
     |> mark_dirty()}
  end

  def handle_info({CountryDrillDown, {:set_country_level, code, false}}, socket) do
    new_country = Enum.reject(socket.assigns.country_places, &(&1 == code))

    {:noreply,
     socket
     |> assign(:country_places, new_country)
     |> compute_map_range()
     |> mark_dirty()}
  end

  def handle_info({CountryDrillDown, {:toggle_exact, code}}, socket) do
    new_exact = toggle_place_code(socket.assigns.exact_places, code)

    {:noreply,
     socket
     |> assign(:exact_places, new_exact)
     |> compute_map_range()
     |> mark_dirty()}
  end

  def handle_info({CountryDrillDown, {:select_all_exact, codes}}, socket) do
    new_exact = Enum.uniq(socket.assigns.exact_places ++ codes)

    {:noreply,
     socket
     |> assign(:exact_places, new_exact)
     |> compute_map_range()
     |> mark_dirty()}
  end

  def handle_info({CountryDrillDown, {:deselect_all_exact, codes}}, socket) do
    new_exact = Enum.reject(socket.assigns.exact_places, &(&1 in codes))

    {:noreply,
     socket
     |> assign(:exact_places, new_exact)
     |> compute_map_range()
     |> mark_dirty()}
  end

  def handle_info({CountryDrillDown, :zoom_out}, socket) do
    {:noreply, push_event(socket, "range-zoom-out", %{})}
  end

  # =================================================================
  # PubSub handlers
  # =================================================================

  @impl true
  def handle_info({:species_updated, species}, socket) do
    # If the currently edited host was updated elsewhere, reload it
    if socket.assigns.host && socket.assigns.host.id == species.id do
      case Plants.get_host_species(species.id) do
        nil ->
          {:noreply,
           socket
           |> put_flash(:warning, "This host was deleted by another user")
           |> build_default_assigns()}

        host ->
          {:noreply, load_host_for_edit(socket, host)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:species_deleted, species}, socket) do
    # If the currently edited host was deleted, clear it
    if socket.assigns.host && socket.assigns.host.id == species.id do
      {:noreply,
       socket
       |> put_flash(:warning, "This host was deleted by another user")
       |> build_default_assigns()}
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
  # Render
  # =================================================================

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
            class="text-sm hover:underline mr-4"
          >
            Species-Source Mappings
          </.link>
          <.link
            navigate={~p"/admin/species-sources/add?species_id=#{@host.id}"}
            class="text-sm hover:underline"
          >
            Add Source Mapping
          </.link>
        </:quick_links>

        <%!-- WCVP pre-fill search (new mode only) --%>
        <div :if={@wcvp_available && @mode != :edit} class="mb-4">
          <.card title="Pre-fill from WCVP" icon="ph-leaf" class="overflow-visible">
            <p class="text-sm text-gray-600 mb-3">
              Search the World Checklist of Vascular Plants to pre-fill name, taxonomy, and range data for a new host.
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
          </.card>
        </div>

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
                phx-click="open_reclassify_modal"
                phx-target="#reclassify"
                class="px-3 py-2 text-sm bg-gray-200 hover:bg-gray-300 border border-gray-300 rounded whitespace-nowrap"
              >
                Rename/Reclassify
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

        <.alias_collision_warning collisions={@alias_collisions} />

        <%!-- Rest of form - disabled until host selected/created --%>
        <fieldset disabled={@mode == :search} class={[@mode == :search && "opacity-50"]}>
          <.form :if={@form} for={@form} id="host-form" phx-change="validate" phx-submit="save">
            <%!-- Row: Genus | Family --%>
            <.taxonomy_genus_family_row
              taxonomy={@taxonomy}
              genus_is_new={@genus_is_new}
              selected_family_id={@selected_family_id}
              families={@families}
              new_genus_hint="selected section/family"
            />

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
                    placeholder="No sections in this genus"
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

            <%!-- WCVP Refresh (edit mode only) --%>
            <div :if={@mode == :edit && @wcvp_available} class="mb-4">
              <.button
                :if={is_nil(@wcvp_diff)}
                phx-click="refresh_from_wcvp"
                type="button"
                variant="secondary"
                size="sm"
              >
                Refresh from WCVP
              </.button>

              <div
                :if={@wcvp_diff}
                class="border rounded-lg p-4 bg-amber-50 dark:bg-amber-950"
              >
                <h4 class="font-medium mb-2">WCVP Data Comparison</h4>

                <div :if={!@wcvp_diff.has_changes} class="text-sm text-gray-600">
                  No differences found. Host data matches WCVP.
                </div>

                <div :if={@wcvp_diff.has_changes} class="text-sm space-y-2">
                  <div :if={@wcvp_diff.places_added != []}>
                    <span class="font-medium text-green-700">+ Places to add:</span>
                    {Enum.join(@wcvp_diff.places_added, ", ")}
                  </div>
                  <div :if={@wcvp_diff.places_removed != []}>
                    <span class="font-medium text-red-700">- Places to remove:</span>
                    {Enum.join(@wcvp_diff.places_removed, ", ")}
                  </div>
                </div>

                <div class="mt-3 flex gap-2">
                  <.button
                    :if={@wcvp_diff.has_changes}
                    phx-click="apply_wcvp_updates"
                    type="button"
                    size="sm"
                  >
                    Apply Updates
                  </.button>
                  <.button
                    phx-click="cancel_wcvp_refresh"
                    type="button"
                    variant="secondary"
                    size="sm"
                  >
                    Cancel
                  </.button>
                </div>
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
                      <span class="text-xs text-gray-600">Documented</span>
                    </div>
                    <div class="flex items-center gap-2">
                      <div class="w-4 h-4 rounded bg-green-700/40"></div>
                      <span class="text-xs text-gray-600">Country-level</span>
                    </div>
                    <div class="flex items-center gap-2">
                      <div class="w-4 h-4 rounded border border-gray-300 bg-white"></div>
                      <span class="text-xs text-gray-600">Out of Range</span>
                    </div>
                  </div>
                </div>
                <%!-- Map + Drill-down panel --%>
                <div class="col-span-5">
                  <label class="gf-label">Range:</label>
                  <%= if @mode == :edit do %>
                    <div class="flex">
                      <div class="flex-1">
                        <.range_map
                          id="host-range-map"
                          in_range={@in_range}
                          inherited_range={@inherited_range}
                          editable
                          class="border border-gray-300 rounded bg-gray-50 min-h-[500px]"
                        />
                      </div>
                      <.live_component
                        module={CountryDrillDown}
                        id="country-drill-down"
                        exact_places={@exact_places}
                        country_places={@country_places}
                        all_places={@all_places}
                      />
                    </div>
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

      <.live_component
        module={GallformersWeb.Admin.ReclassifyLive}
        id="reclassify"
        species_id={@host && @host.id}
        species_name={@host && @host.name}
        current_family={@taxonomy && @taxonomy.family}
        current_genus={@taxonomy && @taxonomy.genus}
        entity_type="Host"
        is_gall={false}
        undescribed={false}
      />

      <%!-- Genus disambiguation modal --%>
      <.genus_disambiguation_modal
        possible_families={@possible_families}
        taxonomy={@taxonomy}
        entity_description="plant"
        select_event="select_family_from_disambiguation"
        clear_event="clear_host"
      />
    </Layouts.admin>
    """
  end
end
