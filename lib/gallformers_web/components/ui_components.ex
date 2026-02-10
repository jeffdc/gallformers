defmodule GallformersWeb.UIComponents do
  @moduledoc """
  Shared UI components for the Gallformers application.

  Provides reusable components for cards, spinners, alerts, pagination,
  error messages, and tooltips. These components follow the visual style
  from the v2_old SvelteKit implementation.
  """
  use Phoenix.Component
  use Gettext, backend: GallformersWeb.Gettext

  import GallformersWeb.CoreComponents, only: [icon: 1]

  alias Gallformers.Taxonomy.TaxonName
  alias Phoenix.LiveView.JS

  @doc """
  Renders a card container with optional header.

  ## Examples

      <.card>
        <p>Card content here</p>
      </.card>

      <.card title="My Card">
        <p>Card content with a title</p>
      </.card>

      <.card title="Actions Card">
        <:actions>
          <button>Edit</button>
        </:actions>
        <p>Card content with header actions</p>
      </.card>
  """
  attr :title, :string, default: nil, doc: "optional card title"
  attr :icon, :string, default: nil, doc: "optional icon name for the card header"
  attr :class, :any, default: nil, doc: "additional CSS classes for the card"
  attr :rest, :global

  slot :inner_block, required: true
  slot :actions, doc: "optional actions slot for the card header"

  def card(assigns) do
    ~H"""
    <div
      class={[
        "bg-white rounded-lg shadow-sm border border-gray-200",
        @title && "overflow-hidden",
        !@title && "p-4",
        @class
      ]}
      {@rest}
    >
      <div
        :if={@title}
        class="px-4 py-3 border-b border-gray-200 bg-gf-sky-blue flex items-center justify-between"
      >
        <h3 class="text-lg font-medium text-gf-maroon flex items-center gap-2">
          <.icon :if={@icon} name={@icon} class="size-5" />
          {@title}
        </h3>
        <div :if={@actions != []} class="flex items-center gap-2">
          {render_slot(@actions)}
        </div>
      </div>
      <div :if={@title} class="p-4 text-gray-700">
        {render_slot(@inner_block)}
      </div>
      <div :if={!@title} class="text-gray-700">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a loading spinner.

  ## Examples

      <.loading_spinner />
      <.loading_spinner size="lg" />
      <.loading_spinner size="sm" label="Loading data..." />
  """
  attr :size, :string, default: "md", values: ~w(sm md lg), doc: "spinner size"
  attr :label, :string, default: "Loading", doc: "accessible label for screen readers"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def loading_spinner(assigns) do
    size_classes = %{
      "sm" => "h-4 w-4",
      "md" => "h-8 w-8",
      "lg" => "h-12 w-12"
    }

    assigns = assign(assigns, :size_class, Map.fetch!(size_classes, assigns.size))

    ~H"""
    <svg
      class={["animate-spin text-gf-maroon", @size_class, @class]}
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
  Renders an error message with icon and optional retry button.

  ## Examples

      <.error_message title="Error" message="Something went wrong" />

      <.error_message
        variant="warning"
        title="Warning"
        message="Please check your input"
      />

      <.error_message
        title="Connection Error"
        message="Could not connect to server"
        on_retry={JS.push("retry")}
      />
  """
  attr :variant, :string,
    default: "error",
    values: ~w(error warning info),
    doc: "the variant of the error message"

  attr :title, :string, required: true, doc: "the error title"
  attr :message, :string, required: true, doc: "the error message"
  attr :on_retry, :any, default: nil, doc: "JS command or event to trigger on retry"
  attr :class, :any, default: nil, doc: "additional CSS classes"
  attr :rest, :global

  def error_message(assigns) do
    variant_styles = %{
      "error" => %{
        bg: "bg-red-50",
        border: "border-red-200",
        icon_color: "text-red-500",
        title_color: "text-red-800",
        text_color: "text-red-700",
        button_bg: "bg-red-100 hover:bg-red-200 text-red-800",
        icon: "ph-warning-circle"
      },
      "warning" => %{
        bg: "bg-yellow-50",
        border: "border-yellow-200",
        icon_color: "text-yellow-500",
        title_color: "text-yellow-800",
        text_color: "text-yellow-700",
        button_bg: "bg-yellow-100 hover:bg-yellow-200 text-yellow-800",
        icon: "ph-warning"
      },
      "info" => %{
        bg: "bg-blue-50",
        border: "border-blue-200",
        icon_color: "text-blue-500",
        title_color: "text-blue-800",
        text_color: "text-blue-700",
        button_bg: "bg-blue-100 hover:bg-blue-200 text-blue-800",
        icon: "ph-info"
      }
    }

    assigns = assign(assigns, :styles, Map.fetch!(variant_styles, assigns.variant))

    ~H"""
    <div
      class={[
        "p-4 rounded-md border",
        @styles.bg,
        @styles.border,
        @class
      ]}
      role="alert"
      {@rest}
    >
      <div class="flex items-start gap-3">
        <div class="flex-shrink-0">
          <.icon name={@styles.icon} class={["size-5", @styles.icon_color]} />
        </div>
        <div class="flex-1 min-w-0">
          <p class={["text-sm font-semibold", @styles.title_color]}>{@title}</p>
          <p class={["text-sm mt-1", @styles.text_color]}>{@message}</p>
        </div>
        <button
          :if={@on_retry}
          type="button"
          phx-click={@on_retry}
          class={[
            "inline-flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-md transition-colors",
            @styles.button_bg
          ]}
        >
          <.icon name="ph-arrows-clockwise" class="size-4" />
          {gettext("Retry")}
        </button>
      </div>
    </div>
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
      <div class="text-sm text-gray-700">
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
          class="px-3 py-1.5 text-sm font-medium rounded-md border border-gray-300 bg-white hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {gettext("Previous")}
        </button>
        <span class="text-sm text-gray-700">
          {gettext("Page %{page} of %{total}", page: @page, total: @total_pages)}
        </span>
        <button
          type="button"
          phx-click={@on_page_change.(@page + 1)}
          disabled={@page >= @total_pages}
          class="px-3 py-1.5 text-sm font-medium rounded-md border border-gray-300 bg-white hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
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
        bg: "bg-blue-50",
        border: "border-blue-200",
        text: "text-blue-800",
        icon: "ph-info"
      },
      "success" => %{
        bg: "bg-green-50",
        border: "border-green-200",
        text: "text-green-800",
        icon: "ph-check-circle"
      },
      "warning" => %{
        bg: "bg-yellow-50",
        border: "border-yellow-200",
        text: "text-yellow-800",
        icon: "ph-warning"
      },
      "error" => %{
        bg: "bg-red-50",
        border: "border-red-200",
        text: "text-red-800",
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
        "p-4 rounded-md border",
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
          <p :if={@title != []} class="text-sm font-medium">
            {render_slot(@title)}
          </p>
          <div class={["text-sm", @title != [] && "mt-1"]}>
            {render_slot(@inner_block)}
          </div>
        </div>
        <div :if={@dismissible} class="ml-auto pl-3">
          <button
            type="button"
            phx-click={JS.hide(to: "##{@id}")}
            class={[
              "-mx-1.5 -my-1.5 p-1.5 rounded-md inline-flex hover:bg-black/5 focus:outline-none focus:ring-2 focus:ring-offset-2",
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
  Renders an info tip tooltip icon.

  Displays a small "i" icon that shows a tooltip on hover with additional information.

  ## Examples

      <.info_tip content="This field is required for all species." />

      <.info_tip>
        <p>This is a longer explanation that can include</p>
        <p>multiple paragraphs or formatted content.</p>
      </.info_tip>
  """
  attr :content, :string, default: nil, doc: "tooltip text content"

  attr :position, :string,
    default: "top",
    values: ~w(top right bottom left),
    doc: "tooltip position"

  attr :class, :any, default: nil, doc: "additional CSS classes for the trigger"

  slot :inner_block, doc: "optional rich content for the tooltip"

  def info_tip(assigns) do
    position_classes = %{
      "top" => "bottom-full left-0 mb-2",
      "right" => "left-full top-1/2 -translate-y-1/2 ml-2",
      "bottom" => "top-full left-0 mt-2",
      "left" => "right-full top-1/2 -translate-y-1/2 mr-2"
    }

    arrow_classes = %{
      "top" => "top-full left-4 border-t-gray-900 border-x-transparent border-b-transparent",
      "right" =>
        "right-full top-1/2 -translate-y-1/2 border-r-gray-900 border-y-transparent border-l-transparent",
      "bottom" =>
        "bottom-full left-4 border-b-gray-900 border-x-transparent border-t-transparent",
      "left" =>
        "left-full top-1/2 -translate-y-1/2 border-l-gray-900 border-y-transparent border-r-transparent"
    }

    assigns =
      assigns
      |> assign(:position_class, Map.fetch!(position_classes, assigns.position))
      |> assign(:arrow_class, Map.fetch!(arrow_classes, assigns.position))

    ~H"""
    <span class={["relative inline-flex group", @class]}>
      <button
        type="button"
        class="inline-flex items-center justify-center min-w-[1.25rem] h-5 px-1.5 text-xs font-mono font-medium text-gray-600 bg-gray-200 rounded-full hover:bg-gray-300 focus:outline-none focus:ring-2 focus:ring-offset-1 focus:ring-blue-500"
        aria-describedby="tooltip"
      >
        i
      </button>
      <div
        class={[
          "absolute z-50 hidden group-hover:block w-max max-w-md px-3 py-2 text-sm text-white bg-gray-900 rounded-md shadow-lg",
          @position_class
        ]}
        role="tooltip"
      >
        <span :if={@content}>{@content}</span>
        <span :if={@inner_block != []}>{render_slot(@inner_block)}</span>
        <div class={["absolute w-0 h-0 border-4", @arrow_class]} />
      </div>
    </span>
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
      "absolute inset-0 z-10 flex items-center justify-center bg-white/80",
      @class
    ]}>
      <div class="flex flex-col items-center gap-2">
        <.loading_spinner size="lg" label={@label} />
        <span class="text-sm text-gray-600">{@label}</span>
      </div>
    </div>
    """
  end

  @doc """
  Renders a skeleton loading placeholder.

  ## Examples

      <.skeleton class="h-4 w-32" />
      <.skeleton variant="circle" class="h-10 w-10" />
      <.skeleton variant="text" lines={3} />
  """
  attr :variant, :string, default: "rect", values: ~w(rect circle text), doc: "shape variant"
  attr :lines, :integer, default: 1, doc: "number of lines for text variant"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def skeleton(assigns) do
    ~H"""
    <div :if={@variant == "rect"} class={["animate-pulse bg-gray-200 rounded", @class]} />
    <div :if={@variant == "circle"} class={["animate-pulse bg-gray-200 rounded-full", @class]} />
    <div :if={@variant == "text"} class="space-y-2">
      <div
        :for={i <- 1..@lines}
        class={[
          "animate-pulse bg-gray-200 rounded h-4",
          i == @lines && "w-3/4",
          i != @lines && "w-full",
          @class
        ]}
      />
    </div>
    """
  end

  @doc """
  Renders tabs for content organization.

  ## Examples

      <.tabs id="species-tabs">
        <:tab id="overview" label="Overview">
          <p>Overview content</p>
        </:tab>
        <:tab id="hosts" label="Hosts">
          <p>Hosts content</p>
        </:tab>
      </.tabs>
  """
  attr :id, :string, required: true, doc: "unique id for the tabs component"
  attr :default_tab, :string, default: nil, doc: "id of the default active tab"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  slot :tab, required: true do
    attr :id, :string, required: true
    attr :label, :string, required: true
  end

  def tabs(assigns) do
    default_tab = assigns.default_tab || (List.first(assigns.tab) || %{})[:id]
    assigns = assign(assigns, :default_tab, default_tab)

    ~H"""
    <div id={@id} class={@class} phx-hook="Tabs" data-default-tab={@default_tab}>
      <div class="border-b border-gray-200">
        <nav class="-mb-px flex gap-1" aria-label="Tabs">
          <button
            :for={tab <- @tab}
            type="button"
            id={"#{@id}-tab-#{tab.id}"}
            data-tab-id={tab.id}
            class="px-4 py-2 text-sm font-medium border-b-2 border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-gf-maroon transition-colors data-[active]:border-gf-maroon data-[active]:text-gf-maroon"
            role="tab"
            aria-selected="false"
            aria-controls={"#{@id}-panel-#{tab.id}"}
          >
            {tab.label}
          </button>
        </nav>
      </div>
      <div class="mt-4">
        <div
          :for={tab <- @tab}
          id={"#{@id}-panel-#{tab.id}"}
          data-tab-panel={tab.id}
          class="hidden data-[active]:block"
          role="tabpanel"
          aria-labelledby={"#{@id}-tab-#{tab.id}"}
        >
          {render_slot(tab)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders "See Also" links to external resources with logo images.

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
    <%= unless @undescribed do %>
      <div>
        <hr class="border-gray-200 my-4" />
        <div class="mb-4 font-semibold text-gray-700">See Also:</div>
        <div class={[
          "grid items-center",
          @type == :gall && "grid-cols-2 md:grid-cols-4",
          @type == :host && "grid-cols-3"
        ]}>
          <a
            href={"https://www.inaturalist.org/search?q=#{@search_name}"}
            target="_blank"
            rel="noreferrer"
            aria-label="Search for this species on iNaturalist"
            class="hover:opacity-80 transition-opacity"
          >
            <img src="/images/inatlogo-small.png" alt="iNaturalist" />
          </a>
          <a
            :if={@type == :gall}
            href={"https://bugguide.net/index.php?q=search&keys=#{@search_name}&search=Search"}
            target="_blank"
            rel="noreferrer"
            aria-label="Search for this species on BugGuide"
            class="hover:opacity-80 transition-opacity"
          >
            <img src="/images/bugguide-small.png" alt="BugGuide" />
          </a>
          <a
            href={"https://scholar.google.com/scholar?hl=en&q=#{@search_name}"}
            target="_blank"
            rel="noreferrer"
            aria-label="Search for this species on Google Scholar"
            class="hover:opacity-80 transition-opacity"
          >
            <img src="/images/gscholar-small.png" alt="Google Scholar" />
          </a>
          <a
            href={"https://www.biodiversitylibrary.org/search?SearchTerm=#{@search_name}&SearchCat=M#/names"}
            target="_blank"
            rel="noreferrer"
            aria-label="Search for this species at the Biodiversity Heritage Library"
            class="hover:opacity-80 transition-opacity"
          >
            <img src="/images/bhllogo.png" alt="Biodiversity Heritage Library" />
          </a>
        </div>
      </div>
    <% end %>
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

  @doc """
  Renders a glossary term with hover tooltip showing its definition.

  Displays the term inline with a dotted underline and help cursor.
  On hover, shows the first sentence of the definition with a link
  to the full glossary entry.

  ## Examples

      <.glossary_tooltip term="agamic" definition="The agamic generation consists of only female wasps..." />
  """
  attr :term, :string, required: true, doc: "the glossary term to display (e.g., \"agamic\")"

  attr :glossary_word, :string,
    default: nil,
    doc: "the glossary word to link to, if different from term (e.g., \"sexgen\" for \"sexual\")"

  attr :definition, :string, default: nil, doc: "the full glossary definition"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def glossary_tooltip(assigns) do
    assigns =
      assigns
      |> assign(:short_definition, first_sentence(assigns.definition))
      |> assign_new(:link_word, fn -> assigns.glossary_word || assigns.term end)

    ~H"""
    <span class={["relative inline-flex group", @class]}>
      <span class="cursor-help border-b border-dotted border-gray-400">({@term})</span>
      <span
        class="absolute z-50 hidden group-hover:block top-full left-1/2 -translate-x-1/2 mt-2 w-80 px-3 py-2 text-sm font-normal not-italic text-white bg-gray-900 rounded-md shadow-lg"
        role="tooltip"
      >
        <span class="absolute bottom-full left-1/2 -translate-x-1/2 w-0 h-0 border-4 border-t-transparent border-x-transparent border-b-gray-900" />
        <span class="font-semibold">{@link_word}:</span>
        <span :if={@short_definition != ""}>{@short_definition}</span>
        <a
          href={"/glossary##{String.downcase(@link_word)}"}
          class="block mt-1 text-blue-300 hover:text-blue-200 text-xs"
        >
          View in glossary &rarr;
        </a>
      </span>
    </span>
    """
  end

  defp first_sentence(text) when is_binary(text) do
    case String.split(text, ~r/(?<=\.)\s/, parts: 2) do
      [sentence | _] -> String.trim(sentence)
      _ -> text
    end
  end

  defp first_sentence(_), do: ""
end
