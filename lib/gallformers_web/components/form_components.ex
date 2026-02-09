defmodule GallformersWeb.FormComponents do
  @moduledoc """
  Form-related components for the Gallformers application.

  Provides enhanced form inputs, multi-select controls, and other
  form-related UI elements that extend Phoenix's core form components.
  """
  use Phoenix.Component
  use Gettext, backend: GallformersWeb.Gettext

  import GallformersWeb.CoreComponents, only: [icon: 1, modal: 1]
  import GallformersWeb.UIComponents, only: [alert: 1]

  alias Phoenix.LiveView.JS

  @doc """
  Renders a multi-select component with pill-style toggle buttons.

  ## Examples

      <.multi_select
        id="shapes"
        label="Select Shapes"
        options={[%{value: "round", label: "Round"}, %{value: "oval", label: "Oval"}]}
        selected={@selected_shapes}
        on_toggle="toggle_shape"
      />
  """
  attr :id, :string, required: true, doc: "unique id for the component"
  attr :label, :string, default: nil, doc: "optional label"
  attr :options, :list, required: true, doc: "list of %{value: _, label: _} maps"
  attr :selected, :list, default: [], doc: "list of selected values"
  attr :on_toggle, :string, required: true, doc: "event name for toggle"
  attr :class, :any, default: nil, doc: "additional CSS classes"
  attr :required, :boolean, default: false, doc: "whether this field is required"

  def multi_select(assigns) do
    ~H"""
    <div id={@id} class={@class}>
      <label :if={@label} class="gf-label mb-2">
        {@label}<span :if={@required} class="text-red-500 ml-0.5">*</span>
      </label>
      <div class="flex flex-wrap gap-2">
        <button
          :for={option <- @options}
          type="button"
          phx-click={@on_toggle}
          phx-value-value={option.value}
          class={[
            "gf-pill",
            (option.value in @selected || to_string(option.value) in @selected) && "gf-pill-selected",
            !(option.value in @selected || to_string(option.value) in @selected) &&
              "gf-pill-unselected"
          ]}
        >
          {option.label}
        </button>
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
  attr :rest, :global, include: ~w(phx-change phx-submit phx-debounce form data-typeahead-input)

  def search_input(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
        <.icon name="ph-magnifying-glass" class="size-5 text-gray-400" />
      </div>
      <input
        type="search"
        id={@id}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        aria-label={@label || @placeholder}
        class="gf-search-input"
        {@rest}
      />
    </div>
    """
  end

  @doc """
  Renders a form field wrapper with label and error display.

  This is a simpler alternative to the full input component when you
  need more control over the actual input element.

  ## Examples

      <.field_wrapper label="Species Name" error={@errors[:name]}>
        <input type="text" name="name" class="..." />
      </.field_wrapper>
  """
  attr :label, :string, required: true, doc: "field label"
  attr :error, :any, default: nil, doc: "error message or nil"
  attr :required, :boolean, default: false, doc: "whether the field is required"
  attr :hint, :string, default: nil, doc: "optional hint text"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  slot :inner_block, required: true

  def field_wrapper(assigns) do
    ~H"""
    <div class={["mb-4", @class]}>
      <label class="gf-label">
        {@label}
        <span :if={@required} class="text-red-500">*</span>
      </label>
      {render_slot(@inner_block)}
      <p :if={@hint && !@error} class="gf-hint">
        {@hint}
      </p>
      <p :if={@error} class="gf-error">
        <.icon name="ph-warning-circle" class="size-4" />
        {@error}
      </p>
    </div>
    """
  end

  @doc """
  Renders a toggle switch.

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
  attr :rest, :global

  def toggle(assigns) do
    ~H"""
    <label class={["inline-flex items-center cursor-pointer", @disabled && "opacity-50", @class]}>
      <input type="hidden" name={@name} value="false" />
      <div class="relative">
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          disabled={@disabled}
          class="sr-only peer"
          {@rest}
        />
        <div class="gf-toggle-track peer peer-checked:bg-gf-maroon peer-focus:ring-2 peer-focus:ring-gf-maroon/50 peer-checked:after:translate-x-full peer-checked:after:border-white">
        </div>
      </div>
      <span :if={@label} class="gf-label ml-3 mb-0">{@label}</span>
    </label>
    """
  end

  @doc """
  Renders a radio button group.

  ## Examples

      <.radio_group
        id="abundance"
        name="abundance"
        label="Abundance"
        options={[%{value: "common", label: "Common"}, %{value: "rare", label: "Rare"}]}
        value={@abundance}
      />
  """
  attr :id, :string, required: true, doc: "unique id for the group"
  attr :name, :string, required: true, doc: "form input name"
  attr :label, :string, default: nil, doc: "group label"
  attr :options, :list, required: true, doc: "list of %{value: _, label: _} maps"
  attr :value, :any, default: nil, doc: "currently selected value"
  attr :class, :any, default: nil, doc: "additional CSS classes"
  attr :rest, :global, include: ~w(phx-change form)

  def radio_group(assigns) do
    ~H"""
    <fieldset id={@id} class={@class}>
      <legend :if={@label} class="gf-label mb-2">{@label}</legend>
      <div class="space-y-2">
        <label :for={option <- @options} class="flex items-center">
          <input
            type="radio"
            name={@name}
            value={option.value}
            checked={@value == option.value || to_string(@value) == to_string(option.value)}
            class="gf-radio"
            {@rest}
          />
          <span class="ml-2 text-base text-gray-700">{option.label}</span>
          <span :if={option[:description]} class="gf-hint ml-1">
            - {option.description}
          </span>
        </label>
      </div>
    </fieldset>
    """
  end

  @doc """
  Renders a file upload dropzone.

  ## Examples

      <.file_dropzone
        id="images"
        upload={@uploads.images}
        label="Upload Images"
        accept=".jpg,.jpeg,.png,.gif"
      />
  """
  attr :id, :string, required: true, doc: "unique id for the dropzone"
  attr :upload, :any, required: true, doc: "Phoenix.LiveView upload configuration"
  attr :label, :string, default: "Drop files here or click to browse", doc: "dropzone label"
  attr :accept, :string, default: nil, doc: "accepted file types"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def file_dropzone(assigns) do
    ~H"""
    <div
      id={@id}
      class={["gf-dropzone", @class]}
      phx-drop-target={@upload.ref}
    >
      <div class="space-y-1 text-center">
        <.icon name="ph-cloud-arrow-up" class="mx-auto size-12 text-gray-400" />
        <div class="flex text-sm text-gray-600">
          <label class="gf-dropzone-link">
            <span>{gettext("Upload a file")}</span>
            <.live_file_input upload={@upload} class="sr-only" />
          </label>
          <p class="pl-1">{gettext("or drag and drop")}</p>
        </div>
        <p class="gf-hint text-xs">{@label}</p>
      </div>
    </div>
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
        {@label}<span :if={@required} class="text-red-500 ml-0.5">*</span>
      </label>
      <div
        id={@id}
        phx-hook="Typeahead"
        data-input-id={"#{@id}-input"}
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
            phx-keyup={@on_search}
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
              class="gf-multi-select-option hover:bg-gray-100 data-[highlighted]:bg-gray-100"
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
        search_lower = String.downcase(query)

        options
        |> Enum.reject(&MapSet.member?(selected_ids, get_item_id(&1, item_id)))
        |> Enum.filter(fn opt ->
          query == "" ||
            String.contains?(String.downcase(get_display_label(opt, result_label)), search_lower)
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

    assigns = assign(assigns, :show_create_option, show_create_option)

    ~H"""
    <div
      id={@id}
      phx-hook="Typeahead"
      data-clear-event={@clear_event}
      data-search-event={@search_event}
      data-input-id={"#{@id}-input"}
      class={@class}
    >
      <label class="gf-label">
        {@label}<span :if={@required} class="text-red-500 ml-0.5">*</span>
        {render_slot(@label_suffix)}
      </label>
      <%= if @selected do %>
        <div
          id={"#{@id}-selected"}
          data-typeahead-selected
          class="flex items-center gap-2 p-2 bg-gray-50 rounded border focus:ring-2 focus:ring-gf-maroon focus:border-gf-maroon cursor-text"
          tabindex="0"
          aria-label={"Selected: #{@display_fn.(@selected)}. Type to search, or press Escape to clear."}
        >
          <span class="flex-1 text-base italic">{@display_fn.(@selected)}</span>
          <button
            type="button"
            phx-click={@clear_event}
            phx-target={@target}
            class="text-gray-400 hover:text-gray-600"
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
            phx-keyup={@search_event}
            phx-target={@target}
            phx-debounce="200"
            placeholder={@placeholder}
            class="gf-input"
            role="combobox"
            aria-expanded={length(@results) > 0 || @show_create_option}
            aria-controls={"#{@id}-results"}
            aria-autocomplete="list"
          />
          <div
            :if={length(@results) > 0 || @show_create_option}
            id={"#{@id}-results"}
            data-typeahead-results
            class="absolute z-10 w-full mt-1 bg-white border border-gray-200 rounded-md shadow-lg max-h-60 overflow-auto"
            role="listbox"
          >
            <%!-- Existing results --%>
            <button
              :for={item <- @results}
              type="button"
              data-typeahead-option
              phx-click={@select_event}
              phx-target={@target}
              phx-value-id={item.id}
              class="w-full text-left px-3 py-2 text-base hover:bg-gray-50 border-b border-gray-100 last:border-b-0"
              role="option"
            >
              <%= if @result != [] do %>
                {render_slot(@result, item)}
              <% else %>
                <span class="italic">{@display_fn.(item)}</span>
              <% end %>
            </button>
            <%!-- Create new option (shown when no results and allow_new is true) --%>
            <button
              :if={@show_create_option}
              type="button"
              data-typeahead-option
              phx-click={@create_event}
              phx-target={@target}
              phx-value-name={@query}
              class="w-full text-left px-3 py-2 text-base hover:bg-green-50 border-b border-gray-100 last:border-b-0 text-green-700 font-medium"
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
    query_lower = String.downcase(assigns.query)

    filtered_options =
      assigns.options
      |> Enum.reject(fn opt -> opt.id in assigns.selected end)
      |> Enum.filter(fn opt ->
        label = Map.get(opt, option_label, "")
        assigns.query == "" or String.contains?(String.downcase(label), query_lower)
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
      class="mb-2"
    >
      <label class="gf-label">
        {@label}<span :if={@required} class="text-red-500 ml-0.5">*</span>
      </label>
      <div class="relative">
        <%!-- Selected tags and input --%>
        <div class="flex flex-wrap gap-1 p-2 border border-gray-300 rounded-md bg-white min-h-[42px]">
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
            phx-keyup={"#{@name}_search"}
            phx-focus={"#{@name}_focus"}
            phx-blur={"#{@name}_blur"}
            phx-debounce="100"
            placeholder={if @selected_options == [], do: @placeholder, else: ""}
            class="flex-1 min-w-[80px] border-0 p-0 text-base focus:ring-0 focus:outline-none"
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
            class="flex-shrink-0 text-gray-400 hover:text-gray-600 p-1"
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
          class="absolute z-10 w-full mt-1 bg-white border border-gray-200 rounded-md shadow-lg max-h-48 overflow-auto"
          role="listbox"
          onmousedown="event.preventDefault()"
        >
          <div
            :for={opt <- @filtered_options}
            data-typeahead-option
            phx-click={"#{@name}_select"}
            phx-value-id={to_string(opt.id)}
            class="w-full text-left px-3 py-2 text-base hover:bg-gray-50 border-b border-gray-100 last:border-b-0 cursor-pointer"
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
  Renders a rename modal for species (galls or hosts).

  The modal allows renaming a species and optionally adding an alias for the old name.
  All events are emitted to the parent LiveView which handles the actual rename logic.

  Backdrop click, ESC, and X button are routed through `on_cancel` to allow the
  parent LiveView to guard against accidental dismiss when the form has changes.
  The Cancel button always fires `close_rename_modal` directly.

  ## Events emitted

  - `request_close_rename` - when user clicks backdrop, presses ESC, or clicks X (via on_cancel)
  - `close_rename_modal` - when user clicks Cancel (always closes)
  - `update_rename_value` - when user types in the input (params: `value`)
  - `toggle_add_alias_on_rename` - when user toggles the checkbox
  - `do_rename` - when user clicks Save Changes

  ## Examples

      <.rename_modal
        show={@show_rename_modal}
        value={@rename_value}
        add_alias_checked={@add_alias_on_rename}
        entity_type="Gall"
      />
  """
  attr :show, :boolean, required: true, doc: "whether to show the modal"
  attr :value, :string, required: true, doc: "current value in the rename input"

  attr :add_alias_checked, :boolean,
    required: true,
    doc: "whether the add alias checkbox is checked"

  attr :entity_type, :string,
    required: true,
    doc: "entity type for display (e.g., 'Gall' or 'Host')"

  attr :rename_collisions, :list,
    default: [],
    doc: "alias collisions for the rename value (from Species.find_species_with_alias/1)"

  def rename_modal(assigns) do
    ~H"""
    <.modal
      :if={@show}
      id="rename-modal"
      show
      on_cancel={JS.push("request_close_rename")}
      class="gf-modal-md"
    >
      <:header>Edit {@entity_type} Name</:header>
      <:body>
        <input
          id="rename-modal-input"
          type="text"
          value={@value}
          phx-keyup="update_rename_value"
          phx-hook="InputEvent"
          data-event="update_rename_value"
          phx-debounce="300"
          class="w-full px-4 py-3 border border-gray-300 rounded text-lg focus:ring-gf-maroon focus:border-gf-maroon"
          autofocus
        />

        <.alert :if={@rename_collisions != []} variant="warning" class="mt-3">
          <:title>Alias collision</:title>
          <div :for={c <- @rename_collisions}>
            This name is a {rename_collision_type_label(c.alias_type)} of
            <.link
              navigate={rename_collision_species_path(c.taxoncode, c.species_id)}
              class="underline font-medium"
            >
              {c.species_name}
            </.link>
          </div>
        </.alert>

        <div class="mt-5">
          <label class="flex items-center gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={@add_alias_checked}
              phx-click="toggle_add_alias_on_rename"
              class="w-5 h-5 rounded border-gray-300 text-gf-maroon focus:ring-gf-maroon"
            />
            <span class="text-base text-gray-700">Add Alias for old name?</span>
          </label>
        </div>

        <div class="mt-4 text-sm text-gray-500">
          If you want to reassign the species to a different genus, enter the new name
          with the new genus. If the genus doesn't exist, it will be created under the same family.
          If it exists, the species will be reassigned to that genus.
        </div>
      </:body>
      <:footer>
        <button
          type="button"
          phx-click="close_rename_modal"
          class="px-5 py-2.5 text-base text-gray-600 hover:text-gray-800"
        >
          Cancel
        </button>
        <button
          type="button"
          phx-click="do_rename"
          class="px-5 py-2.5 bg-gf-maroon text-white text-base rounded hover:bg-gf-maroon/90"
        >
          Save Changes
        </button>
      </:footer>
    </.modal>
    """
  end

  @doc """
  Renders a cascade delete confirmation modal.

  Shows the impact of deleting an entity with cascading relationships:
  - Summary of what will be deleted (counts)
  - Expandable details showing specific items
  - Type-to-confirm input for safety
  - Red/warning styling to indicate destructive action

  ## Events

  The modal sends these events to the parent LiveView:
  - `confirm_cascade_delete` with `%{"confirmation" => value}` on submit
  - `cancel_cascade_delete` when cancelled (including backdrop click, ESC, X button)

  ## Example

      <.cascade_delete_modal
        show={@show_delete_modal}
        impact={@deletion_impact}
        confirmation_value={@delete_confirmation}
      />

  Where `@deletion_impact` has the structure:
      %{
        taxonomy: %{name: "Cynipidae", type: "family"},
        genera: [%{name: "Andricus"}, ...],
        genera_count: 5,
        sections: [%{name: "Lobatae"}, ...],
        sections_count: 2,
        species_count: 150,
        has_impact: true
      }
  """
  attr :show, :boolean, required: true, doc: "whether to show the modal"
  attr :impact, :map, required: true, doc: "deletion impact data from get_deletion_impact/1"
  attr :confirmation_value, :string, default: "", doc: "current value in the confirmation input"

  def cascade_delete_modal(assigns) do
    ~H"""
    <.modal
      :if={@show and @impact}
      id="cascade-delete-modal"
      show
      on_cancel={JS.push("cancel_cascade_delete")}
      class="gf-modal-sm"
    >
      <:header>
        <span class="text-red-800">
          <.icon name="ph-warning" class="h-5 w-5 inline mr-1" /> Delete {@impact.taxonomy.name}?
        </span>
      </:header>
      <:body>
        <div class="space-y-4">
          <p class="text-red-700 font-medium">
            To delete this {@impact.taxonomy.type}, all dependent data will be permanently deleted.
          </p>

          <%!-- Impact Summary --%>
          <div :if={@impact.has_impact} class="bg-red-50 border border-red-200 rounded-lg p-4">
            <p class="font-medium text-red-800 mb-2">This will delete:</p>
            <ul class="list-disc list-inside space-y-1 text-red-700">
              <li :if={@impact.genera_count > 0}>
                <strong>{@impact.genera_count}</strong> genera
              </li>
              <li :if={@impact.sections_count > 0}>
                <strong>{@impact.sections_count}</strong> sections
              </li>
              <li :if={@impact.species_count > 0}>
                <strong>{@impact.species_count}</strong> species
              </li>
              <li :if={@impact.species_count > 0} class="text-sm text-red-600 mt-1">
                Plus all related data: images, aliases, sources, host associations
              </li>
            </ul>
          </div>

          <div
            :if={not @impact.has_impact}
            class="bg-gray-50 border border-gray-200 rounded-lg p-4"
          >
            <p class="text-gray-700">
              This {@impact.taxonomy.type} has no dependent data and can be safely deleted.
            </p>
          </div>

          <%!-- Expandable Details --%>
          <details :if={@impact.genera_count > 0 or @impact.sections_count > 0} class="group">
            <summary class="cursor-pointer text-blue-600 hover:text-blue-800 font-medium">
              <.icon
                name="ph-caret-right"
                class="h-4 w-4 inline group-open:rotate-90 transition-transform"
              /> Show details
            </summary>
            <div class="mt-3 pl-4 text-sm space-y-3 border-l-2 border-gray-200">
              <div :if={@impact.genera_count > 0}>
                <p class="font-medium text-gray-700">Genera:</p>
                <ul class="list-disc list-inside text-gray-600 max-h-32 overflow-y-auto">
                  <li :for={genus <- @impact.genera}>{genus.name}</li>
                </ul>
              </div>
              <div :if={@impact.sections_count > 0}>
                <p class="font-medium text-gray-700">Sections:</p>
                <ul class="list-disc list-inside text-gray-600 max-h-32 overflow-y-auto">
                  <li :for={section <- @impact.sections}>{section.name}</li>
                </ul>
              </div>
            </div>
          </details>

          <%!-- Type to Confirm --%>
          <form id="cascade-delete-form" phx-submit="confirm_cascade_delete" class="mt-4">
            <label for="delete-confirmation" class="block text-sm text-gray-700 mb-1">
              Type <strong class="text-red-700">{@impact.taxonomy.name}</strong> to confirm:
            </label>
            <input
              type="text"
              id="delete-confirmation"
              name="confirmation"
              value={@confirmation_value}
              phx-keyup="update_delete_confirmation"
              autocomplete="off"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-red-500 focus:border-red-500"
              autofocus
            />
          </form>
        </div>
      </:body>
      <:footer>
        <button
          type="button"
          phx-click="cancel_cascade_delete"
          class="px-4 py-2 text-gray-600 hover:text-gray-800 font-medium"
        >
          Cancel
        </button>
        <button
          type="submit"
          form="cascade-delete-form"
          class="px-4 py-2 bg-red-600 text-white font-medium rounded hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed"
          disabled={@confirmation_value != @impact.taxonomy.name}
        >
          <.icon name="ph-trash" class="h-4 w-4 inline mr-1" /> Delete Forever
        </button>
      </:footer>
    </.modal>
    """
  end

  defp rename_collision_type_label("common"), do: "common name"
  defp rename_collision_type_label("scientific"), do: "scientific synonym"
  defp rename_collision_type_label(other), do: other

  defp rename_collision_species_path("gall", id), do: "/gall/#{id}"
  defp rename_collision_species_path(_taxoncode, id), do: "/host/#{id}"
end
