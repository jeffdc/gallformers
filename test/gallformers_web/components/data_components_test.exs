defmodule GallformersWeb.DataComponentsTest do
  @moduledoc "The design system's data components (docs/design-system/components.md)."
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]
  import GallformersWeb.DataComponents

  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.LiveStream

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp count(html, selector), do: html |> query(selector) |> Enum.count()
  defp text(html, selector), do: html |> query(selector) |> LazyHTML.text() |> String.trim()
  defp attr(html, selector, name), do: html |> query(selector) |> LazyHTML.attribute(name)

  describe "share_list" do
    test "each item's name, a bar as wide as its share, the share and the count" do
      assigns = %{
        items: [
          %{device: "desktop", count: 2, percentage: 66.7},
          %{device: "mobile", count: 1, percentage: 33.3}
        ]
      }

      html =
        rendered_to_string(~H"""
        <.share_list id="devices" items={@items} name={&String.capitalize(&1.device)} />
        """)

      assert count(html, "#devices li") == 2
      assert text(html, "#devices li:first-child [data-part=name]") == "Desktop"
      assert attr(html, "#devices li:first-child rect[data-part=bar]", "width") == ["66.7%"]
      assert text(html, "#devices li:first-child [data-part=share]") =~ "66.7%"
      assert text(html, "#devices li:first-child [data-part=share]") =~ "2"
    end

    test "no items says so" do
      assigns = %{}
      html = rendered_to_string(~H|<.share_list id="devices" items={[]} name={& &1} />|)
      assert text(html, "[data-part=empty]") == "Nothing recorded in this period."
    end
  end

  describe "bar_chart" do
    @series [
      %{key: :views, label: "Page views", tone: :brand},
      %{key: :visitors, label: "Unique visitors", tone: :autumn}
    ]

    defp days(n) do
      for i <- 1..n, do: %{label: "Nov #{i}", views: i * 10, visitors: i * 4}
    end

    defp chart(data) do
      assigns = %{data: data, series: @series}

      rendered_to_string(~H"""
      <.bar_chart
        id="daily"
        label="Page views and unique visitors by day"
        data={@data}
        series={@series}
      />
      """)
    end

    test "an accessible SVG: a bar per day and series, each titled with its value" do
      html =
        chart([
          %{label: "Nov 3", views: 1234, visitors: 56},
          %{label: "Nov 4", views: 900, visitors: 40}
        ])

      assert attr(html, "svg[role=img]", "aria-label") == [
               "Page views and unique visitors by day"
             ]

      assert count(html, "rect[data-series=views]") == 2
      assert count(html, "rect[data-series=visitors]") == 2

      assert text(html, "rect[data-series=views]:first-of-type title") ==
               "Nov 3 · Page views: 1,234"
    end

    test "bars are to scale: the y axis runs to a round number, ticks from 0" do
      html = chart([%{label: "a", views: 100, visitors: 50}])

      assert text(html, "[data-part=y-axis] text:first-child") == "0"
      assert text(html, "[data-part=y-axis] text:last-child") == "100"

      [full] = attr(html, "rect[data-series=views]", "height")
      [half] = attr(html, "rect[data-series=visitors]", "height")
      assert String.to_float(half) * 2 == String.to_float(full)
    end

    test "a legend names each series; a hidden table carries the numbers" do
      html = chart(days(3))

      assert text(html, "[data-part=legend]") =~ "Page views"
      assert text(html, "[data-part=legend]") =~ "Unique visitors"
      assert count(html, "table.sr-only tbody tr") == 3
      assert text(html, "table.sr-only tbody tr:first-child") =~ "Nov 1"
    end

    test "day labels thin out on long ranges: every day to 7, every 3rd to 30, else every 7th" do
      assert count(chart(days(7)), "[data-part=x-axis] text") == 7
      assert count(chart(days(30)), "[data-part=x-axis] text") == 10
      assert count(chart(days(90)), "[data-part=x-axis] text") == 13
    end

    test "no data says so" do
      assert text(chart([]), "[data-part=empty]") == "No data for this period."
    end
  end

  describe "chip" do
    test "each variant has its class and keeps its word" do
      for variant <- [:ok, :warn, :danger, :info, :rank, :neutral, :count, :recommended] do
        assigns = %{variant: variant}
        html = rendered_to_string(~H|<.chip variant={@variant}>Complete</.chip>|)
        assert count(html, "span.gf-chip.gf-chip-#{variant}") == 1
        assert html =~ "Complete"
      end
    end

    test "is neutral by default" do
      assigns = %{}
      html = rendered_to_string(~H|<.chip>Plantae</.chip>|)
      assert count(html, ".gf-chip-neutral") == 1
    end

    test "a removable chip has a labelled remove button" do
      assigns = %{remove: JS.push("remove", value: %{id: 1})}

      html =
        rendered_to_string(
          ~H|<.chip on_remove={@remove} remove_label="Remove Quercus">Quercus</.chip>|
        )

      assert count(html, ~s(button[aria-label="Remove Quercus"])) == 1
    end
  end

  @sources [
    %{id: 1, title: "Cynipid galls of the eastern United States", authors: "Weld", year: 1959},
    %{id: 2, title: "Plant galls of the western United States", authors: "Russo", year: 2006}
  ]

  describe "data_table" do
    test "is a real table: column headers with scope, one row per item" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows}>
          <:col :let={s} label="Title" field={:title}>{s.title}</:col>
          <:col :let={s} label="Year" field={:year} numeric>{s.year}</:col>
        </.data_table>
        """)

      assert count(html, "table thead th[scope=col]") == 2
      assert text(html, "thead") =~ "Title"
      assert count(html, "table tbody#sources tr") == 2
      assert text(html, "tbody tr:first-child") =~ "Cynipid galls"
      assert count(html, "[data-part=empty]") == 0
    end

    test "a full column shows its whole text, never cut" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows}>
          <:col :let={s} label="Title" full>{s.title}</:col>
        </.data_table>
        """)

      assert count(html, "tbody td div.truncate") == 0
      assert count(html, "tbody td div.line-clamp-2") == 0
      assert count(html, "tbody td div[data-full]") == 2
    end

    test "the active row (keyboard highlight) is marked current and highlighted" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows} active={&(&1.year == 1959)}>
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert count(html, "tbody tr[aria-current=true]") == 1
      assert text(html, "tbody tr[aria-current=true]") =~ "Cynipid galls"
      assert count(html, "tbody tr[data-active]") == 1
    end

    test "numeric columns are right-aligned with tabular figures, grow and wrap mark their cells" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows}>
          <:col :let={s} label="Title" grow wrap>{s.title}</:col>
          <:col :let={s} label="Authors">{s.authors}</:col>
          <:col :let={s} label="Year" numeric>{s.year}</:col>
        </.data_table>
        """)

      assert count(html, "th.text-right") == 1
      assert count(html, "td.text-right.tabular-nums") == 2
      assert count(html, "td.w-full") == 2
      assert count(html, "td .line-clamp-2") == 2
      # Columns that don't wrap are single-line
      assert count(html, "td .truncate") == 4
    end

    test "a field column's full text is in a title" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows}>
          <:col :let={s} label="Title" field={:title}>{s.title}</:col>
        </.data_table>
        """)

      assert attr(html, "tbody tr:first-child td div", "title") == [
               "Cynipid galls of the eastern United States"
             ]
    end

    test "hide_below hides a column's header and cells on narrow screens" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows}>
          <:col :let={s} label="Title">{s.title}</:col>
          <:col :let={s} label="Authors" hide_below={:md}>{s.authors}</:col>
          <:col :let={s} label="Year" hide_below={:lg}>{s.year}</:col>
        </.data_table>
        """)

      assert count(html, "th.hidden.md\\:table-cell, td.hidden.md\\:table-cell") == 3
      assert count(html, "th.hidden.lg\\:table-cell, td.hidden.lg\\:table-cell") == 3
    end

    test "rows are --gf-row-h tall, or 28px when compact" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows}>
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert count(html, "tbody tr.h-row") == 2

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows} compact>
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert count(html, "tbody tr.h-7") == 2
      assert count(html, "tbody tr.h-row") == 0
    end

    test "a sortable header is a sort button, and the sorted column says so" do
      assigns = %{rows: @sources, sort: %{field: :year, dir: :desc}}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows} sort={@sort}>
          <:col :let={s} label="Title" field={:title} sortable>{s.title}</:col>
          <:col :let={s} label="Year" field={:year} sortable>{s.year}</:col>
          <:col :let={s} label="Authors" field={:authors}>{s.authors}</:col>
        </.data_table>
        """)

      assert count(html, ~s(th button[phx-click="sort"])) == 2
      assert attr(html, "th button", "phx-value-field") == ["title", "year"]
      assert attr(html, "th[aria-sort]", "aria-sort") == ["none", "descending"]

      assigns = %{rows: @sources, sort: %{field: :title, dir: :asc}}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows} sort={@sort}>
          <:col :let={s} label="Title" field={:title} sortable>{s.title}</:col>
        </.data_table>
        """)

      assert attr(html, "th", "aria-sort") == ["ascending"]
    end

    test "row_navigate makes each row navigate to its path" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows} row_navigate={&"/admin/sources/#{&1.id}"}>
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      [first, second] = attr(html, "tbody tr", "phx-click")
      assert first =~ "navigate"
      assert first =~ "/admin/sources/1"
      assert second =~ "/admin/sources/2"
      assert count(html, "tbody tr.cursor-pointer") == 2
    end

    test "row_click takes a function of the row or one JS command" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows} row_click={&JS.push("open", value: %{id: &1.id})}>
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert Enum.count(attr(html, "tbody tr", "phx-click"), &(&1 =~ "open")) == 2

      assigns = %{rows: @sources, click: JS.push("touch")}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows} row_click={@click}>
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert Enum.count(attr(html, "tbody tr", "phx-click"), &(&1 =~ "touch")) == 2
    end

    test "rows without a click or navigate are not clickable" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows}>
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert count(html, "tbody tr[phx-click]") == 0
    end

    test "selectable adds a labelled checkbox column that emits select" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows} selectable selected={[2]}>
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert count(html, "thead th") == 2
      assert count(html, ~s(tbody input[type=checkbox][phx-click="select"])) == 2
      assert attr(html, "tbody input[type=checkbox]", "phx-value-id") == ["1", "2"]

      assert attr(html, "tbody input[type=checkbox]", "aria-label") == [
               "Select row",
               "Select row"
             ]

      assert count(html, "tbody input[checked]") == 1
      assert count(html, "tbody tr:nth-child(2) input[checked]") == 1
      assert count(html, "tbody tr[data-selected]") == 1
    end

    test "row_attrs puts the page's attributes on each row" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows} row_attrs={&%{"data-source-id" => &1.id}}>
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert attr(html, "tbody tr", "data-source-id") == ["1", "2"]
    end

    test "row_state tints a row and names its state; selection is a state" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table
          id="sources"
          rows={@rows}
          row_state={&if(&1.id == 1, do: :warn)}
          selectable
          selected={[2]}
        >
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert attr(html, "tbody tr", "data-state") == ["warn", "selected"]
      assert count(html, "tbody tr.bg-warn-bg") == 1
      assert count(html, "tbody tr.bg-sky") == 1
    end

    test "selection can use the page's event and go to a LiveComponent" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table
          id="sources"
          rows={@rows}
          selectable
          select_event="toggle_copy_target"
          target="#images"
          selectable_row={&(&1.id != 1)}
          select_disabled
        >
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert count(html, "tbody input[type=checkbox]") == 1
      assert attr(html, "tbody input", "phx-click") == ["toggle_copy_target"]
      assert attr(html, "tbody input", "phx-target") == ["#images"]
      assert attr(html, "tbody input", "phx-value-id") == ["2"]
      assert count(html, "tbody input[disabled]") == 1
      # The row without a checkbox keeps its cell, so the columns line up.
      assert count(html, "tbody tr:first-child td") == 2
    end

    test "select_all adds a header checkbox, ticked when every selectable row is" do
      assigns = %{rows: @sources}

      none =
        rendered_to_string(~H"""
        <.data_table
          id="sources"
          rows={@rows}
          selectable
          selected={[1]}
          select_all="select_all"
          select_none="deselect_all"
          target="#hosts"
        >
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert attr(none, "thead input[type=checkbox]", "id") == ["sources-select-all"]
      assert attr(none, "thead input", "aria-label") == ["Select all"]
      assert attr(none, "thead input", "phx-click") == ["select_all"]
      assert attr(none, "thead input", "phx-target") == ["#hosts"]
      assert count(none, "thead input[checked]") == 0

      all =
        rendered_to_string(~H"""
        <.data_table
          id="sources"
          rows={@rows}
          selectable
          selected={MapSet.new([2])}
          selectable_row={&(&1.id == 2)}
          select_all="select_all"
          select_none="deselect_all"
        >
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert count(all, "thead input[checked]") == 1
      assert attr(all, "thead input", "phx-click") == ["deselect_all"]
    end

    test "without select_all the header has no checkbox; select_all alone toggles" do
      assigns = %{rows: @sources}

      plain =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows} selectable>
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert count(plain, "thead input") == 0

      toggle =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows} selectable selected={[1, 2]} select_all="all">
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert attr(toggle, "thead input", "phx-click") == ["all"]
      assert count(toggle, "thead input[checked]") == 1
    end

    test "the checkbox label and id can come from the row" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table
          id="sources"
          rows={@rows}
          selectable
          select_id={& &1.year}
          select_label={&"Select #{&1.title}"}
        >
          <:col :let={s} label="Title">{s.title}</:col>
        </.data_table>
        """)

      assert attr(html, "tbody input", "phx-value-id") == ["1959", "2006"]

      assert hd(attr(html, "tbody input", "aria-label")) ==
               "Select Cynipid galls of the eastern United States"
    end

    test "with no rows shows the empty slot instead of the table" do
      assigns = %{rows: []}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows}>
          <:col :let={s} label="Title">{s.title}</:col>
          <:empty>No Sources match "oak".</:empty>
        </.data_table>
        """)

      assert count(html, "table") == 0
      assert count(html, "th") == 0
      assert text(html, "#sources[data-part=empty]") == ~s(No Sources match "oak".)
    end

    test "a column that is empty for every row is not shown" do
      rows = [
        %{id: 1, title: "A", notes: nil, tags: [], code: ""},
        %{id: 2, title: "B", notes: nil, tags: [], code: ""}
      ]

      assigns = %{rows: rows}

      html =
        rendered_to_string(~H"""
        <.data_table id="t" rows={@rows}>
          <:col :let={r} label="Title" field={:title}>{r.title}</:col>
          <:col :let={r} label="Notes" field={:notes}>{r.notes}</:col>
          <:col :let={r} label="Tags" field={:tags}>{Enum.join(r.tags, ", ")}</:col>
          <:col :let={r} label="Code" field={:code}>{r.code}</:col>
          <:col label="Status">—</:col>
        </.data_table>
        """)

      assert html |> query("thead th") |> Enum.map(&LazyHTML.text/1) |> Enum.map(&String.trim/1) ==
               ["Title", "Status"]

      assert count(html, "tbody tr:first-child td") == 2
    end

    test "a column with a value in any row is shown" do
      assigns = %{rows: [%{id: 1, notes: nil}, %{id: 2, notes: "galls in May"}]}

      html =
        rendered_to_string(~H"""
        <.data_table id="t" rows={@rows}>
          <:col :let={r} label="Notes" field={:notes}>{r.notes}</:col>
        </.data_table>
        """)

      assert count(html, "thead th") == 1
    end

    test "renders a stream into a stream container, with its empty row inside" do
      stream = LiveStream.new(:sources, "0", @sources, [])
      assigns = %{streams: %{sources: stream}}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@streams.sources} row_item={fn {_id, s} -> s end}>
          <:col :let={s} label="Title" field={:title}>{s.title}</:col>
          <:empty>No Sources yet.</:empty>
        </.data_table>
        """)

      assert count(html, ~s(tbody#sources[phx-update="stream"])) == 1
      assert attr(html, "tbody tr.h-row", "id") == ["sources-1", "sources-2"]
      assert text(html, "tbody tr#sources-1") =~ "Cynipid galls"
      # A stream can't be inspected, so the empty state lives in the body
      assert count(html, "tbody #sources-empty.hidden.only\\:table-row") == 1
    end

    test "the footer sits under the table" do
      assigns = %{rows: @sources}

      html =
        rendered_to_string(~H"""
        <.data_table id="sources" rows={@rows} class="mt-4">
          <:col :let={s} label="Title">{s.title}</:col>
          <:footer>2 Sources</:footer>
        </.data_table>
        """)

      assert text(html, "[data-part=footer]") == "2 Sources"
      assert count(html, "div.mt-4 > div.overflow-x-auto > table") == 1
    end
  end

  describe "fact_list" do
    test "is a dl of label/value pairs, from the slot or from value" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.fact_list>
          <:item label="Detachable">Integral</:item>
          <:item label="Color" value="brown" />
          <:item label="Seasons" value={["Spring", "Summer"]} />
        </.fact_list>
        """)

      assert count(html, "dl > div > dt") == 3

      assert html |> query("dt") |> Enum.map(&String.trim(LazyHTML.text(&1))) ==
               ["Detachable", "Color", "Seasons"]

      assert html |> query("dd") |> Enum.map(&String.trim(LazyHTML.text(&1))) ==
               ["Integral", "brown", "Spring, Summer"]
    end

    test "missing items collect into one line at the end" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.fact_list>
          <:item label="Shape" value={nil} />
          <:item label="Detachable">Integral</:item>
          <:item label="Alignment" value="" />
          <:item label="Walls" value={[]} />
        </.fact_list>
        """)

      assert count(html, "dt") == 1
      assert text(html, "[data-part=missing]") == "Not recorded: shape, alignment, walls"
    end

    test "missing_label names the line, and nil hides missing items" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.fact_list missing_label="Unknown">
          <:item label="Shape" />
        </.fact_list>
        """)

      assert text(html, "[data-part=missing]") == "Unknown: shape"
      assert count(html, "dl") == 0

      html =
        rendered_to_string(~H"""
        <.fact_list missing_label={nil}>
          <:item label="Shape" />
          <:item label="Detachable">Integral</:item>
        </.fact_list>
        """)

      assert count(html, "[data-part=missing]") == 0
      refute html =~ "Shape"
    end

    test "grid columns are one on phones and up to three on wider screens" do
      for {columns, class} <- [{1, nil}, {2, "sm:grid-cols-2"}, {3, "lg:grid-cols-3"}] do
        assigns = %{columns: columns}

        html =
          rendered_to_string(~H"""
          <.fact_list columns={@columns}>
            <:item label="Shape">Round</:item>
          </.fact_list>
          """)

        assert count(html, "dl.grid.grid-cols-1") == 1
        if class, do: assert(count(html, "dl.#{String.replace(class, ":", "\\:")}") == 1)
      end
    end

    test "each layout marks itself" do
      for layout <- [:grid, :inline] do
        assigns = %{layout: layout}

        html =
          rendered_to_string(~H"""
          <.fact_list layout={@layout}>
            <:item label="Shape">Round</:item>
          </.fact_list>
          """)

        assert count(html, "dl[data-layout=#{layout}]") == 1
      end
    end
  end

  describe "name_list" do
    test "is a list of names flowing into columns" do
      assigns = %{items: ["Quercus alba", "Quercus rubra", "Quercus velutina"]}
      html = rendered_to_string(~H|<.name_list items={@items} columns={3} />|)

      assert count(html, "ul.columns-1.sm\\:columns-2.lg\\:columns-3") == 1
      assert count(html, "ul > li.break-inside-avoid") == 3
      assert text(html, "li:first-child") == "Quercus alba"
      assert count(html, "ul.italic") == 0
    end

    test "defaults to four columns at most and sets scientific names in italic" do
      assigns = %{items: ["Quercus alba"]}
      html = rendered_to_string(~H|<.name_list items={@items} italic />|)
      assert count(html, "ul.lg\\:columns-4.italic") == 1
    end

    test "one column stays one column" do
      assigns = %{items: ["Quercus alba"]}
      html = rendered_to_string(~H|<.name_list items={@items} columns={1} />|)
      assert count(html, "ul.columns-1") == 1
      assert count(html, "ul[class*=sm\\:columns]") == 0
    end

    test "the item slot renders each item" do
      assigns = %{items: [%{name: "Quercus alba", count: 12}]}

      html =
        rendered_to_string(~H"""
        <.name_list items={@items}>
          <:item :let={h}><a href="/host/1">{h.name}</a> {h.count}</:item>
        </.name_list>
        """)

      assert text(html, "li a[href='/host/1']") == "Quercus alba"
      assert text(html, "li") =~ "12"
    end
  end

  describe "stat" do
    test "a formatted number with its label" do
      assigns = %{}
      html = rendered_to_string(~H|<.stat value={3976} label="Galls" />|)

      assert text(html, "[data-part=value]") == "3,976"
      assert count(html, "[data-part=value].tabular-nums.font-brand") == 1
      assert text(html, "[data-part=label]") == "Galls"
      assert count(html, "a") == 0
    end

    test "shows other values as given, with an icon" do
      assigns = %{}
      html = rendered_to_string(~H|<.stat value="98%" label="Complete" icon="gf-gall" />|)
      assert text(html, "[data-part=value]") == "98%"
      assert count(html, "span.gf-gall") == 1
    end

    test "is a link with navigate" do
      assigns = %{}

      html =
        rendered_to_string(~H|<.stat value={358} label="To review" navigate="/admin/review" />|)

      assert count(html, "a[href='/admin/review'] [data-part=value]") == 1
    end
  end

  describe "empty_state" do
    test "a title, an explanation and an action" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.empty_state title="No Sources yet" icon="gf-source">
          Sources you add appear here.
          <:action><a href="/admin/sources/new">Add a Source</a></:action>
        </.empty_state>
        """)

      assert text(html, "[data-part=title]") == "No Sources yet"
      assert text(html, "[data-part=description]") == "Sources you add appear here."
      assert count(html, "[data-part=actions] a[href='/admin/sources/new']") == 1
      assert count(html, "span.gf-source") == 1
    end

    test "with only a title" do
      assigns = %{}
      html = rendered_to_string(~H|<.empty_state title="Nothing here" />|)
      assert text(html, "[data-part=title]") == "Nothing here"

      assert count(
               html,
               "[data-part=description], [data-part=actions], span[class*=gf-], span[class*=ph-]"
             ) == 0
    end
  end
end
