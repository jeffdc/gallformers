defmodule GallformersWeb.GallLive.RangeEdit do
  @moduledoc """
  Range exclusions in Edit mode on the Gall page (matter ec2c; moved from
  the old admin Gall page with its logic unchanged): a dialog with the
  range map and the place drill-down. The curator clicks places to exclude
  them or restore excluded ones (`GallformersWeb.GallLive.RangeExclusions`
  says which can be marked and what a change means), then puts the change
  in their tray as Fact items on the Gall's exclusions.

  The range map's hook and the drill-down talk to the page's LiveView, so
  `GallformersWeb.GallLive` holds the state and calls these functions from
  its events (`open_range`, `close_range`, `toggle_region`,
  `toggle_country`, `range_to_tray`) and its drill-down messages.
  """
  use GallformersWeb, :html

  alias Gallformers.Curation
  alias Gallformers.Places
  alias GallformersWeb.Admin.PlaceDrillDown
  alias GallformersWeb.GallLive.RangeExclusions

  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3, send_update: 2]

  @doc "Opens the dialog: the Gall's range and current exclusions, nothing marked yet."
  def open(socket) do
    all_places = Places.list_all_places()
    place_by_code = Map.new(all_places, &{&1.code, &1})
    range = RangeExclusions.load(socket.assigns.gall.id, place_by_code)

    socket
    |> assign(range_edit: %{all_places: all_places, place_by_code: place_by_code, range: range})
    |> assign(
      range_bounds_edit: Places.get_bounds_for_codes(RangeExclusions.markable_codes(range))
    )
    |> set_marked(range.excluded, push: false)
  end

  @doc "Closes the dialog."
  def close(socket), do: assign(socket, range_edit: nil)

  @doc "Marks or unmarks a place the Gall's range could exclude."
  def mark(%{assigns: %{range_edit: nil}} = socket, _code), do: socket

  def mark(socket, code) do
    if RangeExclusions.markable?(socket.assigns.range_edit.range, code) do
      marked = socket.assigns.range_edit.marked

      marked =
        if MapSet.member?(marked, code),
          do: MapSet.delete(marked, code),
          else: MapSet.put(marked, code)

      set_marked(socket, marked)
    else
      socket
    end
  end

  @doc "A country: marked when it has no subdivisions, else its drill-down opens."
  def country(%{assigns: %{range_edit: nil}} = socket, _code), do: socket

  def country(socket, code) do
    case Map.get(socket.assigns.range_edit.place_by_code, code) do
      nil ->
        socket

      place ->
        if Places.leaf_descendant_ids(place.id) == [place.id] do
          mark(socket, code)
        else
          send_update(PlaceDrillDown, id: "range-drill-down", action: {:open, place})
          push_event(socket, "range-zoom-to-country", %{code: code})
        end
    end
  end

  @doc "The drill-down's Select all keeps places in the range: restores them."
  def include_all(socket, codes),
    do: set_marked(socket, MapSet.difference(socket.assigns.range_edit.marked, MapSet.new(codes)))

  @doc "The drill-down's Exclude all marks those that can be marked."
  def exclude_all(socket, codes) do
    markable = Enum.filter(codes, &RangeExclusions.markable?(socket.assigns.range_edit.range, &1))
    set_marked(socket, MapSet.union(socket.assigns.range_edit.marked, MapSet.new(markable)))
  end

  @doc """
  Puts the change in the curator's tray (`RangeExclusions.plan/2`): each
  place to exclude as an `add`, each exclusion to restore as a `withdraw`.
  """
  def to_tray(socket) do
    %{range_edit: edit, gall: gall, curator: curator} = socket.assigns
    plan = RangeExclusions.plan(edit.range.exclusions, edit.marked)
    id = &edit.place_by_code[&1].id

    specs =
      Enum.map(plan.exclude, &{:add, id.(&1)}) ++ Enum.map(plan.withdraw, &{:withdraw, id.(&1)})

    errors =
      for {action, place_id} <- specs,
          result =
            Curation.add_item(curator, %{
              kind: :fact,
              gall_id: gall.id,
              action: action,
              key: {:range, :exclude, place_id}
            }),
          match?({:error, _}, result),
          do: result

    case errors do
      [] ->
        close(socket)

      [{:error, reason} | _] ->
        put_flash(socket, :error, "A range change couldn't go in your tray (#{reason}).")
    end
  end

  defp set_marked(socket, marked, opts \\ []) do
    %{range: range, place_by_code: place_by_code} = edit = socket.assigns.range_edit
    map = RangeExclusions.map_ranges(range, marked)
    name = &(place_by_code |> Map.get(&1, %{name: &1}) |> Map.get(:name))

    edit =
      Map.merge(edit, %{
        marked: marked,
        map: map,
        marked_place_ids: for(code <- marked, p = place_by_code[code], do: p.id),
        to_exclude: marked |> MapSet.difference(range.excluded) |> Enum.map(name) |> Enum.sort(),
        to_restore: range.excluded |> MapSet.difference(marked) |> Enum.map(name) |> Enum.sort()
      })

    socket = assign(socket, range_edit: edit)

    if Keyword.get(opts, :push, true),
      do:
        push_event(
          socket,
          "range-update",
          Map.take(map, [:in_range, :excluded_range, :inherited_range, :introduced_range])
        ),
      else: socket
  end

  @doc "The dialog."
  attr :edit, :map, required: true
  attr :bounds, :any, required: true

  def range_dialog(assigns) do
    ~H"""
    <.dialog
      id="range-dialog"
      title="Range exclusions"
      size={:lg}
      show
      on_cancel={JS.push("close_range")}
    >
      <div class="flex flex-col gap-block">
        <p class="text-ui text-ink-2">
          The Gall's potential range comes from its Hosts' ranges. Click a place to exclude it (the Gall does not occur there) or to restore an excluded one; a country with subdivisions opens them. The change goes in your tray; you give the reason when you apply.
        </p>
        <.notice :if={@edit.range.everywhere?} kind={:warn}>
          No Host range data: the Gall's range is everywhere. Any place can be excluded.
        </.notice>
        <div class="flex flex-col gap-3 md:flex-row">
          <div class="min-w-0 flex-1">
            <.range_map
              id="exclusions-range-map"
              in_range={@edit.map.in_range}
              excluded_range={@edit.map.excluded_range}
              inherited_range={@edit.map.inherited_range}
              introduced_range={@edit.map.introduced_range}
              bounds={@bounds}
              editable
              class="h-96 rounded-panel border border-line"
            />
            <.range_map_legend mode={:gall_admin} />
          </div>
          <.live_component
            module={PlaceDrillDown}
            id="range-drill-down"
            mode={:gall}
            omitted_place_ids={@edit.marked_place_ids}
            host_places={
              if @edit.range.everywhere?, do: [], else: RangeExclusions.markable_codes(@edit.range)
            }
            all_places={@edit.all_places}
            introduced_range={@edit.range.introduced_range}
          />
        </div>
        <div
          :if={@edit.to_exclude != [] or @edit.to_restore != []}
          id="marked-places"
          class="flex flex-col gap-1 text-ui"
        >
          <p :if={@edit.to_exclude != []}>
            <span class="font-semibold text-danger">To exclude:</span>
            {Enum.join(@edit.to_exclude, ", ")}
          </p>
          <p :if={@edit.to_restore != []}>
            <span class="font-semibold text-ok">To restore:</span>
            {Enum.join(@edit.to_restore, ", ")}
          </p>
        </div>
      </div>
      <:actions>
        <.button variant="ghost" phx-click="close_range">Cancel</.button>
        <.button
          variant="primary"
          phx-click="range_to_tray"
          disabled={@edit.to_exclude == [] and @edit.to_restore == []}
        >
          Add to tray
        </.button>
      </:actions>
    </.dialog>
    """
  end
end
