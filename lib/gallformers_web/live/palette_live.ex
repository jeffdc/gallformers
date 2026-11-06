defmodule GallformersWeb.PaletteLive do
  @moduledoc """
  The command palette (design system, matters bc0d and ec2c): one sticky
  LiveView in the root layout, on every page, public and admin.

  Closed until opened: the header's trigger, or `/` or `s` while not typing
  in a field (`assets/js/search_shortcut.js`), dispatch `gf:open-palette`,
  which the `Palette` hook sends here as `open`. Open: a search field and
  the groups of `GallformersWeb.Palette`; ↑ ↓ move the selection, Enter
  follows it (the hook clicks the selected row), Esc or a click outside
  closes. Following a row closes the palette.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Accounts
  alias GallformersWeb.Palette

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(admin?: Accounts.admin?(session["current_user"]), open: false)
      |> reset()

    {:ok, socket, layout: false}
  end

  defp reset(socket),
    do:
      assign(socket,
        query: "",
        groups: Palette.groups("", admin?: socket.assigns.admin?),
        active: 0
      )

  @impl true
  def handle_event("open", _params, socket),
    do: {:noreply, socket |> reset() |> assign(open: true)}

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, open: false)}

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply,
     assign(socket, query: q, groups: Palette.groups(q, admin?: socket.assigns.admin?), active: 0)}
  end

  def handle_event("key", %{"key" => "ArrowDown"}, socket),
    do: {:noreply, update(socket, :active, &min(&1 + 1, last(socket.assigns.groups)))}

  def handle_event("key", %{"key" => "ArrowUp"}, socket),
    do: {:noreply, update(socket, :active, &max(&1 - 1, 0))}

  def handle_event("key", %{"key" => "Escape"}, socket),
    do: {:noreply, assign(socket, open: false)}

  def handle_event("key", _params, socket), do: {:noreply, socket}

  defp last(groups), do: max(Enum.sum(Enum.map(groups, &length(&1.rows))) - 1, 0)

  @impl true
  def render(assigns) do
    ~H"""
    <div id="palette" phx-hook="Palette">
      <div :if={@open} class="gf-palette-overlay" phx-window-keydown="key">
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Search Gallformers"
          class="gf-palette"
          phx-click-away="close"
        >
          <form
            id="palette-form"
            phx-change="search"
            phx-submit="search"
            class="flex items-center gap-3 border-b border-line px-4"
          >
            <.icon name="ph-magnifying-glass" class="size-5 shrink-0 text-muted" />
            <input
              id="palette-q"
              name="q"
              value={@query}
              type="text"
              autocomplete="off"
              phx-debounce="150"
              phx-mounted={JS.focus()}
              placeholder="Search galls, plants, places, Sources…"
              aria-controls="palette-results"
              aria-activedescendant={"palette-row-#{@active}"}
              class="h-14 min-w-0 flex-1 border-0 bg-transparent text-body text-ink outline-none placeholder:text-muted"
            />
            <button
              type="button"
              phx-click="close"
              class="rounded-ctl border border-line px-1.5 text-caption text-muted"
            >
              Esc
            </button>
          </form>
          <div
            id="palette-results"
            role="listbox"
            aria-label="Results"
            class="flex-1 overflow-y-auto py-2"
          >
            <div :for={group <- @groups} class="flex flex-col">
              <span
                :if={group.title}
                class="px-4 pb-1 pt-2 text-caption font-semibold uppercase tracking-wide text-muted"
              >
                {group.title}
              </span>
              <.link
                :for={row <- group.rows}
                id={"palette-row-#{row.index}"}
                href={row.href}
                role="option"
                aria-selected={to_string(row.index == @active)}
                phx-click="close"
                class={[
                  "mx-2 flex items-center gap-3 rounded-ctl px-2 py-1.5 text-ui text-ink hover:no-underline",
                  if(row.index == @active, do: "bg-sky-soft", else: "hover:bg-surface-2")
                ]}
              >
                <.icon name={row.icon} class="size-4 shrink-0 text-muted" />
                <span class="min-w-0 truncate">
                  {row.prefix}<.taxon_name :if={row.name} name={row.label} /><span :if={!row.name}>{row.label}</span>{row.suffix}
                </span>
                <span :if={row.detail} class="min-w-0 flex-1 truncate text-meta text-muted">
                  {row.detail}
                </span>
                <.icon
                  :if={row.index == @active}
                  name="ph-arrow-right"
                  class="ml-auto size-4 shrink-0 text-muted"
                />
              </.link>
            </div>
          </div>
          <div class="flex items-center gap-4 border-t border-line px-4 py-2 text-caption text-muted max-sm:hidden">
            <span><kbd class="gf-kbd">↑</kbd> <kbd class="gf-kbd">↓</kbd> move</span>
            <span><kbd class="gf-kbd">Enter</kbd> open</span>
            <span><kbd class="gf-kbd">Esc</kbd> close</span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
