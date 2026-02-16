defmodule GallformersWeb.Admin.GallLive.Undescribed do
  @moduledoc """
  LiveView for the undescribed gall creation workflow.

  This page guides users through creating a new undescribed gall by collecting:
  - Genus (if known) or Family (if genus unknown)
  - Type host
  - Description (2-3 adjectives)
  - Auto-generated name (editable)

  On "Continue", navigates to the gall form with pre-filled data.
  """
  use GallformersWeb, :live_view

  alias Gallformers.{Species, Taxonomy}
  alias Gallformers.Taxonomy.TaxonName

  @impl true
  def mount(params, session, socket) do
    current_user = session["current_user"]
    prefilled_description = Map.get(params, "description", "")

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Add Undescribed Gall")
      |> assign(:genera, Taxonomy.list_genera_for_select())
      |> assign(:families, Taxonomy.list_families_for_select(:gall))
      |> assign(:genus_known, false)
      |> assign(:genus_query, "")
      |> assign(:genus_results, [])
      |> assign(:selected_genus, nil)
      |> assign(:family_query, "")
      |> assign(:family_results, [])
      |> assign(:selected_family, nil)
      |> assign(:host_query, "")
      |> assign(:host_results, [])
      |> assign(:selected_host, nil)
      |> assign(:description, prefilled_description)
      |> assign(:name, "")
      |> assign(:error, nil)
      |> assign(:validating, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <div class="max-w-2xl mx-auto">
        <.link
          navigate={~p"/admin"}
          class="inline-flex items-center gap-1 text-sm text-gray-600 hover:text-gf-maroon mb-4"
        >
          <.icon name="ph-arrow-left" class="size-4" /> Back to Dashboard
        </.link>

        <div class="bg-white rounded-lg border border-gray-200 p-6">
          <h1 class="text-2xl font-bold text-gray-900 mb-6">Create a New Undescribed Gall</h1>

          <div class="space-y-6">
            <%!-- Error message --%>
            <div
              :if={@error}
              class="p-3 bg-red-50 border border-red-200 rounded-md text-red-700 text-sm"
            >
              {@error}
            </div>

            <%!-- Genus known checkbox --%>
            <div class="flex items-center gap-2">
              <input
                type="checkbox"
                id="genus-known"
                checked={@genus_known}
                phx-click="toggle_genus_known"
                class="h-4 w-4 text-gf-maroon border-gray-300 rounded focus:ring-gf-maroon"
              />
              <label for="genus-known" class="text-sm font-medium text-gray-700">
                Is this undescribed species part of a known Genus?
              </label>
            </div>

            <%!-- Genus typeahead (when genus is known) --%>
            <div :if={@genus_known}>
              <.typeahead
                id="undescribed-genus"
                label="Genus"
                placeholder="Search for genus..."
                search_event="search_genus"
                select_event="select_genus"
                clear_event="clear_genus"
                query={@genus_query}
                results={@genus_results}
                selected={@selected_genus}
                display_fn={fn g -> g.name end}
              />
              <p class="mt-1 text-sm text-gray-500">
                The genus, if it is known. Required if known.
              </p>
            </div>

            <%!-- Family typeahead (when genus is NOT known) --%>
            <div :if={!@genus_known}>
              <.typeahead
                id="undescribed-family"
                label="Family"
                placeholder="Search for family..."
                search_event="search_family"
                select_event="select_family"
                clear_event="clear_family"
                query={@family_query}
                results={@family_results}
                selected={@selected_family}
                display_fn={fn f -> f.name end}
              />
              <p class="mt-1 text-sm text-gray-500">
                The family. An "Unknown" genus will be created or used under this family.
              </p>
            </div>

            <%!-- Family display when genus is selected --%>
            <div :if={@genus_known && @selected_genus && @selected_family} class="space-y-1">
              <label class="gf-label">Family</label>
              <div class="p-2 bg-gray-50 rounded border text-gray-700 italic">
                {@selected_family.name}
              </div>
              <p class="text-sm text-gray-500">Auto-populated from selected genus.</p>
            </div>

            <%!-- Type Host typeahead --%>
            <div>
              <.typeahead
                id="undescribed-host"
                label="Type Host"
                placeholder="Search for host plant..."
                search_event="search_host"
                select_event="select_host"
                clear_event="clear_host"
                query={@host_query}
                results={@host_results}
                selected={@selected_host}
                display_fn={fn h -> h.name end}
              />
              <p class="mt-1 text-sm text-gray-500">
                The host that is the Type for this undescribed gall. Required.
              </p>
            </div>

            <%!-- Description --%>
            <div>
              <.input
                type="text"
                id="undescribed-description"
                name="description"
                value={@description}
                label="Description"
                placeholder="e.g., red-bead-gall"
                phx-hook="InputEvent"
                data-event="update_description"
              />
              <p class="mt-1 text-sm text-gray-500">
                2 or 3 adjectives separated by dashes, e.g., red-bead-gall
              </p>
            </div>

            <%!-- Generated Name (read-only) --%>
            <div>
              <label class="gf-label">Name</label>
              <input
                type="text"
                value={@name}
                disabled
                class="w-full px-3 py-2 bg-gray-100 border border-gray-300 rounded text-gray-700 text-sm"
              />
            </div>

            <%!-- Action Buttons --%>
            <div class="flex justify-end gap-3 pt-4 border-t">
              <.link
                navigate={~p"/admin"}
                class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
              >
                Cancel
              </.link>
              <.button
                type="button"
                variant="primary"
                phx-click="continue"
                disabled={!valid_for_continue?(assigns) || @validating}
              >
                <%= if @validating do %>
                  <.icon name="ph-spinner" class="animate-spin size-4 mr-2" />
                <% end %>
                Continue to Gall Form
              </.button>
            </div>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  # =================================================================
  # Event Handlers
  # =================================================================

  @impl true
  def handle_event("toggle_genus_known", _params, socket) do
    {:noreply,
     socket
     |> assign(:genus_known, !socket.assigns.genus_known)
     |> assign(:selected_genus, nil)
     |> assign(:genus_query, "")
     |> assign(:genus_results, [])
     |> assign(:selected_family, nil)
     |> assign(:family_query, "")
     |> assign(:family_results, [])
     |> assign(:error, nil)
     |> maybe_regenerate_name()}
  end

  # Genus search
  @impl true
  def handle_event("search_genus", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        socket.assigns.genera
        |> Enum.filter(fn g ->
          String.contains?(String.downcase(g.name), String.downcase(query))
        end)
        |> Enum.take(20)
      else
        []
      end

    {:noreply, assign(socket, genus_query: query, genus_results: results)}
  end

  @impl true
  def handle_event("select_genus", %{"id" => id}, socket) do
    genus_id = String.to_integer(id)
    genus = Enum.find(socket.assigns.genera, &(&1.id == genus_id))

    if genus do
      family = find_family_for_genus(genus, socket.assigns.families)

      {:noreply,
       socket
       |> assign(:selected_genus, genus)
       |> assign(:selected_family, family)
       |> assign(:genus_query, "")
       |> assign(:genus_results, [])
       |> assign(:error, nil)
       |> maybe_regenerate_name()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_genus", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_genus, nil)
     |> assign(:selected_family, nil)
     |> assign(:genus_query, "")
     |> assign(:genus_results, [])
     |> maybe_regenerate_name()}
  end

  # Family search
  @impl true
  def handle_event("search_family", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        socket.assigns.families
        |> Enum.filter(fn {name, _id} ->
          String.contains?(String.downcase(name), String.downcase(query))
        end)
        |> Enum.map(fn {name, id} -> %{id: id, name: name} end)
        |> Enum.take(20)
      else
        []
      end

    {:noreply, assign(socket, family_query: query, family_results: results)}
  end

  @impl true
  def handle_event("select_family", %{"id" => id}, socket) do
    family_id = String.to_integer(id)
    family = Enum.find(socket.assigns.family_results, &(&1.id == family_id))

    if family do
      {:noreply,
       socket
       |> assign(:selected_family, family)
       |> assign(:family_query, "")
       |> assign(:family_results, [])
       |> assign(:error, nil)
       |> maybe_regenerate_name()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_family", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_family, nil)
     |> assign(:family_query, "")
     |> assign(:family_results, [])
     |> maybe_regenerate_name()}
  end

  # Host search
  @impl true
  def handle_event("search_host", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Species.search_species_by_name(query, "plant", 20)
      else
        []
      end

    {:noreply, assign(socket, host_query: query, host_results: results)}
  end

  @impl true
  def handle_event("select_host", %{"id" => id}, socket) do
    host_id = String.to_integer(id)
    host = Enum.find(socket.assigns.host_results, &(&1.id == host_id))

    if host do
      {:noreply,
       socket
       |> assign(:selected_host, host)
       |> assign(:host_query, "")
       |> assign(:host_results, [])
       |> assign(:error, nil)
       |> maybe_regenerate_name()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_host", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_host, nil)
     |> assign(:host_query, "")
     |> assign(:host_results, [])
     |> maybe_regenerate_name()}
  end

  # Description update
  @impl true
  def handle_event("update_description", %{"value" => value}, socket) do
    {:noreply,
     socket
     |> assign(:description, value)
     |> assign(:error, nil)
     |> maybe_regenerate_name()}
  end

  # Continue - validate and navigate
  @impl true
  def handle_event("continue", _params, socket) do
    socket = assign(socket, :validating, true)
    name = String.trim(socket.assigns.name)

    with :ok <- validate_name_not_taken(name),
         :ok <- validate_genus_in_name(name, socket.assigns) do
      gallformers_code = TaxonName.parse(name).epithet

      query_string =
        URI.encode_query(%{
          species_name: name,
          host_id: to_string(socket.assigns.selected_host.id),
          undescribed: "true",
          gallformers_code: gallformers_code
        })

      {:noreply,
       socket
       |> assign(:validating, false)
       |> push_navigate(to: "/admin/galls/new?#{query_string}")}
    else
      {:error, message} ->
        {:noreply, socket |> assign(:validating, false) |> assign(:error, message)}
    end
  end

  # =================================================================
  # Private Helpers
  # =================================================================

  defp valid_for_continue?(assigns) do
    has_taxonomy =
      if assigns.genus_known do
        assigns.selected_genus != nil
      else
        assigns.selected_family != nil
      end

    has_taxonomy &&
      assigns.selected_host != nil &&
      String.trim(assigns.name) != ""
  end

  defp maybe_regenerate_name(socket) do
    assign(socket, :name, generate_name(socket.assigns))
  end

  defp generate_name(assigns) do
    genus_name = extract_genus_name(assigns)
    host_part = extract_host_part(assigns.selected_host)
    description = String.trim(assigns.description)

    combine_name_parts(genus_name, host_part, description)
  end

  defp extract_genus_name(%{genus_known: true, selected_genus: %{name: name}}), do: name

  defp extract_genus_name(%{genus_known: false, selected_family: family}) when family != nil,
    do: "Unknown (#{family.name})"

  defp extract_genus_name(_), do: nil

  defp extract_host_part(nil), do: nil

  defp extract_host_part(%{name: name}) do
    parsed = TaxonName.parse(name)

    if parsed.epithet do
      first_letter = String.downcase(String.first(parsed.genus))
      "#{first_letter}-#{parsed.epithet}"
    else
      String.downcase(name)
    end
  end

  defp combine_name_parts(nil, _, _), do: ""
  defp combine_name_parts(genus_name, nil, _), do: genus_name
  defp combine_name_parts(genus_name, host_part, ""), do: "#{genus_name} #{host_part}"
  defp combine_name_parts(genus_name, host_part, desc), do: "#{genus_name} #{host_part}-#{desc}"

  defp find_family_for_genus(%{family_id: nil}, _families), do: nil

  defp find_family_for_genus(%{family_id: family_id}, families) do
    case Enum.find(families, fn {_name, fid} -> fid == family_id end) do
      {name, id} -> %{id: id, name: name}
      nil -> nil
    end
  end

  defp validate_name_not_taken(name) do
    if Species.species_name_exists?(name) do
      {:error,
       "The name \"#{name}\" already exists. Please choose a different name or cancel and edit the existing gall."}
    else
      :ok
    end
  end

  defp validate_genus_in_name(name, %{genus_known: false, selected_family: family}) do
    expected_prefix = "Unknown (#{family.name})"

    if String.starts_with?(name, expected_prefix) do
      :ok
    else
      {:error,
       "Name must start with \"#{expected_prefix}\" for an undescribed gall in this family."}
    end
  end

  defp validate_genus_in_name(name, %{genus_known: true, selected_genus: genus}) do
    if String.starts_with?(name, genus.name <> " ") or name == genus.name do
      :ok
    else
      {:error, "Name must start with the selected genus \"#{genus.name}\"."}
    end
  end
end
