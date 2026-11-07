defmodule GallformersWeb.DataComponents do
  @moduledoc """
  The design system's data components.

  Built: `data_table`, `fact_list`, `name_list`, `chip`, `stat`,
  `empty_state`. See docs/design-system/components.md ("Data").
  """
  use Phoenix.Component

  import GallformersWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  @doc """
  A small labelled state or category. Each variant has one meaning:

    * `:ok` done, complete
    * `:warn` in progress, needs a look
    * `:danger` conflict, error
    * `:info` a neutral fact
    * `:rank` a taxonomic rank
    * `:neutral` a category (the default)
    * `:count` a number that needs you
    * `:recommended` the recommended answer to a question

  A chip with `on_remove` is a removable choice (a picked filter or name).

  ## Examples

      <.chip variant={:ok}>Complete</.chip>
      <.chip variant={:rank}>Family</.chip>
      <.chip on_remove={JS.push("remove_host", value: %{id: 1})} remove_label="Remove Quercus rubra">
        Quercus rubra
      </.chip>
  """
  attr :variant, :atom,
    default: :neutral,
    values: [:ok, :warn, :danger, :info, :rank, :neutral, :count, :recommended]

  attr :icon, :string, default: nil
  attr :on_remove, JS, default: nil, doc: "makes the chip removable"

  attr :remove_label, :string,
    default: "Remove",
    doc: ~s|the remove button's accessible label, e.g. "Remove Quercus rubra"|

  attr :size, :string, default: "md", values: ~w(sm md)
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <span
      class={["gf-chip", "gf-chip-#{@variant}", @size == "sm" && "gf-chip-sm", @class]}
      {@rest}
    >
      <.icon :if={@icon} name={@icon} class="size-3.5" />
      {render_slot(@inner_block)}
      <button
        :if={@on_remove}
        type="button"
        class="gf-chip-remove"
        aria-label={@remove_label}
        phx-click={@on_remove}
      >
        <.icon name="ph-x" class="size-3" />
      </button>
    </span>
    """
  end

  @doc """
  The one table. Rows are `--gf-row-h` tall and single-line: long text
  truncates (a column with a `field` puts the full text in a `title`); `wrap`
  lets a column take two lines, and `full` shows its whole text (a glossary
  definition).

  `rows` is a list or a LiveView stream. A stream's rows are `{dom_id, row}`
  tuples: pass `row_item={fn {_id, row} -> row end}` so the columns get the
  row. `row_click` and `row_navigate` are called with the row as given (the
  tuple, for a stream); `select_id` and `select_label` with the row after
  `row_item`.

  A column that declares `field` and is empty (nil, "" or []) in every row is
  not shown. A stream can't be inspected, so the rule doesn't apply to one.

  With no rows the `empty` slot is shown instead of the table, column headers
  included. A stream keeps its table (rows may arrive later) and shows the
  `empty` slot as a row that is visible only while the body has no other rows.

  Sorting and selection are the LiveView's: a sortable header is a button
  that sends `sort` with `phx-value-field`; a selection checkbox sends
  `select` with `phx-value-id` (or `select_event`, to `target` when the
  table is in a LiveComponent). `selectable_row` leaves rows without a
  checkbox. `select_all` adds a header checkbox, ticked when every
  selectable row is selected, sending `select_all`, or `select_none` when
  all are already selected (by default the same event: a toggle).

  Per row, `row_attrs` (row -> a map of attributes, for hooks and tests)
  goes on the `tr`, and `row_state` (row -> nil, `:selected`, `:ok`,
  `:warn`, `:danger` or `:info`) tints it and sets `data-state`. A selected
  row is `:selected`.

  ## Examples

      <.data_table id="sources" rows={@sources} row_navigate={&~p"/admin/sources/\#{&1.id}"} sort={@sort}>
        <:col :let={s} label="Title" field={:title} sortable grow>{s.title}</:col>
        <:col :let={s} label="Authors" field={:authors}>{s.authors}</:col>
        <:col :let={s} label="Year" field={:year} sortable numeric>{s.year}</:col>
        <:col :let={s} label="Status"><.chip :if={s.complete} variant={:ok}>Complete</.chip></:col>
        <:empty>No Sources match "{@query}".</:empty>
        <:footer><.pagination … /></:footer>
      </.data_table>

      <.data_table id="galls" rows={@streams.galls} row_item={fn {_id, g} -> g end} selectable selected={@selected}>
        <:col :let={g} label="Name" grow><em>{g.name}</em></:col>
      </.data_table>

      <.data_table
        id="images-table"
        rows={@images}
        row_attrs={&%{"data-image-id" => &1.id}}
        row_state={&if(unattributed?(&1), do: :warn)}
        selectable
        selected={@copy_mode.selected_ids}
        select_event="toggle_copy_target"
        select_all="select_all_targets"
        target={@myself}
      >
        <:col :let={i} label="Caption" grow>{i.caption}</:col>
      </.data_table>
  """
  attr :id, :string, required: true, doc: "the table body's id (a stream's container)"
  attr :rows, :any, required: true, doc: "a list, or a LiveView stream"

  attr :row_id, :any,
    default: nil,
    doc: "function row -> the row's DOM id (a stream's by default)"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "function mapping each row before it is passed to the columns"

  attr :row_click, :any, default: nil, doc: "a JS command, or a function row -> JS command"
  attr :row_navigate, :any, default: nil, doc: "function row -> path; the row navigates there"

  attr :sort, :map,
    default: nil,
    doc: "the current sort, %{field: atom, dir: :asc | :desc}; nil when unsorted"

  attr :selectable, :boolean, default: false, doc: "adds a checkbox column that sends `select`"
  attr :selected, :any, default: [], doc: "the selected rows' ids (a list or MapSet)"

  attr :select_id, :any,
    default: nil,
    doc: "function item -> the id a checkbox sends and is selected by (default: item.id)"

  attr :select_label, :any,
    default: nil,
    doc: ~s|function item -> the checkbox's accessible label (default: "Select row")|

  attr :select_event, :string, default: "select", doc: "the event a row's checkbox sends"

  attr :selectable_row, :any,
    default: nil,
    doc: "function item -> boolean; a row it rejects has no checkbox (default: every row)"

  attr :select_disabled, :boolean,
    default: false,
    doc: "disables the checkboxes (a bulk action runs)"

  attr :select_all, :string,
    default: nil,
    doc: "adds a header checkbox that sends this event while not every row is selected"

  attr :select_none, :string,
    default: nil,
    doc: "the header checkbox's event when every row is selected (default: `select_all`)"

  attr :target, :any, default: nil, doc: "a LiveComponent's @myself, for the selection events"

  attr :row_attrs, :any,
    default: nil,
    doc: ~s|function row -> a map of attributes for its `tr` (%{"data-image-id" => 4})|

  attr :row_state, :any,
    default: nil,
    doc: "function row -> nil | :selected | :ok | :warn | :danger | :info: the row's tint"

  attr :active, :any,
    default: nil,
    doc: "function row -> boolean: the row a keyboard highlights (aria-current, highlighted)"

  attr :compact, :boolean, default: false, doc: "28px rows"
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  slot :col, required: true do
    attr :label, :string
    attr :field, :atom, doc: "the row's field; enables the empty-column rule and the title"
    attr :sortable, :boolean, doc: "the header sorts by `field`"
    attr :numeric, :boolean, doc: "right-aligned, tabular figures"
    attr :grow, :boolean, doc: "takes the spare width"
    attr :wrap, :boolean, doc: "allows two lines instead of truncating"
    attr :full, :boolean, doc: "shows the whole text, never cut (definitions, notes)"
    attr :hide_below, :atom, values: [:md, :lg], doc: "hidden on screens narrower than this"
  end

  slot :empty, doc: "what the table says when it has no rows"
  slot :footer, doc: "under the table: pagination, totals"

  def data_table(assigns) do
    stream? = match?(%Phoenix.LiveView.LiveStream{}, assigns.rows)

    assigns =
      assigns
      |> assign(:stream?, stream?)
      |> assign(:row_id, assigns.row_id || (stream? && fn {id, _row} -> id end))
      |> assign(:cols, visible_cols(assigns.col, assigns.rows, assigns.row_item, stream?))
      |> assign(:row_h, if(assigns.compact, do: "h-7", else: "h-row"))
      |> assign(:select_key, select_key(assigns.row_item, assigns.select_id))
      |> assign(:select_label, select_label(assigns.row_item, assigns.select_label))
      |> assign(:can_select, can_select(assigns.row_item, assigns.selectable_row))
      |> assign(:row_state, row_state_fn(assigns))
      |> assign(:row_attrs, assigns.row_attrs || fn _row -> %{} end)
      |> assign_select_all()

    ~H"""
    <div class={["overflow-hidden rounded-panel border border-line bg-surface", @class]} {@rest}>
      <div
        :if={!@stream? and @rows == [] and @empty != []}
        id={@id}
        data-part="empty"
        class="p-panel text-ui text-muted"
      >
        {render_slot(@empty)}
      </div>
      <div :if={@stream? or @rows != [] or @empty == []} class="overflow-x-auto">
        <%!-- A minimum width: in a cramped container the table scrolls
             sideways rather than squeezing its grow column to nothing. --%>
        <table class="w-full min-w-xl border-collapse text-ui text-ink">
          <thead>
            <tr class={@row_h}>
              <th
                :if={@selectable}
                scope="col"
                class="w-0 border-b border-line-strong bg-surface-2 px-3"
              >
                <input
                  :if={@select_all}
                  type="checkbox"
                  id={"#{@id}-select-all"}
                  class="gf-checkbox align-middle"
                  phx-click={if @all_selected, do: @select_none || @select_all, else: @select_all}
                  phx-target={@target}
                  checked={@all_selected}
                  disabled={@select_disabled}
                  aria-label="Select all"
                />
                <span :if={!@select_all} class="sr-only">Select</span>
              </th>
              <th
                :for={col <- @cols}
                scope="col"
                aria-sort={col[:sortable] && aria_sort(@sort, col[:field])}
                class={[
                  "whitespace-nowrap border-b border-line-strong bg-surface-2 px-3",
                  "text-meta font-semibold text-muted",
                  if(col[:numeric], do: "text-right", else: "text-left"),
                  hide_below(col[:hide_below])
                ]}
              >
                <button
                  :if={col[:sortable]}
                  type="button"
                  phx-click="sort"
                  phx-value-field={col[:field]}
                  class="inline-flex items-center gap-1 hover:text-ink"
                >
                  {col[:label]}
                  <.icon
                    :if={sort_dir(@sort, col[:field])}
                    name="ph-caret-down"
                    class={["size-3", sort_dir(@sort, col[:field]) == :asc && "rotate-180"]}
                  />
                </button>
                <span :if={!col[:sortable]}>{col[:label]}</span>
              </th>
            </tr>
          </thead>
          <tbody id={@id} phx-update={@stream? && "stream"}>
            <tr :if={@stream? and @empty != []} id={"#{@id}-empty"} class="hidden only:table-row">
              <td colspan={length(@cols) + if(@selectable, do: 1, else: 0)} class="p-panel text-muted">
                {render_slot(@empty)}
              </td>
            </tr>
            <tr
              :for={row <- @rows}
              id={@row_id && @row_id.(row)}
              phx-click={row_action(row, @row_click, @row_navigate)}
              data-selected={@selectable && @select_key.(row) in @selected}
              data-active={@active && @active.(row)}
              data-state={@row_state.(row)}
              aria-current={@active && @active.(row) && "true"}
              class={[
                @row_h,
                "border-b border-line last:border-b-0",
                cond do
                  @row_state.(row) == :selected ->
                    state_class(:selected)

                  @active && @active.(row) ->
                    "bg-sky outline outline-2 -outline-offset-2 outline-brand"

                  state = @row_state.(row) ->
                    state_class(state)

                  true ->
                    "hover:bg-sky-soft"
                end,
                (@row_click || @row_navigate) && "cursor-pointer"
              ]}
              {@row_attrs.(row)}
            >
              <td :if={@selectable} class="w-0 px-3">
                <input
                  :if={@can_select.(row)}
                  type="checkbox"
                  class="gf-checkbox align-middle"
                  phx-click={@select_event}
                  phx-target={@target}
                  phx-value-id={@select_key.(row)}
                  checked={@select_key.(row) in @selected}
                  disabled={@select_disabled}
                  aria-label={@select_label.(row)}
                />
              </td>
              <td
                :for={col <- @cols}
                class={[
                  "px-3 py-1",
                  col[:numeric] && "text-right tabular-nums",
                  col[:grow] && "w-full max-w-0",
                  hide_below(col[:hide_below])
                ]}
              >
                <div
                  title={!col[:full] && cell_title(@row_item.(row), col[:field])}
                  data-full={col[:full]}
                  class={[
                    cond do
                      col[:full] -> "whitespace-normal"
                      col[:wrap] -> "line-clamp-2"
                      true -> "truncate"
                    end,
                    !col[:grow] && "max-w-72"
                  ]}
                >
                  {render_slot(col, @row_item.(row))}
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div
        :if={@footer != []}
        data-part="footer"
        class="border-t border-line px-3 py-2 text-meta text-muted"
      >
        {render_slot(@footer)}
      </div>
    </div>
    """
  end

  defp visible_cols(cols, _rows, _row_item, true), do: cols
  defp visible_cols(cols, [], _row_item, false), do: cols

  defp visible_cols(cols, rows, row_item, false) do
    items = Enum.map(rows, row_item)

    Enum.reject(cols, fn col ->
      col[:field] && Enum.all?(items, &blank?(field(&1, col[:field])))
    end)
  end

  defp field(item, field) when is_map(item), do: Map.get(item, field)
  defp field(_item, _field), do: :not_a_map

  defp blank?(value), do: value in [nil, "", []]

  defp cell_title(item, field) when is_atom(field) and not is_nil(field) do
    case field(item, field) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp cell_title(_item, _field), do: nil

  defp aria_sort(%{field: field, dir: :asc}, field), do: "ascending"
  defp aria_sort(%{field: field, dir: :desc}, field), do: "descending"
  defp aria_sort(_sort, _field), do: "none"

  defp sort_dir(%{field: field, dir: dir}, field), do: dir
  defp sort_dir(_sort, _field), do: nil

  defp hide_below(:md), do: "hidden md:table-cell"
  defp hide_below(:lg), do: "hidden lg:table-cell"
  defp hide_below(_), do: nil

  defp row_action(_row, %JS{} = js, _navigate), do: js
  defp row_action(row, click, _navigate) when is_function(click, 1), do: click.(row)

  defp row_action(row, nil, navigate) when is_function(navigate, 1),
    do: JS.navigate(navigate.(row))

  defp row_action(_row, _click, _navigate), do: nil

  defp select_key(row_item, nil), do: &field(row_item.(&1), :id)
  defp select_key(row_item, select_id), do: &select_id.(row_item.(&1))

  defp select_label(_row_item, nil), do: fn _row -> "Select row" end
  defp select_label(row_item, label), do: &label.(row_item.(&1))

  defp can_select(_row_item, nil), do: fn _row -> true end
  defp can_select(row_item, selectable_row), do: &selectable_row.(row_item.(&1))

  # A selected row is :selected; otherwise the page's state, if any.
  defp row_state_fn(%{selectable: selectable, selected: selected, row_state: row_state} = assigns) do
    select_key = select_key(assigns.row_item, assigns.select_id)

    fn row ->
      if selectable && select_key.(row) in selected,
        do: :selected,
        else: row_state && row_state.(row)
    end
  end

  defp state_class(:selected), do: "bg-sky"
  defp state_class(:ok), do: "bg-ok-bg"
  defp state_class(:warn), do: "bg-warn-bg"
  defp state_class(:danger), do: "bg-danger-bg"
  defp state_class(:info), do: "bg-info-bg"

  # Whether every selectable row is selected (a stream can't be inspected).
  defp assign_select_all(%{select_all: nil} = assigns), do: assign(assigns, :all_selected, false)

  defp assign_select_all(%{stream?: true} = assigns), do: assign(assigns, :all_selected, false)

  defp assign_select_all(assigns) do
    keys =
      for row <- assigns.rows, assigns.can_select.(row), do: assigns.select_key.(row)

    assign(assigns, :all_selected, keys != [] and Enum.all?(keys, &(&1 in assigns.selected)))
  end

  @doc """
  Label/value pairs: a Gall's traits, a record's facts in a rail.

  An item is missing when it has no inner block and its `value` is nil, ""
  or []. Missing items collect into one line at the end ("Not recorded:
  shape, alignment, walls"), so known values stand out and gaps stay
  visible. With `missing_label={nil}` they are left out.

  Layouts: `:grid` (the default) sets each pair in a ruled cell, in up to
  three columns (one on phones); `:inline` sets label and value on one line,
  compact enough for a rail. A list value is joined with commas.

  ## Examples

      <.fact_list columns={3}>
        <:item label="Detachable">Integral</:item>
        <:item label="Shape" value={@gall.shape} />
        <:item label="Seasons" value={@gall.seasons} />
      </.fact_list>

      <.fact_list layout={:inline} missing_label={nil}>
        <:item label="Added" value={@source.inserted_on} />
      </.fact_list>
  """
  attr :columns, :integer, default: 1, values: [1, 2, 3], doc: "grid columns on wide screens"

  attr :missing_label, :any,
    default: "Not recorded",
    doc: "starts the line of missing items; nil leaves them out"

  attr :layout, :atom, default: :grid, values: [:grid, :inline]
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  slot :item, required: true do
    attr :label, :string, required: true
    attr :value, :any, doc: "the value, when there is no inner block"
  end

  def fact_list(assigns) do
    {present, missing} = Enum.split_with(assigns.item, &(&1.inner_block || !blank?(&1[:value])))

    assigns =
      assigns
      |> assign(:present, present)
      |> assign(:missing, Enum.map_join(missing, ", ", &String.downcase(&1.label)))

    ~H"""
    <div class={["flex flex-col gap-2", @class]} {@rest}>
      <dl
        :if={@present != []}
        data-layout={@layout}
        class={
          if @layout == :grid,
            do: ["grid grid-cols-1 gap-x-6", fact_columns(@columns)],
            else: ["grid grid-cols-1 gap-x-6 gap-y-1", fact_columns(@columns)]
        }
      >
        <div
          :for={item <- @present}
          class={
            if @layout == :grid,
              do: "grid grid-cols-2 gap-2 border-b border-line py-1.5",
              else: "flex items-baseline gap-2"
          }
        >
          <dt class="text-meta text-muted">{item.label}</dt>
          <dd class={["text-ui", if(@layout == :grid, do: "text-ink", else: "min-w-0 text-ink-2")]}>
            {if item.inner_block, do: render_slot(item), else: fact_value(item.value)}
          </dd>
        </div>
      </dl>
      <p :if={@missing_label && @missing != ""} data-part="missing" class="text-meta text-muted">
        {@missing_label}: {@missing}
      </p>
    </div>
    """
  end

  defp fact_columns(1), do: nil
  defp fact_columns(2), do: "sm:grid-cols-2"
  defp fact_columns(3), do: "sm:grid-cols-2 lg:grid-cols-3"

  defp fact_value(values) when is_list(values), do: Enum.map_join(values, ", ", &to_string/1)
  defp fact_value(value), do: to_string(value)

  @doc """
  A list of short names that flows into columns, alphabetical down each
  column: Hosts, a Source's Galls, families on a browse page. Pass the items
  in order. `columns` is the most columns, on wide screens; narrower screens
  get fewer (one on phones).

  Without an `item` slot each item is shown as text.

  ## Examples

      <.name_list items={@host_names} columns={3} italic />

      <.name_list items={@hosts} italic>
        <:item :let={h}><.link navigate={~p"/host/\#{h.id}"}>{h.name}</.link> {h.count}</:item>
      </.name_list>
  """
  attr :items, :list, required: true
  attr :columns, :integer, default: 4, values: [1, 2, 3, 4, 5, 6], doc: "the most columns"
  attr :italic, :boolean, default: false, doc: "scientific names"
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  slot :item, doc: "renders one item (given with :let)"

  def name_list(assigns) do
    ~H"""
    <ul
      :if={@items != []}
      class={[
        "columns-1 gap-x-8 text-ui text-ink",
        name_columns(@columns),
        @italic && "italic",
        @class
      ]}
      {@rest}
    >
      <li :for={item <- @items} class="break-inside-avoid py-0.5">
        {if @item != [], do: render_slot(@item, item), else: to_string(item)}
      </li>
    </ul>
    """
  end

  defp name_columns(1), do: nil
  defp name_columns(2), do: "sm:columns-2"
  defp name_columns(3), do: "sm:columns-2 lg:columns-3"
  defp name_columns(4), do: "sm:columns-2 md:columns-3 lg:columns-4"
  defp name_columns(5), do: "sm:columns-2 md:columns-3 lg:columns-5"
  defp name_columns(6), do: "sm:columns-2 md:columns-3 lg:columns-6"

  @doc """
  A number with a label: 3,976 Galls. For dashboards and the home page only,
  where the figures are the point.

  An integer gets thousands separators; any other value is shown as given.
  The number is set at the section-heading size (`text-section`), so a row of
  figures doesn't outweigh the page title. With `navigate` the stat is a link
  to what it counts.

  ## Examples

      <.stat value={3976} label="Galls" icon="gf-gall" navigate={~p"/galls"} />
      <.stat value={358} label="To review" />
  """
  attr :value, :any, required: true
  attr :label, :string, required: true
  attr :icon, :string, default: nil, doc: "a ph-* or gf-* icon name, shown before the number"
  attr :navigate, :string, default: nil, doc: "makes the stat a link"
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  def stat(assigns) do
    ~H"""
    <.link
      :if={@navigate}
      navigate={@navigate}
      class={["group flex flex-col gap-0.5 hover:no-underline", @class]}
      {@rest}
    >
      <.stat_body value={@value} label={@label} icon={@icon} link />
    </.link>
    <div :if={!@navigate} class={["flex flex-col gap-0.5", @class]} {@rest}>
      <.stat_body value={@value} label={@label} icon={@icon} />
    </div>
    """
  end

  attr :value, :any, required: true
  attr :label, :string, required: true
  attr :icon, :string, default: nil
  attr :link, :boolean, default: false

  defp stat_body(assigns) do
    ~H"""
    <span class="flex items-center gap-2">
      <.icon :if={@icon} name={@icon} class="size-5 text-muted" />
      <span data-part="value" class="font-brand text-section font-semibold text-ink tabular-nums">
        {GallformersWeb.Helpers.format_number(@value)}
      </span>
    </span>
    <span
      data-part="label"
      class={["text-meta", if(@link, do: "text-link group-hover:underline", else: "text-muted")]}
    >
      {@label}
    </span>
    """
  end

  @doc """
  What a list or region says when it has nothing: a title saying what would
  be here, an optional one-line explanation and, when possible, the action
  that adds the first one. Quiet: centered text, no box.

  ## Examples

      <.empty_state title="No Sources yet" icon="gf-source">
        Sources you add appear here.
        <:action><.button navigate={~p"/admin/sources/new"}>Add a Source</.button></:action>
      </.empty_state>
  """
  attr :title, :string, required: true
  attr :icon, :string, default: nil, doc: "a ph-* or gf-* icon name, shown above the title"
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  slot :inner_block, doc: "a one-line explanation"
  slot :action, doc: "the action that fills the region"

  def empty_state(assigns) do
    ~H"""
    <div class={["flex flex-col items-center gap-2 px-4 py-10 text-center", @class]} {@rest}>
      <.icon :if={@icon} name={@icon} class="size-8 text-muted" />
      <p data-part="title" class="text-ui font-semibold text-ink">{@title}</p>
      <p :if={@inner_block != []} data-part="description" class="max-w-text text-meta text-ink-2">
        {render_slot(@inner_block)}
      </p>
      <div :if={@action != []} data-part="actions" class="mt-2 flex flex-wrap justify-center gap-2">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  @doc """
  A bar chart drawn on the server as SVG: one group of bars per item (a
  day), one bar per series, to scale against a y axis that runs from 0 to a
  round number. Each bar is titled with its value (the browser's tooltip);
  a legend names the series; a visually hidden table carries the numbers
  for screen readers. Bars and labels take their color from tokens. Day
  labels thin out on long ranges (every day up to 7, every 3rd up to 30,
  else every 7th). With no data it says so.

      <.bar_chart
        id="daily"
        label="Page views and unique visitors by day"
        data={[%{label: "Nov 3", views: 1234, visitors: 56}, …]}
        series={[
          %{key: :views, label: "Page views", tone: :brand},
          %{key: :visitors, label: "Unique visitors", tone: :autumn}
        ]}
      />
  """
  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "the chart's accessible name"
  attr :data, :list, required: true, doc: "maps with `label` and a number per series key"

  attr :series, :list,
    required: true,
    doc: "maps with `key`, `label` and `tone` (`:brand`, `:autumn`, `:sky`)"

  attr :height, :integer, default: 180, doc: "the plot's height in px"
  attr :class, :any, default: nil, doc: "layout only"

  @chart_pad 8
  @y_axis_width 44

  def bar_chart(assigns) do
    %{data: data, series: series, height: height} = assigns

    peak =
      data
      |> Enum.flat_map(fn row -> Enum.map(series, &(row[&1.key] || 0)) end)
      |> Enum.max(fn -> 0 end)

    {top, step} = nice_scale(peak)
    n = max(length(data), 1)
    band = 100 / n
    bar_width = band * 0.8 / max(length(series), 1)
    every = label_every(length(data))

    y = fn value -> @chart_pad + height - value / top * height end

    bars =
      for {row, i} <- Enum.with_index(data), {s, j} <- Enum.with_index(series) do
        value = row[s.key] || 0
        h = Float.round(value / top * height, 2)

        %{
          series: s,
          x: pct(i * band + band * 0.1 + j * bar_width),
          width: pct(bar_width * 0.92),
          y: Float.round(@chart_pad + height - h, 2),
          height: h,
          title: "#{row.label} · #{s.label}: #{format_count(value)}"
        }
      end

    ticks = for t <- 0..round(top / step), do: t * step

    assigns =
      assign(assigns,
        bars: bars,
        ticks: Enum.map(ticks, &{&1, Float.round(y.(&1), 2)}),
        x_labels:
          for {row, i} <- Enum.with_index(data), rem(i, every) == 0 do
            {row.label, pct(i * band + band / 2)}
          end,
        pad: @chart_pad,
        y_axis_width: @y_axis_width
      )

    ~H"""
    <figure id={@id} class={["m-0 flex flex-col gap-2", @class]}>
      <p :if={@data == []} data-part="empty" class="py-8 text-center text-ui text-muted">
        No data for this period.
      </p>
      <%= if @data != [] do %>
        <ul data-part="legend" class="flex flex-wrap gap-x-4 gap-y-1 text-meta text-ink-2">
          <li :for={s <- @series} class="flex items-center gap-1.5">
            <span class={["size-3 rounded-ctl", tone_bg(s.tone)]}></span>{s.label}
          </li>
        </ul>
        <div class="flex">
          <svg
            data-part="y-axis"
            width={@y_axis_width}
            height={@height + @pad + 20}
            aria-hidden="true"
            class="shrink-0 overflow-visible"
          >
            <text
              :for={{value, y} <- @ticks}
              x={@y_axis_width - 6}
              y={y + 4}
              text-anchor="end"
              class="fill-muted text-caption tabular-nums"
            >
              {format_count(value)}
            </text>
          </svg>
          <div class="min-w-0 flex-1">
            <svg
              role="img"
              aria-label={@label}
              width="100%"
              height={@height + @pad}
              class="block overflow-visible"
            >
              <line
                :for={{_value, y} <- @ticks}
                x1="0"
                x2="100%"
                y1={y}
                y2={y}
                class="stroke-line"
              />
              <rect
                :for={bar <- @bars}
                data-series={bar.series.key}
                x={bar.x}
                y={bar.y}
                width={bar.width}
                height={bar.height}
                class={["hover:opacity-80", tone_fill(bar.series.tone)]}
              >
                <title>{bar.title}</title>
              </rect>
            </svg>
            <svg
              data-part="x-axis"
              width="100%"
              height="20"
              aria-hidden="true"
              class="block overflow-visible"
            >
              <text
                :for={{label, x} <- @x_labels}
                x={x}
                y="14"
                text-anchor="middle"
                class="fill-muted text-caption"
              >
                {label}
              </text>
            </svg>
          </div>
        </div>
        <table class="sr-only">
          <caption>{@label}</caption>
          <thead>
            <tr>
              <th scope="col"></th>
              <th :for={s <- @series} scope="col">{s.label}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @data}>
              <th scope="row">{row.label}</th>
              <td :for={s <- @series}>{format_count(row[s.key] || 0)}</td>
            </tr>
          </tbody>
        </table>
      <% end %>
    </figure>
    """
  end

  # The axis top: the smallest 1, 2, 2.5 or 5 × 10^k step that covers the
  # peak in at most five steps.
  defp nice_scale(peak) when peak <= 0, do: {1, 1}

  defp nice_scale(peak) do
    magnitude = :math.pow(10, floor(:math.log10(peak)))

    step =
      [0.1, 0.2, 0.25, 0.5, 1, 2, 2.5, 5, 10]
      |> Enum.map(&(&1 * magnitude))
      |> Enum.find(&(peak / &1 <= 5))

    step = if step >= 1, do: round(step), else: step
    {step * ceil(peak / step), step}
  end

  defp label_every(n) when n <= 7, do: 1
  defp label_every(n) when n <= 30, do: 3
  defp label_every(_n), do: 7

  defp pct(value), do: "#{Float.round(value * 1.0, 3)}%"

  defp format_count(value) when is_float(value) and value != trunc(value), do: to_string(value)
  defp format_count(value), do: GallformersWeb.Helpers.format_number(trunc(value))

  defp tone_fill(:brand), do: "fill-brand-fill"
  defp tone_fill(:autumn), do: "fill-autumn"
  defp tone_fill(:sky), do: "fill-link"

  defp tone_bg(:brand), do: "bg-brand-fill"
  defp tone_bg(:autumn), do: "bg-autumn"
  defp tone_bg(:sky), do: "bg-link"

  @doc """
  Shares of a whole, one row each: the item's name, a bar as wide as its
  share, the share and the count (the analytics page's devices and
  browsers). Items carry `count` and `percentage`; `name` is a function
  item -> its name.

      <.share_list id="devices" items={@devices} name={&String.capitalize(&1.device_type)} />
  """
  attr :id, :string, required: true
  attr :items, :list, required: true, doc: "maps with `count` and `percentage`"
  attr :name, :any, required: true, doc: "function item -> its name"
  attr :class, :any, default: nil, doc: "layout only"

  def share_list(assigns) do
    ~H"""
    <div id={@id} class={@class}>
      <p :if={@items == []} data-part="empty" class="py-4 text-ui text-muted">
        Nothing recorded in this period.
      </p>
      <ul :if={@items != []} class="flex flex-col gap-2 text-ui">
        <li :for={item <- @items} class="grid grid-cols-3 items-center gap-3">
          <span data-part="name" class="truncate text-ink">{@name.(item)}</span>
          <svg width="100%" height="10" aria-hidden="true" class="block">
            <rect width="100%" height="10" rx="2" class="fill-surface-2" />
            <rect
              data-part="bar"
              width={"#{item.percentage}%"}
              height="10"
              rx="2"
              class="fill-brand-fill"
            />
          </svg>
          <span data-part="share" class="text-right tabular-nums text-ink-2">
            {item.percentage}% <span class="text-muted">· {format_count(item.count)}</span>
          </span>
        </li>
      </ul>
    </div>
    """
  end
end
