defmodule GallformersWeb.ActionComponents do
  @moduledoc """
  The design system's actions: `button`, `menu` and `segmented_switch`.

  See docs/design-system/components.md ("Actions and navigation").
  """
  use Phoenix.Component

  import GallformersWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  @variants ~w(primary secondary ghost danger link)
  # Retiring values from the old button, still passed by unmigrated templates.
  @retiring %{"soft" => "secondary", "warning" => "secondary"}

  @doc """
  One button, as a `<button>` or, with `navigate`, `patch` or `href`, a link.

  Variants: `primary` (maroon fill, one per region), `secondary` (the
  default), `ghost` (low emphasis, link color), `danger` (destructive; confirm
  through a dialog), `link` (a quiet text action in running content: "+ Add
  a host"; not for navigation). Height follows the density context; `size="sm"` is a
  compact button for dense rows.

  Labels say exactly what happens: "Approve 9 notes", "Add synonym".

  ## Examples

      <.button variant="primary" phx-click="approve">Approve 9 notes</.button>
      <.button icon="ph-plus" phx-click="add">Add synonym</.button>
      <.button navigate={~p"/gall/582"} icon="ph-arrow-square-out">View public page</.button>
      <.button icon="ph-x" label="Close" icon_only phx-click="close" />

  Retiring values (`variant` soft/warning, `size` lg, `shape` pill) still
  render, as secondary, default size and default shape.
  """
  attr :variant, :string,
    default: "secondary",
    values: @variants ++ Map.keys(@retiring)

  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :shape, :string, default: "rect", values: ~w(rect pill), doc: "retiring; ignored"
  attr :icon, :string, default: nil, doc: "a ph-* or gf-* icon name, shown before the label"
  attr :icon_only, :boolean, default: false, doc: "show only the icon; requires `label`"
  attr :label, :string, default: nil, doc: "accessible label (required with icon_only)"
  attr :class, :any, default: nil, doc: "layout only (margins, placement)"

  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type form phx-disable-with
         target rel replace)

  slot :inner_block

  def button(assigns) do
    variant = Map.get(@retiring, assigns.variant, assigns.variant)

    assigns =
      assign(assigns, :classes, [
        "gf-btn",
        "gf-btn-#{variant}",
        assigns.size == "sm" && "gf-btn-sm",
        assigns.icon_only && "gf-btn-icon",
        assigns.class
      ])

    if assigns.rest[:href] || assigns.rest[:navigate] || assigns.rest[:patch] do
      ~H"""
      <.link class={@classes} aria-label={@icon_only && @label} {@rest}>
        <.icon :if={@icon} name={@icon} />
        <span :if={!@icon_only}>{render_slot(@inner_block)}</span>
      </.link>
      """
    else
      assigns =
        assigns
        |> assign(:type, assigns.rest[:type] || "button")
        |> assign(:rest, Map.delete(assigns.rest, :type))

      ~H"""
      <button
        type={@type}
        class={@classes}
        aria-label={@icon_only && @label}
        {@rest}
      >
        <.icon :if={@icon} name={@icon} />
        <span :if={!@icon_only}>{render_slot(@inner_block)}</span>
      </button>
      """
    end
  end

  @doc """
  A button that opens a list of links or actions: the header's Browse and
  Resources, a row's actions. Closes on Escape and on a click outside.

  ## Examples

      <.menu id="browse-menu" label="Browse">
        <:item navigate={~p"/galls"}>Galls</:item>
        <:item navigate={~p"/hosts"}>Hosts</:item>
      </.menu>
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :align, :atom, default: :right, values: [:left, :right]
  attr :trigger_class, :any, default: nil, doc: "the trigger's look, set by the shell"
  attr :class, :any, default: nil

  slot :item, required: true do
    attr :navigate, :string
    attr :href, :string
  end

  def menu(assigns) do
    ~H"""
    <div class={["relative", @class]} id={@id} phx-window-keydown={hide_menu(@id)} phx-key="Escape">
      <button
        type="button"
        class={@trigger_class || "gf-btn gf-btn-ghost"}
        aria-haspopup="true"
        aria-expanded="false"
        aria-controls={"#{@id}-list"}
        phx-click={toggle_menu(@id)}
      >
        {@label} <.icon name="ph-caret-down" class="size-4" />
      </button>
      <div
        id={"#{@id}-list"}
        class={["gf-menu hidden mt-1", if(@align == :right, do: "right-0", else: "left-0")]}
        role="menu"
        phx-click-away={hide_menu(@id)}
      >
        <.link
          :for={item <- @item}
          navigate={item[:navigate]}
          href={item[:href]}
          role="menuitem"
        >
          {render_slot(item)}
        </.link>
      </div>
    </div>
    """
  end

  @doc """
  A few mutually exclusive choices as one joined row of buttons, the current
  one filled with the brand (`aria-pressed`): how a region shows its content
  (Photos | Table) or what a click does (Native | Introduced). Not for page
  tabs (`tab_nav`) or a form value.

  Each button sends `event` with `phx-value-<param>` set to its option's
  value (to `target`, a LiveComponent's `@myself`, when given). Values
  compare as strings, so atoms and strings mix. An option with an `icon`
  and no inner block is icon-only, named by its `label`.

  ## Examples

      <.segmented_switch label="View" value={@view} event="galls_view" param="view">
        <:option value={:photos}>Photos</:option>
        <:option value={:table}>Table</:option>
      </.segmented_switch>

      <.segmented_switch label="View" value={@mode} event="toggle_view" param="view" target={@myself}>
        <:option value={:grid} icon="ph-squares-four" label="Grid view" />
        <:option value={:table} icon="ph-list" label="Table view" />
      </.segmented_switch>
  """
  attr :label, :string, required: true, doc: "the group's accessible name"
  attr :value, :any, required: true, doc: "the current choice"
  attr :event, :string, required: true, doc: "sent on a click"
  attr :param, :string, default: "value", doc: "the phx-value-* key carrying the option's value"
  attr :target, :any, default: nil, doc: "a LiveComponent's @myself"
  attr :disabled, :boolean, default: false
  attr :size, :string, default: "md", values: ~w(sm md)
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  slot :option, required: true do
    attr :value, :any, required: true
    attr :id, :string, doc: "the button's id"
    attr :icon, :string, doc: "shown before the words; alone when the option has none"
    attr :label, :string, doc: "the accessible name and title of an icon-only option"
  end

  def segmented_switch(assigns) do
    assigns = assign(assigns, :current, to_string(assigns.value))

    ~H"""
    <span
      class={[
        "inline-flex self-start overflow-hidden rounded-ctl border border-line-strong",
        @class
      ]}
      role="group"
      aria-label={@label}
      {@rest}
    >
      <button
        :for={{option, i} <- Enum.with_index(@option)}
        id={option[:id]}
        type="button"
        phx-click={@event}
        phx-target={@target}
        disabled={@disabled}
        aria-pressed={to_string(to_string(option.value) == @current)}
        aria-label={option[:label]}
        title={option[:label]}
        {%{"phx-value-#{@param}" => option.value}}
        class={[
          "inline-flex items-center gap-1 font-semibold disabled:cursor-not-allowed",
          if(@size == "sm", do: "px-2 py-0.5 text-caption", else: "px-2.5 py-1 text-meta"),
          i > 0 && "border-l border-line-strong",
          cond do
            to_string(option.value) == @current -> "bg-brand-fill text-on-fill"
            @disabled -> "bg-surface-2 text-muted"
            true -> "bg-surface text-ink-2 hover:bg-surface-2"
          end
        ]}
      >
        <.icon :if={option[:icon]} name={option[:icon]} class="size-4" />
        {option.inner_block && render_slot(option)}
      </button>
    </span>
    """
  end

  defp toggle_menu(id) do
    JS.toggle(to: "##{id}-list")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{id} > button")
  end

  defp hide_menu(id) do
    JS.hide(to: "##{id}-list")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "##{id} > button")
  end
end
