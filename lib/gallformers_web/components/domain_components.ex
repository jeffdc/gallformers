defmodule GallformersWeb.DomainComponents do
  @moduledoc """
  The design system's domain components: `gall_card`, `category_tile`,
  `family_card`, `photo_viewer`, `source_entry`, `source_quote`,
  `article_card`, `change_entry` (and later `range_map`).

  They take plain values (strings, URLs, booleans), not database structs, so
  any page can map its own read model onto them.

  See docs/design-system/components.md ("Domain").
  """
  use Phoenix.Component

  import GallformersWeb.ActionComponents, only: [button: 1]
  import GallformersWeb.CoreComponents, only: [icon: 1]
  import GallformersWeb.DataComponents, only: [chip: 1]
  import GallformersWeb.DataDisplayComponents, only: [taxon_name: 1]
  import GallformersWeb.Helpers, only: [format_number: 1, list_separator: 2, time_ago: 1]
  import GallformersWeb.PageComponents, only: [panel: 1]

  alias GallformersWeb.TaxonomyURL
  alias Phoenix.LiveView.JS

  @doc """
  A Gall at a glance, for photo grids (ID results, rank pages, browse, the
  home page): a square photo, the name, and one muted line of what tells the
  Gall apart. The whole card is one link.

  A Gall with no photo shows the gall icon on a well, never an empty box.
  The page's grid sets the card's width (about 200px cells for `:md`, 140px
  for `:sm`); `size` sets the type to match.

  ## Examples

      <.gall_card
        navigate={~p"/gall/582"}
        name="Callirhytis quercuscornigera (agamic)"
        image_url={gall.image_url}
        subtitle="stem · abrupt swelling · spring"
      />

      <.gall_card navigate={~p"/gall/9"} name="Unknown (Cynipidae) q-rubra-spur-gall" size={:sm}>
        <:chip variant={:info}>Undescribed</:chip>
      </.gall_card>
  """
  attr :navigate, :string, required: true, doc: "the Gall's page"
  attr :name, :string, required: true, doc: "the Gall's full name, set as a scientific name"
  attr :image_url, :string, default: nil, doc: "the photo; nil shows the placeholder"

  attr :image_alt, :string,
    default: nil,
    doc: ~s|the photo's alt text; nil derives "Photo of <name>", "" marks it decorative|

  attr :subtitle, :string,
    default: nil,
    doc: ~s|the muted line of distinguishing traits, e.g. "stem · abrupt swelling · spring"|

  attr :size, :atom, default: :md, values: [:md, :sm]
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  slot :chip, doc: "a chip under the name, e.g. Undescribed" do
    attr :variant, :atom
  end

  def gall_card(assigns) do
    assigns = assign(assigns, :alt, assigns.image_alt || "Photo of #{assigns.name}")

    ~H"""
    <.link
      navigate={@navigate}
      data-size={@size}
      class={["group flex min-w-0 flex-col gap-1.5 rounded-panel hover:no-underline", @class]}
      {@rest}
    >
      <img
        :if={@image_url}
        src={@image_url}
        alt={@alt}
        loading="lazy"
        class="aspect-square w-full rounded-panel bg-surface-2 object-cover"
      />
      <div
        :if={!@image_url}
        data-part="placeholder"
        class="flex aspect-square w-full items-center justify-center rounded-panel bg-surface-2 text-muted"
      >
        <.icon name="gf-gall" class={if(@size == :sm, do: "size-8", else: "size-12")} />
      </div>
      <div class="flex min-w-0 flex-col gap-0.5">
        <span
          data-part="name"
          class={[
            "line-clamp-2 font-semibold text-ink group-hover:underline",
            if(@size == :sm, do: "text-meta", else: "text-ui")
          ]}
        >
          <.taxon_name name={@name} />
        </span>
        <span
          :if={@subtitle}
          data-part="subtitle"
          title={@subtitle}
          class={["truncate text-muted", if(@size == :sm, do: "text-caption", else: "text-meta")]}
        >
          {@subtitle}
        </span>
        <span :if={@chip != []} data-part="chips" class="flex flex-wrap gap-1 pt-0.5">
          <.chip :for={chip <- @chip} variant={chip[:variant] || :neutral} size="sm">
            {render_slot(chip)}
          </.chip>
        </span>
      </div>
    </.link>
    """
  end

  @doc """
  A group of Galls to browse into, with a photo, its name and how many
  Galls it holds: the home page's "Start from the plant" (Host genera) and
  "Browse by what causes them" (Gallformer groups). The whole tile is one
  link.

  `layout` `:row` (the default) is a compact list row: a small thumbnail,
  the name and the count on one line, ruled below. Lay rows out in a
  `<ul>` grid, one or two columns. `:tile` puts a square photo above the
  name and count, for `gf-photo-grid data-size="sm"`.

  The photo is decorative (the name says what the tile is). With no photo
  the tile shows `icon` on a well, so names stay aligned.

  ## Examples

      <ul class="grid gap-x-6 sm:grid-cols-2">
        <li :for={genus <- @genera}>
          <.category_tile navigate={"/id?g=\#{genus.name}"} name={genus.name}
            count={genus.count} image_url={genus.image_url} italic />
        </li>
      </ul>
  """
  attr :navigate, :string, required: true
  attr :name, :string, required: true
  attr :count, :integer, required: true, doc: "how many Galls the group holds"
  attr :image_url, :string, default: nil

  attr :italic, :boolean,
    default: false,
    doc: "set the name as a scientific name (genus and below)"

  attr :icon, :string, default: "gf-gall", doc: "shown on the well when there is no photo"
  attr :layout, :atom, default: :row, values: [:row, :tile]
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  def category_tile(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      data-layout={@layout}
      class={[
        "group flex min-w-0 hover:no-underline",
        if(@layout == :row,
          do: "items-center gap-3 border-b border-line py-1.5",
          else: "flex-col gap-1.5"
        ),
        @class
      ]}
      {@rest}
    >
      <img
        :if={@image_url}
        src={@image_url}
        alt=""
        loading="lazy"
        class={["shrink-0 bg-surface-2 object-cover", thumb_class(@layout)]}
      />
      <div
        :if={!@image_url}
        data-part="placeholder"
        class={[
          "flex shrink-0 items-center justify-center bg-surface-2 text-muted",
          thumb_class(@layout)
        ]}
      >
        <.icon name={@icon} class={if(@layout == :row, do: "size-5", else: "size-8")} />
      </div>
      <div class="flex min-w-0 flex-1 items-baseline gap-2">
        <span
          data-part="name"
          class="flex-1 truncate text-ui font-semibold text-ink group-hover:underline"
        >
          <em :if={@italic}>{@name}</em>
          <%= if !@italic do %>
            {@name}
          <% end %>
        </span>
        <span data-part="count" class="text-meta tabular-nums text-muted">
          {format_number(@count)}
        </span>
      </div>
    </.link>
    """
  end

  defp thumb_class(:row), do: "size-10 rounded-ctl"
  defp thumb_class(:tile), do: "aspect-square w-full rounded-panel"

  @doc """
  A family on a Browse page (`/galls`, `/hosts`), built by
  `GallformersWeb.BrowseHelpers.family_cards/2`: a photo, the family (a
  link) and its common names, how many Galls and genera, and its largest
  genera with their counts.

  It is also the Browse tree. Its toggle (`on_toggle` with
  `phx-value-key` = the family's key) opens it across the grid to every
  genus, each with its own toggle that lists its leaves (Galls or plants).
  `expanded` holds the open keys, as the tree's did. Put cards in a
  `grid md:grid-cols-2 xl:grid-cols-3`; an open card spans the row.
  """
  attr :card, :map, required: true, doc: "from `BrowseHelpers.family_cards/2`"
  attr :expanded, :any, default: MapSet.new(), doc: "the open family and genus keys"
  attr :on_toggle, :string, required: true, doc: "the event a toggle sends, with `phx-value-key`"
  attr :limit, :integer, default: 6, doc: "genera shown while closed"
  attr :icon, :string, default: "gf-gall", doc: "shown on the well when there is no photo"
  attr :leaves, :string, default: "galls", doc: ~s|what the genera list: "galls" or "plants"|

  def family_card(assigns) do
    assigns =
      assign(assigns,
        open?: MapSet.member?(assigns.expanded, assigns.card.key),
        hidden: max(length(assigns.card.genera) - assigns.limit, 0),
        shown: Enum.take(assigns.card.genera, assigns.limit)
      )

    ~H"""
    <article
      id={"family-#{@card.key}"}
      data-expanded={to_string(@open?)}
      class={[
        "flex min-w-0 gap-3 rounded-panel border border-line bg-surface p-3",
        @open? && "col-span-full"
      ]}
    >
      <.link navigate={@card.url} class="shrink-0" tabindex="-1" aria-hidden="true">
        <img
          :if={@card.image_url}
          src={@card.image_url}
          alt=""
          loading="lazy"
          class="size-16 rounded-ctl bg-surface-2 object-cover"
        />
        <span
          :if={!@card.image_url}
          data-part="placeholder"
          class="flex size-16 items-center justify-center rounded-ctl bg-surface-2 text-muted"
        >
          <.icon name={@icon} class="size-6" />
        </span>
      </.link>
      <div class="flex min-w-0 flex-1 flex-col gap-1">
        <div class="flex flex-wrap items-baseline gap-x-2">
          <span data-part="name" class="font-semibold">
            <.link navigate={@card.url}>{@card.name}</.link>
          </span>
          <span :if={@card.description} data-part="description" class="text-meta text-ink-2">
            {@card.description}
          </span>
          <span data-part="count" class="text-meta tabular-nums text-muted">
            {plural(@card.count, "gall", "galls")} · {plural(length(@card.genera), "genus", "genera")}
          </span>
        </div>
        <p :if={!@open?} data-part="genera" class="flex flex-wrap gap-x-1.5 text-meta text-ink-2">
          <span :for={{genus, i} <- Enum.with_index(@shown)} class="whitespace-nowrap">
            <.link navigate={genus.url}><.taxon_name name={genus.name} /></.link>
            <span class="tabular-nums text-muted">{format_number(genus.count)}</span>{list_separator(
              i,
              @shown
            )}
          </span>
        </p>
        <ul
          :if={@open?}
          data-part="genera"
          class="columns-1 gap-x-6 pt-1 sm:columns-2 lg:columns-3 2xl:columns-4"
        >
          <li :for={genus <- @card.genera} class="min-w-0 pb-1 text-meta">
            <.genus_row
              genus={genus}
              open?={MapSet.member?(@expanded, genus.key)}
              on_toggle={@on_toggle}
            />
          </li>
        </ul>
        <div>
          <button
            type="button"
            phx-click={@on_toggle}
            phx-value-key={@card.key}
            aria-expanded={to_string(@open?)}
            aria-controls={"family-#{@card.key}"}
            class="text-meta text-link hover:underline"
          >
            {cond do
              @open? -> "Show less"
              @hidden > 0 -> "#{@hidden} more · show all"
              true -> "Show #{@leaves}"
            end}
          </button>
        </div>
      </div>
    </article>
    """
  end

  attr :genus, :map, required: true
  attr :open?, :boolean, required: true
  attr :on_toggle, :string, required: true

  defp genus_row(assigns) do
    ~H"""
    <div class="flex min-w-0 break-inside-avoid items-baseline gap-1">
      <button
        type="button"
        phx-click={@on_toggle}
        phx-value-key={@genus.key}
        aria-expanded={to_string(@open?)}
        aria-label={"Show the #{@genus.name} list"}
        class="inline-flex size-5 shrink-0 items-center justify-center self-center text-muted hover:text-ink"
      >
        <.icon name="ph-caret-right" class={["size-3.5", @open? && "rotate-90"]} />
      </button>
      <.link navigate={@genus.url} class="truncate"><.taxon_name name={@genus.name} /></.link>
      <span class="tabular-nums text-muted">{format_number(@genus.count)}</span>
    </div>
    <ul :if={@open?} class="flex flex-col gap-0.5 py-1 pl-6">
      <li :for={leaf <- @genus.leaves}>
        <.link navigate={leaf.url}><.taxon_name name={leaf.label} /></.link>
      </li>
    </ul>
    """
  end

  defp plural(1, one, _many), do: "1 #{one}"
  defp plural(n, _one, many), do: "#{format_number(n)} #{many}"

  @doc """
  The photos of a Gall, a Host or a Source: one large photo (shown whole,
  never cropped: many are plates and drawings) with its caption and credit,
  arrows and a thumbnail strip when there are two or more, a full-size view
  and a details dialog. Each photo's caption, credit and details are its
  own (rendered for every photo; the `PhotoViewer` hook shows the current
  one). Arrow keys move (wrapping) while focus is in the viewer, a swipe
  moves on touch screens, Escape closes a dialog and focus returns to what
  opened it. Every move pushes `gallery_index_changed` with the index.

  `photos` are maps with atom or string keys: `src` (full size), `thumb`
  (small; defaults to `src`), `alt` (defaults to "Photo n of <name>"),
  `caption`, `creator`, `license`, `licenselink`, `sourcelink`,
  `attribution`, `uploader`, `lastchangedby`. With no photos it says so,
  and an admin gets "Add images".

  ## Examples

      <.photo_viewer id="gall-images" photos={@images} name={@gall.name}
        edit_href={"/gall/\#{@gall.id}?edit"} admin={Accounts.admin?(@current_user)} />
  """
  attr :id, :string, required: true
  attr :photos, :list, required: true
  attr :name, :string, required: true, doc: "what the photos show, for alt text and labels"
  attr :edit_href, :string, default: nil, doc: "where an admin edits these photos"
  attr :admin, :boolean, default: false, doc: "show the edit links"
  attr :class, :any, default: nil, doc: "layout only"

  def photo_viewer(assigns) do
    assigns =
      assign(assigns,
        indexed: Enum.with_index(assigns.photos),
        count: length(assigns.photos),
        edit?: assigns.admin and assigns.edit_href != nil
      )

    ~H"""
    <div
      id={@id}
      phx-hook="PhotoViewer"
      phx-update="ignore"
      tabindex="0"
      data-count={@count}
      aria-label={"Photos of #{@name}"}
      class={["flex min-w-0 flex-col gap-2 rounded-panel", @class]}
    >
      <div
        :if={@count == 0}
        data-part="empty"
        class="flex h-56 flex-col items-center justify-center gap-2 rounded-panel bg-surface-2 text-muted"
      >
        <.icon name="ph-image" class="size-8" />
        <span class="text-ui">No photos yet.</span>
        <.link :if={@edit?} href={@edit_href} class="text-ui">Add images</.link>
      </div>

      <div :if={@count > 0} class="relative">
        <figure
          :for={{photo, i} <- @indexed}
          data-slide={i}
          hidden={i != 0}
          class="m-0 flex flex-col gap-1"
        >
          <button
            type="button"
            data-open
            data-stage
            aria-label={"Open photo #{i + 1} full size"}
            class="flex h-80 w-full cursor-zoom-in items-center justify-center overflow-hidden rounded-panel bg-surface-2"
          >
            <img
              src={pfield(photo, :src)}
              alt={photo_alt(photo, i, @name)}
              loading="lazy"
              class="max-h-full max-w-full object-contain"
            />
          </button>
          <figcaption class="flex flex-col gap-0.5 text-meta text-ink-2">
            <span :if={pfield(photo, :caption)} data-part="caption" class="italic">
              {pfield(photo, :caption)}
            </span>
            <.photo_credit photo={photo} />
          </figcaption>
        </figure>

        <div
          :if={@count > 1}
          class="pointer-events-none absolute inset-x-0 top-0 flex h-80 items-center justify-between px-1.5"
        >
          <button
            type="button"
            data-prev
            aria-label="Previous photo"
            class="pointer-events-auto inline-flex h-12 w-8 items-center justify-center rounded-ctl bg-ink/40 text-paper hover:bg-ink/65"
          >
            <.icon name="ph-caret-left" class="size-5" />
          </button>
          <button
            type="button"
            data-next
            aria-label="Next photo"
            class="pointer-events-auto inline-flex h-12 w-8 items-center justify-center rounded-ctl bg-ink/40 text-paper hover:bg-ink/65"
          >
            <.icon name="ph-caret-right" class="size-5" />
          </button>
        </div>
      </div>

      <div :if={@count > 0} class="flex items-center gap-2 text-meta text-muted">
        <span :if={@count > 1} data-counter class="tabular-nums">1 / {@count}</span>
        <button
          type="button"
          data-open-details
          class="ml-auto inline-flex items-center gap-1 text-link"
        >
          <.icon name="ph-info" class="size-4" /> Details
        </button>
        <.link :if={@edit?} href={@edit_href} class="inline-flex items-center gap-1">
          <.icon name="ph-pencil-simple" class="size-4" /> Edit photos
        </.link>
      </div>

      <div :if={@count > 1} data-thumbs class="gf-thumbs flex gap-1.5 overflow-x-auto pb-1">
        <button
          :for={{photo, i} <- @indexed}
          type="button"
          data-go={i}
          aria-current={to_string(i == 0)}
          aria-label={"Photo #{i + 1} of #{@count}"}
          class="shrink-0 rounded-ctl border-2 border-transparent"
        >
          <img
            src={pfield(photo, :thumb) || pfield(photo, :src)}
            alt=""
            loading="lazy"
            class="size-14 rounded-ctl bg-surface-2 object-cover"
          />
        </button>
      </div>

      <dialog
        :if={@count > 0}
        data-lightbox
        aria-label={"Photos of #{@name}, full size"}
        class="m-0 h-dvh max-h-none w-dvw max-w-none bg-ink p-0 text-paper backdrop:bg-overlay"
      >
        <div class="flex h-full flex-col gap-2 p-3">
          <div class="flex items-center gap-2">
            <span :if={@count > 1} data-counter class="text-meta tabular-nums">1 / {@count}</span>
            <button
              type="button"
              data-close
              aria-label="Close"
              class="ml-auto inline-flex size-9 items-center justify-center rounded-ctl hover:bg-surface/10"
            >
              <.icon name="ph-x" class="size-5" />
            </button>
          </div>
          <div class="relative min-h-0 flex-1" data-stage>
            <figure
              :for={{photo, i} <- @indexed}
              data-full={i}
              hidden={i != 0}
              class="m-0 flex h-full flex-col items-center gap-2"
            >
              <img
                data-src={pfield(photo, :src)}
                alt={photo_alt(photo, i, @name)}
                class="h-0 w-full flex-1 object-contain"
              />
              <figcaption class="text-meta">
                <span :if={pfield(photo, :caption)} class="italic">
                  {pfield(photo, :caption)} ·
                </span>
                <.photo_credit photo={photo} />
              </figcaption>
            </figure>
            <button
              :if={@count > 1}
              type="button"
              data-prev
              aria-label="Previous photo"
              class="absolute top-1/2 left-1 inline-flex h-14 w-10 -translate-y-1/2 items-center justify-center rounded-ctl bg-paper/10 text-paper hover:bg-paper/25"
            >
              <.icon name="ph-caret-left" class="size-5" />
            </button>
            <button
              :if={@count > 1}
              type="button"
              data-next
              aria-label="Next photo"
              class="absolute top-1/2 right-1 inline-flex h-14 w-10 -translate-y-1/2 items-center justify-center rounded-ctl bg-paper/10 text-paper hover:bg-paper/25"
            >
              <.icon name="ph-caret-right" class="size-5" />
            </button>
          </div>
        </div>
      </dialog>

      <dialog
        :if={@count > 0}
        data-details
        aria-label="Photo details"
        class="m-auto w-full max-w-form rounded-panel bg-surface p-4 text-ink shadow-float backdrop:bg-overlay"
      >
        <div class="mb-3 flex items-center">
          <h2 class="text-subsection">Photo details</h2>
          <button
            type="button"
            data-close
            aria-label="Close"
            class="ml-auto inline-flex size-8 items-center justify-center rounded-ctl hover:bg-surface-2"
          >
            <.icon name="ph-x" class="size-5" />
          </button>
        </div>
        <dl
          :for={{photo, i} <- @indexed}
          data-info={i}
          hidden={i != 0}
          class="grid grid-cols-3 gap-x-3 gap-y-1.5 text-ui"
        >
          <%= for {label, key} <- [{"Source", :sourcelink}, {"License", :license}, {"Attribution", :attribution}, {"Creator", :creator}, {"Uploader", :uploader}, {"Last changed by", :lastchangedby}, {"Caption", :caption}] do %>
            <dt class="text-meta text-muted">{label}</dt>
            <dd class="col-span-2 min-w-0 break-words">
              <%= cond do %>
                <% key == :sourcelink and pfield(photo, key) -> %>
                  <a href={pfield(photo, key)} target="_blank" rel="noopener noreferrer">
                    {pfield(photo, :source_title) || pfield(photo, key)}
                  </a>
                <% key == :license and pfield(photo, :licenselink) -> %>
                  <a href={pfield(photo, :licenselink)} target="_blank" rel="noopener noreferrer">
                    {pfield(photo, key)}
                  </a>
                <% true -> %>
                  {pfield(photo, key) || "—"}
              <% end %>
            </dd>
          <% end %>
        </dl>
      </dialog>
    </div>
    """
  end

  attr :photo, :map, required: true

  defp photo_credit(assigns) do
    ~H"""
    <span data-part="credit">
      Photo{if pfield(@photo, :creator), do: " by #{pfield(@photo, :creator)}"}<span :if={
        pfield(@photo, :license)
      }>
        ·
        <a
          :if={pfield(@photo, :licenselink)}
          href={pfield(@photo, :licenselink)}
          target="_blank"
          rel="noopener noreferrer"
        >{pfield(@photo, :license)}</a><span :if={!pfield(@photo, :licenselink)}>{pfield(@photo, :license)}</span></span>
      <span :if={pfield(@photo, :sourcelink)}>
        · <a href={pfield(@photo, :sourcelink)} target="_blank" rel="noopener noreferrer">Source ↗</a>
      </span>
    </span>
    """
  end

  # A photo's field (atom or string key); blank is nil.
  defp pfield(photo, key) do
    case Map.get(photo, key, Map.get(photo, Atom.to_string(key))) do
      value when value in [nil, ""] -> nil
      value -> to_string(value)
    end
  end

  defp photo_alt(photo, i, name) do
    case Map.get(photo, :alt, Map.get(photo, "alt")) do
      alt when alt in [nil, ""] -> "Photo #{i + 1} of #{name}"
      alt -> alt
    end
  end

  @doc """
  One Source as it relates to a page (a Gall page lists one per Source, by
  year).

  Collapsed, a row: the year, the title (a link to the Source page) and
  authors, and the first line of the excerpt in serif. The caret button
  opens it in place, in the browser, to the whole excerpt, the license, and
  links to the Source page and the original.

  `pinned` is Gallformers' own ID Notes: an info panel, always open, placed
  above the list.

  The excerpt is plain text; blank lines separate paragraphs.

  ## Examples

      <.source_entry
        id={"source-\#{s.id}"}
        year={s.pubyear}
        title={s.title}
        href={~p"/source/\#{s.id}"}
        authors={s.author}
        excerpt={s.description}
        license={s.license}
        license_url={s.licenselink}
        original_url={s.externallink}
      />

      <.source_entry id="source-1" pinned title="Gallformers ID Notes" href={~p"/source/1"} excerpt={notes} />
  """
  attr :id, :string, required: true, doc: "the entry's DOM id; the toggle targets it"
  attr :title, :string, required: true, doc: "the Source's title"
  attr :href, :string, default: nil, doc: "the Source page"
  attr :year, :any, default: nil, doc: ~s|the year of publication; nil shows "n.d."|
  attr :authors, :string, default: nil

  attr :excerpt, :string,
    default: nil,
    doc: "what the Source says here; blank lines split paragraphs"

  attr :license, :string, default: nil, doc: ~s|the excerpt's license, e.g. "CC BY 4.0"|
  attr :license_url, :string, default: nil, doc: "the license's text (external)"
  attr :original_url, :string, default: nil, doc: "the original publication (external)"
  attr :open, :boolean, default: false, doc: "expanded when first rendered"
  attr :pinned, :boolean, default: false, doc: "Gallformers' ID Notes: an info panel, always open"
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  def source_entry(%{pinned: true} = assigns) do
    assigns = assign(assigns, :paragraphs, paragraphs(assigns.excerpt))

    ~H"""
    <.panel id={@id} variant={:info} title={@title} class={@class} {@rest}>
      <.source_quote :if={@paragraphs != []} cite={@original_url}>
        <p :for={paragraph <- @paragraphs}>{paragraph}</p>
      </.source_quote>
      <.source_meta
        license={@license}
        license_url={@license_url}
        href={@href}
        original_url={@original_url}
      />
    </.panel>
    """
  end

  def source_entry(assigns) do
    paragraphs = paragraphs(assigns.excerpt)

    assigns =
      assign(assigns,
        paragraphs: paragraphs,
        first_line: List.first(paragraphs),
        toggle_label:
          if(paragraphs == [],
            do: "Show the license and links for #{assigns.title}",
            else: "Show the excerpt from #{assigns.title}"
          )
      )

    ~H"""
    <div id={@id} class={["flex gap-3 border-b border-line py-2 last:border-b-0", @class]} {@rest}>
      <span data-part="year" class="w-14 shrink-0 pt-0.5 text-meta text-muted tabular-nums">
        <%= if present?(@year) do %>
          {@year}
        <% else %>
          <abbr title="No date">n.d.</abbr>
        <% end %>
      </span>
      <div class="flex min-w-0 flex-1 flex-col gap-1">
        <p class="text-ui text-ink">
          <.link :if={@href} href={@href} data-part="title" class="font-semibold">{@title}</.link>
          <span :if={!@href} data-part="title" class="font-semibold">{@title}</span>
          <span :if={@authors} data-part="authors" class="text-muted">· {@authors}</span>
        </p>
        <p
          :if={@first_line}
          id={"#{@id}-short"}
          class={["truncate font-serif text-body text-ink-2", @open && "hidden"]}
        >
          {@first_line}
        </p>
        <div id={"#{@id}-full"} class={["flex flex-col gap-2", !@open && "hidden"]}>
          <.source_quote :if={@paragraphs != []} cite={@original_url}>
            <p :for={paragraph <- @paragraphs}>{paragraph}</p>
          </.source_quote>
          <.source_meta
            license={@license}
            license_url={@license_url}
            href={@href}
            original_url={@original_url}
          />
        </div>
      </div>
      <.button
        id={"#{@id}-toggle"}
        variant="ghost"
        size="sm"
        icon="ph-caret-down"
        icon_only
        label={@toggle_label}
        aria-expanded={to_string(@open)}
        aria-controls={"#{@id}-full"}
        phx-click={toggle_source_entry(@id)}
        class="shrink-0 transition-transform duration-150 ease-out aria-expanded:rotate-180"
      />
    </div>
    """
  end

  # The line under an open entry: license · Source page · Original ↗
  attr :license, :string, required: true
  attr :license_url, :string, required: true
  attr :href, :string, required: true
  attr :original_url, :string, required: true

  defp source_meta(assigns) do
    ~H"""
    <p
      :if={@license || @href || @original_url}
      data-part="meta"
      class="flex flex-wrap items-baseline gap-x-1.5 text-meta text-muted"
    >
      <span :if={@license} data-part="license">
        <.link :if={@license_url} href={@license_url} target="_blank" rel="noopener">
          {@license} ↗
        </.link>
        <span :if={!@license_url}>{@license}</span>
      </span>
      <span :if={@license && @href} aria-hidden="true">·</span>
      <.link :if={@href} href={@href}>Source page</.link>
      <span :if={(@license || @href) && @original_url} aria-hidden="true">·</span>
      <.link :if={@original_url} href={@original_url} target="_blank" rel="noopener">
        Original ↗
      </.link>
    </p>
    """
  end

  # Opens and closes an entry in the browser. The caret turns with
  # aria-expanded (the button's aria-expanded:rotate-180).
  defp toggle_source_entry(id) do
    JS.toggle_class("hidden", to: "##{id}-short")
    |> JS.toggle_class("hidden", to: "##{id}-full")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{id}-toggle")
  end

  defp paragraphs(nil), do: []

  defp paragraphs(text) do
    text
    |> String.split(~r/\R\s*\R/u)
    |> Enum.map(&(&1 |> String.split() |> Enum.join(" ")))
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  What a Source wrote, set in Source Serif to separate the literature from
  Gallformers' own words: an excerpt as a block of one or more paragraphs,
  or, with `inline`, a short quote within a sentence. `page` is shown muted
  after the text.

  ## Examples

      <.source_quote page="p. 113" cite="https://archive.org/details/cynipids">
        <p>Gall on the stem, an abrupt swelling up to 18 mm.</p>
      </.source_quote>

      The Source calls it <.source_quote inline page="p. 2">an abrupt swelling</.source_quote>.
  """
  attr :page, :string, default: nil, doc: ~s|a page reference, e.g. "p. 113"|
  attr :cite, :string, default: nil, doc: "the quoted work's URL (the cite attribute)"
  attr :inline, :boolean, default: false, doc: "a short quote within a sentence"
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global
  slot :inner_block, required: true

  def source_quote(%{inline: true} = assigns) do
    ~H"""
    <span class={@class} {@rest}>
      <q cite={@cite} class="font-serif text-ink-2">{render_slot(@inner_block)}</q><span
        :if={@page}
        data-part="page"
        class="pl-1 text-meta text-muted"
      >{@page}</span>
    </span>
    """
  end

  def source_quote(assigns) do
    ~H"""
    <blockquote
      cite={@cite}
      class={["my-0 flex max-w-text flex-col gap-2 font-serif text-body text-ink-2", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
      <p :if={@page} data-part="page" class="font-sans text-meta text-muted">{@page}</p>
    </blockquote>
    """
  end

  defp present?(nil), do: false
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: true

  @doc """
  An article in the Articles list: a band tinted by its topic (`tone`)
  with the topic named and a large tilted icon, then the title, a
  three-line preview and a meta line. The card is one link; `edit_href`
  adds an admin edit link in its corner. `featured` lays it out wide (the
  band beside the text, a larger title and preview) and names it with
  `label` ("Newest").

      <.article_card href={~p"/articles/\#{a.slug}"} title={a.title} topic="faq"
        icon="ph-question" tone={:autumn} meta="Adam Kranz · January 26, 2026">
        Preface At the time of writing…
      </.article_card>
  """
  attr :href, :string, required: true
  attr :title, :string, required: true
  attr :topic, :string, default: nil, doc: "named on the band"
  attr :icon, :string, default: "ph-article"
  attr :tone, :atom, default: :plain, values: [:sky, :autumn, :brand, :plain]
  attr :meta, :string, default: nil, doc: "author · date"
  attr :featured, :boolean, default: false
  attr :label, :string, default: nil, doc: "a featured card's label"
  attr :edit_href, :string, default: nil
  attr :class, :any, default: nil, doc: "layout only"

  slot :inner_block, doc: "the preview"

  def article_card(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <.link
        href={@href}
        data-layout={if @featured, do: "featured", else: "card"}
        class={[
          "group h-full overflow-hidden rounded-panel border border-line bg-surface hover:no-underline",
          if(@featured, do: "grid md:grid-cols-5", else: "flex flex-col hover:shadow-float")
        ]}
      >
        <div
          data-part="band"
          data-tone={@tone}
          class={[
            "relative overflow-hidden",
            if(@featured, do: "min-h-40 md:col-span-2", else: "h-24"),
            tone_class(@tone)
          ]}
        >
          <span
            :if={@label}
            data-part="label"
            class="absolute left-4 top-4 font-brand text-caption font-semibold uppercase tracking-wide text-ink-2"
          >
            {@label}
          </span>
          <span
            :if={@topic && !@featured}
            class="absolute left-4 top-3 text-caption font-semibold uppercase tracking-wide text-ink-2"
          >
            {@topic}
          </span>
          <.icon
            name={@icon}
            class={[
              "absolute -rotate-12 opacity-80",
              if(@featured, do: "-bottom-6 -right-4 size-48", else: "-bottom-5 right-3 size-24")
            ]}
          />
        </div>
        <div class={[
          "flex flex-col",
          if(@featured, do: "gap-2 p-6 md:col-span-3", else: "flex-1 gap-1.5 p-4")
        ]}>
          <p
            :if={@topic && @featured}
            class="text-caption font-semibold uppercase tracking-wide text-muted"
          >
            {@topic}
          </p>
          <h2 class={[
            "font-brand text-ink group-hover:underline",
            if(@featured, do: "text-section", else: "text-subsection")
          ]}>
            {@title}
          </h2>
          <p
            :if={@inner_block != []}
            data-part="preview"
            class={["line-clamp-3 text-ink-2", if(@featured, do: "text-lead", else: "text-ui")]}
          >
            {render_slot(@inner_block)}
          </p>
          <p :if={@meta} data-part="meta" class="mt-auto pt-2 text-meta text-muted">{@meta}</p>
        </div>
      </.link>
      <.link
        :if={@edit_href}
        href={@edit_href}
        class="absolute right-2 top-2 rounded-ctl bg-surface/80 p-1 text-muted"
        title="Edit in admin"
      >
        <.icon name="ph-pencil-simple" class="size-4" />
      </.link>
    </div>
    """
  end

  defp tone_class(:sky), do: "bg-sky text-link"
  defp tone_class(:autumn), do: "bg-autumn/15 text-autumn-ink"
  defp tone_class(:brand), do: "bg-brand/10 text-brand"
  defp tone_class(:plain), do: "bg-surface-2 text-ink-2"

  @doc """
  One curator change in the change log (`Gallformers.Audit.ChangeLog`
  group): who did what, from which Source, and when; the Galls and taxa
  it touched and the taxon names it added; what happened to its Facts, counted, and
  the Facts themselves on request. Every Gall, name and Fact links to
  **View** (the public page it shows on, at the Fact) and **Edit** (that
  page with Edit on, matter ec2c). A taxon with no page of its own (an
  inducer species) is found by search and edited in the taxonomy admin.

  The admin dashboard and the Changes page render the same entry.
  """
  attr :group, :map, required: true, doc: "a `ChangeLog` group"

  def change_entry(assigns) do
    ~H"""
    <li id={@group.key} class="flex gap-4 py-3">
      <span
        data-part="when"
        class="w-24 shrink-0 text-meta text-muted tabular-nums"
        title={to_string(@group.at)}
      >
        {time_ago(@group.at)}
      </span>
      <div class="flex min-w-0 flex-1 flex-col gap-1">
        <p data-part="summary" class="text-ui text-ink">
          <span class="font-semibold">{@group.who}</span>
          {lowercase_first(@group.title)}<span :if={@group.source}>
            from <.link href={"/admin/review/sources/#{@group.source.id}"}>{@group.source.title}</.link></span>
        </p>
        <ul :if={@group.galls != []} data-part="galls" class="flex flex-col gap-0.5 text-meta">
          <li :for={g <- @group.galls} class="flex items-baseline gap-3">
            <span class="text-ink-2"><.taxon_name name={g.name} /></span>
            <.view_edit view={"/gall/#{g.id}"} edit={"/gall/#{g.id}?edit"} />
          </li>
        </ul>
        <ul :if={@group.names != []} data-part="names" class="flex flex-col gap-0.5 text-meta">
          <li :for={t <- @group.names} class="flex items-baseline gap-3">
            <span class="text-ink-2">New name: <.taxon_name name={t.name} /></span>
            <span :if={t[:rank]} data-part="rank" class="text-muted">{t.rank}</span>
            <.view_edit view={taxon_view(t)} edit={taxon_edit(t)} />
          </li>
        </ul>
        <ul
          :if={@group[:taxa] not in [nil, []]}
          data-part="taxa"
          class="flex flex-col gap-0.5 text-meta"
        >
          <li :for={t <- @group.taxa} class="flex items-baseline gap-3">
            <span class="text-ink-2"><.taxon_name name={t.name} /></span>
            <span :if={t[:rank]} data-part="rank" class="text-muted">{t.rank}</span>
            <.view_edit view={taxon_view(t)} edit={taxon_edit(t)} />
          </li>
        </ul>
        <div :if={@group.counts != %{}} data-part="counts" class="flex flex-wrap items-center gap-1.5">
          <.chip :if={@group.counts[:added]} variant={:ok} size="sm">
            {@group.counts[:added]} {if @group.counts[:added] == 1, do: "Fact", else: "Facts"} added
          </.chip>
          <.chip :if={@group.counts[:made_current]} variant={:info} size="sm">
            {@group.counts[:made_current]} made current
          </.chip>
          <.chip :if={@group.counts[:superseded]} variant={:warn} size="sm">
            {@group.counts[:superseded]} superseded
          </.chip>
          <.chip :if={@group.counts[:withdrawn]} variant={:danger} size="sm">
            {@group.counts[:withdrawn]} withdrawn
          </.chip>
          <.chip :if={@group.counts[:unsupported]} variant={:neutral} size="sm">
            {@group.counts[:unsupported]} unsupported
          </.chip>
        </div>
        <details :if={@group.facts != []} data-part="facts" class="text-meta">
          <summary class="cursor-pointer text-link">Show the {length(@group.facts)} Facts</summary>
          <ul class="mt-1 flex flex-col divide-y divide-line rounded-ctl border border-line bg-surface">
            <li
              :for={f <- @group.facts}
              id={"#{@group.key}-fact-#{f.id}"}
              class="flex items-baseline gap-3 px-2 py-1"
            >
              <span class="w-24 shrink-0 text-muted">{change_word(f.change)}</span>
              <span class="min-w-0 flex-1 truncate text-ink-2">
                <.taxon_name :if={subject(f)} name={subject(f).name} />
              </span>
              <span class="min-w-0 flex-1 text-ink">{f.what}</span>
              <span class="flex shrink-0 gap-3">
                <.view_edit view={fact_view(f)} edit={fact_edit(f)} />
              </span>
            </li>
          </ul>
        </details>
      </div>
    </li>
    """
  end

  attr :view, :string, default: nil
  attr :edit, :string, default: nil

  defp view_edit(assigns) do
    ~H"""
    <.link :if={@view} href={@view} target="_blank" title="Where this shows on the public site">
      View
    </.link>
    <.link :if={@edit} href={@edit} title="Change it">Edit</.link>
    """
  end

  defp lowercase_first(<<first::utf8, rest::binary>>),
    do: String.downcase(<<first::utf8>>) <> rest

  defp lowercase_first(other), do: other

  defp change_word(:added), do: "added"
  defp change_word(:made_current), do: "made current"
  defp change_word(other), do: to_string(other)

  defp subject(%{gall: %{} = gall}), do: gall
  defp subject(%{taxon: %{} = taxon}), do: taxon
  defp subject(_), do: nil

  defp taxon_view(t),
    do: TaxonomyURL.taxon_path(t) || "/globalsearch?q=#{URI.encode_www_form(t.name)}"

  defp taxon_edit(t) do
    case TaxonomyURL.taxon_path(t) do
      nil -> "/admin/taxonomy/#{t.id}"
      path -> path <> "?edit"
    end
  end

  defp fact_view(%{gall: %{id: id}} = f), do: "/gall/#{id}#fact-#{f.id}"
  defp fact_view(%{taxon: %{} = t} = f), do: anchored(taxon_view(t), TaxonomyURL.taxon_path(t), f)
  defp fact_view(_), do: nil

  defp fact_edit(%{gall: %{id: id}} = f), do: "/gall/#{id}?edit#fact-#{f.id}"
  defp fact_edit(%{taxon: %{} = t} = f), do: anchored(taxon_edit(t), TaxonomyURL.taxon_path(t), f)
  defp fact_edit(_), do: nil

  # A Fact on a taxon's own page is anchored there; a search or the taxonomy
  # admin isn't.
  defp anchored(url, nil, _fact), do: url
  defp anchored(url, _page, fact), do: "#{url}#fact-#{fact.id}"
end
