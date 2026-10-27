defmodule GallformersWeb.RankPageComponents do
  @moduledoc """
  The species table the rank pages share (genus, section, and the Galls
  placed at a family or intermediate rank): name, common name and a count,
  sortable by each. Rows are `GallformersWeb.RankPage.row/0`s.
  """
  use Phoenix.Component

  import GallformersWeb.DataDisplayComponents, only: [taxon_name: 1]

  alias GallformersWeb.RankPage

  attr :id, :string, required: true
  attr :rows, :list, required: true, doc: "the rows shown (already filtered)"
  attr :url_prefix, :string, required: true, doc: "each row links to this plus its ID"
  attr :name_header, :string, default: "Species Name"
  attr :count_header, :string, required: true
  attr :sort_by, :atom, default: nil, doc: "nil for an unsortable table"
  attr :sort_dir, :atom, default: :asc

  def species_table(assigns) do
    assigns =
      assign(
        assigns,
        :sorted,
        if(assigns.sort_by,
          do: RankPage.sort_rows(assigns.rows, assigns.sort_by, assigns.sort_dir),
          else: assigns.rows
        )
      )

    ~H"""
    <div id={@id} class="bg-white rounded border border-gray-200 overflow-hidden">
      <table class="gf-table">
        <thead>
          <tr>
            <.sort_header column="name" label={@name_header} sort_by={@sort_by} sort_dir={@sort_dir} />
            <.sort_header
              column="common_name"
              label="Common Name"
              class="text-center"
              sort_by={@sort_by}
              sort_dir={@sort_dir}
            />
            <.sort_header
              column="count"
              label={@count_header}
              class="text-center"
              sort_by={@sort_by}
              sort_dir={@sort_dir}
            />
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @sorted}>
            <td>
              <.link href={"#{@url_prefix}#{row.id}"} class="hover:underline">
                <.taxon_name name={row.name} />
              </.link>
            </td>
            <td class="text-center">{row.common_name}</td>
            <td class="text-center text-gray-600">{row.count}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :column, :string, required: true
  attr :label, :string, required: true
  attr :class, :string, default: nil
  attr :sort_by, :atom, default: nil
  attr :sort_dir, :atom, default: :asc

  defp sort_header(%{sort_by: nil} = assigns) do
    ~H"""
    <th class={@class}>{@label}</th>
    """
  end

  defp sort_header(assigns) do
    ~H"""
    <th class={["sortable", @class]} phx-click="sort" phx-value-column={@column}>
      {@label}
      <span :if={Atom.to_string(@sort_by) == @column} class="ml-1">
        {if @sort_dir == :asc, do: "↑", else: "↓"}
      </span>
    </th>
    """
  end
end
