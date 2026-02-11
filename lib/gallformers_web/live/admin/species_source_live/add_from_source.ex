defmodule GallformersWeb.Admin.SpeciesSourceLive.AddFromSource do
  @moduledoc """
  Admin page for bulk-adding species-source mappings.

  Optimized for the workflow: "I have a new paper and want to add
  all the species it covers."

  The source stays locked at the top while you cycle through species,
  adding mappings with "Save & Add Another".
  """
  use GallformersWeb, :live_view

  alias Gallformers.Sources
  alias Gallformers.Species
  alias Gallformers.Species.SpeciesSource

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Add Species from Source")
      |> assign(:source_search_query, "")
      |> assign(:source_search_results, [])
      |> assign(:selected_source, nil)
      |> assign(:mapped_species, [])
      |> assign(:species_search_query, "")
      |> assign(:species_search_results, [])
      |> assign(:selected_species, nil)
      |> assign(:form, nil)
      |> assign(:editing_existing, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    # Allow pre-selecting a source via query param
    socket =
      case params do
        %{"source_id" => source_id} ->
          case Sources.get_source(String.to_integer(source_id)) do
            nil -> socket
            source -> select_source(socket, source)
          end

        _ ->
          socket
      end

    {:noreply, socket}
  end

  defp select_source(socket, source) do
    mapped_species = Sources.get_species_for_source(source.id)

    socket
    |> assign(:selected_source, source)
    |> assign(:mapped_species, mapped_species)
    |> assign(:source_search_query, "")
    |> assign(:source_search_results, [])
    |> clear_species_form()
  end

  defp clear_species_form(socket) do
    socket
    |> assign(:selected_species, nil)
    |> assign(:species_search_query, "")
    |> assign(:species_search_results, [])
    |> assign(:form, nil)
    |> assign(:editing_existing, false)
  end

  defp load_species_form(socket, species, existing_mapping \\ nil) do
    species_source =
      if existing_mapping do
        %SpeciesSource{
          id: existing_mapping.id,
          species_id: species.id,
          source_id: socket.assigns.selected_source.id,
          description: existing_mapping.description || "",
          externallink: existing_mapping.externallink || "",
          useasdefault: existing_mapping.useasdefault || false
        }
      else
        %SpeciesSource{
          species_id: species.id,
          source_id: socket.assigns.selected_source.id,
          description: "",
          externallink: "",
          useasdefault: false
        }
      end

    changeset = Sources.change_species_source(species_source)

    socket
    |> assign(:selected_species, species)
    |> assign(:form, to_form(changeset))
    |> assign(:editing_existing, existing_mapping != nil)
    |> assign(:species_search_query, "")
    |> assign(:species_search_results, [])
  end

  # Event handlers

  @impl true
  def handle_event("search_sources", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Sources.search_sources(query)
        |> Enum.take(10)
      else
        []
      end

    {:noreply, assign(socket, source_search_query: query, source_search_results: results)}
  end

  @impl true
  def handle_event("select_source", %{"id" => id}, socket) do
    source = Sources.get_source!(String.to_integer(id))
    {:noreply, select_source(socket, source)}
  end

  @impl true
  def handle_event("clear_source", _params, socket) do
    socket =
      socket
      |> assign(:selected_source, nil)
      |> assign(:mapped_species, [])
      |> clear_species_form()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_species", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Species.search_species(query, 10)
      else
        []
      end

    {:noreply, assign(socket, species_search_query: query, species_search_results: results)}
  end

  @impl true
  def handle_event("select_species", %{"id" => id}, socket) do
    species_id = String.to_integer(id)
    source_id = socket.assigns.selected_source.id

    # Check if this species is already mapped to this source
    existing = Sources.get_species_source_by_ids(species_id, source_id)

    species = %{id: species_id, name: get_species_name(species_id)}

    socket =
      if existing do
        # Load existing mapping for editing
        existing_data = %{
          id: existing.id,
          description: existing.description,
          externallink: existing.externallink,
          useasdefault: existing.useasdefault
        }

        load_species_form(socket, species, existing_data)
        |> put_flash(:info, "This species is already mapped. Editing existing entry.")
      else
        load_species_form(socket, species)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_existing", %{"id" => species_id}, socket) do
    species_id = String.to_integer(species_id)
    source_id = socket.assigns.selected_source.id

    existing = Sources.get_species_source_by_ids(species_id, source_id)

    if existing do
      species = %{id: species_id, name: get_species_name(species_id)}

      existing_data = %{
        id: existing.id,
        description: existing.description,
        externallink: existing.externallink,
        useasdefault: existing.useasdefault
      }

      {:noreply, load_species_form(socket, species, existing_data)}
    else
      {:noreply, put_flash(socket, :error, "Mapping not found")}
    end
  end

  @impl true
  def handle_event("clear_species", _params, socket) do
    {:noreply, clear_species_form(socket)}
  end

  @impl true
  def handle_event("validate", %{"species_source" => params}, socket) do
    # Get current species_source from form
    species_source = get_species_source_from_form(socket)

    changeset =
      species_source
      |> Sources.change_species_source(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  # Catch-all for validate events that don't match the expected form structure
  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", params, socket) do
    species_source_params = params["species_source"] || %{}
    action = if params["action"] == "add_another", do: :add_another, else: :done
    save_mapping(socket, species_source_params, action)
  end

  @impl true
  def handle_event("delete_mapping", _params, socket) do
    species_id = socket.assigns.selected_species.id
    source_id = socket.assigns.selected_source.id

    case Sources.get_species_source_by_ids(species_id, source_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Mapping not found")}

      species_source ->
        case Sources.delete_species_source(species_source) do
          {:ok, _} ->
            mapped_species = Sources.get_species_for_source(source_id)

            {:noreply,
             socket
             |> assign(:mapped_species, mapped_species)
             |> clear_species_form()
             |> put_flash(:info, "Mapping deleted")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete mapping")}
        end
    end
  end

  defp save_mapping(socket, params, action) do
    species_source = get_species_source_from_form(socket)
    params = normalize_params(params, socket)

    result =
      if socket.assigns.editing_existing do
        existing = Sources.get_species_source!(species_source.id)
        Sources.update_species_source(existing, params)
      else
        Sources.create_species_source(params)
      end

    case result do
      {:ok, _} ->
        source_id = socket.assigns.selected_source.id
        mapped_species = Sources.get_species_for_source(source_id)

        socket =
          socket
          |> assign(:mapped_species, mapped_species)
          |> put_flash(:info, "Mapping saved")

        socket =
          case action do
            :add_another -> clear_species_form(socket)
            :done -> push_navigate(socket, to: ~p"/admin/sources")
          end

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp get_species_source_from_form(socket) do
    %SpeciesSource{
      id: if(socket.assigns.editing_existing, do: socket.assigns.form.data.id, else: nil),
      species_id: socket.assigns.selected_species.id,
      source_id: socket.assigns.selected_source.id
    }
  end

  defp normalize_params(params, socket) do
    params
    |> Map.put("species_id", socket.assigns.selected_species.id)
    |> Map.put("source_id", socket.assigns.selected_source.id)
  end

  defp get_species_name(species_id) do
    case Species.get_species(species_id) do
      nil -> "Unknown"
      species -> species.name
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <div class="max-w-5xl mx-auto">
        <div class="mb-4">
          <.link navigate={~p"/admin/sources"} class="hover:underline text-sm">
            &larr; Back to Sources
          </.link>
        </div>

        <div class="bg-white border border-gray-200 rounded shadow-sm">
          <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
            <h4 class="text-lg font-semibold text-gf-maroon">Add Species from Source</h4>
            <p class="text-sm text-gray-600 mt-1">
              Select a source, then add species mappings one at a time.
              The source stays selected while you add multiple species.
            </p>
          </div>

          <div class="p-4">
            <%!-- Source Selection (sticky at top) --%>
            <div class="mb-6 pb-4 border-b border-gray-200">
              <label class="gf-label mb-2">
                Source:
              </label>

              <%= if @selected_source do %>
                <div class="flex items-center gap-3 p-3 bg-blue-50 border border-blue-200 rounded">
                  <div class="flex-1">
                    <div class="font-medium text-gray-900">{@selected_source.title}</div>
                    <div class="text-sm text-gray-600">
                      {@selected_source.author} ({@selected_source.pubyear})
                    </div>
                  </div>
                  <button
                    type="button"
                    phx-click="clear_source"
                    class="px-3 py-1 text-sm text-gray-600 hover:text-gray-800 border border-gray-300 rounded"
                  >
                    Change
                  </button>
                </div>
              <% else %>
                <.typeahead
                  id="source-picker"
                  label=""
                  placeholder="Search sources by title or author..."
                  query={@source_search_query}
                  results={@source_search_results}
                  selected={nil}
                  search_event="search_sources"
                  select_event="select_source"
                  clear_event="clear_source"
                  display_fn={& &1.title}
                >
                  <:result :let={source}>
                    <div class="font-medium text-gray-900">{source.title}</div>
                    <div class="text-sm text-gray-600">
                      {source.author} ({source.pubyear})
                    </div>
                  </:result>
                </.typeahead>
              <% end %>
            </div>

            <%= if @selected_source do %>
              <%!-- Already Mapped Species --%>
              <div class="mb-6">
                <label class="gf-label mb-2">
                  Already mapped ({length(@mapped_species)} species):
                </label>
                <%= if @mapped_species == [] do %>
                  <p class="text-sm text-gray-500 italic">No species mapped to this source yet.</p>
                <% else %>
                  <div class="border border-gray-200 rounded max-h-40 overflow-auto">
                    <div class="divide-y divide-gray-100">
                      <button
                        :for={sp <- @mapped_species}
                        type="button"
                        phx-click="edit_existing"
                        phx-value-id={sp.id}
                        class={[
                          "w-full px-3 py-1.5 text-left text-sm hover:bg-gray-50 flex justify-between items-center",
                          @selected_species && @selected_species.id == sp.id && "bg-canary"
                        ]}
                      >
                        <.taxon_name name={sp.name} />
                        <span class="text-xs text-gray-400">click to edit</span>
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>

              <%!-- Add New Species --%>
              <div class="mb-6">
                <.typeahead
                  id="species-picker"
                  label="Add species:"
                  placeholder="Search species by name..."
                  query={@species_search_query}
                  results={@species_search_results}
                  selected={@selected_species}
                  search_event="search_species"
                  select_event="select_species"
                  clear_event="clear_species"
                  display_fn={& &1.name}
                >
                  <:result :let={species}>
                    <div class="flex justify-between items-center w-full">
                      <.taxon_name name={species.name} />
                      <span class="text-xs text-gray-400">{species.taxoncode}</span>
                    </div>
                  </:result>
                </.typeahead>
              </div>

              <%!-- Mapping Form --%>
              <%= if @selected_species do %>
                <div class="border-t border-gray-200 pt-4">
                  <div class="flex items-center justify-between mb-4">
                    <h5 class="font-medium text-gray-900">
                      <%= if @editing_existing do %>
                        Editing: <.taxon_name name={@selected_species.name} />
                      <% else %>
                        New mapping: <.taxon_name name={@selected_species.name} />
                      <% end %>
                    </h5>
                    <button
                      type="button"
                      phx-click="clear_species"
                      class="text-sm text-gray-500 hover:text-gray-700"
                    >
                      Cancel
                    </button>
                  </div>

                  <.form
                    for={@form}
                    id="species-source-form"
                    phx-change="validate"
                    phx-submit="save"
                  >
                    <div class="space-y-4">
                      <div>
                        <label class="gf-label">
                          Description (info from this source about this species):
                        </label>
                        <.input
                          field={@form[:description]}
                          type="textarea"
                          rows={6}
                          placeholder="Enter the relevant description from this source..."
                          class="w-full"
                        />
                        <p class="mt-1 text-xs text-gray-500">
                          Supports Markdown formatting
                        </p>
                      </div>

                      <div>
                        <label class="gf-label">
                          External Link (direct link to description page, if available):
                        </label>
                        <.input
                          field={@form[:externallink]}
                          type="url"
                          placeholder="https://www.biodiversitylibrary.org/page/..."
                          class="w-full"
                        />
                        <p class="mt-1 text-xs text-gray-500">
                          e.g., BHL or HathiTrust page. Don't duplicate the main source link.
                        </p>
                      </div>

                      <.input
                        type="checkbox"
                        field={@form[:useasdefault]}
                        label="Use as default source for this species"
                      />

                      <div class="flex justify-between items-center pt-4 border-t border-gray-200">
                        <div>
                          <%= if @editing_existing do %>
                            <button
                              type="button"
                              phx-click="delete_mapping"
                              data-confirm="Are you sure you want to delete this mapping?"
                              class="text-sm text-red-600 hover:text-red-800"
                            >
                              Delete mapping
                            </button>
                          <% end %>
                        </div>
                        <div class="flex gap-2">
                          <button
                            type="submit"
                            name="action"
                            value="add_another"
                            class="px-4 py-2 text-sm border border-gf-maroon text-gf-maroon rounded hover:bg-gf-maroon/10"
                          >
                            Save & Add Another
                          </button>
                          <button
                            type="submit"
                            name="action"
                            value="done"
                            class="px-4 py-2 text-sm bg-gf-maroon text-white rounded hover:bg-gf-maroon/90"
                          >
                            Save & Done
                          </button>
                        </div>
                      </div>
                    </div>
                  </.form>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
