defmodule GallformersWeb.FormComponents do
  @moduledoc """
  Form-related components for the Gallformers application.

  Provides enhanced form inputs, multi-select controls, and other
  form-related UI elements that extend Phoenix's core form components.

  The design system's form components (docs/design-system/components.md,
  "Forms") are `field`, `search_field`, `facet_group`, `filter_select`,
  `file_drop` and `radio_card`; the others here are restyled or retired as
  pages move onto the system.
  """
  use Phoenix.Component
  use Gettext, backend: GallformersWeb.Gettext

  import GallformersWeb.CoreComponents, only: [icon: 1]
  import GallformersWeb.ActionComponents, only: [button: 1]
  import GallformersWeb.FeedbackComponents, only: [dialog: 1, notice: 1]
  import GallformersWeb.DataComponents, only: [chip: 1]

  alias Gallformers.TextMatch
  alias GallformersWeb.Helpers
  alias Phoenix.LiveView.JS

  # ── Design system: field, search_field, facet_group ──────────────────────
  # docs/design-system/components.md ("Forms").

  @doc """
  A control with its label, help and errors.

  Layouts: `:stacked` (label above; public forms and narrow spaces) and
  `:row` (label in a fixed left column, help and errors under the control;
  admin edit pages). A row stacks on phones.

  The control is the inner block, so `field` can't wire it up itself. Give
  `for` the control's id; `field` then renders the help as `<for>-help` and
  the errors as `<for>-errors`. Point the control at them:

      aria-describedby="title-help title-errors"   (only the ones rendered)
      aria-invalid={@errors != [] && "true"}

  `saved` shows "Saved" beside the control, in a polite live region that is
  always rendered so screen readers announce the change.

  ## Examples

      <.field label="Name" for="taxon-name" help="The old name is kept as a synonym."
              errors={@errors} layout={:row} required>
        <input id="taxon-name" name="name" aria-describedby="taxon-name-help taxon-name-errors"
               aria-invalid={@errors != [] && "true"} class="…" />
      </.field>

      <.field label="Rank" for="rank" saved={@saved == :rank}>
        <select id="rank" name="rank">…</select>
      </.field>
  """
  attr :label, :string, required: true
  attr :for, :string, default: nil, doc: "the control's id; also names the help and error ids"
  attr :help, :string, default: nil, doc: "a line under the control saying what the value does"
  attr :errors, :list, default: [], doc: "error messages, each shown on its own line"
  attr :layout, :atom, default: :stacked, values: [:stacked, :row]
  attr :required, :boolean, default: false
  attr :saved, :boolean, default: false, doc: ~s|shows "Saved" beside the control|
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global
  slot :inner_block, required: true, doc: "the control"

  def field(assigns) do
    ~H"""
    <div
      data-layout={@layout}
      class={[
        "flex flex-col gap-1",
        @layout == :row && "sm:flex-row sm:items-start sm:gap-3",
        @class
      ]}
      {@rest}
    >
      <label
        for={@for}
        class={[
          "text-ui font-semibold text-ink",
          @layout == :row && "sm:flex sm:min-h-ctl sm:w-38 sm:shrink-0 sm:items-center sm:gap-1"
        ]}
      >
        {@label}
        <span :if={@required} class="text-muted" aria-hidden="true">*</span>
        <span :if={@required} class="sr-only">(required)</span>
      </label>
      <div data-part="control" class="flex min-w-0 flex-1 flex-col gap-1">
        <div class="flex items-center gap-2">
          <div class="min-w-0 flex-1">{render_slot(@inner_block)}</div>
          <span aria-live="polite" class="shrink-0 text-meta text-ok">
            {if @saved, do: "Saved"}
          </span>
        </div>
        <p :if={@help} id={@for && "#{@for}-help"} class="text-meta text-muted">{@help}</p>
        <div :if={@errors != []} id={@for && "#{@for}-errors"} class="flex flex-col gap-0.5">
          <p :for={error <- @errors} class="flex items-center gap-1.5 text-meta text-danger">
            <.icon name="ph-warning-circle" class="size-4 shrink-0" />
            {error}
          </p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  One search input: the header search, list filters, the admin top bar.

  `label` names the input for screen readers (there is no visible label);
  `placeholder` defaults to it. `on_clear` adds a "Clear search" button while
  there is a value. `shortcut` shows a key hint while the field is empty and
  puts the key in `data-shortcut` and `aria-keyshortcuts`; focusing the field
  on that key needs a client-side listener for `[data-shortcut]`.

  Attributes not listed here (`phx-change`, `phx-keydown`, `form` …) go on
  the input.

  ## Examples

      <.search_field
        id="gall-search"
        name="q"
        value={@query}
        label="Search Galls"
        placeholder="Name or Host"
        shortcut="/"
        on_clear={JS.push("clear_search")}
        phx-change="search"
      />
  """
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :label, :string, required: true, doc: "the input's accessible name"
  attr :placeholder, :string, default: nil, doc: "defaults to the label"
  attr :shortcut, :string, default: nil, doc: ~s|a key that focuses the field, e.g. "/"|
  attr :on_clear, JS, default: nil, doc: "shows a clear button while there is a value"
  attr :debounce, :string, default: "300", doc: "milliseconds, or \"blur\""
  attr :id, :string, default: nil
  attr :class, :any, default: nil, doc: "layout only (width, placement)"
  attr :rest, :global, include: ~w(form autocomplete disabled), doc: "goes on the input"

  def search_field(assigns) do
    assigns = assign(assigns, :empty?, assigns.value in [nil, ""])

    ~H"""
    <div class={["relative", @class]}>
      <.icon
        name="ph-magnifying-glass"
        class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted"
      />
      <input
        type="search"
        id={@id}
        name={@name}
        value={@value}
        placeholder={@placeholder || @label}
        aria-label={@label}
        aria-keyshortcuts={@shortcut}
        data-shortcut={@shortcut}
        phx-debounce={@debounce}
        class="peer h-ctl w-full rounded-ctl border border-line-strong bg-surface pl-8 pr-8 text-ui text-ink placeholder:text-muted"
        {@rest}
      />
      <kbd
        :if={@shortcut && @empty?}
        aria-hidden="true"
        class="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 rounded-ctl border border-line-strong bg-surface-2 px-1.5 font-sans text-caption text-muted peer-not-placeholder-shown:hidden"
      >
        {@shortcut}
      </kbd>
      <button
        :if={@on_clear && !@empty?}
        type="button"
        aria-label="Clear search"
        phx-click={@on_clear}
        class="absolute right-1 top-1/2 inline-flex size-6 -translate-y-1/2 items-center justify-center rounded-ctl text-muted hover:text-ink"
      >
        <.icon name="ph-x" class="size-4" />
      </button>
    </div>
    """
  end

  @doc """
  A filter with counts: a heading and options, each with how many results it
  would leave. For the ID page and browse pages.

  Options are maps `%{value:, label:, count:, selected:}`. `count` may be nil
  (no count shown). Options with a count of 0 are dimmed, never hidden or
  disabled. Past `limit`, options hide behind "Show N more"; selected options
  always show.

  `multiple` (the default) renders checkboxes named `name[]`, with a hidden
  empty value so clearing every box still sends the param: drop `""` from the
  list. `multiple={false}` renders radios named `name`; to let the reader go
  back to no choice, pass an option such as `%{value: "", label: "Any"}`.

  It has no `phx-change` of its own: put it in the page's filter form.

  ## Examples

      <form phx-change="filter">
        <.facet_group id="facet-part" title="Plant part" name="lo" options={@part_facets} />
        <.facet_group id="facet-host" title="Host" name="h" options={@host_facets}
                      multiple={false} italic />
      </form>
  """
  attr :id, :string, required: true, doc: "the fieldset's id, used by the show-more toggle"
  attr :title, :string, required: true, doc: "the legend"
  attr :name, :string, required: true, doc: "the form param"
  attr :options, :list, default: [], doc: "%{value:, label:, count:, selected:} maps, in order"
  attr :multiple, :boolean, default: true, doc: "checkboxes (true) or radios (false)"
  attr :limit, :integer, default: 8, doc: "options shown before Show N more"
  attr :italic, :boolean, default: false, doc: "labels are scientific names"
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  def facet_group(assigns) do
    options =
      assigns.options
      |> Enum.with_index()
      |> Enum.map(fn {option, i} ->
        Map.put(option, :overflow?, i >= assigns.limit and not option_selected?(option))
      end)

    assigns =
      assigns
      |> assign(:indexed, Enum.with_index(options))
      |> assign(:hidden_count, Enum.count(options, & &1.overflow?))
      |> assign(:input_name, if(assigns.multiple, do: "#{assigns.name}[]", else: assigns.name))

    ~H"""
    <fieldset id={@id} class={["flex flex-col", @class]} {@rest}>
      <legend class="mb-1 text-caption font-semibold uppercase tracking-wide text-muted">
        {@title}
      </legend>
      <input :if={@multiple} type="hidden" name={@input_name} value="" />
      <label
        :for={{option, i} <- @indexed}
        data-overflow={option.overflow?}
        data-zero={option[:count] == 0}
        class={[
          "flex min-h-row items-center gap-2 text-ui",
          if(option[:count] == 0, do: "text-muted", else: "text-ink"),
          option.overflow? && "hidden"
        ]}
      >
        <input
          type={if @multiple, do: "checkbox", else: "radio"}
          id={"#{@id}-#{i}"}
          name={@input_name}
          value={option.value}
          checked={option_selected?(option)}
          class="size-4 shrink-0 accent-brand-fill"
        />
        <span class={["min-w-0 flex-1", @italic && "italic"]}>{option.label}</span>
        <span :if={option[:count]} data-part="count" class="text-meta tabular-nums text-muted">
          {Helpers.format_number(option.count)}
        </span>
      </label>
      <.button
        :if={@hidden_count > 0}
        id={"#{@id}-more"}
        variant="ghost"
        size="sm"
        class="self-start"
        aria-expanded="false"
        aria-controls={@id}
        phx-click={toggle_facet_overflow(@id)}
      >
        <span data-part="more">Show {@hidden_count} more</span>
        <span data-part="fewer" class="hidden">Show fewer</span>
      </.button>
    </fieldset>
    """
  end

  defp option_selected?(option), do: Map.get(option, :selected, false) == true

  defp toggle_facet_overflow(id) do
    JS.toggle_class("hidden", to: "##{id} [data-overflow]")
    |> JS.toggle_class("hidden", to: "##{id}-more [data-part=more]")
    |> JS.toggle_class("hidden", to: "##{id}-more [data-part=fewer]")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{id}-more")
  end

  @doc """
  A single-value filter: a labelled select in its own form, for a row of
  filters (the ID page). See docs/design-system/components.md (`filter_select`).

  The form carries whatever change event and values the page passes
  (`phx-change`, `phx-value-*`), so the page's handlers stay as they are.
  While unset, each option shows how many results it would leave
  (`counts`, keyed by option value); once set, the select is marked and the
  counts are hidden. Multi-value filters use `multi_select_typeahead`.

  ## Examples

      <.filter_select
        id="filter-season"
        name="value"
        label="Season"
        prompt="Any"
        options={[{"Spring", "Spring"}, {"Fall", "Fall"}]}
        value={@filters.season}
        counts={@season_counts}
        phx-change="change_filter"
        phx-value-filter="season"
      />
  """
  attr :id, :string, required: true, doc: "the select's id (its label points to it)"
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :prompt, :string, required: true, doc: "the empty choice, e.g. Any"
  attr :options, :list, required: true, doc: "{label, value} pairs"
  attr :value, :any, default: nil, doc: "the current value; nil when unset"
  attr :counts, :map, default: %{}, doc: "results per option value, shown while unset"
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global, doc: "for the form: phx-change, phx-value-*, phx-target"

  def filter_select(assigns) do
    assigns = assign(assigns, :set?, assigns.value not in [nil, ""])

    ~H"""
    <form class={["min-w-0", @class]} {@rest}>
      <label class="gf-label" for={@id}>{@label}</label>
      <select
        id={@id}
        name={@name}
        data-set={@set?}
        class={["gf-select", @set? && "border-brand font-semibold"]}
      >
        <option value="">{@prompt}</option>
        <option
          :for={{label, value} <- @options}
          value={value}
          selected={to_string(value) == to_string(@value)}
        >
          {label}{if not @set? and Map.has_key?(@counts, value), do: " (#{@counts[value]})"}
        </option>
      </select>
    </form>
    """
  end

  @doc """
  Where to drop or choose files, for the upload hooks (`ImageUpload`,
  `ContentImageUpload`). See docs/design-system/components.md (`file_drop`).

  Renders the `data-dropzone` element and its hidden `data-file-input`; the
  hook, on an enclosing element, handles the click, the drop and its
  highlight. `layout={:box}` (the default) is a dashed box with an icon;
  `:row` is one line, for tight spaces.

  ## Examples

      <div id="uploader" phx-hook="ImageUpload" phx-update="ignore">
        <.file_drop accept="image/jpeg,image/png" multiple hint="Max 20 files. JPG or PNG only." />
        <div data-preview-container></div>
      </div>

      <.file_drop layout={:row} label="Choose files… or drop JPG or PNG images here" multiple />
  """
  attr :accept, :string, default: "image/jpeg,image/png", doc: "the file input's accept"
  attr :multiple, :boolean, default: false
  attr :label, :string, default: "Drop images here, or click to choose"
  attr :hint, :string, default: nil, doc: "the limits: how many, which types"
  attr :icon, :string, default: "ph-cloud-arrow-up"
  attr :layout, :atom, default: :box, values: [:box, :row]
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  def file_drop(assigns) do
    ~H"""
    <div
      data-dropzone
      data-layout={@layout}
      class={[
        "flex w-full cursor-pointer border-dashed border-line-strong transition-colors",
        "hover:border-brand hover:bg-sky-soft",
        if(@layout == :row,
          do: "items-center gap-2 rounded-ctl border px-3 py-1.5 text-left",
          else: "flex-col items-center gap-1 rounded-panel border-2 p-6 text-center"
        ),
        @class
      ]}
      {@rest}
    >
      <.icon
        name={@icon}
        class={["shrink-0 text-muted", if(@layout == :row, do: "size-5", else: "size-8")]}
      />
      <span class="text-ui text-ink-2">{@label}</span>
      <span :if={@hint} class="text-meta text-muted">{@hint}</span>
      <input data-file-input type="file" accept={@accept} multiple={@multiple} hidden />
    </div>
    """
  end

  @doc """
  One option of a question as a card: a radio (or checkbox) with its name,
  what it does, and what it needs once chosen. See
  docs/design-system/components.md (`radio_card`).

  The card is plain, recommended (a brand border and a "Recommended" chip,
  `data-recommended`) or chosen (a brand border on a brand tint,
  `data-chosen`). `rest` (`phx-click`, `phx-value-*`, `phx-target`) goes on
  the input. The `follow` slot shows only once chosen. Put the cards in an
  element with `role="radiogroup"` and the question as its `aria-label`.

  ## Examples

      <div role="radiogroup" aria-label="Which plant is meant?" class="grid gap-1.5">
        <.radio_card id="q-0" name="q" value={0} checked={@choice == 0} recommended
          summary="The accepted name." phx-click="pick" phx-value-choice={0}>
          <:label>Quercus lobata</:label>
          <:aside>2 of 3 readers</:aside>
          <:follow><.typeahead … /></:follow>
        </.radio_card>
      </div>
  """
  attr :id, :string, required: true, doc: "the input's id"
  attr :name, :string, required: true
  attr :value, :any, required: true
  attr :checked, :boolean, default: false
  attr :type, :string, default: "radio", values: ~w(radio checkbox)
  attr :recommended, :boolean, default: false

  attr :recommended_label, :string,
    default: "Recommended",
    doc: "the recommended chip's words; nil for no chip"

  attr :summary, :string, default: nil, doc: "under the label, muted: what it does"
  attr :size, :atom, default: :md, values: [:md, :sm], doc: ":sm for long value lists"
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global, doc: "for the input: phx-click, phx-value-*, phx-target"

  slot :label, required: true, doc: "the option's name; chips may follow it"
  slot :aside, doc: "right of the label on wide screens: who recommends it, who chose it"
  slot :extra, doc: "under the card's text, chosen or not"
  slot :follow, doc: "the input the option needs, shown once chosen"

  def radio_card(assigns) do
    ~H"""
    <div
      class={[
        "rounded-ctl border",
        if(@size == :sm, do: "px-2.5 py-1.5", else: "px-3 py-2"),
        cond do
          @checked -> "border-brand bg-brand/5"
          @recommended -> "border-brand bg-surface"
          true -> "border-line bg-surface hover:border-line-strong"
        end,
        @class
      ]}
      data-recommended={@recommended}
      data-chosen={@checked}
    >
      <label for={@id} class="flex cursor-pointer flex-wrap items-start gap-x-2.5 gap-y-0.5 text-ui">
        <input
          type={@type}
          id={@id}
          name={@name}
          value={@value}
          checked={@checked}
          class="mt-0.5 size-4 shrink-0 accent-brand-fill"
          {@rest}
        />
        <span class={[
          "min-w-0 flex-1 text-ink",
          if(@size == :sm, do: "font-medium", else: "font-semibold")
        ]}>
          {render_slot(@label)}
          <.chip
            :if={@recommended and @recommended_label}
            variant={:recommended}
            size="sm"
            data-role="recommended"
            class="ml-1"
          >
            {@recommended_label}
          </.chip>
        </span>
        <span
          :if={@aside != []}
          class={[
            "max-w-72 basis-full pl-6.5 text-meta md:basis-auto md:pl-0 md:text-right",
            if(@recommended, do: "font-semibold text-brand", else: "text-muted")
          ]}
        >
          {render_slot(@aside)}
        </span>
        <span :if={@summary} class="basis-full pl-6.5 text-meta text-muted">{@summary}</span>
      </label>
      <div :if={@extra != []} data-part="extra" class="mt-1 ml-6.5 grid gap-1">
        {render_slot(@extra)}
      </div>
      <div :if={@checked and @follow != []} data-part="follow" class="mt-2 grid gap-2 md:ml-6.5">
        {render_slot(@follow)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a search input with icon.

  ## Examples

      <.search_input
        id="species-search"
        name="query"
        value={@query}
        placeholder="Search species..."
        phx-change="search"
      />
  """
  attr :id, :string, required: true, doc: "unique id for the input"
  attr :name, :string, required: true, doc: "input name"
  attr :value, :string, default: "", doc: "current value"
  attr :placeholder, :string, default: "Search...", doc: "placeholder text"
  attr :label, :string, default: nil, doc: "accessible label for screen readers"
  attr :class, :any, default: nil, doc: "additional CSS classes"
  attr :size, :atom, values: [:default, :sm], default: :default, doc: "input size variant"
  attr :rest, :global, include: ~w(phx-change phx-submit phx-debounce form data-typeahead-input)

  def search_input(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <div class={[
        "absolute inset-y-0 left-0 flex items-center pointer-events-none",
        if(@size == :sm, do: "pl-2.5", else: "pl-3")
      ]}>
        <.icon
          name="ph-magnifying-glass"
          class={if(@size == :sm, do: "size-4 text-muted", else: "size-5 text-muted")}
        />
      </div>
      <input
        type="search"
        id={@id}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        aria-label={@label || @placeholder}
        class={if(@size == :sm, do: "gf-search-input-sm", else: "gf-search-input")}
        {@rest}
      />
    </div>
    """
  end

  @doc """
  A switch: a checkbox (`role="switch"`) drawn as a track, for a setting
  that takes effect at once. With no visible `label`, give it an
  `aria-label`; events (`phx-click`, `phx-value-*`) go on the checkbox.

  ## Examples

      <.toggle
        id="auto-save"
        name="auto_save"
        checked={@auto_save}
        label="Enable auto-save"
      />
  """
  attr :id, :string, required: true, doc: "unique id for the toggle"
  attr :name, :string, required: true, doc: "form input name"
  attr :checked, :boolean, default: false, doc: "whether the toggle is on"
  attr :label, :string, default: nil, doc: "optional label"
  attr :disabled, :boolean, default: false, doc: "whether the toggle is disabled"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  attr :form, :string,
    default: nil,
    doc: "form id to associate with, or arbitrary value to disassociate from parent form"

  attr :rest, :global

  def toggle(assigns) do
    ~H"""
    <label class={["inline-flex cursor-pointer items-center gap-2.5", @class]}>
      <input type="hidden" name={@name} value="false" form={@form} />
      <input
        type="checkbox"
        role="switch"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        disabled={@disabled}
        class="sr-only"
        form={@form}
        {@rest}
      />
      <span class="gf-toggle-track" aria-hidden="true"></span>
      <span :if={@label} class="text-ui text-ink">{@label}</span>
    </label>
    """
  end

  @doc """
  Renders a multi-select dropdown with search/filter capability.

  This component displays selected items as removable chips, with a text input
  for filtering options and a dropdown that appears on focus/click and dismisses
  on click-away. Supports both static options (client-side filtering) and async
  search (server-provided results).

  ## Modes

  **Static Mode** (options provided):
  - Pass `options` as a list of maps with `:id` and display field
  - Component filters options based on search query
  - Good for small/medium option lists

  **Async Mode** (search_results provided):
  - Pass `search_results` instead of `options`
  - Parent LiveView handles search and provides filtered results
  - Good for large datasets or server-side filtering

  ## Events

  The component emits these events with the specified params:
  - `on_search` - when user types (params include `type` and `value`)
  - `on_add` - when user selects an option (params include `type` and `id`)
  - `on_remove` - when user removes a chip (params include `type` and `id`)
  - `on_open` - when dropdown should open (params include `type`)
  - `on_close` - when dropdown should close (no params)

  ## Examples

  Static options mode (admin filter):

      <.multi_select_dropdown
        id="colors"
        label="Color(s):"
        type={:colors}
        options={@filter_options.colors}
        selected={@filter_values.colors}
        search_query={@filter_search.colors}
        dropdown_open={@filter_dropdown_open == :colors}
        item_label={:field}
        on_search="filter_search"
        on_add="add_filter"
        on_remove="remove_filter"
        on_open="open_filter_dropdown"
        on_close="close_filter_dropdown"
        size="sm"
      />

  Async search mode (host picker):

      <.multi_select_dropdown
        id="hosts"
        label="Hosts:"
        type={:hosts}
        search_results={@host_search_results}
        selected={@hosts}
        search_query={@host_search_query}
        dropdown_open={@host_dropdown_open}
        item_id={:host_species_id}
        item_label={:host_name}
        on_search="search_hosts"
        on_add="add_host"
        on_remove="remove_host"
        on_open="open_host_dropdown"
        on_close="close_host_dropdown"
        size="md"
      />
  """
  attr :id, :string, required: true, doc: "unique identifier for the component"
  attr :label, :string, default: nil, doc: "optional label text"
  attr :type, :any, required: true, doc: "type key for event params (atom or string)"

  # Options (use one or the other)
  attr :options, :list, default: nil, doc: "static list of all options (for client filtering)"

  attr :search_results, :list,
    default: nil,
    doc: "server-provided search results (for async mode)"

  # State
  attr :selected, :list, required: true, doc: "list of currently selected items"
  attr :search_query, :string, required: true, doc: "current search/filter query"
  attr :dropdown_open, :boolean, required: true, doc: "whether dropdown is visible"

  # Display configuration
  attr :item_id, :atom, default: :id, doc: "field name for selected item ID (used for remove)"

  attr :result_id, :atom,
    default: nil,
    doc: "field name for search result ID (used for add, defaults to item_id)"

  attr :selected_match_id, :atom,
    default: nil,
    doc: "field in selected items to match against result_id for dedup (defaults to result_id)"

  attr :item_label, :atom, required: true, doc: "field name for item display text"

  attr :result_label, :atom,
    default: nil,
    doc: "field name for search result display (defaults to item_label)"

  attr :placeholder, :string, default: "Select...", doc: "placeholder when empty"

  # Events
  attr :on_search, :string, required: true, doc: "event for search input changes"
  attr :on_add, :string, required: true, doc: "event for adding an item"
  attr :on_remove, :string, required: true, doc: "event for removing an item"
  attr :on_open, :string, required: true, doc: "event for opening dropdown"
  attr :on_close, :string, required: true, doc: "event for closing dropdown"

  # Styling
  attr :size, :string,
    default: "sm",
    values: ~w(sm md),
    doc: "size variant: sm (admin) or md (public)"

  attr :class, :any, default: nil, doc: "additional CSS classes"
  attr :required, :boolean, default: false, doc: "whether this field is required"

  def multi_select_dropdown(assigns) do
    # Resolve result_id and result_label (default to item_id/item_label)
    result_id = assigns.result_id || assigns.item_id
    result_label = assigns.result_label || assigns.item_label
    # selected_match_id: the field in selected items to compare against result_id
    selected_match_id = assigns.selected_match_id || result_id

    # Compute available options (filtered, excluding already selected)
    available =
      compute_available_options(
        assigns.options,
        assigns.search_results,
        assigns.selected,
        assigns.search_query,
        assigns.item_id,
        result_id,
        selected_match_id,
        result_label
      )

    # Size-based classes - use semantic CSS with size modifiers
    is_md = assigns.size == "md"

    assigns =
      assigns
      |> assign(:available, available)
      |> assign(:result_id_resolved, result_id)
      |> assign(:result_label_resolved, result_label)
      |> assign(:is_md, is_md)

    ~H"""
    <div class={@class}>
      <label :if={@label} class="gf-label">
        {@label}<span :if={@required} class="ml-0.5 text-danger">*</span>
      </label>
      <div
        id={@id}
        phx-hook="Typeahead"
        data-input-id={"#{@id}-input"}
        data-search-event={@on_search}
        data-search-type={@type}
        data-query={@search_query}
        data-close-event={@on_close}
        class="relative"
      >
        <div
          class={["gf-multi-select-container", @is_md && "gf-multi-select-container-md"]}
          phx-click={@on_open}
          phx-value-type={@type}
        >
          <span
            :for={item <- @selected}
            class={["gf-chip", !@is_md && "gf-chip-sm"]}
          >
            {get_display_label(item, @item_label)}
            <button
              type="button"
              phx-click={@on_remove}
              phx-value-type={@type}
              phx-value-id={get_item_id(item, @item_id)}
              onmousedown="event.preventDefault()"
              class="gf-chip-remove"
            >
              <.icon name="ph-x" class="h-3 w-3" />
            </button>
          </span>
          <input
            id={"#{@id}-input"}
            data-typeahead-input
            type="text"
            value={@search_query}
            placeholder={if @selected == [], do: @placeholder, else: ""}
            phx-focus={@on_open}
            phx-blur={@on_close}
            phx-value-type={@type}
            class={["gf-multi-select-input", @is_md && "gf-multi-select-input-md"]}
          />
        </div>
        <%= if @dropdown_open && @available != [] do %>
          <div
            id={"#{@id}-results"}
            data-typeahead-results
            phx-click-away={@on_close}
            onmousedown="event.preventDefault()"
            class={["gf-multi-select-dropdown", @is_md && "gf-multi-select-dropdown-md"]}
          >
            <button
              :for={opt <- @available}
              type="button"
              data-typeahead-option
              phx-click={@on_add}
              phx-value-type={@type}
              phx-value-id={get_item_id(opt, @result_id_resolved)}
              class="gf-multi-select-option hover:bg-sky-soft"
            >
              {get_display_label(opt, @result_label_resolved)}
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Compute available options based on mode (static vs async)
  # - item_id: field in selected items for comparison in static mode
  # - result_id: field in search results/options for comparison
  # - selected_match_id: field in selected items to match against result_id (for async mode with different structures)
  # - result_label: field in options for filtering by text
  defp compute_available_options(
         options,
         search_results,
         selected,
         query,
         item_id,
         result_id,
         selected_match_id,
         result_label
       ) do
    cond do
      # Async mode: use search_results directly (already filtered by server)
      # Compare result_id from search results against selected_match_id from selected items
      search_results != nil ->
        selected_ids = MapSet.new(Enum.map(selected, &get_item_id(&1, selected_match_id)))
        Enum.reject(search_results, &MapSet.member?(selected_ids, get_item_id(&1, result_id)))

      # Static mode: filter options client-side
      # Options and selected items typically have same structure, use item_id for both
      options != nil ->
        selected_ids = MapSet.new(Enum.map(selected, &get_item_id(&1, item_id)))

        options
        |> Enum.reject(&MapSet.member?(selected_ids, get_item_id(&1, item_id)))
        |> Enum.filter(fn opt ->
          TextMatch.matches_all_terms?(query, get_display_label(opt, result_label))
        end)

      # No options provided
      true ->
        []
    end
  end

  # Get item ID from a map, supporting different field names
  defp get_item_id(item, field) when is_map(item) do
    Map.get(item, field)
  end

  # Get display label from a map
  defp get_display_label(item, field) when is_map(item) and is_atom(field) do
    Map.get(item, field, "")
  end

  @doc """
  Renders a single-select typeahead component with server-side search.

  Displays a search input that shows results in a dropdown. When an item is selected,
  it displays the selection with a clear button. Includes full keyboard navigation
  via the Typeahead JS hook.

  ## Keyboard behavior
  - Arrow Down/Up: Navigate through results
  - Enter: Select highlighted item
  - Escape: Clear results or selection
  - Backspace/Delete on selection: Clear and focus input
  - Type on selection: Clear and start new search

  ## Events

  The component emits events using the provided event names:
  - `search_event` - when user types (params: %{"value" => query})
  - `select_event` - when user selects an option (params: %{"id" => id})
  - `clear_event` - when user clears the selection
  - `create_event` - when user selects "create new" (params: %{"name" => query})
    (only fires if `allow_new` is true)

  ## Create-or-select mode

  When `allow_new` is true, a "Create '{query}'" option appears when:
  - The query has at least 2 characters
  - No result name exactly matches the query (case-insensitive)

  This is useful for admin forms where users need to either select existing
  items or create new ones with the same input.

  ## Examples

      <.typeahead
        id="host-picker"
        label="Host:"
        placeholder="Search hosts..."
        search_event="search_host"
        select_event="select_host"
        clear_event="clear_host"
        query={@host_query}
        results={@host_results}
        selected={@selected_host}
        display_fn={fn host -> host.name end}
      />

      <%!-- Create-or-select mode --%>
      <.typeahead
        id="gall-picker"
        label="Gall:"
        placeholder="Search or create gall..."
        search_event="search_gall"
        select_event="select_gall"
        clear_event="clear_gall"
        create_event="create_gall"
        allow_new={true}
        query={@gall_query}
        results={@gall_results}
        selected={@selected_gall}
        display_fn={fn gall -> gall.name end}
      />
  """
  attr :id, :string, required: true, doc: "unique identifier for the component"
  attr :label, :string, required: true, doc: "label text"
  attr :placeholder, :string, default: "Search...", doc: "placeholder for the input"
  attr :search_event, :string, required: true, doc: "event name for search"
  attr :select_event, :string, required: true, doc: "event name for selection"
  attr :clear_event, :string, required: true, doc: "event name for clearing"

  attr :create_event, :string,
    default: nil,
    doc: "event name for creating new (requires allow_new)"

  attr :allow_new, :boolean, default: false, doc: "allow creating new items when no results"
  attr :query, :string, required: true, doc: "current search query"
  attr :results, :list, required: true, doc: "list of search results"
  attr :selected, :any, default: nil, doc: "currently selected item"
  attr :display_fn, :any, required: true, doc: "function to display an item (fn item -> string)"
  attr :result_slot, :any, default: nil, doc: "optional slot for custom result rendering"
  attr :class, :string, default: "", doc: "additional CSS classes for the wrapper"
  attr :target, :any, default: nil, doc: "phx-target for events (use @myself for LiveComponents)"
  attr :required, :boolean, default: false, doc: "whether this field is required"

  attr :group_key, :atom,
    default: nil,
    doc: "Key in result maps to group by. When set, inserts non-selectable group headers."

  slot :result, doc: "optional slot for custom result item rendering" do
    attr :item, :any
  end

  slot :label_suffix, doc: "optional content to render after the label (e.g., info_tip)"

  def typeahead(assigns) do
    # Determine if we should show the "create new" option
    # Show when no result name exactly matches the query (e.g., alias matches show
    # the owning species but the typed name is still new and creatable)
    query_lower = String.downcase(assigns.query)

    exact_match? =
      Enum.any?(assigns.results, fn item ->
        String.downcase(assigns.display_fn.(item)) == query_lower
      end)

    show_create_option =
      assigns.allow_new &&
        assigns.create_event &&
        String.length(assigns.query) >= 2 &&
        not exact_match?

    show_no_matches =
      Enum.empty?(assigns.results) &&
        not show_create_option &&
        String.length(assigns.query) >= 2

    assigns =
      assigns
      |> assign(:show_create_option, show_create_option)
      |> assign(:show_no_matches, show_no_matches)

    ~H"""
    <div
      id={@id}
      phx-hook="Typeahead"
      data-clear-event={@clear_event}
      data-search-event={@search_event}
      data-input-id={"#{@id}-input"}
      data-query={@query}
      data-target={@target && @target.cid}
      class={@class}
    >
      <label class="gf-label">
        {@label}<span :if={@required} class="ml-0.5 text-danger">*</span>
        {render_slot(@label_suffix)}
      </label>
      <%= if @selected do %>
        <div
          id={"#{@id}-selected"}
          data-typeahead-selected
          class="flex h-ctl items-center gap-2 rounded-ctl border border-line-strong bg-surface-2 px-3 cursor-text"
          tabindex="0"
          aria-label={"Selected: #{@display_fn.(@selected)}. Type to search, or press Escape to clear."}
        >
          <span class="flex-1 truncate text-ui italic text-ink">{@display_fn.(@selected)}</span>
          <button
            type="button"
            phx-click={@clear_event}
            phx-target={@target}
            class="text-muted hover:text-ink"
            aria-label="Clear selection"
            tabindex="-1"
          >
            <.icon name="ph-x" class="size-4" />
          </button>
        </div>
      <% else %>
        <div class="relative">
          <input
            id={"#{@id}-input"}
            data-typeahead-input
            type="text"
            value={@query}
            phx-target={@target}
            phx-debounce="200"
            placeholder={@placeholder}
            class="gf-input"
            role="combobox"
            aria-expanded={length(@results) > 0 || @show_create_option || @show_no_matches}
            aria-controls={"#{@id}-results"}
            aria-autocomplete="list"
          />
          <div
            :if={length(@results) > 0 || @show_create_option || @show_no_matches}
            id={"#{@id}-results"}
            data-typeahead-results
            class="absolute z-10 mt-1 max-h-60 w-full overflow-auto rounded-panel border border-line bg-surface shadow-float"
            role="listbox"
          >
            <%!-- No matches message --%>
            <div
              :if={@show_no_matches}
              class="px-3 py-2 text-meta italic text-muted"
              role="status"
            >
              No matches found
            </div>
            <%!-- Existing results with optional group headers --%>
            <%= for {item, index} <- Enum.with_index(@results) do %>
              <%= if @group_key && show_group_header?(item, index, @results, @group_key) do %>
                <div
                  class="px-3 py-1.5 text-caption font-semibold uppercase tracking-wide text-muted"
                  role="presentation"
                >
                  {Map.get(item, @group_key)}
                </div>
              <% end %>
              <button
                type="button"
                data-typeahead-option
                phx-click={@select_event}
                phx-target={@target}
                phx-value-id={item.id}
                class="w-full border-b border-line px-3 py-1.5 text-left text-ui text-ink last:border-b-0 hover:bg-sky-soft"
                role="option"
              >
                <%= if @result != [] do %>
                  {render_slot(@result, item)}
                <% else %>
                  <span class="italic">{@display_fn.(item)}</span>
                <% end %>
              </button>
            <% end %>
            <%!-- Create new option (shown when no results and allow_new is true) --%>
            <button
              :if={@show_create_option}
              type="button"
              data-typeahead-option
              phx-click={@create_event}
              phx-target={@target}
              phx-value-name={@query}
              class="w-full border-b border-line px-3 py-1.5 text-left text-ui font-semibold text-ok last:border-b-0 hover:bg-ok-bg"
              role="option"
            >
              <.icon name="ph-plus" class="size-4 inline-block mr-1" />
              Create "<span class="italic">{@query}</span>"
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a multi-select typeahead component.

  Displays selected items as removable tags, with a text input for filtering
  and a dropdown showing available options.

  ## Events

  The component emits events prefixed with the `name` attribute:
  - `{name}_search` - when user types in the input (params: %{"value" => query})
  - `{name}_focus` - when input receives focus
  - `{name}_blur` - when input loses focus
  - `{name}_select` - when user selects an option (params: %{"id" => id})
  - `{name}_remove` - when user removes a selected item (params: %{"id" => id})
  - `{name}_clear` - when user clicks the clear all button

  ## Examples

      <.multi_select_typeahead
        id="plant_parts"
        name="plant_part"
        label="Plant Part(s):"
        placeholder="Plant Parts"
        options={@filter_options.plant_parts}
        selected={@filters.plant_parts}
        option_label={:plant_part}
        query={@plant_part_query}
        focused={@plant_part_focused}
      />
  """
  attr :id, :string, required: true, doc: "unique identifier for the component"
  attr :name, :string, required: true, doc: "name prefix for events"
  attr :label, :string, required: true, doc: "label text"
  attr :placeholder, :string, default: "", doc: "placeholder when no items selected"
  attr :options, :list, required: true, doc: "list of all available options"
  attr :selected, :list, required: true, doc: "list of selected option ids"
  attr :option_label, :atom, required: true, doc: "field name to display from option map"
  attr :query, :string, required: true, doc: "current search query"
  attr :focused, :boolean, required: true, doc: "whether the input is focused"
  attr :required, :boolean, default: false, doc: "whether this field is required"

  def multi_select_typeahead(assigns) do
    option_label = assigns.option_label

    # Get selected option objects
    selected_options = Enum.filter(assigns.options, fn opt -> opt.id in assigns.selected end)

    # Filter available options based on query
    filtered_options =
      assigns.options
      |> Enum.reject(fn opt -> opt.id in assigns.selected end)
      |> Enum.filter(fn opt ->
        label = Map.get(opt, option_label, "")
        TextMatch.matches_all_terms?(assigns.query, label)
      end)

    assigns =
      assigns
      |> assign(:selected_options, selected_options)
      |> assign(:filtered_options, filtered_options)

    ~H"""
    <div
      id={"#{@id}-wrapper"}
      phx-hook="Typeahead"
      data-clear-event={"#{@name}_clear"}
      data-search-event={"#{@name}_search"}
      data-input-id={@id}
      data-query={@query}
      class="mb-2"
    >
      <label class="gf-label">
        {@label}<span :if={@required} class="ml-0.5 text-danger">*</span>
      </label>
      <div class="relative">
        <%!-- Selected tags and input --%>
        <div class="flex min-h-ctl flex-wrap items-center gap-1 rounded-ctl border border-line-strong bg-surface px-2 py-1">
          <span
            :for={opt <- @selected_options}
            class="gf-chip gf-chip-sm"
          >
            {Map.get(opt, @option_label)}
            <button
              type="button"
              phx-click={"#{@name}_remove"}
              phx-value-id={to_string(opt.id)}
              class="gf-chip-remove"
            >
              <.icon name="ph-x" class="size-3" />
            </button>
          </span>
          <input
            type="text"
            id={@id}
            data-typeahead-input
            value={@query}
            phx-focus={"#{@name}_focus"}
            phx-blur={"#{@name}_blur"}
            phx-debounce="100"
            placeholder={if @selected_options == [], do: @placeholder, else: ""}
            class="min-w-20 flex-1 border-0 bg-transparent p-0 text-ui text-ink focus:outline-none"
            role="combobox"
            aria-expanded={@focused and length(@filtered_options) > 0}
            aria-controls={"#{@id}-results"}
            aria-autocomplete="list"
          />
          <%!-- Clear all button --%>
          <button
            :if={@selected_options != []}
            type="button"
            phx-click={"#{@name}_clear"}
            class="shrink-0 p-1 text-muted hover:text-ink"
            title="Clear all"
          >
            <.icon name="ph-x" class="size-4" />
          </button>
        </div>
        <%!-- Dropdown --%>
        <div
          :if={@focused and length(@filtered_options) > 0}
          id={"#{@id}-results"}
          data-typeahead-results
          class="absolute z-10 mt-1 max-h-48 w-full overflow-auto rounded-panel border border-line bg-surface shadow-float"
          role="listbox"
          onmousedown="event.preventDefault()"
        >
          <div
            :for={opt <- @filtered_options}
            data-typeahead-option
            phx-click={"#{@name}_select"}
            phx-value-id={to_string(opt.id)}
            class="w-full cursor-pointer border-b border-line px-3 py-1.5 text-left text-ui text-ink last:border-b-0 hover:bg-sky-soft"
            role="option"
          >
            {Map.get(opt, @option_label)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a slide-in drill-down panel for country subdivision editing.

  Used by both CountryDrillDown and PlaceDrillDown. Provides the
  panel chrome (slide-in transition, header, close button) and slots for
  custom content.

  ## Example

      <.drill_down_panel
        open={@open}
        country_name={@country.name}
        on_close="close"
        target={@myself}
      >
        <:header_extra>
          <p class="mb-3 text-caption text-muted">Help text here.</p>
        </:header_extra>
        <ul>...</ul>
      </.drill_down_panel>
  """
  attr :open, :boolean, required: true
  attr :country_name, :string, default: nil
  attr :on_close, :string, required: true
  attr :target, :any, required: true

  slot :header_extra,
    doc: "Content after the header, before the list (e.g., toggles, bulk buttons)"

  slot :inner_block, required: true, doc: "The subdivision list content"

  def drill_down_panel(assigns) do
    ~H"""
    <div class={[
      "transition-all duration-300 overflow-hidden",
      if(@open, do: "w-80 border-l border-line", else: "w-0")
    ]}>
      <div :if={@open} class="p-4 h-full overflow-y-auto">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-subsection font-semibold text-ink">{@country_name}</h3>
          <button
            type="button"
            phx-click={@on_close}
            phx-target={@target}
            class="text-muted hover:text-ink"
            aria-label="Close panel"
          >
            <.icon name="ph-x" class="size-5" />
          </button>
        </div>
        {render_slot(@header_extra)}
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a high-friction confirmation modal for destructive admin deletes.

  The record is not deletable until the admin types its exact name. The parent
  LiveView (or the LiveComponent given as `target`) must handle
  `update_delete_confirmation`, `confirm_delete`, and `cancel_delete`, and
  must validate the submitted confirmation again before deleting.
  """
  attr :show, :boolean, required: true, doc: "whether to show the modal"
  attr :item_type, :string, required: true, doc: "human-readable record type"
  attr :item_name, :string, required: true, doc: "exact record name required for confirmation"
  attr :consequences, :list, required: true, doc: "descriptions of data affected by deletion"
  attr :confirmation_value, :string, default: "", doc: "current confirmation input value"
  attr :id, :string, default: "dangerous-delete-modal", doc: "modal DOM id"
  attr :target, :any, default: nil, doc: "phx-target for its events (a LiveComponent's @myself)"

  def dangerous_delete_modal(assigns) do
    ~H"""
    <.dialog
      :if={@show}
      id={@id}
      title={"Permanently delete this #{@item_type}?"}
      size={:sm}
      show
      on_cancel={JS.push("cancel_delete", target: @target)}
    >
      <div class="flex flex-col gap-block">
        <.notice kind={:danger} title="This cannot be undone.">
          Deleting <strong>{@item_name}</strong>
          will have the following impact:
          <ul class="mt-1 list-disc pl-5">
            <li :for={consequence <- @consequences}>{consequence}</li>
          </ul>
        </.notice>

        <form id={"#{@id}-form"} phx-submit="confirm_delete" phx-target={@target}>
          <label for="dangerous-delete-confirmation" class="gf-label">
            Type <strong>{@item_name}</strong> to confirm:
          </label>
          <input
            type="text"
            id="dangerous-delete-confirmation"
            name="confirmation"
            value={@confirmation_value}
            phx-hook="InputEvent"
            data-event="update_delete_confirmation"
            data-target={@target && @target.cid}
            autocomplete="off"
            autocapitalize="off"
            spellcheck="false"
            class="gf-input"
            autofocus
          />
        </form>
      </div>
      <:actions>
        <.button type="button" variant="ghost" phx-click="cancel_delete" phx-target={@target}>
          Cancel
        </.button>
        <.button
          id="dangerous-delete-submit"
          type="submit"
          form={"#{@id}-form"}
          variant="danger"
          icon="ph-trash"
          disabled={@confirmation_value != @item_name}
        >
          Delete permanently
        </.button>
      </:actions>
    </.dialog>
    """
  end

  @doc """
  Renders a selectable tree with groups, tristate checkboxes, expand/collapse, and select/deselect all.

  Each group has a tristate checkbox (all, none, or some selected) and can be expanded to show
  individual items. Uses the `IndeterminateCheckbox` JS hook for tristate rendering.

  ## Examples

      <.selectable_tree
        id="places-tree"
        label="Native places"
        groups={@grouped_places}
        selected={@selected_places}
        expanded={@expanded_groups}
        toggle_item_event="toggle_place"
        toggle_group_event="toggle_country"
        expand_group_event="expand_country"
        select_all_event="select_all_places"
        deselect_all_event="deselect_all_places"
      />
  """
  attr :id, :string, required: true
  attr :label, :string, required: true

  attr :groups, :list,
    required: true,
    doc: "list of %{id: term, label: String.t(), items: [%{id: term, label: String.t()}]}"

  attr :selected, :any, required: true, doc: "MapSet of selected item IDs"
  attr :expanded, :any, required: true, doc: "MapSet of expanded group IDs"
  attr :toggle_item_event, :string, required: true
  attr :toggle_group_event, :string, required: true
  attr :expand_group_event, :string, required: true
  attr :select_all_event, :string, required: true
  attr :deselect_all_event, :string, required: true
  attr :container_class, :string, default: "rounded-panel border border-line p-3"
  attr :text_class, :string, default: "text-ink-2"
  attr :heading_class, :string, default: "text-ink-2"
  attr :checkbox_class, :string, default: ""
  attr :target, :any, default: nil, doc: "phx-target for events (use @myself for LiveComponents)"

  slot :group_footer, doc: "optional per-group content rendered when group is expanded"

  def selectable_tree(assigns) do
    total_items = Enum.reduce(assigns.groups, 0, fn g, acc -> acc + length(g.items) end)

    selected_count =
      Enum.reduce(assigns.groups, 0, fn g, acc ->
        acc + Enum.count(g.items, &MapSet.member?(assigns.selected, &1.id))
      end)

    all_selected = total_items > 0 and selected_count == total_items

    assigns =
      assigns
      |> assign(:total_items, total_items)
      |> assign(:selected_count, selected_count)
      |> assign(:all_selected, all_selected)

    ~H"""
    <div id={@id} class={@container_class}>
      <div class="flex items-center justify-between">
        <span class={"font-medium #{@text_class}"}>
          {@label} ({@selected_count}/{@total_items})
        </span>
        <button
          type="button"
          phx-click={if @all_selected, do: @deselect_all_event, else: @select_all_event}
          phx-target={@target}
          class={"text-caption #{@text_class} hover:underline"}
        >
          {if @all_selected, do: "Deselect all", else: "Select all"}
        </button>
      </div>
      <div class="mt-2 max-h-96 overflow-y-auto space-y-1">
        <div :for={group <- @groups}>
          <% gs = selectable_tree_group_state(group, @selected, @expanded) %>
          <div class="flex items-center gap-1.5">
            <input
              id={"#{@id}-group-#{group.id}"}
              type="checkbox"
              checked={gs.all_selected}
              data-indeterminate={to_string(!gs.all_selected and !gs.none_selected)}
              phx-hook="IndeterminateCheckbox"
              phx-click={@toggle_group_event}
              phx-target={@target}
              phx-value-group={to_string(group.id)}
              class={"gf-checkbox #{@checkbox_class}"}
            />
            <button
              type="button"
              phx-click={@expand_group_event}
              phx-target={@target}
              phx-value-group={to_string(group.id)}
              class={"flex items-center gap-1 text-caption font-medium #{@heading_class} hover:underline"}
            >
              <span class="w-3 text-center">{if gs.expanded, do: "▾", else: "▸"}</span>
              {group.label}
              <span class="font-normal text-muted">
                ({gs.selected_count}/{gs.total_count})
              </span>
            </button>
          </div>
          <div :if={gs.expanded} class="ml-6 space-y-0.5 mt-0.5">
            <label :for={item <- group.items} class="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={MapSet.member?(@selected, item.id)}
                phx-click={@toggle_item_event}
                phx-target={@target}
                phx-value-id={to_string(item.id)}
                class={"gf-checkbox #{@checkbox_class}"}
              />
              <span class="text-caption">{item.label}</span>
            </label>
            {render_slot(@group_footer, group)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp selectable_tree_group_state(group, selected, expanded) do
    selected_count = Enum.count(group.items, &MapSet.member?(selected, &1.id))
    total_count = length(group.items)

    %{
      selected_count: selected_count,
      total_count: total_count,
      all_selected: selected_count == total_count,
      none_selected: selected_count == 0,
      expanded: MapSet.member?(expanded, group.id)
    }
  end

  # Typeahead grouping helpers

  defp show_group_header?(_result, 0, _results, _group_key) do
    true
  end

  defp show_group_header?(result, index, results, group_key) do
    prev = Enum.at(results, index - 1)
    Map.get(result, group_key) != Map.get(prev, group_key)
  end
end
