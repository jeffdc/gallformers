defmodule GallformersWeb.Admin.PowoDiffReview do
  @moduledoc """
  LiveComponent that owns the POWO diff review UI lifecycle.

  Renders a selectable tree for each non-empty diff bucket, allowing the user
  to cherry-pick which POWO-WCVP changes to apply to a host's range.

  ## Props

  - `diff` — from `Plants.compute_powo_diff/3`
  - `place_by_code` — `%{code => %{name: _, ...}}`

  ## Messages sent to parent

  - `{PowoDiffReview, {:apply, selections}}` — map of MapSets per bucket
  - `{PowoDiffReview, :cancel}` — dismiss the diff
  """
  use GallformersWeb, :live_component

  import GallformersWeb.BrowseHelpers, only: [toggle_set: 2, toggle_group_selection: 3]

  @buckets ~w(add_native add_introduced remove reclassify_to_introduced reclassify_to_native)a

  @bucket_config %{
    add_native: %{
      label: "+ Native places in WCVP but not in current range",
      container_class: "bg-green-50 border border-green-200 rounded p-3",
      text_class: "text-green-700",
      heading_class: "text-green-800",
      checkbox_class: "text-green-600 focus:ring-green-500"
    },
    add_introduced: %{
      label: "+ Introduced places in WCVP but not in current range",
      container_class: "border border-green-200 rounded p-3",
      container_style:
        "background: repeating-linear-gradient(-45deg, #dcfce7, #dcfce7 3px, #bbf7d0 3px, #bbf7d0 6px)",
      text_class: "text-green-700",
      heading_class: "text-green-800",
      checkbox_class: "text-green-600 focus:ring-green-500"
    },
    remove: %{
      label: "- Places in current range but not in WCVP",
      container_class: "bg-red-50 border border-red-200 rounded p-3",
      text_class: "text-red-700",
      heading_class: "text-red-800",
      checkbox_class: "text-red-600 focus:ring-red-500"
    },
    reclassify_to_introduced: %{
      label: "Reclassify: WCVP says introduced (currently native)",
      container_class: "border border-green-200 rounded p-3",
      container_style:
        "background: repeating-linear-gradient(-45deg, #dcfce7, #dcfce7 3px, #bbf7d0 3px, #bbf7d0 6px)",
      text_class: "text-green-700",
      heading_class: "text-green-800",
      checkbox_class: "text-green-600 focus:ring-green-500"
    },
    reclassify_to_native: %{
      label: "Reclassify: WCVP says native (currently introduced)",
      container_class: "bg-green-50 border border-green-200 rounded p-3",
      text_class: "text-green-700",
      heading_class: "text-green-800",
      checkbox_class: "text-green-600 focus:ring-green-500"
    }
  }

  @impl true
  def update(%{diff: diff, place_by_code: place_by_code} = assigns, socket) do
    if socket.assigns[:diff] != diff do
      {:ok,
       socket
       |> assign(:id, assigns.id)
       |> assign(:diff, diff)
       |> assign(:place_by_code, place_by_code)
       |> init_selections(diff)
       |> init_groups(diff, place_by_code)}
    else
      {:ok, assign(socket, assigns)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="border border-blue-200 rounded-lg p-4 bg-blue-50">
      <h4 class="font-medium mb-2">POWO-WCVP Data Comparison</h4>

      <div :if={!@diff.has_changes} class="text-sm text-gray-600">
        No differences found. Host data matches WCVP.
      </div>

      <div :if={@diff.has_changes} class="text-sm space-y-3">
        <.bucket_tree
          :for={bucket <- @active_buckets}
          bucket={bucket}
          groups={Map.get(assigns, groups_field(bucket))}
          selected={Map.get(assigns, selected_field(bucket))}
          expanded={section_expanded(@expanded_countries, Atom.to_string(bucket))}
          myself={@myself}
        />
      </div>

      <p :if={@diff.agree_count > 0} class="text-sm text-gray-500 mt-2">
        {@diff.agree_count} places match — no changes needed
      </p>

      <div class="mt-3 flex gap-2">
        <.button
          :if={@diff.has_changes}
          phx-click="apply"
          phx-target={@myself}
          type="button"
          size="sm"
          disabled={!has_any_selections?(assigns)}
        >
          Apply Selected Changes
        </.button>
        <.button
          phx-click="cancel"
          phx-target={@myself}
          type="button"
          variant="secondary"
          size="sm"
        >
          Cancel
        </.button>
      </div>
    </div>
    """
  end

  defp bucket_tree(assigns) do
    config = Map.get(@bucket_config, assigns.bucket)
    bid = bucket_id(assigns.bucket)
    has_style = Map.has_key?(config, :container_style)

    assigns =
      assigns
      |> assign(:config, config)
      |> assign(:tree_id, "powo-#{bid}")
      |> assign(:has_style, has_style)
      |> assign(:toggle_item_event, "toggle_item_#{bid}")
      |> assign(:toggle_group_event, "toggle_group_#{bid}")
      |> assign(:expand_group_event, "expand_group_#{bid}")
      |> assign(:select_all_event, "select_all_#{bid}")
      |> assign(:deselect_all_event, "deselect_all_#{bid}")

    ~H"""
    <div :if={@has_style} style={@config.container_style} class={@config.container_class}>
      <.selectable_tree
        id={@tree_id}
        label={@config.label}
        groups={@groups}
        selected={@selected}
        expanded={@expanded}
        toggle_item_event={@toggle_item_event}
        toggle_group_event={@toggle_group_event}
        expand_group_event={@expand_group_event}
        select_all_event={@select_all_event}
        deselect_all_event={@deselect_all_event}
        target={@myself}
        container_class=""
        text_class={@config.text_class}
        heading_class={@config.heading_class}
        checkbox_class={@config.checkbox_class}
      />
    </div>
    <.selectable_tree
      :if={!@has_style}
      id={@tree_id}
      label={@config.label}
      groups={@groups}
      selected={@selected}
      expanded={@expanded}
      toggle_item_event={@toggle_item_event}
      toggle_group_event={@toggle_group_event}
      expand_group_event={@expand_group_event}
      select_all_event={@select_all_event}
      deselect_all_event={@deselect_all_event}
      target={@myself}
      container_class={@config.container_class}
      text_class={@config.text_class}
      heading_class={@config.heading_class}
      checkbox_class={@config.checkbox_class}
    />
    """
  end

  # --- Event handlers ---

  # Per-bucket event handlers generated from bucket config.
  # Each bucket gets toggle_item, toggle_group, expand_group, select_all, deselect_all.

  for bucket <- @buckets do
    bid =
      case bucket do
        :add_native -> "add-native"
        :add_introduced -> "add-introduced"
        :remove -> "remove"
        :reclassify_to_introduced -> "reclassify-to-introduced"
        :reclassify_to_native -> "reclassify-to-native"
      end

    sel_field = :"selected_#{bucket}"
    grp_field = :"groups_#{bucket}"

    @impl true
    def handle_event(unquote("toggle_item_#{bid}"), %{"id" => code}, socket) do
      current = Map.get(socket.assigns, unquote(sel_field))
      {:noreply, assign(socket, unquote(sel_field), toggle_set(current, code))}
    end

    @impl true
    def handle_event(unquote("toggle_group_#{bid}"), %{"group" => country_code}, socket) do
      groups = Map.get(socket.assigns, unquote(grp_field))
      selected = Map.get(socket.assigns, unquote(sel_field))
      updated = toggle_group_selection(groups, selected, country_code)
      {:noreply, assign(socket, unquote(sel_field), updated)}
    end

    @impl true
    def handle_event(unquote("expand_group_#{bid}"), %{"group" => country_code}, socket) do
      expanded =
        toggle_set(socket.assigns.expanded_countries, {unquote(to_string(bucket)), country_code})

      {:noreply, assign(socket, :expanded_countries, expanded)}
    end

    @impl true
    def handle_event(unquote("select_all_#{bid}"), _params, socket) do
      groups = Map.get(socket.assigns, unquote(grp_field))
      all_ids = groups |> Enum.flat_map(& &1.items) |> MapSet.new(& &1.id)
      {:noreply, assign(socket, unquote(sel_field), all_ids)}
    end

    @impl true
    def handle_event(unquote("deselect_all_#{bid}"), _params, socket) do
      {:noreply, assign(socket, unquote(sel_field), MapSet.new())}
    end
  end

  @impl true
  def handle_event("apply", _params, socket) do
    selections = %{
      add_native: socket.assigns.selected_add_native,
      add_introduced: socket.assigns.selected_add_introduced,
      remove: socket.assigns.selected_remove,
      reclassify_to_introduced: socket.assigns.selected_reclassify_to_introduced,
      reclassify_to_native: socket.assigns.selected_reclassify_to_native
    }

    send(self(), {__MODULE__, {:apply, selections}})
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    send(self(), {__MODULE__, :cancel})
    {:noreply, socket}
  end

  # --- Private helpers ---

  defp init_selections(socket, diff) do
    Enum.reduce(@buckets, socket, fn bucket, sock ->
      codes = Map.get(diff, bucket, [])
      assign(sock, selected_field(bucket), MapSet.new(codes))
    end)
  end

  defp init_groups(socket, diff, place_by_code) do
    active_buckets =
      Enum.filter(@buckets, fn bucket ->
        Map.get(diff, bucket, []) != []
      end)

    socket =
      Enum.reduce(@buckets, socket, fn bucket, sock ->
        codes = Map.get(diff, bucket, [])
        assign(sock, groups_field(bucket), group_places_by_country(codes, place_by_code))
      end)

    socket
    |> assign(:active_buckets, active_buckets)
    |> assign(:expanded_countries, MapSet.new())
  end

  defp selected_field(:add_native), do: :selected_add_native
  defp selected_field(:add_introduced), do: :selected_add_introduced
  defp selected_field(:remove), do: :selected_remove
  defp selected_field(:reclassify_to_introduced), do: :selected_reclassify_to_introduced
  defp selected_field(:reclassify_to_native), do: :selected_reclassify_to_native

  defp groups_field(:add_native), do: :groups_add_native
  defp groups_field(:add_introduced), do: :groups_add_introduced
  defp groups_field(:remove), do: :groups_remove
  defp groups_field(:reclassify_to_introduced), do: :groups_reclassify_to_introduced
  defp groups_field(:reclassify_to_native), do: :groups_reclassify_to_native

  defp bucket_id(:add_native), do: "add-native"
  defp bucket_id(:add_introduced), do: "add-introduced"
  defp bucket_id(:remove), do: "remove"
  defp bucket_id(:reclassify_to_introduced), do: "reclassify-to-introduced"
  defp bucket_id(:reclassify_to_native), do: "reclassify-to-native"

  defp section_expanded(expanded_countries, section) do
    expanded_countries
    |> Enum.filter(fn {s, _} -> s == section end)
    |> MapSet.new(fn {_, country} -> country end)
  end

  defp has_any_selections?(assigns) do
    Enum.any?(@buckets, fn bucket ->
      MapSet.size(Map.get(assigns, selected_field(bucket))) > 0
    end)
  end

  defp place_display(code, place_by_code) do
    case Map.get(place_by_code, code) do
      %{name: name} -> "#{name} (#{code})"
      nil -> code
    end
  end

  defp group_places_by_country(codes, place_by_code) do
    codes
    |> Enum.group_by(fn code ->
      case String.split(code, "-", parts: 2) do
        [country, _region] -> country
        [bare] -> bare
      end
    end)
    |> Enum.map(fn {country_code, group_codes} ->
      country_name =
        case Map.get(place_by_code, country_code) do
          %{name: name} -> name
          nil -> country_code
        end

      items =
        group_codes
        |> Enum.sort()
        |> Enum.map(fn code -> %{id: code, label: place_display(code, place_by_code)} end)

      %{id: country_code, label: country_name, items: items}
    end)
    |> Enum.sort_by(& &1.label)
  end
end
