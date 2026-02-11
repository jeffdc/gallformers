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
  alias GallformersWeb.Admin.DeferredChanges

  import GallformersWeb.Admin.FormComponents,
    only: [alias_collision_warning: 1, alias_editor: 1, form_actions: 1]

  import GallformersWeb.Admin.ReclassifyHelpers

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    if connected?(socket), do: Species.subscribe()

    abundances = Species.list_abundances()
    all_places = Places.list_places()
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
    places = Ranges.get_places_for_host(host_id)
    taxonomy = Taxonomy.get_taxonomy_for_species(host_id)

    socket
    |> build_default_assigns()
    |> assign(:mode, :edit)
    |> assign(:page_title, "Edit Host - #{host.name}")
    |> assign(:host, host)
    |> assign(:form, to_form(Plants.change_host(host)))
    # Deferred changes tracking (override defaults with loaded data)
    |> assign(DeferredChanges.init(:aliases, aliases))
    |> assign(:original_places, places)
    |> assign(:places, places)
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

  # Sets ALL host form assigns to their default/empty values.
  # Each init path calls this first, then overrides only what differs.
  defp build_default_assigns(socket) do
    socket
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
    # Alias collision warnings
    |> assign(:alias_collisions, [])
    # Genus disambiguation modal state
    |> assign(:show_genus_disambiguation, false)
    |> assign(:possible_families, [])
    # Typeahead search state
    |> assign(:host_search_query, "")
    |> assign(:host_search_results, [])
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

  defp assign_taxonomy_fields(socket, nil) do
    socket
    |> assign(:taxonomy, nil)
    |> assign(:selected_family_id, nil)
    |> assign(:selected_section_id, nil)
    |> assign(:sections_for_family, [])
  end

  defp assign_taxonomy_fields(socket, taxonomy) do
    genus_id = taxonomy.genus && taxonomy.genus.id
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
        original_places: socket.assigns.original_places,
        current_places: socket.assigns.places,
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
        places = Ranges.get_places_for_host(host_id)
        taxonomy = Taxonomy.get_taxonomy_for_species(host_id)

        {:noreply,
         socket
         |> assign(:host, updated_host)
         |> assign(:taxonomy, taxonomy)
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
