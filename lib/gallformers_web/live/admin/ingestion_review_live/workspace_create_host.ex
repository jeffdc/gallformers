defmodule GallformersWeb.Admin.IngestionReviewLive.WorkspaceCreateHost do
  use GallformersWeb, :live_component

  alias Gallformers.Places
  alias Gallformers.Plants
  alias Gallformers.Ranges
  alias Gallformers.Taxonomy
  alias Gallformers.Wcvp

  defp wcvp_lookup do
    Application.get_env(:gallformers, :wcvp_lookup, Wcvp.Lookup)
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    # Initialize once, then auto-run WCVP search if available.
    if socket.assigns[:initialized] do
      {:ok, socket}
    else
      socket =
        socket
        |> assign(:initialized, true)
        |> assign(:wcvp_available, wcvp_lookup().available?())
        |> assign(:wcvp_results, [])
        |> assign(:wcvp_searching, false)
        |> assign(:wcvp_selected, nil)
        |> assign(:wcvp_loading, false)
        |> assign(:error_message, nil)

      {:ok, maybe_start_wcvp_search(socket, assigns.name)}
    end
  end

  defp maybe_start_wcvp_search(socket, name) do
    if socket.assigns.wcvp_available and is_binary(name) and String.length(name) >= 2 do
      socket
      |> assign(:wcvp_searching, true)
      |> start_async(:wcvp_search, fn ->
        wcvp_lookup().search(name, limit: 10)
      end)
    else
      socket
    end
  end

  @impl true
  def handle_async(:wcvp_search, {:ok, results}, socket) do
    {:noreply,
     socket
     |> assign(:wcvp_searching, false)
     |> assign(:wcvp_results, results)}
  end

  def handle_async(:wcvp_search, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:wcvp_searching, false)
     |> assign(:wcvp_results, [])}
  end

  def handle_async(:wcvp_select, {:ok, data}, socket) do
    {:noreply,
     socket
     |> assign(:wcvp_loading, false)
     |> assign(:wcvp_selected, data)}
  end

  def handle_async(:wcvp_select, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :wcvp_loading, false)}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    send(self(), {:cancel_create_host})
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_wcvp", %{"id" => plant_name_id}, socket) do
    {:noreply,
     socket
     |> assign(:wcvp_loading, true)
     |> start_async(:wcvp_select, fn -> wcvp_lookup().get(plant_name_id) end)}
  end

  @impl true
  def handle_event("create_host", _params, socket) do
    name = socket.assigns.name
    wcvp = socket.assigns.wcvp_selected
    index = socket.assigns.index

    case create_host(name, wcvp) do
      {:ok, host} ->
        send(self(), {:host_created_and_mapped, index, host})
        {:noreply, socket}

      {:error, message} ->
        {:noreply, assign(socket, :error_message, message)}
    end
  end

  defp create_host(name, wcvp) do
    plant_family_ids =
      Taxonomy.list_families_for_select(:plant)
      |> MapSet.new(fn {_name, id} -> id end)

    raw_taxonomy = Taxonomy.lookup_taxonomy_for_new_species(name)

    %{taxonomy: taxonomy, family_id: resolved_family_id} =
      Taxonomy.resolve_taxonomy_for_species(raw_taxonomy, plant_family_ids)

    family_id = resolve_wcvp_family_id(wcvp) || resolved_family_id

    with {:ok, family_id} <- ensure_family_id(family_id, name),
         create_params = %{
           species_attrs: %{"name" => name, "taxoncode" => "plant"},
           taxonomy: taxonomy,
           parent_id: family_id,
           aliases: []
         },
         {:ok, host} <- Plants.create_host_with_associations(create_params) do
      if wcvp, do: persist_wcvp_data(host.id, wcvp)
      {:ok, host}
    end
  end

  defp ensure_family_id(nil, name), do: {:error, "Could not resolve a family for #{name}."}
  defp ensure_family_id(id, _name), do: {:ok, id}

  defp resolve_wcvp_family_id(nil), do: nil

  defp resolve_wcvp_family_id(wcvp) do
    case Enum.find(Taxonomy.list_families_for_select(:plant), fn {name, _id} ->
           name == wcvp.family
         end) do
      {_name, id} ->
        id

      nil ->
        case Taxonomy.create_taxonomy(%{
               name: wcvp.family,
               type: "family",
               description: "Plant"
             }) do
          {:ok, family} -> family.id
          {:error, _} -> nil
        end
    end
  end

  defp persist_wcvp_data(host_id, wcvp) do
    Plants.upsert_host_traits(host_id, %{
      wcvp_id: wcvp.plant_name_id,
      powo_id: wcvp.powo_id,
      wcvp_synced_at: DateTime.utc_now(:second)
    })

    place_entries = wcvp_place_entries(wcvp)
    if place_entries != [], do: Ranges.update_host_places(host_id, place_entries)
  end

  defp wcvp_place_entries(wcvp) do
    tdwg_lookup = Wcvp.Tdwg.load()

    native =
      wcvp.native_distribution
      |> Wcvp.Tdwg.convert_tdwg_codes(tdwg_lookup)
      |> Enum.map(&Map.put(&1, :distribution_type, "native"))

    introduced =
      wcvp.introduced_distribution
      |> Wcvp.Tdwg.convert_tdwg_codes(tdwg_lookup)
      |> Enum.map(&Map.put(&1, :distribution_type, "introduced"))

    place_by_code = Map.new(Places.list_all_places(), &{&1.code, &1})

    (native ++ introduced)
    |> Enum.flat_map(fn entry ->
      case Map.get(place_by_code, entry.code) do
        nil -> []
        place -> [{place.id, entry.precision, entry.distribution_type}]
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="workspace-create-host" class="space-y-4">
      <div>
        <label class="gf-label">Name</label>
        <input
          type="text"
          name="name"
          value={@name}
          class="gf-input"
          autocomplete="off"
        />
      </div>

      <div :if={@wcvp_available && is_nil(@wcvp_selected)}>
        <div class="text-xs font-medium uppercase tracking-wide text-gray-500 mb-2">
          POWO/WCVP matches
        </div>
        <div :if={@wcvp_searching || @wcvp_loading} class="text-sm text-gray-500">
          Searching WCVP...
        </div>
        <div
          :if={!@wcvp_searching && !@wcvp_loading && @wcvp_results == []}
          class="text-sm text-gray-500"
        >
          No WCVP match. Host will be created without range data; edit later from the host admin.
        </div>
        <ul :if={@wcvp_results != []} class="rounded border border-gray-200 divide-y divide-gray-100">
          <li
            :for={result <- @wcvp_results}
            class="px-3 py-2 text-sm flex items-center gap-2"
          >
            <span class="font-medium italic">{result.taxon_name}</span>
            <span class="text-gray-500">{result.taxon_authors}</span>
            <span class="text-xs text-gray-400 ml-auto mr-2">{result.family}</span>
            <button
              type="button"
              phx-click="select_wcvp"
              phx-value-id={result.plant_name_id}
              phx-target={@myself}
              class="text-xs text-gf-maroon hover:underline"
            >
              Use
            </button>
          </li>
        </ul>
      </div>

      <div
        :if={@wcvp_selected}
        class="rounded border border-green-200 bg-green-50 px-3 py-3 text-sm space-y-1"
      >
        <div class="text-xs font-medium uppercase tracking-wide text-green-700">Selected match</div>
        <div>
          <span class="font-medium italic">{@wcvp_selected.taxon_name}</span>
          <span class="text-gray-500 ml-1">{@wcvp_selected.taxon_authors}</span>
        </div>
        <div class="text-xs text-gray-600">
          Family <span class="font-medium">{@wcvp_selected.family}</span>
          · {length(@wcvp_selected.native_distribution)} native
          <span :if={@wcvp_selected.introduced_distribution != []}>
            · {length(@wcvp_selected.introduced_distribution)} introduced
          </span>
        </div>
      </div>

      <div
        :if={!@wcvp_available}
        class="text-sm text-amber-700 bg-amber-50 border border-amber-200 rounded px-3 py-2"
      >
        WCVP not available. Host will be created without range data; edit later from the host admin.
      </div>

      <div
        :if={@error_message}
        class="text-sm text-red-700 bg-red-50 border border-red-200 rounded px-3 py-2"
      >
        {@error_message}
      </div>

      <div class="flex justify-end gap-2 pt-4 border-t border-gray-200">
        <button
          type="button"
          phx-click="cancel"
          phx-target={@myself}
          class="gf-btn gf-btn-soft"
        >
          Cancel
        </button>
        <button
          type="button"
          phx-click="create_host"
          phx-target={@myself}
          class="gf-btn gf-btn-primary"
        >
          Create host
        </button>
      </div>
    </div>
    """
  end
end
