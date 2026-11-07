defmodule GallformersWeb.FeedbackComponents do
  @moduledoc """
  The design system's feedback and overlays: `notice`, `progress_bar`,
  `dialog`.

  A `notice` is a message inline in the page; a `dialog` is the one modal,
  opened with `show_dialog/2` and closed with `hide_dialog/2`. See
  docs/design-system/components.md ("Feedback", "Overlays") and patterns.md
  ("Confirmation", "Errors").
  """
  use Phoenix.Component

  import GallformersWeb.ActionComponents, only: [button: 1]
  import GallformersWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  @notice_icons %{
    info: "ph-info",
    ok: "ph-check-circle",
    warn: "ph-warning",
    danger: "ph-warning-circle"
  }

  @doc """
  An inline message in the page, one line where possible.

  Kinds: `:info` (a neutral notice, the default), `:ok` (done, saved),
  `:warn` (needs a look), `:danger` (an error). A `:danger` notice is
  announced at once (`role="alert"`); the others politely (`role="status"`).

  Page errors are a `:danger` notice at the top of the main column; field
  errors go under the field, not here. Say what went wrong and how to fix
  it, with no apology.

  ## Examples

      <.notice>Where the Hosts grow, not where the Gall was found.</.notice>

      <.notice kind={:danger} title="Not saved">
        That name is already a synonym of <em>Quercus rubra</em>. Search for it instead.
      </.notice>

      <.notice kind={:warn}>
        Leaving this open holds approval of the Source's Gall statements.
        <:action><.button size="sm" navigate={~p"/admin/review"}>Review</.button></:action>
      </.notice>

      <.notice id="saved-notice" kind={:ok} on_dismiss={JS.hide(to: "#saved-notice")}>
        Approved 9 notes
      </.notice>
  """
  attr :kind, :atom, default: :info, values: [:info, :ok, :warn, :danger]
  attr :title, :string, default: nil, doc: "a bold first line, in the kind's color"

  attr :icon, :string,
    default: nil,
    doc: "a ph-* or gf-* icon in place of the kind's own"

  attr :on_dismiss, JS, default: nil, doc: "shows a Dismiss button that runs this command"
  attr :id, :string, default: nil
  attr :class, :any, default: nil, doc: "layout only"
  attr :rest, :global

  slot :inner_block, required: true, doc: "the message"
  slot :action, doc: "an action at the right: a button or a link"

  def notice(assigns) do
    assigns = assign(assigns, :icon_name, assigns.icon || Map.fetch!(@notice_icons, assigns.kind))

    ~H"""
    <div
      id={@id}
      role={if @kind == :danger, do: "alert", else: "status"}
      data-kind={@kind}
      class={[
        "flex items-start gap-2 rounded-panel px-3 py-2 text-ui",
        notice_kind(@kind),
        @class
      ]}
      {@rest}
    >
      <span aria-hidden="true" class="flex shrink-0 pt-0.5">
        <.icon name={@icon_name} class="size-4" />
      </span>
      <div class="min-w-0 flex-1">
        <p :if={@title} data-part="title" class="font-semibold">{@title}</p>
        <div data-part="message" class="text-ink-2">{render_slot(@inner_block)}</div>
      </div>
      <div :if={@action != []} data-part="action" class="flex shrink-0 items-center gap-2">
        {render_slot(@action)}
      </div>
      <.button
        :if={@on_dismiss}
        variant="ghost"
        size="sm"
        icon="ph-x"
        icon_only
        label="Dismiss"
        class="-my-0.5 shrink-0"
        phx-click={@on_dismiss}
      />
    </div>
    """
  end

  defp notice_kind(:info), do: "bg-info-bg text-info"
  defp notice_kind(:ok), do: "bg-ok-bg text-ok"
  defp notice_kind(:warn), do: "bg-warn-bg text-warn"
  defp notice_kind(:danger), do: "bg-danger-bg text-danger"

  @doc """
  The one modal: a title, a body and a row of actions, over a backdrop.

  Open it with `show_dialog/2` (or render it with `show`), close it with
  `hide_dialog/2`. Escape, a click on the backdrop and the Close button
  cancel it: they run `on_cancel`, then hide it. While it is open, focus
  stays inside it and the page behind does not scroll. Opening moves focus
  to the first control in the body, or to the Close button when the body
  has none; closing returns focus to whatever opened it.

  Sizes: `:sm` (a confirmation), `:md` (the default: a short form), `:lg`
  (a wide form or table), `:full` (nearly the whole viewport: the large
  range map). In a `:full` dialog the body fills the height left under
  the title, so a map inside can take `h-full`.

  ## Examples

      <.button phx-click={show_dialog("add-synonym")}>Add synonym</.button>

      <.dialog id="add-synonym" title="Add synonym">
        <.form for={@form} id="add-synonym-form" phx-submit="add_synonym">…</.form>
        <:actions>
          <.button phx-click={hide_dialog("add-synonym")}>Cancel</.button>
          <.button variant="primary" type="submit" form="add-synonym-form">Add synonym</.button>
        </:actions>
      </.dialog>

  A dialog the server opens and closes renders under `:if` with `show`, and
  tells the server when it is cancelled:

      <.dialog :if={@editing} id="rename" title="Rename taxon" show on_cancel={JS.push("cancel_rename")}>
        …
      </.dialog>

  ## Confirming a destructive action

  Ask only before something destructive or hard to undo. The title names
  the thing, the body says the consequence, and the confirm button repeats
  the verb (never "OK" or "Yes") as a `danger` button:

      <.button variant="danger" icon="ph-trash" phx-click={show_dialog("delete-taxon")}>
        Delete taxon
      </.button>

      <.dialog id="delete-taxon" size={:sm} title="Delete the taxon Acanthaceae?">
        Its 3 synonyms are deleted with it. This can't be undone.
        <:actions>
          <.button phx-click={hide_dialog("delete-taxon")}>Cancel</.button>
          <.button variant="danger" phx-click={JS.push("delete_taxon") |> hide_dialog("delete-taxon")}>
            Delete taxon
          </.button>
        </:actions>
      </.dialog>

  When a mistake would be costly, ask for the name to be typed: put the
  input in a form in the body, and make the confirm button that form's
  submit button (`type="submit" form="…"`), disabled until the typed name
  matches. Leaving with unsaved changes confirms the same way: "Discard
  your changes to Acanthaceae?", with "Keep editing" and a `danger`
  "Discard changes".
  """
  attr :id, :string, required: true
  attr :title, :string, required: true, doc: "the heading; it also labels the dialog"
  attr :size, :atom, default: :md, values: [:sm, :md, :lg, :full]
  attr :show, :boolean, default: false, doc: "open when mounted"
  attr :on_cancel, JS, default: %JS{}, doc: "runs on Escape, a backdrop click or Close"
  attr :class, :any, default: nil, doc: "layout only, on the panel"
  attr :rest, :global

  slot :inner_block, required: true, doc: "the body"
  slot :actions, doc: "the buttons at the foot, right-aligned; the confirming one last"

  def dialog(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_dialog(@id)}
      phx-remove={hide_dialog(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-60 hidden"
      {@rest}
    >
      <div id={"#{@id}-backdrop"} class="fixed inset-0 bg-overlay" aria-hidden="true" />
      <div class="fixed inset-0 overflow-y-auto">
        <div class={[
          "flex justify-center p-4",
          if(@size == :full, do: "h-full", else: "min-h-full items-center")
        ]}>
          <.focus_wrap
            id={"#{@id}-panel"}
            role="dialog"
            aria-modal="true"
            aria-labelledby={"#{@id}-title"}
            aria-describedby={"#{@id}-body"}
            data-size={@size}
            phx-window-keydown={JS.exec("data-cancel", to: "##{@id}[data-open]")}
            phx-key="Escape"
            phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
            class={[
              "w-full rounded-panel bg-surface shadow-float",
              dialog_size(@size),
              @class
            ]}
          >
            <div class={["flex flex-col gap-block p-panel", @size == :full && "h-full"]}>
              <div data-part="header" class="flex items-start gap-2">
                <h2 id={"#{@id}-title"} class="font-brand text-subsection text-ink">{@title}</h2>
                <.button
                  variant="ghost"
                  size="sm"
                  icon="ph-x"
                  icon_only
                  label="Close"
                  class="-mr-1 ml-auto shrink-0"
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                />
              </div>
              <div
                id={"#{@id}-body"}
                data-part="body"
                class={["text-body text-ink", @size == :full && "min-h-0 flex-1"]}
              >
                {render_slot(@inner_block)}
              </div>
              <div :if={@actions != []} data-part="actions" class="flex flex-wrap justify-end gap-2">
                {render_slot(@actions)}
              </div>
            </div>
          </.focus_wrap>
        </div>
      </div>
    </div>
    """
  end

  defp dialog_size(:sm), do: "max-w-md"
  defp dialog_size(:md), do: "max-w-2xl"
  defp dialog_size(:lg), do: "max-w-5xl"
  defp dialog_size(:full), do: "h-full"

  @doc """
  Opens the dialog with the given id: shows it, locks the page's scrolling
  and moves focus into it, remembering what had focus.

  ## Examples

      <.button phx-click={show_dialog("delete-taxon")}>Delete taxon</.button>
      <.button phx-click={JS.push("load_map") |> show_dialog("range-map")}>Open map</.button>
  """
  def show_dialog(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.push_focus()
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-backdrop",
      time: 150,
      transition: {"transition-opacity ease-out duration-150", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-panel",
      time: 150,
      transition:
        {"transition ease-out duration-150", "opacity-0 translate-y-2 scale-95",
         "opacity-100 translate-y-0 scale-100"}
    )
    |> JS.set_attribute({"data-open", "true"}, to: "##{id}")
    |> JS.add_class("overflow-hidden", to: "body")
    # The first control in the body if there is one (the later focus wins),
    # else the first in the panel: the Close button.
    |> JS.focus_first(to: "##{id}-panel")
    |> JS.focus_first(to: "##{id}-body")
  end

  @doc """
  Closes the dialog with the given id: hides it, unlocks the page's
  scrolling and returns focus to what opened it. Doesn't run `on_cancel`.

  ## Examples

      <.button phx-click={hide_dialog("delete-taxon")}>Cancel</.button>
      <.button variant="danger" phx-click={JS.push("delete_taxon") |> hide_dialog("delete-taxon")}>
        Delete taxon
      </.button>
  """
  def hide_dialog(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.hide(
      to: "##{id}-backdrop",
      time: 150,
      transition: {"transition-opacity ease-in duration-150", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-panel",
      time: 150,
      transition:
        {"transition ease-in duration-150", "opacity-100 translate-y-0 scale-100",
         "opacity-0 translate-y-2 scale-95"}
    )
    |> JS.hide(to: "##{id}", time: 150, transition: {"", "", ""})
    |> JS.remove_attribute("data-open", to: "##{id}")
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  How far something has got: a sync, an upload, a review. A thin track
  filled from the left, drawn as SVG so the width needs no inline style.

  With a `label` the bar is a `progressbar` (`aria-valuenow`, `aria-valuemax`);
  without one it is decorative (`aria-hidden`): the words beside it say the
  numbers. `segments` (`{value, tone}` pairs, in place of `value`) are drawn
  one after another, e.g. decided then proposed. Values are clamped to `max`;
  a zero `max` draws an empty bar.

  The upload hooks draw the same markup from JavaScript (`.gf-progress`, a
  `rect[data-bar]` whose width they set).

  ## Examples

      <.progress_bar value={@done} max={@total} label="Hosts synced" />
      <.progress_bar max={@total} segments={[{@done, :ok}, {@proposed, :info}]} size="sm" />
  """
  attr :id, :string, default: nil
  attr :value, :integer, default: 0
  attr :max, :integer, required: true
  attr :label, :string, default: nil, doc: "the accessible name; nil makes the bar decorative"
  attr :tone, :atom, default: :brand, values: [:brand, :ok, :info, :warn]

  attr :segments, :list,
    default: nil,
    doc: "`{value, tone}` pairs drawn one after another, in place of `value` and `tone`"

  attr :size, :string, default: "md", values: ~w(sm md)
  attr :class, :any, default: nil, doc: "layout only (width, margins)"

  def progress_bar(assigns) do
    assigns = assign(assigns, :rects, progress_rects(assigns))

    ~H"""
    <div
      id={@id}
      class={["gf-progress", @size == "sm" && "gf-progress-sm", @class]}
      role={@label && "progressbar"}
      aria-label={@label}
      aria-valuemin={@label && 0}
      aria-valuemax={@label && @max}
      aria-valuenow={@label && @value}
      aria-hidden={!@label && "true"}
    >
      <svg width="100%" height="100%" preserveAspectRatio="none" aria-hidden="true">
        <rect
          :for={{x, width, tone} <- @rects}
          data-bar
          data-tone={tone}
          x={x}
          width={width}
          height="100%"
        />
      </svg>
    </div>
    """
  end

  defp progress_rects(%{segments: segments, max: max}) when is_list(segments),
    do: rects(segments, max)

  defp progress_rects(%{value: value, tone: tone, max: max}), do: rects([{value, tone}], max)

  # Each segment's start and width as percentages, never past the end.
  defp rects(segments, max) do
    {rects, _end} =
      Enum.map_reduce(segments, 0.0, fn {value, tone}, start ->
        width = if max > 0, do: min(100 * value / max, 100 - start), else: 0.0
        width = Float.round(max(width, 0.0), 1)
        {{pct(start), pct(width), tone}, start + width}
      end)

    rects
  end

  defp pct(n), do: "#{Float.round(n * 1.0, 1)}%"
end
