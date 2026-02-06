defmodule GallformersWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework.
  Here are useful references:

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: GallformersWeb.Gettext

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :auto_dismiss, :integer, default: nil, doc: "auto-dismiss after this many milliseconds"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-hook={@auto_dismiss && "AutoDismiss"}
      data-dismiss-after={@auto_dismiss}
      data-flash-kind={@kind}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="gf-toast"
      {@rest}
    >
      <div class={[
        "gf-alert",
        @kind == :info && "gf-alert-info",
        @kind == :error && "gf-alert-error"
      ]}>
        <.icon :if={@kind == :info} name="ph-info" class="gf-alert-icon size-5 shrink-0" />
        <.icon :if={@kind == :error} name="ph-warning-circle" class="gf-alert-icon size-5 shrink-0" />
        <div class="flex-1 min-w-0">
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <button type="button" class="group shrink-0 cursor-pointer" aria-label={gettext("close")}>
          <.icon name="ph-x" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Variants

    * `primary` - Maroon background, white text
    * `secondary` - White background, gray text, gray border
    * `danger` - Red background, white text
    * `warning` - Yellow background, white text
    * `ghost` - Transparent background, maroon text
    * `soft` - Light maroon background, maroon text (default)

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button variant="danger">Delete</.button>
      <.button navigate={~p"/"}>Home</.button>
      <.button type="submit" variant="primary">Save</.button>
  """
  attr :rest, :global,
    include:
      ~w(href navigate patch method download name value disabled type form phx-disable-with)

  attr :class, :any, default: nil
  attr :variant, :string, default: "soft", values: ~w(primary secondary danger warning ghost soft)
  attr :size, :string, default: "md", values: ~w(sm md lg)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" => "gf-btn-primary",
      "secondary" => "gf-btn-secondary",
      "danger" => "gf-btn-danger",
      "warning" => "gf-btn-warning",
      "ghost" => "gf-btn-ghost",
      "soft" => "gf-btn-soft"
    }

    sizes = %{
      "sm" => "gf-btn-sm",
      "md" => nil,
      "lg" => "gf-btn-lg"
    }

    assigns =
      assigns
      |> assign(:variant_class, Map.fetch!(variants, assigns.variant))
      |> assign(:size_class, Map.fetch!(sizes, assigns.size))

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={["gf-btn", @variant_class, @size_class, @class]} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={["gf-btn", @variant_class, @size_class, @class]} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :schema, :atom,
    default: nil,
    doc: "optional schema module implementing SchemaFields behavior for auto-required detection"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :required, :boolean,
    default: nil,
    doc: "explicitly set required (overrides schema detection)"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    # Determine if field is required: explicit > schema detection > false
    is_required =
      case assigns[:required] do
        nil ->
          if assigns[:schema] do
            Gallformers.SchemaFields.required?(assigns.schema, field.field)
          else
            false
          end

        explicit ->
          explicit
      end

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign(:required, is_required)
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset">
      <label>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label text-base font-medium text-gray-700">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "gf-checkbox"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset">
      <label>
        <span :if={@label} class="label mb-2 text-base font-medium text-gray-700">
          {@label}<span :if={@required} class="text-red-600 ml-0.5">*</span>
        </span>
        <select
          id={@id}
          name={@name}
          class={[@class || "gf-select", @errors != [] && (@error_class || "gf-select-error")]}
          multiple={@multiple}
          required={@required}
          aria-required={@required && "true"}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset">
      <label>
        <span :if={@label} class="label mb-2 text-base font-medium text-gray-700">
          {@label}<span :if={@required} class="text-red-600 ml-0.5">*</span>
        </span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "gf-textarea",
            @errors != [] && (@error_class || "gf-textarea-error")
          ]}
          required={@required}
          aria-required={@required && "true"}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset">
      <label>
        <span :if={@label} class="label mb-2 text-base font-medium text-gray-700">
          {@label}<span :if={@required} class="text-red-600 ml-0.5">*</span>
        </span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "gf-input",
            @errors != [] && (@error_class || "gf-input-error")
          ]}
          required={@required}
          aria-required={@required && "true"}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="ph-warning-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-gray-500">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>

      <.table id="users" rows={@users} variant="compact">
        <:col :let={user} label="id">{user.id}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :variant, :string,
    default: "default",
    values: ~w(default compact dense),
    doc: "table density variant"

  attr :zebra, :boolean, default: true, doc: "whether to show zebra striping"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class={[
      "gf-table",
      @variant == "compact" && "gf-table-compact",
      @variant == "dense" && "gf-table-dense",
      @zebra && "gf-table-zebra"
    ]}>
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <span :for={action <- @action}>
                {render_slot(action, @row_item.(row))}
              </span>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="gf-list">
      <li :for={item <- @item} class="gf-list-row">
        <div class="gf-list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders an icon from the Gallformers icon library.

  Two icon sources are available:
  - `gf-*` prefix: Custom gallformers domain icons (gall, host, taxon, source, place)
  - `ph-*` prefix: Phosphor icons (MIT licensed)

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are bundled within your compiled app.css by the plugin
  in `assets/vendor/icons.js`.

  ## Examples

      <.icon name="ph-x" />
      <.icon name="ph-arrows-clockwise" class="ml-1 size-3 motion-safe:animate-spin" />
      <.icon name="gf-gall" class="size-6 text-gf-maroon" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "gf-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  def icon(%{name: "ph-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a data complete/in progress badge.

  Used on species (gall/host) and source pages to indicate data completeness.

  ## Examples

      <.data_complete_badge
        complete={true}
        complete_tooltip="All data has been entered."
        incomplete_tooltip="Data entry is still in progress."
      />
  """
  attr :complete, :boolean, required: true, doc: "whether the data is complete"
  attr :complete_tooltip, :string, required: true, doc: "tooltip when complete"
  attr :incomplete_tooltip, :string, required: true, doc: "tooltip when incomplete"

  def data_complete_badge(assigns) do
    ~H"""
    <span
      class={[
        "gf-badge cursor-help",
        if(@complete, do: "gf-badge-success", else: "gf-badge-warning")
      ]}
      title={if @complete, do: @complete_tooltip, else: @incomplete_tooltip}
    >
      {if @complete, do: "Complete", else: "In Progress"}
    </span>
    """
  end

  @doc """
  Status badge component.

  ## Examples

      <.badge variant="success">Complete</.badge>
      <.badge variant="warning">Pending</.badge>
      <.badge>Default info badge</.badge>
  """
  attr :variant, :string, default: "info", values: ~w(success warning info)
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={"gf-badge gf-badge-#{@variant}"}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Removable chip/tag component.

  ## Examples

      <.chip>Tag</.chip>
      <.chip size="sm" on_remove={JS.push("remove", value: %{id: 1})}>Removable</.chip>
  """
  attr :size, :string, default: "md", values: ~w(sm md)
  attr :on_remove, JS, default: nil
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <span class={["gf-chip", @size == "sm" && "gf-chip-sm"]}>
      {render_slot(@inner_block)}
      <button :if={@on_remove} type="button" class="gf-chip-remove" phx-click={@on_remove}>
        <.icon name="ph-x" class="h-3 w-3" />
      </button>
    </span>
    """
  end

  @doc """
  Renders a generic modal dialog.

  ## Examples

      <.modal id="confirm-delete" on_cancel={JS.exec("data-cancel", to: "#confirm-delete")}>
        <:header>Confirm Delete</:header>
        <:body>Are you sure you want to delete this item?</:body>
        <:footer>
          <.button phx-click={hide_modal("confirm-delete")}>Cancel</.button>
          <.button variant="primary" phx-click="delete">Delete</.button>
        </:footer>
      </.modal>

  ## Showing the modal

  Use the `show_modal/1` JS command to show the modal:

      <.button phx-click={show_modal("confirm-delete")}>Delete</.button>

  ## Hiding the modal

  Use the `hide_modal/1` JS command to hide the modal. The modal also closes
  when clicking the backdrop or pressing Escape.

  ## Focus management

  The modal traps focus inside when open. When opened, focus moves to the first
  focusable element inside the modal (or the close button if no header).
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}, doc: "JS command to run when the modal is cancelled"
  attr :class, :any, default: nil, doc: "additional CSS classes for the modal container"

  slot :header, doc: "optional header content displayed at the top of the modal"
  slot :body, required: true, doc: "the main content of the modal"
  slot :footer, doc: "optional footer content, typically for action buttons"

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="gf-modal-backdrop hidden"
    >
      <div
        id={"#{@id}-bg"}
        class="fixed inset-0 z-[60] bg-black/50 transition-opacity"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 z-[60] overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center p-4">
          <.focus_wrap
            id={"#{@id}-container"}
            phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
            phx-key="escape"
            phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
            class={["gf-modal shadow-xl transition", @class]}
          >
            <div :if={@header != []} class="gf-modal-header">
              <h3 id={"#{@id}-title"} class="text-xl font-semibold text-gray-900">
                {render_slot(@header)}
              </h3>
              <button
                type="button"
                phx-click={JS.exec("data-cancel", to: "##{@id}")}
                class="text-gray-400 hover:text-gray-600 cursor-pointer"
                aria-label={gettext("close")}
              >
                <.icon name="ph-x" class="size-6" />
              </button>
            </div>
            <div :if={@header == []} class="absolute right-4 top-4">
              <button
                type="button"
                phx-click={JS.exec("data-cancel", to: "##{@id}")}
                class="text-gray-400 hover:text-gray-600 cursor-pointer"
                aria-label={gettext("close")}
              >
                <.icon name="ph-x" class="size-6" />
              </button>
            </div>
            <div id={"#{@id}-description"} class="gf-modal-body">
              {render_slot(@body)}
            </div>
            <div :if={@footer != []} class="gf-modal-footer">
              {render_slot(@footer)}
            </div>
          </.focus_wrap>
        </div>
      </div>
    </div>
    """
  end

  ## JS Commands

  @doc """
  Shows the modal with the given id.

  ## Example

      <.button phx-click={show_modal("my-modal")}>Open</.button>
  """
  def show_modal(id) when is_binary(id) do
    %JS{}
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-opacity ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-container",
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-container")
  end

  @doc """
  Hides the modal with the given id.

  ## Example

      <.button phx-click={hide_modal("my-modal")}>Close</.button>
  """
  def hide_modal(id) when is_binary(id) do
    %JS{}
    |> JS.hide(
      to: "##{id}-bg",
      time: 200,
      transition: {"transition-opacity ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-container",
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
    |> JS.hide(to: "##{id}", time: 200, transition: {"", "", ""})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Displays record metadata (created/updated timestamps) at the bottom of detail pages.

  ## Examples

      <.record_metadata inserted_at={@record.inserted_at} updated_at={@record.updated_at} />
  """
  attr :inserted_at, :any, default: nil, doc: "Creation timestamp (NaiveDateTime)"
  attr :updated_at, :any, default: nil, doc: "Last update timestamp (NaiveDateTime)"
  attr :class, :string, default: nil, doc: "Additional CSS classes"

  def record_metadata(assigns) do
    ~H"""
    <div
      :if={@inserted_at || @updated_at}
      class={[
        "mt-8 pt-4 border-t border-gray-200 text-sm text-gray-600",
        @class
      ]}
    >
      <span :if={@inserted_at}>
        Created {format_timestamp(@inserted_at)}
      </span>
      <span :if={@inserted_at && @updated_at} class="mx-2">•</span>
      <span :if={@updated_at}>
        Last updated {format_timestamp(@updated_at)}
      </span>
    </div>
    """
  end

  # Formats a DateTime or NaiveDateTime as "Feb 1, 2026 3:45 PM UTC"
  defp format_timestamp(nil), do: ""

  defp format_timestamp(%DateTime{} = dt) do
    # Shift to UTC if not already
    dt_utc = DateTime.shift_zone!(dt, "Etc/UTC")
    Calendar.strftime(dt_utc, "%b %-d, %Y %-I:%M %p UTC")
  end

  defp format_timestamp(%NaiveDateTime{} = dt) do
    # NaiveDateTime has no timezone, assume UTC
    Calendar.strftime(dt, "%b %-d, %Y %-I:%M %p UTC")
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(GallformersWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(GallformersWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
