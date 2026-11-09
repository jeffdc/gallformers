defmodule GallformersWeb.UIComponents do
  @moduledoc """
  Shared UI components for the Gallformers application.

  Provides spinners, alerts, pagination, the glossary tooltip, the region
  scope and see-also links, styled from the design system's tokens
  (docs/design-system/). `alert` is retiring: new code uses `notice`.
  """
  use Phoenix.Component
  use Gettext, backend: GallformersWeb.Gettext

  import GallformersWeb.CoreComponents, only: [icon: 1]

  alias Gallformers.TaxonName
  alias GallformersWeb.Live.ContinentScope
  alias Phoenix.LiveView.JS

  @doc """
  Renders a loading spinner.

  `tone` `:brand` (the default) suits a page or panel; `:current` takes the
  text colour around it, for a spinner inside a button (on a primary
  button's fill it is `text-on-fill`).

  ## Examples

      <.loading_spinner />
      <.loading_spinner size="lg" />
      <.loading_spinner size="sm" label="Loading data..." />
      <.button variant="primary" disabled>
        <.loading_spinner size="sm" tone={:current} label="Loading" /> Loading…
      </.button>
  """
  attr :size, :string, default: "md", values: ~w(sm md lg), doc: "spinner size"
  attr :label, :string, default: "Loading", doc: "accessible label for screen readers"

  attr :tone, :atom,
    default: :brand,
    values: [:brand, :current],
    doc: ":brand, or :current (the text colour around it: inside a button)"

  attr :class, :any, default: nil, doc: "layout only"

  def loading_spinner(assigns) do
    size_classes = %{
      "sm" => "h-4 w-4",
      "md" => "h-8 w-8",
      "lg" => "h-12 w-12"
    }

    assigns = assign(assigns, :size_class, Map.fetch!(size_classes, assigns.size))

    ~H"""
    <svg
      class={["animate-spin", @tone == :brand && "text-brand", @size_class, @class]}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      role="status"
      aria-label={@label}
    >
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
      <path
        class="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
      />
    </svg>
    """
  end

  @doc """
  Renders a pagination component.

  ## Examples

      <.pagination
        page={@page}
        total_pages={@total_pages}
        total_items={@total_items}
        on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
      />
  """
  attr :page, :integer, required: true, doc: "current page number (1-indexed)"
  attr :total_pages, :integer, required: true, doc: "total number of pages"
  attr :total_items, :integer, default: nil, doc: "total number of items (optional)"
  attr :page_size, :integer, default: 20, doc: "items per page (for calculating range)"

  attr :on_page_change, :any,
    required: true,
    doc: "function that takes page number and returns JS command"

  attr :class, :any, default: nil, doc: "additional CSS classes"

  def pagination(assigns) do
    start_item = (assigns.page - 1) * assigns.page_size + 1

    end_item =
      min(
        assigns.page * assigns.page_size,
        assigns.total_items || assigns.page * assigns.page_size
      )

    assigns =
      assigns
      |> assign(:start_item, start_item)
      |> assign(:end_item, end_item)

    ~H"""
    <nav class={["flex items-center justify-between", @class]} aria-label={gettext("Pagination")}>
      <div class="text-meta text-ink-2">
        <span :if={@total_items}>
          {gettext("Showing %{start} to %{end} of %{total} results",
            start: @start_item,
            end: @end_item,
            total: @total_items
          )}
        </span>
        <span :if={!@total_items}>
          {gettext("Page %{page} of %{total}", page: @page, total: @total_pages)}
        </span>
      </div>
      <div class="flex items-center gap-2">
        <button
          type="button"
          phx-click={@on_page_change.(@page - 1)}
          disabled={@page <= 1}
          class="gf-btn gf-btn-sm"
        >
          {gettext("Previous")}
        </button>
        <span class="text-meta text-ink-2">
          {gettext("Page %{page} of %{total}", page: @page, total: @total_pages)}
        </span>
        <button
          type="button"
          phx-click={@on_page_change.(@page + 1)}
          disabled={@page >= @total_pages}
          class="gf-btn gf-btn-sm"
        >
          {gettext("Next")}
        </button>
      </div>
    </nav>
    """
  end

  @doc """
  Renders an alert banner.

  Unlike flash messages which appear as toasts, alerts are inline banners
  that display within the page content.

  ## Examples

      <.alert variant="info">
        This is an informational message.
      </.alert>

      <.alert variant="success" dismissible>
        Your changes have been saved.
      </.alert>

      <.alert variant="error">
        <:title>Error</:title>
        Something went wrong. Please try again.
      </.alert>
  """
  attr :variant, :string,
    default: "info",
    values: ~w(info success warning error),
    doc: "the variant of the alert"

  attr :dismissible, :boolean, default: false, doc: "whether the alert can be dismissed"
  attr :id, :string, default: nil, doc: "optional id for dismissible alerts"
  attr :class, :any, default: nil, doc: "additional CSS classes"
  attr :rest, :global

  slot :title, doc: "optional title for the alert"
  slot :inner_block, required: true

  def alert(assigns) do
    variant_styles = %{
      "info" => %{
        bg: "bg-info-bg",
        border: "border-info/30",
        text: "text-info",
        icon: "ph-info"
      },
      "success" => %{
        bg: "bg-ok-bg",
        border: "border-ok/30",
        text: "text-ok",
        icon: "ph-check-circle"
      },
      "warning" => %{
        bg: "bg-warn-bg",
        border: "border-warn/30",
        text: "text-warn",
        icon: "ph-warning"
      },
      "error" => %{
        bg: "bg-danger-bg",
        border: "border-danger/30",
        text: "text-danger",
        icon: "ph-warning-circle"
      }
    }

    assigns =
      assigns
      |> assign(:styles, Map.fetch!(variant_styles, assigns.variant))
      |> assign_new(:id, fn ->
        if assigns.dismissible, do: "alert-#{System.unique_integer()}", else: nil
      end)

    ~H"""
    <div
      id={@id}
      class={[
        "rounded-panel border p-panel",
        @styles.bg,
        @styles.border,
        @class
      ]}
      role="alert"
      {@rest}
    >
      <div class="flex">
        <div class="flex-shrink-0">
          <.icon name={@styles.icon} class={["size-5", @styles.text]} />
        </div>
        <div class={["ml-3 flex-1", @styles.text]}>
          <p :if={@title != []} class="text-ui font-semibold">
            {render_slot(@title)}
          </p>
          <div class={["text-ui", @title != [] && "mt-1"]}>
            {render_slot(@inner_block)}
          </div>
        </div>
        <div :if={@dismissible} class="ml-auto pl-3">
          <button
            type="button"
            phx-click={JS.hide(to: "##{@id}")}
            class={[
              "-m-1.5 inline-flex rounded-ctl p-1.5 hover:bg-surface",
              @styles.text
            ]}
          >
            <span class="sr-only">{gettext("Dismiss")}</span>
            <.icon name="ph-x" class="size-5" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a loading overlay that covers its container.

  ## Examples

      <div class="relative">
        <.loading_overlay :if={@loading} />
        <p>Content that will be covered while loading</p>
      </div>
  """
  attr :label, :string, default: "Loading...", doc: "loading message to display"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def loading_overlay(assigns) do
    ~H"""
    <div class={[
      "absolute inset-0 z-10 flex items-center justify-center bg-surface/80",
      @class
    ]}>
      <div class="flex flex-col items-center gap-2">
        <.loading_spinner size="lg" label={@label} />
        <span class="text-meta text-ink-2">{@label}</span>
      </div>
    </div>
    """
  end

  @doc """
  "See also": links searching external resources for the name (design
  system, matter bc0d; the logos were retired).

  For galls: iNaturalist, BugGuide, Google Scholar, BHL
  For hosts: iNaturalist, Google Scholar, BHL

  ## Examples

      <.see_also name="Andricus quercuscalifornicus" type={:gall} />
      <.see_also name="Quercus lobata" type={:host} />
      <.see_also name="Undescribed ABC123" type={:gall} undescribed={true} />
  """
  attr :name, :string, required: true, doc: "species name for search queries"
  attr :type, :atom, values: [:gall, :host], required: true, doc: "type of entity"
  attr :undescribed, :boolean, default: false, doc: "whether the species is undescribed"
  attr :class, :any, default: nil, doc: "layout only"

  def see_also(assigns) do
    parsed = TaxonName.parse(assigns.name)

    # "Genus epithet" for search (drops qualifier like "agamic")
    search_name =
      if parsed.epithet do
        "#{parsed.genus} #{parsed.epithet}" |> URI.encode()
      else
        parsed.genus |> URI.encode()
      end

    # For undescribed species, extract the epithet as the code
    undescribed_code =
      if assigns.undescribed && parsed.full_epithet do
        parsed.full_epithet |> URI.encode()
      else
        nil
      end

    assigns =
      assigns
      |> assign(:search_name, search_name)
      |> assign(:undescribed_code, undescribed_code)

    ~H"""
    <div :if={!@undescribed} class={["flex flex-col gap-0.5", @class]}>
      <span data-part="label" class="text-meta text-muted">See also</span>
      <div class="flex flex-wrap gap-x-4 text-ui">
        <a
          href={"https://www.inaturalist.org/search?q=#{@search_name}"}
          target="_blank"
          rel="noreferrer"
          aria-label="Search for this species on iNaturalist"
        >
          iNaturalist ↗
        </a>
        <a
          :if={@type == :gall}
          href={"https://bugguide.net/index.php?q=search&keys=#{@search_name}&search=Search"}
          target="_blank"
          rel="noreferrer"
          aria-label="Search for this species on BugGuide"
        >
          BugGuide ↗
        </a>
        <a
          href={"https://scholar.google.com/scholar?hl=en&q=#{@search_name}"}
          target="_blank"
          rel="noreferrer"
          aria-label="Search for this species on Google Scholar"
        >
          Google Scholar ↗
        </a>
        <a
          href={"https://www.biodiversitylibrary.org/search?SearchTerm=#{@search_name}&SearchCat=M#/names"}
          target="_blank"
          rel="noreferrer"
          aria-label="Search for this species at the Biodiversity Heritage Library"
        >
          Biodiversity Heritage Library ↗
        </a>
      </div>
    </div>
    """
  end

  # Date/time formatting helpers

  @doc """
  Formats a datetime for display.

  Uses a consistent format across the application: "January 14, 2026"

  ## Examples

      format_date(~N[2026-01-14 12:00:00])
      #=> "January 14, 2026"

      format_date(~N[2026-01-14 12:00:00], :short)
      #=> "Jan 14, 2026"
  """
  @spec format_date(NaiveDateTime.t() | DateTime.t(), :long | :short) :: String.t()
  def format_date(datetime, format \\ :long)

  def format_date(datetime, :long) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end

  def format_date(datetime, :short) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  @legacy_source_text "From the original Gallformers data"

  @doc """
  A Source's line of when it came to Gallformers
  (`Gallformers.Import.source_dates/1`, matter `f14c`): "Added to
  Gallformers <date> · updated <date>", the update left out when it was on
  the day the Source was added; for a Source from the old data, "From the
  original Gallformers data", with any later update. Nothing when there is
  no date to give (a Source whose first package is not applied yet).

  ## Examples

      <.source_dates id="source-dates" dates={@dates} />
      <.source_dates dates={@dates} format={:short} />
  """
  attr :dates, :map, required: true, doc: "`%{ingested, updated, legacy?}`"
  attr :format, :atom, default: :long, values: [:long, :short], doc: "as `format_date/2`'s"
  attr :class, :any, default: nil
  attr :rest, :global

  def source_dates(assigns) do
    assigns = assign(assigns, :text, source_dates_text(assigns.dates, assigns.format))

    ~H"""
    <p :if={@text} class={@class} {@rest}>{@text}</p>
    """
  end

  @doc "The text `source_dates/1` shows, or nil when it shows nothing."
  @spec source_dates_text(map(), :long | :short) :: String.t() | nil
  def source_dates_text(dates, format \\ :long)

  def source_dates_text(%{legacy?: true, updated: nil}, _format), do: @legacy_source_text

  def source_dates_text(%{legacy?: true, updated: updated}, format),
    do: "#{@legacy_source_text} · updated #{format_date(updated, format)}"

  def source_dates_text(%{ingested: nil}, _format), do: nil

  def source_dates_text(%{ingested: ingested, updated: updated}, format) do
    added = "Added to Gallformers #{format_date(ingested, format)}"

    if is_nil(updated) or DateTime.to_date(updated) == DateTime.to_date(ingested),
      do: added,
      else: "#{added} · updated #{format_date(updated, format)}"
  end

  @doc "What a Source from the old data shows instead of a date."
  @spec legacy_source_text() :: String.t()
  def legacy_source_text, do: @legacy_source_text

  @doc """
  A short explanation of what it wraps, shown on hover or keyboard focus
  (`bg-ink text-paper`, caption size, `shadow-float`), below it. The
  wrapped content is described by it (`aria-describedby`). Hover only: on a
  touch screen it doesn't show, so nothing must depend on it.

  ## Examples

      <.tooltip id="def-tan" text="Tan to light brown.">tan</.tooltip>
  """
  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :class, :any, default: nil, doc: "layout only"
  slot :inner_block, required: true

  def tooltip(assigns) do
    ~H"""
    <span id={@id} class={["gf-tooltip", @class]}>
      <span aria-describedby={"#{@id}-text"}>{render_slot(@inner_block)}</span>
      <span id={"#{@id}-text"} role="tooltip" class="gf-tooltip-text">{@text}</span>
    </span>
    """
  end

  @doc """
  A glossary term in a name, as the Gall page's generation qualifier
  ("(agamic)"): a plain link to its glossary entry (`/glossary#word`), the
  first sentence of its definition in a `tooltip` on hover and keyboard
  focus. The link works on touch, where the tooltip doesn't show. The
  dotted underline is `fact_ref`'s alone (matter `87a1`).

  ## Examples

      <.glossary_tooltip term="agamic" definition="The agamic generation consists of only female wasps..." />
  """
  attr :term, :string, required: true, doc: "the glossary term to display (e.g., \"agamic\")"

  attr :glossary_word, :string,
    default: nil,
    doc: "the glossary word to link to, if different from term (e.g., \"sexgen\" for \"sexual\")"

  attr :definition, :string, default: nil, doc: "the full glossary definition"
  attr :class, :any, default: nil, doc: "layout only"

  def glossary_tooltip(assigns) do
    word = String.downcase(assigns.glossary_word || assigns.term)

    assigns =
      assign(assigns,
        short_definition: first_sentence(assigns.definition),
        href: "/glossary##{word}",
        tip_id: "glossary-#{word}"
      )

    ~H"""
    <span :if={@short_definition != ""} class={@class} phx-no-format>(<.tooltip id={@tip_id} text={@short_definition}><.link href={@href}>{@term}</.link></.tooltip>)</span>
    <span :if={@short_definition == ""} class={@class} phx-no-format>(<.link href={@href}>{@term}</.link>)</span>
    """
  end

  defp first_sentence(text) when is_binary(text) do
    case String.split(text, ~r/(?<=\.)\s/, parts: 2) do
      [sentence | _] -> String.trim(sentence)
      _ -> text
    end
  end

  defp first_sentence(_), do: ""

  @doc """
  Renders a region scope widget strip for continent filtering.

  Shows below the header on scoped pages (ID, Search, Explore). Displays the
  current continent selection with a dropdown to change it. When the user
  selects a different region from their saved default, "Set as default" and
  "Reset" actions appear.

  The widget communicates with a `RegionScope` JS hook for localStorage
  persistence. Region changes fire a `change_region` event to the parent
  LiveView for immediate result filtering.

  ## Examples

      <.region_scope continent_code={@continent_code} continent_name={@continent_name} />
  """
  attr :continent_code, :string, default: nil, doc: "currently active continent code"
  attr :continent_name, :string, default: nil, doc: "currently active continent display name"

  attr :default_continent_code, :string,
    default: nil,
    doc: "saved default continent code from localStorage"

  def region_scope(assigns) do
    assigns =
      assigns
      |> assign(:continents, ContinentScope.continents_list())
      |> assign(:overridden?, assigns.continent_code != assigns.default_continent_code)

    ~H"""
    <div
      :if={!@default_continent_code}
      id="region-prompt"
      phx-hook="RegionPrompt"
      class="hidden fixed inset-0 z-60 flex items-center justify-center bg-overlay"
    >
      <div class="mx-4 w-full max-w-md rounded-panel bg-surface p-6 shadow-float">
        <div class="text-center mb-4">
          <.icon name="ph-globe" class="mx-auto mb-2 size-10 text-brand" />
          <h2 class="text-subsection text-ink">Welcome to Gallformers!</h2>
          <p class="mt-1 text-ui text-ink-2">
            Select your region to see the most relevant results on filterable pages
            like Search, ID Tool, and Explore.
          </p>
          <p class="mt-1 text-caption text-muted">
            You can change this anytime. Your choice is saved in this browser only.
          </p>
        </div>
        <div class="grid grid-cols-2 gap-2 mb-4">
          <button
            :for={{code, name} <- @continents}
            type="button"
            phx-click="change_region"
            phx-value-code={code}
            data-prompt-code={code}
            class="rounded-ctl border border-line-strong px-3 py-2 text-ui font-medium text-ink hover:border-brand hover:bg-sky-soft"
          >
            {name}
          </button>
        </div>
        <div class="text-center">
          <button
            type="button"
            phx-click="change_region"
            phx-value-code=""
            data-prompt-code=""
            class="text-meta text-muted underline hover:text-ink"
          >
            Show all regions
          </button>
        </div>
      </div>
    </div>

    <div
      id="region-scope"
      phx-hook="RegionScope"
      data-default-code={@default_continent_code || ""}
      data-filtered={to_string(@continent_code != nil)}
      class={[
        "border-b",
        if(@continent_code, do: "border-line bg-warn-bg", else: "border-line bg-surface-2")
      ]}
    >
      <div class="px-6 sm:px-10 lg:px-16 py-1.5 flex items-center justify-between">
        <div class="flex items-center gap-1.5">
          <.icon
            name="ph-globe"
            class={["size-4", if(@continent_code, do: "text-warn", else: "text-muted")]}
          />
          <div class="relative">
            <button
              type="button"
              data-region-toggle
              class={[
                "flex items-center gap-1 text-meta",
                if(@continent_code,
                  do: "font-medium text-warn hover:text-ink",
                  else: "text-ink-2 hover:text-ink"
                )
              ]}
            >
              <span data-region-label>
                {if @continent_code, do: "Filtered to #{@continent_name}", else: "All Regions"}
              </span>
              <.icon name="ph-caret-down" class="size-3" />
            </button>
            <div
              data-region-dropdown
              class="gf-menu hidden left-0 mt-1 w-48"
            >
              <button
                type="button"
                phx-click="change_region"
                phx-value-code=""
                data-region-code=""
                aria-current={!@continent_code && "true"}
                class={[
                  "block w-full text-left",
                  !@continent_code && "bg-surface-2 font-semibold"
                ]}
              >
                All Regions
              </button>
              <button
                :for={{code, name} <- @continents}
                type="button"
                phx-click="change_region"
                phx-value-code={code}
                data-region-code={code}
                aria-current={@continent_code == code && "true"}
                class={[
                  "block w-full text-left",
                  @continent_code == code && "bg-surface-2 font-semibold"
                ]}
              >
                {name}
              </button>
            </div>
          </div>
        </div>

        <div :if={@overridden?} class="flex items-center gap-2 text-meta">
          <button
            type="button"
            data-region-save
            class="text-link hover:underline"
          >
            Set as default
          </button>
          <span class="text-line-strong">&middot;</span>
          <button
            type="button"
            data-region-reset
            phx-click="change_region"
            phx-value-code={@default_continent_code || ""}
            class="text-muted hover:text-ink hover:underline"
          >
            Reset
          </button>
        </div>
      </div>
    </div>
    """
  end
end
