defmodule GallformersWeb.PageComponents do
  @moduledoc """
  The design system's page structure: `page_header`, `section`, `panel`,
  `rail`, `tab_nav`, `chip_nav`, `link_tile`, and `prose` for running
  text.

  A page is a `page_header` (its only `h1`), then `section`s: headings on a
  rule, not boxes. A `panel` is a separate object on the page; a `rail` is
  the side column of a detail or edit page. See
  docs/design-system/components.md ("Page structure") and patterns.md.
  """
  use Phoenix.Component

  import GallformersWeb.DataComponents, only: [chip: 1]

  @doc """
  The top of every page: breadcrumb, title (the page's only `h1`), chips,
  one meta line and actions.

  `title` with `name` sets a scientific name in the text face's true italics;
  without it, the title is set in the brand face.

  ## Examples

      <.page_header>
        <:crumb navigate={~p"/family/Cynipidae"}>Cynipidae</:crumb>
        <:crumb navigate={~p"/genus/Callirhytis"} italic>Callirhytis</:crumb>
        <:title name>Callirhytis quercuscornigera (agamic)</:title>
        <:chip variant={:warn}>In progress</:chip>
        <:meta label="Season">Spring, Summer</:meta>
        <:action><.edit_toggle editing={@editing} path={~p"/gall/821"} /></:action>
      </.page_header>
  """
  attr :class, :any, default: nil, doc: "layout only"

  slot :crumb, doc: "one breadcrumb step, in order" do
    attr :navigate, :string
    attr :href, :string
    attr :italic, :boolean
  end

  slot :title, required: true do
    attr :name, :boolean, doc: "a scientific name: text face, italic"
  end

  slot :chip do
    attr :variant, :atom
  end

  slot :meta, doc: "a label/value pair on the line under the title" do
    attr :label, :string
  end

  slot :action, doc: "an action at the right of the title row"
  slot :description, doc: "a sentence under the title saying what this page is"

  def page_header(assigns) do
    ~H"""
    <header class={["flex flex-col gap-1", @class]}>
      <nav :if={@crumb != []} aria-label="Breadcrumb" class="text-meta text-muted">
        <ol class="flex flex-wrap items-center gap-x-1.5">
          <li :for={{crumb, i} <- Enum.with_index(@crumb)} class="flex items-center gap-x-1.5">
            <span :if={i > 0} aria-hidden="true">›</span>
            <.link navigate={crumb[:navigate]} href={crumb[:href]}>
              <em :if={crumb[:italic]}>{render_slot(crumb)}</em>
              <span :if={!crumb[:italic]}>{render_slot(crumb)}</span>
            </.link>
          </li>
        </ol>
      </nav>

      <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
        <h1
          :for={title <- @title}
          class={[
            "text-page text-ink",
            if(title[:name], do: "font-sans italic font-semibold", else: "font-brand")
          ]}
        >
          {render_slot(title)}
        </h1>
        <div :if={@chip != []} data-part="chips" class="flex flex-wrap items-center gap-1.5">
          <.chip :for={chip <- @chip} variant={chip[:variant] || :neutral}>
            {render_slot(chip)}
          </.chip>
        </div>
        <div :if={@action != []} data-part="actions" class="ml-auto flex flex-wrap items-center gap-2">
          {render_slot(@action)}
        </div>
      </div>

      <p :if={@description != []} data-part="description" class="max-w-lead text-lead text-ink-2">
        {render_slot(@description)}
      </p>

      <dl :if={@meta != []} data-part="meta" class="flex flex-wrap gap-x-5 gap-y-1 text-body">
        <div :for={meta <- @meta} class="flex items-baseline gap-1.5">
          <dt :if={meta[:label]} class="text-caption font-semibold uppercase tracking-wide text-muted">
            {meta[:label]}
          </dt>
          <dd class="text-ink-2">{render_slot(meta)}</dd>
        </div>
      </dl>
    </header>
    """
  end

  @doc """
  A part of a page: a heading on a rule, then its content. Not a box.

  ## Examples

      <.section id="hosts" title="Hosts" count={14}>
        <:aside>Oldest first</:aside>
        <.name_list … />
      </.section>
  """
  attr :title, :string, required: true
  attr :count, :any, default: nil, doc: "shown muted beside the title"
  attr :level, :integer, default: 2, values: [2, 3]
  attr :id, :string, default: nil
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  slot :aside, doc: "the right side of the heading row: a sort, a filter, an action"
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <section id={@id} class={["flex flex-col gap-block", @class]} {@rest}>
      <header class={[
        "flex flex-wrap items-baseline gap-x-2.5 gap-y-1 border-b pb-1.5",
        if(@level == 2, do: "border-line-strong", else: "border-line")
      ]}>
        <h2 :if={@level == 2} class="text-section text-ink">{@title}</h2>
        <h3 :if={@level == 3} class="text-subsection text-ink">{@title}</h3>
        <span :if={@count} data-part="count" class="text-meta text-muted tabular-nums">
          {@count}
        </span>
        <div :if={@aside != []} data-part="aside" class="ml-auto text-meta text-muted">
          {render_slot(@aside)}
        </div>
      </header>
      <div>{render_slot(@inner_block)}</div>
    </section>
    """
  end

  @doc """
  A separate object on the page: a bordered surface. Use it when what's
  inside is one object (a review item, the ID Notes, a box in a rail), never
  for a page region (use `section`).

  Variants: `:plain` (surface, line border), `:info` (sky-soft, for
  Gallformers' own notes), `:danger` (a destructive zone).
  """
  attr :variant, :atom, default: :plain, values: [:plain, :info, :danger]
  attr :title, :string, default: nil
  attr :padding, :atom, default: :default, values: [:default, :none]
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  slot :header_action
  slot :inner_block, required: true
  slot :footer

  def panel(assigns) do
    ~H"""
    <div
      data-variant={@variant}
      class={[
        "flex flex-col gap-2 rounded-panel",
        @padding == :default && "p-panel",
        panel_variant(@variant),
        @class
      ]}
      {@rest}
    >
      <div :if={@title || @header_action != []} class="flex items-baseline gap-2">
        <h3
          :if={@title}
          class={[
            "font-brand text-body font-semibold",
            if(@variant == :danger, do: "text-danger", else: "text-ink")
          ]}
        >
          {@title}
        </h3>
        <div :if={@header_action != []} class="ml-auto text-meta">
          {render_slot(@header_action)}
        </div>
      </div>
      {render_slot(@inner_block)}
      <div :if={@footer != []} class="text-meta text-muted">{render_slot(@footer)}</div>
    </div>
    """
  end

  defp panel_variant(:plain), do: "border border-line bg-surface"
  defp panel_variant(:info), do: "bg-sky-soft text-ink-2"
  defp panel_variant(:danger), do: "border border-danger/40 bg-surface"

  @doc """
  The side column of a detail page (`:wide`, 420px) or an admin edit page
  (`:narrow`, 300px). Facts about the record go here; its content goes in
  the main column.

  Put the main column and the rail in a `gf-with-rail` grid. On narrow
  screens they stack: a wide rail comes first (the photo straight after
  the title), a narrow rail last (after the form). `stack` overrides that.

      <div class="gf-with-rail">
        <div>…main column…</div>
        <.rail width={:wide}>…</.rail>
      </div>
  """
  attr :width, :atom, default: :wide, values: [:wide, :narrow]

  attr :stack, :atom,
    default: nil,
    values: [nil, :first, :last],
    doc: "stacking on narrow screens"

  attr :class, :any, default: nil, doc: "layout only"
  slot :inner_block, required: true

  def rail(assigns) do
    ~H"""
    <aside
      data-width={@width}
      data-stack={@stack || if(@width == :wide, do: :first, else: :last)}
      class={["flex flex-col gap-block min-w-0", @class]}
    >
      {render_slot(@inner_block)}
    </aside>
    """
  end

  @doc """
  Tabs that are links: each tab is its own page (Browse's "By what causes
  them", "By host plant", "By place"). The current tab carries
  `aria-current="page"`. For tabs that switch content within a page, use
  `tabs`.

      <.tab_nav label="Browse by">
        <:tab navigate={~p"/galls"} current>By what causes them</:tab>
        <:tab navigate={~p"/hosts"}>By host plant</:tab>
      </.tab_nav>
  """
  attr :label, :string, required: true, doc: "the nav's accessible name"
  attr :class, :any, default: nil, doc: "layout only"

  slot :tab, required: true do
    attr :navigate, :string
    attr :href, :string
    attr :patch, :string
    attr :current, :boolean
  end

  def tab_nav(assigns) do
    ~H"""
    <nav aria-label={@label} class={["flex flex-wrap gap-1 border-b border-line text-ui", @class]}>
      <.link
        :for={tab <- @tab}
        navigate={tab[:navigate]}
        href={tab[:href]}
        patch={tab[:patch]}
        aria-current={tab[:current] && "page"}
        class={[
          "-mb-px border-b-2 px-3 py-2 hover:no-underline",
          if(tab[:current],
            do: "border-brand font-semibold text-ink",
            else: "border-transparent text-ink-2 hover:border-line-strong hover:text-ink"
          )
        ]}
      >
        {render_slot(tab)}
      </.link>
    </nav>
    """
  end

  @doc """
  Running text: rendered Markdown (articles, ID Notes, a Source's text) or a
  page's own long-form markup (Privacy). Styles headings, lists, links,
  quotes, figures, tables, code and `details` from tokens. It sets no width;
  put it in a `max-w-text` column for reading.

  `size` steps the text (the source reader's A−/A+); `font` sets the face
  (ID Notes and Source text read in serif).

      <.prose markdown={@article.content} class="max-w-text" />
      <.prose markdown={@note.description} size={:sm} font={:serif} />
      <.prose><h2>How it works</h2><p>…</p></.prose>

  `markdown` is rendered with `Gallformers.Markdown` (glossary terms linked)
  and inserted unescaped: only admins write it.
  """
  attr :markdown, :string, default: nil
  attr :size, :atom, default: :base, values: [:sm, :base, :lg, :xl]
  attr :font, :atom, default: :sans, values: [:sans, :serif]
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  slot :inner_block

  def prose(assigns) do
    ~H"""
    <div class={["gf-prose", @class]} data-size={@size} data-font={@font} {@rest}>
      <%= if @inner_block != [] do %>
        {render_slot(@inner_block)}
      <% else %>
        {Phoenix.HTML.raw(Gallformers.Markdown.render!(@markdown))}
      <% end %>
    </div>
    """
  end

  @doc """
  Links as a row of chips that wraps: filters that are their own pages
  (the Articles list's topics). The current chip is filled and carries
  `aria-current="page"`; a chip may show a `count`. For page tabs, use
  `tab_nav`.

      <.chip_nav label="Topics">
        <:chip href={~p"/articles"} current>All</:chip>
        <:chip href={~p"/articles?tag=faq"} count={1}>faq</:chip>
      </.chip_nav>
  """
  attr :label, :string, required: true, doc: "the nav's accessible name"
  attr :class, :any, default: nil, doc: "layout only"

  slot :chip, required: true do
    attr :href, :string
    attr :navigate, :string
    attr :patch, :string
    attr :current, :boolean
    attr :count, :integer
  end

  def chip_nav(assigns) do
    ~H"""
    <nav aria-label={@label} class={["flex flex-wrap gap-2 text-ui", @class]}>
      <.link
        :for={chip <- @chip}
        href={chip[:href]}
        navigate={chip[:navigate]}
        patch={chip[:patch]}
        aria-current={chip[:current] && "page"}
        class={[
          "rounded-full border px-3 py-1 hover:no-underline",
          if(chip[:current],
            do: "border-brand-fill bg-brand-fill text-on-fill",
            else: "border-line-strong bg-surface text-ink-2 hover:border-brand hover:text-ink"
          )
        ]}
      >
        {render_slot(chip)}
        <span
          :if={chip[:count]}
          data-part="count"
          class={if(chip[:current], do: "opacity-80", else: "text-muted")}
        >
          {chip[:count]}
        </span>
      </.link>
    </nav>
    """
  end

  @doc """
  A link to another part of the site, as a small tile: an icon on a tinted
  square, a name and one line saying what is there. For a row of "More to
  read" links at the end of a page.

      <.link_tile href={~p"/keys"} icon="ph-tree-structure" name="Identification keys">
        4 step-by-step keys
      </.link_tile>
  """
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :name, :string, required: true
  attr :class, :any, default: nil, doc: "layout only"

  slot :inner_block, doc: "the line under the name"

  def link_tile(assigns) do
    ~H"""
    <.link
      href={@href}
      class={[
        "flex items-center gap-3 rounded-panel border border-line bg-surface p-3 hover:bg-sky-soft hover:no-underline",
        @class
      ]}
    >
      <span class="flex size-10 shrink-0 items-center justify-center rounded-ctl bg-sky text-link">
        <GallformersWeb.CoreComponents.icon name={@icon} class="size-5" />
      </span>
      <span class="flex min-w-0 flex-col">
        <span data-part="name" class="font-semibold text-ink">{@name}</span>
        <span :if={@inner_block != []} data-part="line" class="text-meta text-muted">
          {render_slot(@inner_block)}
        </span>
      </span>
    </.link>
    """
  end
end
