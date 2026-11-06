defmodule GallformersWeb.RankPageComponents do
  @moduledoc """
  The rank pages' parts (genus, section, family and the intermediate ranks;
  docs/design-system/patterns.md, "Rank pages" and "Plant pages"): the
  Galls list with facets (`rank_galls`), the plants table (`plant_table`)
  with its Gallformer-genus filter (`inducer_genera_panel`), the Galls on a
  taxon as a whole (`galls_on_panel`), the taxa within (`children_list`),
  and the admin edit button.
  """
  use Phoenix.Component

  import GallformersWeb.ActionComponents, only: [button: 1]
  import GallformersWeb.CoreComponents, only: [icon: 1]
  import GallformersWeb.DataComponents, only: [chip: 1, data_table: 1]
  import GallformersWeb.DataDisplayComponents, only: [taxon_name: 1]
  import GallformersWeb.DomainComponents, only: [gall_card: 1]
  import GallformersWeb.FormComponents, only: [facet_group: 1]
  import GallformersWeb.Helpers, only: [format_number: 1]
  import GallformersWeb.PageComponents, only: [panel: 1, section: 1]
  import GallformersWeb.UIComponents, only: [pagination: 1]

  alias Phoenix.LiveView.JS

  alias Gallformers.Accounts

  @doc """
  The rank page's "Edit" button to the taxon's page in the taxonomy admin,
  shown to admins only. Goes in the `page_header`'s `action` slot.
  """
  attr :current_user, :any, required: true
  attr :taxon_id, :integer, required: true

  def admin_edit_link(assigns) do
    ~H"""
    <.button
      :if={Accounts.admin?(@current_user)}
      href={"/admin/taxonomy/#{@taxon_id}"}
      variant="ghost"
      size="sm"
      icon="ph-pencil-simple"
      title="Edit in admin"
    >
      Edit
    </.button>
    """
  end

  @doc """
  The Galls list of a rank page (`GallformersWeb.RankGalls`): facets beside
  it when it has them ("Narrow it down", Clear all), the Photos/Table switch,
  `gall_card`s in a photo grid or a sortable `data_table`, and pagination.
  The heading counts what is shown, "N of M" while the name filter or a
  facet narrows it. Events: `galls_filter`, `galls_clear`, `galls_view`,
  `galls_page` (`RankGalls.handle/3`), and the page's `sort`.
  """
  attr :id, :string, required: true, doc: "the table's id"
  attr :list, :map, required: true, doc: "a computed `RankGalls` list"
  attr :sort, :map, required: true
  attr :narrowed, :boolean, required: true, doc: "whether the page's name filter is set"
  attr :title, :string, default: "Galls"

  attr :edit_path, :any,
    default: nil,
    doc: "function gall -> its admin page; gives each Gall an edit link (pass it for admins only)"

  def rank_galls(assigns) do
    ~H"""
    <div class="grid gap-section lg:grid-cols-4">
      <aside
        :if={@list.facets != []}
        class="flex flex-col gap-4 self-start lg:sticky lg:top-20"
        aria-label="Filters"
      >
        <div class="flex items-baseline justify-between">
          <h2 class="text-subsection">Narrow it down</h2>
          <.button :if={@list.selected != %{}} variant="ghost" size="sm" phx-click="galls_clear">
            Clear all
          </.button>
        </div>
        <form id={"#{@id}-facets"} phx-change="galls_filter" class="flex flex-col gap-5">
          <.facet_group
            :for={facet <- @list.facets}
            id={"#{@id}-facet-#{facet.key}"}
            title={facet.title}
            name={facet.key}
            options={facet.options}
            italic={facet.key == "host"}
            limit={5}
          />
        </form>
      </aside>

      <div class={["min-w-0", if(@list.facets != [], do: "lg:col-span-3", else: "lg:col-span-4")]}>
        <.section id={"#{@id}-section"} title={@title} count={count_label(@list, @narrowed)}>
          <:aside>
            <.view_switch :if={length(@list.views) > 1} view={@list.view} />
          </:aside>
          <p :if={@list.shown == []} class="text-ui text-muted">
            No galls match these filters.
          </p>
          <div :if={@list.view == :photos and @list.shown != []} class="gf-photo-grid" data-size="sm">
            <div :for={g <- @list.shown} class="relative min-w-0">
              <.gall_card
                navigate={g.navigate}
                name={g.name}
                image_url={g.image_url}
                image_alt=""
                subtitle={g.subtitle}
                size={:sm}
              >
                <:chip :if={g.undescribed} variant={:info}>Undescribed</:chip>
              </.gall_card>
              <.link
                :if={@edit_path}
                href={@edit_path.(g)}
                title={"Edit #{g.name} in admin"}
                aria-label={"Edit #{g.name} in admin"}
                class="absolute top-1.5 right-1.5 inline-flex size-7 items-center justify-center rounded-ctl bg-surface text-ink-2 shadow-float hover:text-ink"
              >
                <.icon name="ph-pencil-simple" class="size-4" />
              </.link>
            </div>
          </div>
          <.data_table
            :if={@list.view == :table and @list.shown != []}
            id={@id}
            rows={@list.shown}
            row_navigate={& &1.navigate}
            sort={@sort}
          >
            <:col :let={g} label="Gall" field={:name} sortable grow>
              <.link navigate={g.navigate}><.taxon_name name={g.name} /></.link>
              <.chip :if={g.undescribed} variant={:info} size="sm" class="ml-1">Undescribed</.chip>
            </:col>
            <:col :let={g} label="Common name" field={:common_name} sortable>{g.common_name}</:col>
            <:col :let={g} label="Hosts" field={:count} sortable numeric>{g.count}</:col>
            <:col :let={g} label="Plant part" field={:plant_part} hide_below={:md}>
              {g.plant_part}
            </:col>
            <:col :let={g} label="Season" field={:season} hide_below={:lg}>{g.season}</:col>
            <:col :let={g} :if={@edit_path} label="Edit">
              <.link
                href={@edit_path.(g)}
                title={"Edit #{g.name} in admin"}
                aria-label={"Edit #{g.name} in admin"}
              >
                <.icon name="ph-pencil-simple" class="size-4" />
              </.link>
            </:col>
          </.data_table>
          <.pagination
            :if={@list.total_pages > 1}
            page={@list.page}
            total_pages={@list.total_pages}
            total_items={@list.shown_count}
            page_size={@list.page_size}
            on_page_change={&JS.push("galls_page", value: %{page: &1})}
            class="mt-3"
          />
        </.section>
      </div>
    </div>
    """
  end

  defp count_label(list, narrowed) do
    shown = format_number(list.shown_count)

    if narrowed or list.selected != %{},
      do: "#{shown} of #{format_number(length(list.all))}",
      else: shown
  end

  attr :view, :atom, required: true

  defp view_switch(assigns) do
    ~H"""
    <span
      class="inline-flex overflow-hidden rounded-ctl border border-line-strong"
      role="group"
      aria-label="View"
    >
      <button
        :for={{view, label} <- [photos: "Photos", table: "Table"]}
        type="button"
        phx-click="galls_view"
        phx-value-view={view}
        aria-pressed={to_string(@view == view)}
        class={[
          "px-3 py-1 text-meta font-semibold",
          if(@view == view, do: "bg-brand-fill text-on-fill", else: "bg-surface text-ink-2")
        ]}
      >
        {label}
      </button>
    </span>
    """
  end

  @doc """
  A rank page's plants (`GallformersWeb.RankPage.host_rows/1`, already filtered): a
  sortable `data_table` of name, common name and Galls, each row linking to
  its Host page. The heading counts what is shown, "N of M" while narrowed.
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :total, :integer, required: true
  attr :sort, :map, required: true
  attr :title, :string, default: "Species"

  def plant_table(assigns) do
    ~H"""
    <.section
      id={"#{@id}-section"}
      title={@title}
      count={
        if length(@rows) == @total,
          do: format_number(@total),
          else: "#{format_number(length(@rows))} of #{format_number(@total)}"
      }
    >
      <.data_table id={@id} rows={@rows} row_navigate={&"/host/#{&1.id}"} sort={@sort}>
        <:col :let={s} label="Species" field={:name} sortable grow>
          <.link navigate={"/host/#{s.id}"}><.taxon_name name={s.name} /></.link>
        </:col>
        <:col :let={s} label="Common name" field={:common_name} sortable>{s.common_name}</:col>
        <:col :let={s} label="Galls" field={:count} sortable numeric>
          <span class={s.count == 0 && "text-muted"}>{s.count}</span>
        </:col>
        <:empty>No species match this filter.</:empty>
      </.data_table>
    </.section>
    """
  end

  @doc """
  The Gallformer genera with Galls on a rank page's plants, each with how
  many of the plants it has Galls on. Each is a filter for the plants table
  (`plants_filter` with `phx-value-id`, `"all"` to clear); the chosen one
  is pressed, and its name links to its page.
  """
  attr :name, :string, required: true, doc: "the taxon's name, for the heading"
  attr :genera, :list, required: true, doc: "`Catalog.inducer_genera_on_hosts/1`"
  attr :selected, :any, default: nil, doc: "the chosen genus's taxon ID"

  def inducer_genera_panel(assigns) do
    ~H"""
    <.panel title={"Gallformers on #{@name}"}>
      <p class="text-meta text-ink-2">Choose a genus to see the plants it has galls on.</p>
      <ul class="flex flex-col text-ui" role="group" aria-label="Filter by gall-former genus">
        <li
          :for={g <- @genera}
          class="flex items-baseline justify-between gap-2 border-b border-line py-1 last:border-b-0"
        >
          <button
            type="button"
            phx-click="plants_filter"
            phx-value-id={g.taxon_id}
            aria-pressed={to_string(@selected == g.taxon_id)}
            title={"#{g.association_count} associations"}
            class={["text-left text-link hover:underline", @selected == g.taxon_id && "font-semibold"]}
          >
            <.taxon_name name={g.name} rank="genus" />
          </button>
          <span class="flex items-baseline gap-2">
            <span class="text-meta tabular-nums text-muted">{length(g.focal_ids)}</span>
            <.link
              navigate={"/genus/#{URI.encode(g.name)}"}
              class="text-muted hover:text-ink"
              aria-label={"#{g.name} page"}
            >
              <.icon name="ph-arrow-right" class="size-3.5" />
            </.link>
          </span>
        </li>
      </ul>
      <:footer :if={@selected}>
        <.button variant="ghost" size="sm" phx-click="plants_filter" phx-value-id="all">
          Show all plants
        </.button>
      </:footer>
    </.panel>
    """
  end

  @doc """
  The Galls recorded on a taxon as a whole, with no species named (today's
  "Genus spp."): links with their Host counts.
  """
  attr :name, :string, required: true
  attr :galls, :list, required: true, doc: "`GallformersWeb.RankPage.row/0`s"

  def galls_on_panel(assigns) do
    ~H"""
    <.panel title={"Galls on #{@name} as a whole"}>
      <p class="text-meta text-ink-2">Recorded on the genus, with no species named.</p>
      <ul id="galls-on-taxon" class="flex flex-col gap-1 text-ui">
        <li :for={g <- @galls} class="flex items-baseline justify-between gap-2">
          <.link navigate={"/gall/#{g.id}"}><.taxon_name name={g.name} /></.link>
          <span class="text-meta tabular-nums text-muted">
            {if g.count == 1, do: "1 host", else: "#{g.count} hosts"}
          </span>
        </li>
      </ul>
    </.panel>
    """
  end

  @doc """
  The taxa directly under a family or intermediate rank (`GallformersWeb.RankPage.children/1`):
  for Gallformers a dense list in columns, each with its Galls; for plants a
  `data_table` of name, common name, species and Galls on it. Sorted by the
  page's `sort` (`name`, `type`, `gall_count`, `host_count`); children whose
  rank has no page are plain text.
  """
  attr :children, :list, required: true
  attr :sort, :map, required: true
  attr :plants, :boolean, default: false

  def children_list(%{plants: true} = assigns) do
    ~H"""
    <.data_table id="children" rows={@children} row_navigate={& &1.url} sort={@sort}>
      <:col :let={c} label="Name" field={:name} sortable grow>
        <.link :if={c.url} navigate={c.url}><.taxon_name name={c.name} rank={c.rank} /></.link>
        <.taxon_name :if={!c.url} name={c.name} rank={c.rank} />
        <span :if={c.rank != "genus"} class="text-meta text-muted">{c.rank}</span>
      </:col>
      <:col :let={c} label="Common name" field={:description} wrap>{c.description}</:col>
      <:col :let={c} label="Species" field={:host_count} sortable numeric>
        {format_number(c.host_count)}
      </:col>
      <:col :let={c} label="Galls" field={:gall_count} sortable numeric>
        <span class={c.gall_count == 0 && "text-muted"}>{format_number(c.gall_count)}</span>
      </:col>
      <:empty>No taxa match this filter.</:empty>
    </.data_table>
    """
  end

  def children_list(assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <div class="flex items-center gap-2 text-meta text-ink-2" role="group" aria-label="Sort">
        Sort:
        <button
          :for={{field, label} <- [gall_count: "Most galls", name: "Name"]}
          type="button"
          phx-click="sort"
          phx-value-field={field}
          aria-pressed={to_string(@sort.field == field)}
          class={[
            "hover:underline",
            if(@sort.field == field, do: "font-semibold text-ink", else: "text-link")
          ]}
        >
          {label}
        </button>
      </div>
      <p :if={@children == []} class="text-ui text-muted">No taxa match this filter.</p>
      <ul id="children" class="columns-1 gap-x-8 sm:columns-2 lg:columns-3 xl:columns-4">
        <li :for={c <- @children} class="break-inside-avoid border-b border-line">
          <div class="flex items-baseline justify-between gap-3 py-1.5">
            <span class="min-w-0">
              <.link :if={c.url} navigate={c.url}><.taxon_name name={c.name} rank={c.rank} /></.link>
              <.taxon_name :if={!c.url} name={c.name} rank={c.rank} />
              <span :if={c.rank != "genus"} class="text-meta text-muted">{c.rank}</span>
              <span :if={c.description} class="text-meta text-ink-2">({c.description})</span>
            </span>
            <span class="text-meta tabular-nums text-muted">
              {format_number(c.gall_count)} {if c.gall_count == 1, do: "gall", else: "galls"}
            </span>
          </div>
        </li>
      </ul>
    </div>
    """
  end
end
