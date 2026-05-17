defmodule GallformersWeb.Admin.IngestionReviewLive.WorkspaceTraits do
  use GallformersWeb, :live_component

  @trait_option_keys %{
    "color" => :colors,
    "shape" => :shapes,
    "texture" => :textures,
    "walls" => :walls,
    "cells" => :cells,
    "alignment" => :alignments,
    "plant_part" => :plant_parts,
    "form" => :forms,
    "season" => :seasons,
    "detachable" => :detachable
  }

  @trait_labels %{
    "alignment" => "Alignment",
    "cells" => "Cells",
    "color" => "Color",
    "detachable" => "Detachable",
    "form" => "Form",
    "plant_part" => "Plant part",
    "season" => "Season",
    "shape" => "Shape",
    "texture" => "Texture",
    "walls" => "Walls"
  }

  @impl true
  def update(assigns, socket) do
    existing_gall_changed =
      socket.assigns[:initialized] &&
        assigns.existing_gall != socket.assigns[:existing_gall_ref]

    if socket.assigns[:initialized] && !existing_gall_changed do
      {:ok,
       socket
       |> assign(:workspace, assigns.workspace)
       |> assign(:filter_options, assigns.filter_options)
       |> assign(:existing_gall, assigns.existing_gall)}
    else
      trait_rows = build_trait_rows(assigns)
      existing_mode = not is_nil(assigns.existing_gall)

      {:ok,
       socket
       |> assign(assigns)
       |> assign(:initialized, true)
       |> assign(:trait_rows, trait_rows)
       |> assign(:existing_mode, existing_mode)
       |> assign(:existing_gall_ref, assigns.existing_gall)
       |> assign(:vocab_open_for, nil)}
    end
  end

  @impl true
  def handle_event("toggle_current", %{"trait" => name, "value" => value}, socket) do
    {:noreply, toggle_value(socket, name, :current_selected, value)}
  end

  @impl true
  def handle_event("toggle_extracted", %{"trait" => name, "value" => value}, socket) do
    {:noreply, toggle_value(socket, name, :extracted_selected, value)}
  end

  @impl true
  def handle_event("toggle_vocab", %{"trait" => name}, socket) do
    open = if socket.assigns.vocab_open_for == name, do: nil, else: name
    {:noreply, assign(socket, :vocab_open_for, open)}
  end

  @impl true
  def handle_event("add_from_vocab", %{"trait" => name, "value" => value}, socket) do
    socket =
      update_trait_row(socket, name, fn row ->
        %{row | extracted_selected: MapSet.put(row.extracted_selected, value)}
      end)

    notify_parent(socket, name)
    {:noreply, assign(socket, :vocab_open_for, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="workspace-section-traits" class="rounded-lg border border-gray-200 p-3">
      <h3 class="text-sm font-semibold text-gray-900 mb-2">Traits</h3>

      <.table
        :if={@trait_rows != []}
        id="traits-table"
        rows={@trait_rows}
        row_id={fn row -> "trait-#{row.name}" end}
        variant="compact"
        zebra={false}
      >
        <:col :let={row} label="Trait">
          <span class="font-medium text-gray-900 whitespace-nowrap">{row.label}</span>
        </:col>
        <:col :let={row} :if={@existing_mode} label="Current">
          <.trait_pills
            values={row.current_values}
            selected={row.current_selected}
            event="toggle_current"
            trait={row.name}
            myself={@myself}
          />
        </:col>
        <:col :let={row} label="Extracted">
          <.trait_pills
            values={row.extracted_values}
            selected={row.extracted_selected}
            event="toggle_extracted"
            trait={row.name}
            myself={@myself}
          />
          <.vocab_picker
            row={row}
            filter_options={@filter_options}
            vocab_open={@vocab_open_for == row.name}
            myself={@myself}
          />
        </:col>
        <:col :let={row} label="Result">
          <.result_display result={compute_result(row)} />
        </:col>
      </.table>

      <p :if={@trait_rows == []} class="text-sm text-gray-500">
        No traits extracted from source.
      </p>
    </section>
    """
  end

  attr :values, :list, required: true
  attr :selected, :any, required: true
  attr :event, :string, required: true
  attr :trait, :string, required: true
  attr :myself, :any, required: true

  defp trait_pills(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-1 items-center">
      <button
        :for={value <- @values}
        type="button"
        phx-click={@event}
        phx-value-trait={@trait}
        phx-value-value={value}
        phx-target={@myself}
        class={[
          "gf-pill gf-pill-compact",
          if(MapSet.member?(@selected, value),
            do: "gf-pill-selected",
            else: "gf-pill-unselected"
          )
        ]}
      >
        {value}
      </button>
    </div>
    """
  end

  attr :row, :map, required: true
  attr :filter_options, :map, required: true
  attr :vocab_open, :boolean, required: true
  attr :myself, :any, required: true

  defp vocab_picker(assigns) do
    remaining = remaining_vocab_options(assigns.filter_options, assigns.row)
    assigns = assign(assigns, :remaining, remaining)

    ~H"""
    <div :if={@remaining != []} class="relative inline-block mt-1">
      <button
        type="button"
        phx-click="toggle_vocab"
        phx-value-trait={@row.name}
        phx-target={@myself}
        class="gf-pill gf-pill-compact gf-pill-unselected"
        title="Add from vocabulary"
      >
        +
      </button>
      <div
        :if={@vocab_open}
        class="absolute left-0 top-full z-10 mt-1 max-h-48 w-40 overflow-y-auto rounded border border-gray-200 bg-white shadow-lg"
      >
        <button
          :for={option <- @remaining}
          type="button"
          phx-click="add_from_vocab"
          phx-value-trait={@row.name}
          phx-value-value={option.field}
          phx-target={@myself}
          class="block w-full px-2 py-1 text-left text-xs hover:bg-gray-100"
        >
          {option.field}
        </button>
      </div>
    </div>
    """
  end

  defp result_display(assigns) do
    ~H"""
    <span :if={@result == []} class="text-xs text-gray-400">&mdash;</span>
    <span :if={@result != []}>
      <span :for={{value, status, idx} <- Enum.with_index(@result, fn {v, s}, i -> {v, s, i} end)}>
        <span :if={idx > 0} class="text-gray-400">,&nbsp;</span><span class={result_class(status)}>{value}</span>
      </span>
    </span>
    """
  end

  defp result_class(:unchanged), do: "font-bold text-gray-900"
  defp result_class(:added), do: "font-bold text-amber-700 trait-added"
  defp result_class(:removed), do: "line-through text-gray-400 trait-removed"

  defp build_trait_rows(assigns) do
    trait_reviews = assigns.workspace.trait_reviews
    existing_traits = if assigns.existing_gall, do: assigns.existing_gall.traits, else: nil

    Enum.map(trait_reviews, fn review ->
      current_values = existing_trait_values(existing_traits, review.name)
      extracted_values = review.suggested_values || []

      %{
        name: review.name,
        label: Map.get(@trait_labels, review.name, String.capitalize(review.name)),
        current_values: current_values,
        extracted_values: extracted_values,
        current_selected: MapSet.new(current_values),
        extracted_selected: MapSet.new(extracted_values),
        original_current: MapSet.new(current_values)
      }
    end)
  end

  defp compute_result(row) do
    selected = MapSet.union(row.current_selected, row.extracted_selected)

    kept =
      selected
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.map(fn value ->
        status =
          if MapSet.member?(row.original_current, value), do: :unchanged, else: :added

        {value, status}
      end)

    removed =
      row.original_current
      |> MapSet.difference(selected)
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.map(&{&1, :removed})

    kept ++ removed
  end

  defp remaining_vocab_options(filter_options, row) do
    key = Map.get(@trait_option_keys, row.name)

    options =
      if key && key != :detachable,
        do: Map.get(filter_options, key, []),
        else: detachable_options(row.name)

    shown = MapSet.union(MapSet.new(row.current_values), MapSet.new(row.extracted_values))

    already_added =
      MapSet.difference(row.extracted_selected, MapSet.new(row.extracted_values))

    all_shown = MapSet.union(shown, already_added)
    Enum.reject(options, &MapSet.member?(all_shown, &1.field))
  end

  defp detachable_options("detachable") do
    [%{field: "integral"}, %{field: "detachable"}]
  end

  defp detachable_options(_), do: []

  defp toggle_value(socket, name, field, value) do
    socket =
      update_trait_row(socket, name, fn row ->
        set = Map.get(row, field)

        updated =
          if MapSet.member?(set, value),
            do: MapSet.delete(set, value),
            else: MapSet.put(set, value)

        Map.put(row, field, updated)
      end)

    notify_parent(socket, name)
    socket
  end

  defp update_trait_row(socket, name, fun) do
    rows =
      Enum.map(socket.assigns.trait_rows, fn row ->
        if row.name == name, do: fun.(row), else: row
      end)

    assign(socket, :trait_rows, rows)
  end

  defp notify_parent(socket, name) do
    row = Enum.find(socket.assigns.trait_rows, &(&1.name == name))
    result_values = MapSet.union(row.current_selected, row.extracted_selected)
    send(self(), {:trait_updated, name, MapSet.to_list(result_values)})
  end

  defp existing_trait_values(nil, _name), do: []

  defp existing_trait_values(existing_traits, trait_name) do
    key = Map.get(@trait_option_keys, trait_name)

    if key do
      existing_traits
      |> Map.get(key, [])
      |> List.wrap()
      |> Enum.map(fn
        %{field: f} -> f
        v when is_binary(v) -> v
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end
end
