defmodule GallformersWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as forms, inputs,
  icons and the legacy modal. The components consist mostly of markup and are well-documented
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
  import Phoenix.Component, except: [form: 1]
  use Gettext, backend: GallformersWeb.Gettext

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @doc """
  Wraps Phoenix's `<.form>` to prevent Enter key from submitting.

  Pressing Enter in text inputs, selects, or other non-button elements will not
  submit the form. Users must click the submit button explicitly. This prevents
  accidental saves, especially in forms with typeaheads where Enter confirms a
  selection.

  Accepts all the same attributes as `Phoenix.Component.form/1`.
  """
  attr :for, :any, required: true, doc: "the data structure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true

  def form(assigns) do
    ~H"""
    <Phoenix.Component.form
      for={@for}
      as={@as}
      onkeydown="if(event.key === 'Enter' && !['BUTTON','TEXTAREA'].includes(event.target.tagName)) event.preventDefault()"
      {@rest}
    >
      {render_slot(@inner_block)}
    </Phoenix.Component.form>
    """
  end

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

  # button/1 moved to GallformersWeb.ActionComponents (docs/design-system/components.md).

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
        <span class="inline-flex items-center gap-2 text-ui text-ink">
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
        <span :if={@label} class="gf-label">
          {@label}<span :if={@required} class="ml-0.5 text-danger">*</span>
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
        <span :if={@label} class="gf-label">
          {@label}<span :if={@required} class="ml-0.5 text-danger">*</span>
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
        <span :if={@label} class="gf-label">
          {@label}<span :if={@required} class="ml-0.5 text-danger">*</span>
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
    <p class="mt-1 flex items-center gap-1.5 text-meta text-danger">
      <.icon name="ph-warning-circle" class="size-4" />
      {render_slot(@inner_block)}
    </p>
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
      <.icon name="gf-gall" class="size-6 text-brand" />
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

  # chip/1 moved to GallformersWeb.DataComponents (docs/design-system/components.md).

  ## JS Commands

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
        "mt-8 border-t border-line pt-4 text-meta text-muted",
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
