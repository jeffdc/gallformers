defmodule GallformersWeb.Admin.PowoDiffReview do
  @moduledoc """
  LiveComponent that owns the POWO diff review UI lifecycle.

  Renders a selectable tree for each non-empty diff bucket, allowing the user
  to cherry-pick which POWO-WCVP changes to apply to a host's range.

  ## Props

  - `diff` — from `Gallformers.Ranges.Wcvp.compute_powo_diff/3`
  - `place_by_code` — `%{code => %{name: _, ...}}`

  ## Messages sent to parent

  - `{PowoDiffReview, {:apply, selections}}` — map of MapSets per bucket
  - `{PowoDiffReview, :cancel}` — dismiss the diff
  """
  use GallformersWeb, :live_component

  import GallformersWeb.BrowseHelpers, only: [toggle_set: 2, toggle_group_selection: 3]

  @default_buckets ~w(
    add_native
    add_introduced
    remove
    reclassify_to_introduced
    reclassify_to_native
  )a

  @default_bucket_config %{
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
      checkbox_class: "text-red-600 focus:ring-red-500",
      mode: :review_remove,
      selection_noun: "kept",
      select_all_label: "Include all",
      deselect_all_label: "Exclude all",
      help_text:
        "These places were added before this WCVP sync. Review each for correct native/introduced status. Use the badge to toggle classification."
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
    buckets = Map.get(assigns, :buckets, @default_buckets)
    bucket_config = merge_bucket_config(Map.get(assigns, :bucket_config, %{}))
    default_selections = Map.get(assigns, :default_selections, %{})
    special_remove_bucket = Enum.find(buckets, &review_remove_bucket?(&1, bucket_config))

    base_assigns =
      assigns
      |> Map.put(:buckets, buckets)
      |> Map.put(:bucket_config, bucket_config)
      |> Map.put(:default_selections, default_selections)
      |> Map.put(:special_remove_bucket, special_remove_bucket)
      |> Map.put(:title, Map.get(assigns, :title, "POWO-WCVP Data Comparison"))
      |> Map.put(
        :empty_message,
        Map.get(assigns, :empty_message, "No differences found. Host data matches WCVP.")
      )
      |> Map.put(:apply_label, Map.get(assigns, :apply_label, "Apply Selected Changes"))

    if socket.assigns[:diff] != diff do
      {:ok,
       socket
       |> assign(base_assigns)
       |> assign(:id, assigns.id)
       |> assign(:diff, diff)
       |> assign(:place_by_code, place_by_code)
       |> init_selections(diff, buckets, default_selections)
       |> init_groups(diff, place_by_code, buckets)}
    else
      {:ok, assign(socket, base_assigns)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="border border-blue-200 rounded-lg p-4 bg-blue-50">
      <h4 class="font-medium mb-2">{@title}</h4>

      <div :if={!@diff.has_changes} class="text-sm text-gray-600">
        {@empty_message}
      </div>

      <div :if={@diff.has_changes} class="text-sm space-y-3">
        <.bucket_tree
          :for={bucket <- Enum.reject(@active_buckets, &(&1 == @special_remove_bucket))}
          bucket={bucket}
          bucket_config={@bucket_config}
          groups={Map.get(assigns, groups_field(bucket))}
          selected={Map.get(assigns, selected_field(bucket))}
          expanded={section_expanded(@expanded_countries, Atom.to_string(bucket))}
          myself={@myself}
        />
        <.remove_bucket
          :if={@special_remove_bucket && Map.get(@diff, @special_remove_bucket, []) != []}
          bucket={@special_remove_bucket}
          config={Map.fetch!(@bucket_config, @special_remove_bucket)}
          groups={Map.get(assigns, groups_field(@special_remove_bucket))}
          selected={Map.get(assigns, selected_field(@special_remove_bucket))}
          introduced={@remove_as_introduced}
          expanded={section_expanded(@expanded_countries, Atom.to_string(@special_remove_bucket))}
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
          {@apply_label}
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
    config = Map.fetch!(assigns.bucket_config, assigns.bucket)
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

  defp remove_bucket(assigns) do
    bid = bucket_id(assigns.bucket)
    total_items = Enum.reduce(assigns.groups, 0, fn g, acc -> acc + length(g.items) end)

    kept_count =
      Enum.reduce(assigns.groups, 0, fn g, acc ->
        acc + Enum.count(g.items, &MapSet.member?(assigns.selected, &1.id))
      end)

    introduced_count = MapSet.size(MapSet.intersection(assigns.introduced, assigns.selected))
    removed_count = total_items - kept_count
    all_selected = total_items > 0 and kept_count == total_items

    assigns =
      assigns
      |> assign(:bid, bid)
      |> assign(:total_items, total_items)
      |> assign(:kept_count, kept_count)
      |> assign(:introduced_count, introduced_count)
      |> assign(:removed_count, removed_count)
      |> assign(:all_selected, all_selected)

    ~H"""
    <div id={"powo-#{@bid}"} class={@config.container_class}>
      <div class="flex items-center justify-between">
        <span class={["font-medium", @config.heading_class]}>
          {@config.label} ({@kept_count}/{@total_items} {@config.selection_noun})
        </span>
        <button
          type="button"
          phx-click={if @all_selected, do: "deselect_all_#{@bid}", else: "select_all_#{@bid}"}
          phx-target={@myself}
          class={["text-xs hover:underline", @config.text_class]}
        >
          {if @all_selected, do: @config.deselect_all_label, else: @config.select_all_label}
        </button>
      </div>

      <p :if={@config[:help_text]} class={["text-xs mt-1 mb-2", @config.text_class]}>
        <.icon name="ph-warning" class="h-3.5 w-3.5 inline-block align-text-bottom" />
        {@config.help_text}
      </p>

      <p :if={@introduced_count > 0 or @removed_count > 0} class="text-xs text-gray-600 mb-2">
        {@kept_count} kept<span :if={@introduced_count > 0}>
          ({@introduced_count} as introduced)</span>, {@removed_count} excluded
      </p>

      <div class="mt-2 max-h-96 overflow-y-auto space-y-1">
        <div :for={group <- @groups}>
          <% gs = remove_group_state(group, @selected, @expanded) %>
          <div class="flex items-center gap-1.5">
            <input
              id={"powo-#{@bid}-group-#{group.id}"}
              type="checkbox"
              checked={gs.all_selected}
              data-indeterminate={to_string(!gs.all_selected and !gs.none_selected)}
              phx-hook="IndeterminateCheckbox"
              phx-click={"toggle_group_#{@bid}"}
              phx-target={@myself}
              phx-value-group={to_string(group.id)}
              class={["rounded border-gray-300", @config.checkbox_class]}
            />
            <button
              type="button"
              phx-click={"expand_group_#{@bid}"}
              phx-target={@myself}
              phx-value-group={to_string(group.id)}
              class={[
                "flex items-center gap-1 text-xs font-medium hover:underline",
                @config.heading_class
              ]}
            >
              <span class="w-3 text-center">{if gs.expanded, do: "▾", else: "▸"}</span>
              {group.label}
              <span class="font-normal text-gray-500">
                ({gs.selected_count}/{gs.total_count})
              </span>
            </button>
          </div>
          <div :if={gs.expanded} class="ml-6 space-y-0.5 mt-0.5">
            <div :for={item <- group.items} class="flex items-center gap-2">
              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={MapSet.member?(@selected, item.id)}
                  phx-click={"toggle_item_#{@bid}"}
                  phx-target={@myself}
                  phx-value-id={to_string(item.id)}
                  class={["rounded border-gray-300", @config.checkbox_class]}
                />
                <span class="text-xs">{item.label}</span>
              </label>
              <button
                :if={MapSet.member?(@selected, item.id)}
                type="button"
                phx-click="toggle_remove_introduced"
                phx-target={@myself}
                phx-value-id={to_string(item.id)}
                class={[
                  "text-[10px] px-1.5 py-0.5 rounded-full font-medium cursor-pointer",
                  if(MapSet.member?(@introduced, item.id),
                    do: "bg-amber-100 text-amber-700 hover:bg-amber-200",
                    else: "bg-green-100 text-green-700 hover:bg-green-200"
                  )
                ]}
              >
                {if MapSet.member?(@introduced, item.id), do: "Introduced", else: "Native"}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp remove_group_state(group, selected, expanded) do
    selected_count = Enum.count(group.items, &MapSet.member?(selected, &1.id))
    total_count = length(group.items)

    %{
      selected_count: selected_count,
      total_count: total_count,
      all_selected: selected_count == total_count,
      none_selected: selected_count == 0,
      expanded: MapSet.member?(expanded, group.id)
    }
  end

  # --- Event handlers ---

  # Per-bucket event handlers generated from bucket config.
  # Each bucket gets toggle_item, toggle_group, expand_group, select_all, deselect_all.

  for bucket <- @default_buckets ++ [:orphaned] do
    bid = bucket |> Atom.to_string() |> String.replace("_", "-")

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
  def handle_event("toggle_remove_introduced", %{"id" => code}, socket) do
    {:noreply,
     assign(
       socket,
       :remove_as_introduced,
       toggle_set(socket.assigns.remove_as_introduced, code)
     )}
  end

  @impl true
  def handle_event("apply", _params, socket) do
    selections =
      socket.assigns.buckets
      |> Enum.map(fn bucket ->
        {bucket, Map.get(socket.assigns, selected_field(bucket), MapSet.new())}
      end)
      |> Enum.into(%{})
      |> maybe_put_remove_as_introduced(socket)

    send(self(), {__MODULE__, {:apply, selections}})
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    send(self(), {__MODULE__, :cancel})
    {:noreply, socket}
  end

  # --- Private helpers ---

  defp init_selections(socket, diff, buckets, default_selections) do
    socket =
      Enum.reduce(buckets, socket, fn bucket, sock ->
        codes = Map.get(diff, bucket, [])

        assign(
          sock,
          selected_field(bucket),
          initial_selection(codes, Map.get(default_selections, bucket, true))
        )
      end)

    # Items in the remove bucket start as native (not introduced).
    # The user can toggle individual items to introduced via the secondary control.
    assign(socket, :remove_as_introduced, MapSet.new())
  end

  defp init_groups(socket, diff, place_by_code, buckets) do
    active_buckets =
      Enum.filter(buckets, fn bucket ->
        Map.get(diff, bucket, []) != []
      end)

    socket =
      Enum.reduce(buckets, socket, fn bucket, sock ->
        codes = Map.get(diff, bucket, [])
        assign(sock, groups_field(bucket), group_places_by_country(codes, place_by_code))
      end)

    socket
    |> assign(:active_buckets, active_buckets)
    |> assign(:expanded_countries, MapSet.new())
  end

  defp selected_field(bucket), do: String.to_atom("selected_#{bucket}")
  defp groups_field(bucket), do: String.to_atom("groups_#{bucket}")
  defp bucket_id(bucket), do: bucket |> Atom.to_string() |> String.replace("_", "-")

  defp section_expanded(expanded_countries, section) do
    expanded_countries
    |> Enum.filter(fn {s, _} -> s == section end)
    |> MapSet.new(fn {_, country} -> country end)
  end

  defp has_any_selections?(assigns) do
    # Add buckets: having selections means "add these places"
    add_buckets_have_selections? =
      Enum.any?(assigns.buckets -- [:orphaned], fn bucket ->
        MapSet.size(Map.get(assigns, selected_field(bucket))) > 0
      end)

    # Orphaned bucket: having FEWER selections than total orphaned means "remove some places"
    # (deselecting items = marking them for removal)
    # Only check this for buckets that exist in the diff (orphaned may not be present)
    orphaned_codes = Map.get(assigns.diff, :orphaned) || Map.get(assigns.diff, :remove) || []
    orphaned_count = length(orphaned_codes)
    selected_orphaned = Map.get(assigns, :selected_orphaned, MapSet.new())

    orphaned_has_removals? =
      orphaned_count > 0 and MapSet.size(selected_orphaned) < orphaned_count

    add_buckets_have_selections? or orphaned_has_removals?
  end

  defp review_remove_bucket?(bucket, bucket_config) do
    Map.get(bucket_config[bucket] || %{}, :mode) == :review_remove
  end

  defp merge_bucket_config(overrides) do
    Enum.reduce(overrides, @default_bucket_config, fn {bucket, config}, acc ->
      Map.update(acc, bucket, config, &Map.merge(&1, config))
    end)
  end

  defp initial_selection(codes, true), do: MapSet.new(codes)
  defp initial_selection(_codes, false), do: MapSet.new()

  defp initial_selection(codes, values) when is_list(values),
    do: MapSet.new(values) |> MapSet.intersection(MapSet.new(codes))

  defp initial_selection(codes, %MapSet{} = values),
    do: MapSet.intersection(values, MapSet.new(codes))

  defp initial_selection(codes, _), do: MapSet.new(codes)

  defp maybe_put_remove_as_introduced(selections, socket) do
    case socket.assigns.special_remove_bucket do
      nil ->
        selections

      bucket ->
        selected = Map.get(selections, bucket, MapSet.new())

        Map.put(
          selections,
          :remove_as_introduced,
          MapSet.intersection(socket.assigns.remove_as_introduced, selected)
        )
    end
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
