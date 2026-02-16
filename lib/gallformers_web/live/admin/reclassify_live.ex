defmodule GallformersWeb.Admin.ReclassifyLive do
  @moduledoc """
  LiveComponent for the rename/reclassify modal.

  Owns all reclassify state internally and renders the shared
  `FormComponents.reclassify_modal/1` function component.

  ## Required assigns (from parent)

    * `:species_id` - ID of the species being reclassified
    * `:species_name` - current name of the species
    * `:current_family` - `%{id, name}` or nil
    * `:current_genus` - `%{id, name, is_placeholder}` or nil
    * `:entity_type` - "Gall" or "Host"
    * `:is_gall` - boolean, enables undescribed alias options

  ## Messages sent to parent

    * `{:reclassify_complete, %{species: updated_species, name_changed?: bool, add_alias?: bool}}`
    * `{:reclassify_error, reason}`
  """
  use GallformersWeb, :live_component

  alias Gallformers.Species
  alias Gallformers.Taxonomy
  alias Gallformers.Taxonomy.TaxonName

  # -------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> sync_parent_assigns(assigns)
      |> init_component_state()

    {:ok, socket}
  end

  # Overwrites on every update/2 call to stay in sync with the parent.
  defp sync_parent_assigns(socket, assigns) do
    socket
    |> assign(:id, assigns.id)
    |> assign(:species_id, assigns[:species_id])
    |> assign(:species_name, assigns[:species_name])
    |> assign(:current_family, assigns[:current_family])
    |> assign(:current_genus, assigns[:current_genus])
    |> assign(:entity_type, assigns[:entity_type])
    |> assign(:is_gall, assigns[:is_gall] || false)
    |> assign(:undescribed, assigns[:undescribed] || false)
  end

  # Sets component-internal state only on first mount; preserved across updates.
  defp init_component_state(socket) do
    socket
    |> assign_new(:show, fn -> false end)
    |> assign_new(:family_query, fn -> "" end)
    |> assign_new(:family_results, fn -> [] end)
    |> assign_new(:selected_family, fn -> nil end)
    |> assign_new(:genus_query, fn -> "" end)
    |> assign_new(:genus_results, fn -> [] end)
    |> assign_new(:selected_genus, fn -> nil end)
    |> assign_new(:epithet, fn -> "" end)
    |> assign_new(:add_alias_on_rename, fn -> true end)
    |> assign_new(:rename_collisions, fn -> [] end)
  end

  defp open_modal(socket) do
    taxonomy_genus = resolve_current_genus(socket.assigns.current_genus)
    epithet = Taxonomy.extract_epithet(socket.assigns.species_name)

    socket
    |> assign(:show, true)
    |> assign(:family_query, "")
    |> assign(:family_results, [])
    |> assign(:selected_family, socket.assigns.current_family)
    |> assign(:genus_query, "")
    |> assign(:genus_results, [])
    |> assign(:selected_genus, taxonomy_genus)
    |> assign(:epithet, epithet)
    |> assign(:add_alias_on_rename, true)
    |> assign(:rename_collisions, [])
  end

  defp resolve_current_genus(nil), do: nil

  defp resolve_current_genus(%{id: genus_id} = genus_info) do
    # Fetch from DB to get is_placeholder (not available in taxonomy map)
    case Taxonomy.get_taxonomy(genus_id) do
      %{id: id, name: name, is_placeholder: is_placeholder} ->
        %{id: id, name: name, is_placeholder: is_placeholder}

      _ ->
        # Fall back to what the parent provided (missing is_placeholder)
        if Map.has_key?(genus_info, :name),
          do: %{id: genus_id, name: genus_info.name, is_placeholder: false},
          else: nil
    end
  end

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.reclassify_modal
        show={@show}
        target={@myself}
        entity_type={@entity_type}
        family_query={@family_query}
        family_results={@family_results}
        selected_family={@selected_family}
        genus_query={@genus_query}
        genus_results={@genus_results}
        selected_genus={@selected_genus}
        epithet={@epithet}
        add_alias_checked={@add_alias_on_rename}
        rename_collisions={@rename_collisions}
        is_gall={@is_gall}
      />
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Event handlers
  # -------------------------------------------------------------------

  @impl true
  def handle_event("open_reclassify_modal", _params, socket) do
    {:noreply, open_modal(socket)}
  end

  @impl true
  def handle_event("close_reclassify_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show, false)
     |> assign(:rename_collisions, [])}
  end

  @impl true
  def handle_event("reclassify_search_family", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 1 do
        Taxonomy.search_families(query, taxoncode: taxoncode_for(socket))
      else
        []
      end

    {:noreply,
     socket
     |> assign(:family_query, query)
     |> assign(:family_results, results)}
  end

  @impl true
  def handle_event("reclassify_select_family", %{"id" => id}, socket) do
    family_id = String.to_integer(id)
    family = Enum.find(socket.assigns.family_results, &(&1.id == family_id))

    if family do
      {:noreply,
       socket
       |> assign(:selected_family, family)
       |> assign(:family_query, "")
       |> assign(:family_results, [])
       |> assign(:selected_genus, nil)
       |> assign(:genus_query, "")
       |> assign(:genus_results, [])}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reclassify_clear_family", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_family, nil)
     |> assign(:family_query, "")
     |> assign(:family_results, [])
     |> assign(:selected_genus, nil)
     |> assign(:genus_query, "")
     |> assign(:genus_results, [])}
  end

  @impl true
  def handle_event("reclassify_search_genus", %{"value" => query}, socket) do
    family_id = socket.assigns.selected_family && socket.assigns.selected_family.id

    results =
      if String.length(query) >= 1 && family_id do
        Taxonomy.search_genera(query, family_id, taxoncode: taxoncode_for(socket))
      else
        []
      end

    {:noreply,
     socket
     |> assign(:genus_query, query)
     |> assign(:genus_results, results)}
  end

  @impl true
  def handle_event("reclassify_select_genus", %{"id" => id}, socket) do
    genus_id = String.to_integer(id)
    genus = Enum.find(socket.assigns.genus_results, &(&1.id == genus_id))

    if genus do
      {:noreply,
       socket
       |> assign(:selected_genus, genus)
       |> assign(:genus_query, "")
       |> assign(:genus_results, [])}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reclassify_clear_genus", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_genus, nil)
     |> assign(:genus_query, "")
     |> assign(:genus_results, [])}
  end

  @impl true
  def handle_event("update_reclassify_epithet", %{"value" => value}, socket) do
    genus = socket.assigns.selected_genus
    epithet = String.trim(value)

    collisions =
      if genus && String.length(epithet) >= 2 do
        full_name = compute_name(genus, epithet, socket.assigns.selected_family)
        Species.find_species_with_alias(full_name)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:epithet, value)
     |> assign(:rename_collisions, collisions)}
  end

  @impl true
  def handle_event("toggle_add_alias_on_rename", _params, socket) do
    {:noreply, assign(socket, :add_alias_on_rename, !socket.assigns.add_alias_on_rename)}
  end

  @impl true
  def handle_event("do_reclassify", _params, %{assigns: %{selected_genus: nil}} = socket) do
    send(self(), {:reclassify_flash, :error, "Please select a genus"})
    {:noreply, socket}
  end

  def handle_event("do_reclassify", _params, socket) do
    %{
      selected_genus: selected_genus,
      selected_family: selected_family,
      species_id: species_id,
      epithet: raw_epithet,
      add_alias_on_rename: add_alias?,
      species_name: old_name,
      current_genus: current_genus
    } = socket.assigns

    epithet = String.trim(raw_epithet)
    genus_id = Taxonomy.resolve_genus_id(selected_genus, selected_family)
    new_name = compute_name(selected_genus, epithet, selected_family)
    current_genus_id = current_genus && current_genus.id
    genus_changed? = genus_id != current_genus_id
    name_changed? = new_name != old_name

    cond do
      not genus_changed? and not name_changed? ->
        send(self(), {:reclassify_flash, :info, "No changes made"})
        {:noreply, assign(socket, :show, false)}

      epithet == "" ->
        send(self(), {:reclassify_flash, :error, "Epithet cannot be empty"})
        {:noreply, socket}

      true ->
        execute_reclassify(socket, species_id, genus_id, new_name, old_name,
          genus_changed?: genus_changed?,
          name_changed?: name_changed?,
          add_alias?: add_alias?
        )
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp execute_reclassify(socket, species_id, genus_id, new_name, old_name, opts) do
    params = %{
      genus_id: genus_id,
      new_name: new_name,
      old_name: old_name,
      genus_changed?: opts[:genus_changed?],
      name_changed?: opts[:name_changed?],
      add_alias?: opts[:add_alias?]
    }

    result = Taxonomy.reclassify_species(species_id, params)
    handle_reclassify_result(socket, result, opts[:name_changed?], opts[:add_alias?])
  end

  defp handle_reclassify_result(socket, {:ok, species}, name_changed?, add_alias?) do
    send(
      self(),
      {:reclassify_complete,
       %{species: species, name_changed?: name_changed?, add_alias?: add_alias?}}
    )

    {:noreply, assign(socket, :show, false)}
  end

  defp handle_reclassify_result(socket, {:error, :name_exists}, _, _) do
    send(self(), {:reclassify_flash, :error, "That name is already in use"})
    {:noreply, socket}
  end

  defp handle_reclassify_result(socket, {:error, reason}, _, _) do
    send(self(), {:reclassify_flash, :error, "Failed to update: #{inspect(reason)}"})
    {:noreply, socket}
  end

  defp compute_name(%{is_placeholder: true}, epithet, selected_family) do
    family_name = if selected_family, do: selected_family.name, else: "Unknown"
    TaxonName.build("Unknown (#{family_name})", epithet)
  end

  defp compute_name(genus, epithet, _selected_family) do
    TaxonName.build(genus.name, epithet)
  end

  defp taxoncode_for(%{assigns: %{is_gall: true}}), do: "gall"
  defp taxoncode_for(_socket), do: "plant"
end
