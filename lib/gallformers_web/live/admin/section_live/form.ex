defmodule GallformersWeb.Admin.SectionLive.Form do
  @moduledoc """
  Admin form for creating and editing taxonomy sections.

  Sections group host plant species within a genus. Species can be added/removed
  from sections, and the section's parent genus is derived from the species.
  """
  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers

  alias Gallformers.Plants
  alias Gallformers.Taxonomy
  alias Gallformers.Taxonomy.Taxonomy, as: TaxonomySchema

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Section")
      |> init_form_state()
      |> assign(:section, nil)
      |> assign(:form, nil)
      |> assign(:species, [])
      |> assign(:search_results, [])
      |> assign(:search_query, "")

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    section = %TaxonomySchema{type: "section"}
    changeset = Taxonomy.change_taxonomy(section)

    socket
    |> assign(:page_title, "New Section")
    |> assign(:section, section)
    |> assign(:form, to_form(changeset))
    |> assign(:species, [])
    |> assign(:mode, :new)
    |> reset_dirty()
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    section = Taxonomy.get_taxonomy!(id)
    species = Taxonomy.get_species_for_section(section.id)
    changeset = Taxonomy.change_taxonomy(section)

    socket
    |> assign(:page_title, "Edit Section: #{section.name}")
    |> assign(:section, section)
    |> assign(:form, to_form(changeset))
    |> assign(:species, species)
    |> assign(:mode, :edit)
    |> reset_dirty()
  end

  @impl true
  def handle_event("validate", %{"taxonomy" => params}, socket) do
    changeset =
      socket.assigns.section
      |> Taxonomy.change_taxonomy(params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form, to_form(changeset)) |> mark_dirty()}
  end

  @impl true
  def handle_event("save", %{"taxonomy" => params}, socket) do
    save_section(socket, socket.assigns.mode, params)
  end

  @impl true
  def handle_event("search_species", %{"query" => query}, socket) do
    if String.length(query) >= 2 do
      # Filter out already selected species
      selected_ids = Enum.map(socket.assigns.species, & &1.id)

      results =
        Plants.search_hosts_for_section(query, 20)
        |> Enum.reject(fn s -> s.id in selected_ids end)

      {:noreply,
       socket
       |> assign(:search_results, results)
       |> assign(:search_query, query)}
    else
      {:noreply,
       socket
       |> assign(:search_results, [])
       |> assign(:search_query, query)}
    end
  end

  @impl true
  def handle_event("add_species", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    species_to_add = Enum.find(socket.assigns.search_results, &(&1.id == id))

    if species_to_add do
      new_species = socket.assigns.species ++ [species_to_add]

      # Check if all species are from the same genus
      genera = new_species |> Enum.map(&extract_genus/1) |> Enum.uniq()

      socket =
        if length(genera) > 1 do
          put_flash(socket, :error, "All species must be from the same genus.")
        else
          socket
          |> assign(:species, new_species)
          |> assign(:search_results, Enum.reject(socket.assigns.search_results, &(&1.id == id)))
          |> mark_dirty()
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_species", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    new_species = Enum.reject(socket.assigns.species, &(&1.id == id))
    {:noreply, socket |> assign(:species, new_species) |> mark_dirty()}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_results, [])
     |> assign(:search_query, "")}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Taxonomy.delete_taxonomy(socket.assigns.section) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Section deleted successfully")
         |> push_navigate(to: ~p"/admin/section")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete section")}
    end
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(request_cancel cancel_discard confirm_discard) do
    handle_form_event(event, params, socket)
  end

  def close_form(socket) do
    push_navigate(socket, to: ~p"/admin/section")
  end

  defp save_section(socket, :new, params) do
    species_ids = Enum.map(socket.assigns.species, & &1.id)

    if species_ids == [] do
      {:noreply, put_flash(socket, :error, "At least one species is required.")}
    else
      # Derive parent genus from first species
      first_species = hd(socket.assigns.species)
      genus_name = extract_genus(first_species)
      genus = Taxonomy.get_taxonomy_by_name(genus_name, "genus")

      params =
        params
        |> Map.put("type", "section")
        |> Map.put("parent_id", genus && genus.id)

      case Taxonomy.create_taxonomy(params) do
        {:ok, section} ->
          # Link species to section
          Taxonomy.update_section_species(section.id, species_ids)

          {:noreply,
           socket
           |> put_flash(:info, "Section created successfully")
           |> push_navigate(to: ~p"/admin/section")}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end
  end

  defp save_section(socket, :edit, params) do
    species_ids = Enum.map(socket.assigns.species, & &1.id)

    if species_ids == [] do
      {:noreply, put_flash(socket, :error, "At least one species is required.")}
    else
      case Taxonomy.update_taxonomy(socket.assigns.section, params) do
        {:ok, _section} ->
          # Update species links
          Taxonomy.update_section_species(socket.assigns.section.id, species_ids)

          {:noreply,
           socket
           |> put_flash(:info, "Section updated successfully")
           |> push_navigate(to: ~p"/admin/section")}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}
      end
    end
  end

  defp extract_genus(%{name: name}) do
    case String.split(name, " ", parts: 2) do
      [genus | _] -> genus
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_user={@current_user}
      page_title={@page_title}
      public_url={if @mode == :edit, do: ~p"/section/#{@section.id}"}
    >
      <Layouts.admin_edit_layout
        back_path={~p"/admin/section"}
        back_label="Back to Sections"
        title={if @mode == :new, do: "Create New Section", else: "Edit Section"}
      >
        <:intro>
          Sections group host plant species within a genus. All species in a section
          must be from the same genus. The section's parent genus is automatically
          determined from the species.
        </:intro>

        <.form for={@form} id="section-form" phx-change="validate" phx-submit="save">
          <div class="mb-4">
            <.input
              field={@form[:name]}
              type="text"
              label="Section Name"
              placeholder="e.g., Quercus sect. Lobatae"
              required
            />
          </div>

          <div class="mb-4">
            <.input
              field={@form[:description]}
              type="text"
              label="Description"
              placeholder="e.g., Red Oaks"
              required
            />
            <p class="mt-1 text-xs text-gray-500">
              A friendly name for the section (e.g., "Red Oaks", "White Oaks")
            </p>
          </div>

          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Species in this Section <span class="text-red-500">*</span>
            </label>

            <%!-- Selected species chips --%>
            <div class="mb-3">
              <%= if @species != [] do %>
                <div class="flex flex-wrap gap-2 p-3 bg-gray-50 rounded-lg border border-gray-200">
                  <%= for species <- @species do %>
                    <span class="inline-flex items-center gap-1 px-3 py-1 rounded-full text-sm bg-green-100 text-green-800">
                      {species.name}
                      <button
                        type="button"
                        phx-click="remove_species"
                        phx-value-id={species.id}
                        class="ml-1 text-green-600 hover:text-green-800"
                      >
                        <.icon name="ph-x" class="h-3 w-3" />
                      </button>
                    </span>
                  <% end %>
                </div>
              <% else %>
                <p class="text-sm text-gray-500 italic p-3 bg-gray-50 rounded-lg border border-gray-200">
                  No species selected. Search below to add host plants.
                </p>
              <% end %>
            </div>

            <%!-- Search input --%>
            <div class="relative">
              <input
                type="text"
                phx-keyup="search_species"
                phx-debounce="300"
                value={@search_query}
                name="query"
                placeholder="Search for host plants to add..."
                class="gf-input w-full"
                autocomplete="off"
              />

              <%!-- Search results dropdown --%>
              <%= if @search_results != [] do %>
                <div class="absolute z-10 w-full mt-1 bg-white border border-gray-200 rounded-lg shadow-lg max-h-60 overflow-y-auto">
                  <%= for result <- @search_results do %>
                    <button
                      type="button"
                      phx-click="add_species"
                      phx-value-id={result.id}
                      class="w-full text-left px-4 py-2 hover:bg-gray-100 border-b border-gray-100 last:border-0"
                    >
                      {result.name}
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>

            <p class="mt-2 text-xs text-gray-500">
              All species must be from the same genus. Search by species name and click to add.
            </p>
          </div>

          <%!-- Genus info --%>
          <%= if @species != [] do %>
            <div class="mb-4 p-3 bg-blue-50 border border-blue-200 rounded-lg">
              <p class="text-sm text-blue-800">
                <.icon name="ph-info" class="h-4 w-4 inline mr-1" /> Parent genus:
                <strong>{extract_genus(hd(@species))}</strong>
                (derived from species)
              </p>
            </div>
          <% end %>

          <div class="flex justify-between pt-4 border-t border-gray-200">
            <div>
              <button
                :if={@mode == :edit}
                type="button"
                phx-click="delete"
                data-confirm="Are you sure? This will remove all species from this section."
                class="gf-btn gf-btn-danger"
              >
                Delete
              </button>
            </div>
            <div class="flex gap-2">
              <button
                type="button"
                phx-click="request_cancel"
                class="gf-btn gf-btn-secondary"
              >
                Cancel
              </button>
              <button type="submit" class="gf-btn gf-btn-primary">
                {if @mode == :new, do: "Create Section", else: "Save Changes"}
              </button>
            </div>
          </div>
        </.form>
      </Layouts.admin_edit_layout>

      <.discard_confirm_modal show={@show_discard_confirm} />
    </Layouts.admin>
    """
  end
end
