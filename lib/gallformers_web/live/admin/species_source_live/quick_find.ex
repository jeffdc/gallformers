defmodule GallformersWeb.Admin.SpeciesSourceLive.QuickFind do
  @moduledoc """
  Admin page for quick find and edit of species-source mappings.

  Optimized for the workflow: "I need to quickly fix something
  in a specific mapping."

  Search by species name, source title, or description text.
  Click a result to edit inline.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Sources
  alias Gallformers.Species.SpeciesSource

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Quick Find Species-Source Mappings")
      |> assign(:search_query, "")
      |> assign(:species_id, nil)
      |> assign(:results, [])
      |> assign(:searched, false)
      |> assign(:editing_id, nil)
      |> assign(:form, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      case params do
        # Pre-select a specific mapping by species_id and source_id
        %{"species_id" => species_id_str, "source_id" => source_id_str} ->
          with {species_id, ""} <- Integer.parse(species_id_str),
               {source_id, ""} <- Integer.parse(source_id_str),
               %{id: mapping_id} <- Sources.get_species_source_by_ids(species_id, source_id),
               mapping when not is_nil(mapping) <- Sources.get_species_source_for_edit(mapping_id) do
            # Include this mapping in results and auto-open edit form
            species_source = %SpeciesSource{
              id: mapping.id,
              species_id: mapping.species_id,
              source_id: mapping.source_id,
              description: mapping.description || "",
              externallink: mapping.externallink || "",
              useasdefault: mapping.useasdefault || false
            }

            changeset = Sources.change_species_source(species_source)

            socket
            |> assign(:search_query, mapping.species_name)
            |> assign(:species_id, mapping.species_id)
            |> assign(:results, [mapping])
            |> assign(:searched, true)
            |> assign(:editing_id, mapping_id)
            |> assign(:form, to_form(changeset))
          else
            _ -> socket
          end

        # Show all mappings for a species (from admin gall/host forms)
        %{"species_id" => species_id_str} ->
          with {species_id, ""} <- Integer.parse(species_id_str),
               species when not is_nil(species) <- Gallformers.Species.get_species(species_id) do
            results = Sources.get_species_source_mappings_for_species(species_id)

            socket
            |> assign(:search_query, species.name)
            |> assign(:species_id, species_id)
            |> assign(:results, results)
            |> assign(:searched, true)
          else
            _ -> socket
          end

        # Allow pre-populating search via query param
        %{"q" => query} when query != "" ->
          results = Sources.search_species_source_mappings(query)

          socket
          |> assign(:search_query, query)
          |> assign(:results, results)
          |> assign(:searched, true)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  # Event handlers

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    if String.length(query) >= 2 do
      results = Sources.search_species_source_mappings(query)

      {:noreply,
       socket
       |> assign(:search_query, query)
       |> assign(:results, results)
       |> assign(:searched, true)
       |> assign(:editing_id, nil)
       |> assign(:form, nil)}
    else
      {:noreply,
       socket
       |> assign(:search_query, query)
       |> assign(:results, [])
       |> assign(:searched, false)}
    end
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    mapping_id = String.to_integer(id)
    mapping = Sources.get_species_source_for_edit(mapping_id)

    if mapping do
      species_source = %SpeciesSource{
        id: mapping.id,
        species_id: mapping.species_id,
        source_id: mapping.source_id,
        description: mapping.description || "",
        externallink: mapping.externallink || "",
        useasdefault: mapping.useasdefault || false
      }

      changeset = Sources.change_species_source(species_source)

      {:noreply,
       socket
       |> assign(:editing_id, mapping_id)
       |> assign(:form, to_form(changeset))}
    else
      {:noreply, put_flash(socket, :error, "Mapping not found")}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_id, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_event("validate", %{"species_source" => params}, socket) do
    species_source = %SpeciesSource{
      id: socket.assigns.editing_id,
      species_id: get_mapping_field(socket, :species_id),
      source_id: get_mapping_field(socket, :source_id)
    }

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
  def handle_event("save", %{"species_source" => params}, socket) do
    existing = Sources.get_species_source!(socket.assigns.editing_id)

    params =
      params
      |> Map.put("species_id", existing.species_id)
      |> Map.put("source_id", existing.source_id)

    case Sources.update_species_source(existing, params) do
      {:ok, _} ->
        results = refetch_results(socket)

        # Rebuild the form with fresh data so the user can keep editing
        mapping = Sources.get_species_source_for_edit(socket.assigns.editing_id)

        species_source = %SpeciesSource{
          id: mapping.id,
          species_id: mapping.species_id,
          source_id: mapping.source_id,
          description: mapping.description || "",
          externallink: mapping.externallink || "",
          useasdefault: mapping.useasdefault || false
        }

        changeset = Sources.change_species_source(species_source)

        {:noreply,
         socket
         |> assign(:results, results)
         |> assign(:form, to_form(changeset))
         |> put_flash(:info, "Mapping updated")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    existing = Sources.get_species_source!(socket.assigns.editing_id)

    case Sources.delete_species_source(existing) do
      {:ok, _} ->
        results = refetch_results(socket)

        {:noreply,
         socket
         |> assign(:results, results)
         |> assign(:editing_id, nil)
         |> assign(:form, nil)
         |> put_flash(:info, "Mapping deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete mapping")}
    end
  end

  defp refetch_results(socket) do
    case socket.assigns.species_id do
      nil -> Sources.search_species_source_mappings(socket.assigns.search_query)
      species_id -> Sources.get_species_source_mappings_for_species(species_id)
    end
  end

  defp get_mapping_field(socket, field) do
    Enum.find_value(socket.assigns.results, fn r ->
      if r.id == socket.assigns.editing_id, do: Map.get(r, field)
    end)
  end

  defp truncate_description(nil), do: ""
  defp truncate_description(""), do: ""

  defp truncate_description(desc) do
    if String.length(desc) > 150 do
      String.slice(desc, 0, 150) <> "..."
    else
      desc
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
            <h4 class="text-lg font-semibold text-gf-maroon">Quick Find & Edit</h4>
            <p class="text-sm text-gray-600 mt-1">
              Search by species name, source title, author, or description text.
            </p>
          </div>
          <%!-- Quick link to Add from Source --%>
          <div class="mt-4 text-center">
            <.link
              navigate={~p"/admin/species-sources/add"}
              class="text-sm hover:underline"
            >
              Need to add new mappings? Use Add from Source &rarr;
            </.link>
          </div>

          <div class="p-4">
            <%!-- Search Box --%>
            <div class="mb-6">
              <form phx-change="search" phx-submit="search" id="quick-find-search-form">
                <.search_input
                  id="quick-find-search"
                  name="query"
                  value={@search_query}
                  placeholder="Search mappings..."
                  phx-debounce="300"
                />
              </form>
            </div>

            <%!-- Results --%>
            <%= if @searched do %>
              <div class="mb-2 text-sm text-gray-600">
                Found {@results |> length()} mapping(s)
              </div>

              <%= if @results == [] do %>
                <p class="text-gray-500 italic py-4">No mappings found matching your search.</p>
              <% else %>
                <div class="space-y-2">
                  <div
                    :for={result <- @results}
                    class={[
                      "border rounded",
                      @editing_id == result.id && "border-gf-maroon bg-amber-50",
                      @editing_id != result.id && "border-gray-200 hover:border-gray-300"
                    ]}
                  >
                    <%!-- Result Header (always visible) --%>
                    <div
                      class={[
                        "px-4 py-3 cursor-pointer",
                        @editing_id != result.id && "hover:bg-gray-50"
                      ]}
                      phx-click="edit"
                      phx-value-id={result.id}
                    >
                      <div class="flex justify-between items-start">
                        <div class="flex-1">
                          <div class="font-medium text-gray-900 italic">
                            {result.species_name}
                          </div>
                          <div class="text-sm text-gray-600">
                            {result.source_title}
                            <span class="text-gray-400">
                              ({result.source_author}, {result.source_pubyear})
                            </span>
                          </div>
                          <div
                            :if={
                              result.description && result.description != "" &&
                                @editing_id != result.id
                            }
                            class="text-sm text-gray-500 mt-1"
                          >
                            {truncate_description(result.description)}
                          </div>
                        </div>
                        <div class="flex items-center gap-2 ml-4">
                          <span
                            :if={result.useasdefault}
                            class="text-xs bg-green-100 text-green-800 px-2 py-0.5 rounded"
                          >
                            default
                          </span>
                          <span class="text-xs text-gray-400">{result.species_taxoncode}</span>
                        </div>
                      </div>
                    </div>

                    <%!-- Edit Form (shown when editing) --%>
                    <div
                      :if={@editing_id == result.id}
                      class="px-4 pb-4 border-t border-gray-200 bg-white"
                    >
                      <.form
                        for={@form}
                        id={"edit-form-#{result.id}"}
                        phx-change="validate"
                        phx-submit="save"
                        class="mt-4"
                      >
                        <div class="space-y-4">
                          <div>
                            <label class="gf-label">
                              Description:
                            </label>
                            <.input
                              field={@form[:description]}
                              type="textarea"
                              rows={5}
                              class="w-full"
                            />
                          </div>

                          <div>
                            <label class="gf-label">
                              External Link:
                            </label>
                            <.input
                              field={@form[:externallink]}
                              type="url"
                              placeholder="https://..."
                              class="w-full"
                            />
                          </div>

                          <.input
                            type="checkbox"
                            field={@form[:useasdefault]}
                            label="Use as default source for this species"
                          />

                          <div class="flex justify-between items-center pt-3 border-t border-gray-200">
                            <button
                              type="button"
                              phx-click="delete"
                              data-confirm="Are you sure you want to delete this mapping?"
                              class="text-sm text-red-600 hover:text-red-800"
                            >
                              Delete
                            </button>
                            <div class="flex gap-2">
                              <button
                                type="button"
                                phx-click="cancel_edit"
                                class="px-3 py-1.5 text-sm text-gray-600 hover:text-gray-800"
                              >
                                Cancel
                              </button>
                              <button
                                type="submit"
                                class="px-3 py-1.5 text-sm bg-gf-maroon text-white rounded hover:bg-gf-maroon/90"
                              >
                                Save
                              </button>
                            </div>
                          </div>
                        </div>
                      </.form>
                    </div>
                  </div>
                </div>
              <% end %>
            <% else %>
              <p class="text-gray-500 text-center py-8">
                Enter a search term to find species-source mappings.
              </p>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
