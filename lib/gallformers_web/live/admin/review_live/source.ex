defmodule GallformersWeb.Admin.ReviewLive.Source do
  @moduledoc """
  The Gallformers notes, `/admin/review/notes` (`6611` Task 7, screen 4
  of the design): the Gallformers Source's notes under review, built for
  scanning
  (`GallformersWeb.Admin.ReviewLive.Loader.notes_page/1`), in three tabs
  kept in the URL (`tab`: `ready` — the default; `needs`; `approved`):

    * **Ready, nothing to decide:** notes awaiting review that nothing
      holds, one line each with chips of what they add and a muted one for
      what they set aside, ticked by default. "Approve N ticked notes" (or
      a group's "Approve N ticked here") approves the ticked ones, each on
      its own (`Gallformers.Import.approve_packages/2`).
    * **Needs you:** notes held by an open item, each with those items in
      the rows of a Source page, decided in place; a note nothing holds any
      more moves to Ready.
    * **Approved:** the approved notes.

  Each tab groups its notes by what the note holds
  (`GallformersWeb.Admin.ReviewLive.Notes`). One note's own page is its
  package's review (`GallformersWeb.Admin.ReviewLive.Review`).
  """
  use GallformersWeb, :live_view

  import GallformersWeb.ReviewComponents

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias GallformersWeb.Admin.ReviewLive.ItemRow
  alias GallformersWeb.Admin.ReviewLive.Loader
  alias GallformersWeb.Admin.ReviewLive.Notes

  @tabs ~w(ready needs approved)

  @impl true
  def mount(_params, _session, socket) do
    source =
      Gallformers.Sources.get_gallformers_source() ||
        raise Ecto.NoResultsError, queryable: Gallformers.Sources.Source

    {:ok,
     socket
     |> assign(source_id: source.id, closed: MapSet.new(), tab: "ready", unticked: MapSet.new())
     |> load()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "ready"
    {:noreply, assign(socket, tab: tab)}
  end

  # -- events ------------------------------------------------------------------

  @impl true
  def handle_event("toggle_section", %{"section" => section}, socket) do
    closed = socket.assigns.closed

    closed =
      if MapSet.member?(closed, section),
        do: MapSet.delete(closed, section),
        else: MapSet.put(closed, section)

    {:noreply, assign(socket, closed: closed)}
  end

  def handle_event("tab", %{"tab" => tab}, socket) when tab in @tabs do
    path =
      if tab == "ready",
        do: ~p"/admin/review/notes",
        else: ~p"/admin/review/notes?#{[tab: tab]}"

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("tick", %{"id" => id}, socket) do
    id = String.to_integer(id)
    unticked = socket.assigns.unticked

    unticked =
      if MapSet.member?(unticked, id),
        do: MapSet.delete(unticked, id),
        else: MapSet.put(unticked, id)

    {:noreply, assign(socket, unticked: unticked)}
  end

  def handle_event("approve_notes", params, socket) do
    notes =
      socket.assigns
      |> ticked()
      |> Enum.filter(&(params["group"] in [nil, Atom.to_string(&1.group)]))

    %{approved: approved, refused: refused} =
      Import.approve_packages(socket.assigns.actor, Enum.map(notes, & &1.package))

    socket =
      cond do
        notes == [] ->
          put_flash(socket, :error, "No note is ticked.")

        refused == [] ->
          put_flash(socket, :info, approved_text(length(approved)))

        true ->
          socket
          |> put_flash(:info, approved_text(length(approved)))
          |> put_flash(:error, refused_text(refused))
      end

    {:noreply, load(socket)}
  end

  @impl true
  def handle_info({ItemRow, {:decided, _item}}, socket),
    do: {:noreply, socket |> put_flash(:info, "Decision recorded.") |> load()}

  def handle_info({ItemRow, {:undone, _item}}, socket),
    do: {:noreply, socket |> put_flash(:info, "Decision undone.") |> load()}

  def handle_info({ItemRow, {:proposal, _item}}, socket), do: {:noreply, load(socket)}

  # The Ready notes left ticked.
  defp ticked(%{notes: notes, unticked: unticked}),
    do: Enum.filter(notes, &(&1.state == :ready and not MapSet.member?(unticked, &1.id)))

  defp approved_text(0), do: "No note was approved."

  defp approved_text(n),
    do: "Approved #{n} #{notes_word(n)}; their statements are applied by the import worker."

  defp refused_text(refused) do
    why =
      refused
      |> Enum.map(fn {_package, reason} -> refusal(reason) end)
      |> Enum.uniq()
      |> Enum.join("; ")

    "#{length(refused)} could not be approved: #{why}."
  end

  defp refusal({:open_items, _items}), do: "questions that hold it are still open"
  defp refusal({:blocked, _batches}), do: "Host names are still unsettled"
  defp refusal(:not_approvable), do: "it is no longer awaiting review"
  defp refusal(reason), do: inspect(reason)

  defp notes_word(1), do: "note"
  defp notes_word(_n), do: "notes"

  defp load(socket) do
    data = Loader.notes_page(socket.assigns.source_id)

    assign(socket,
      page_title: data.summary.title,
      source: data.source,
      summary: data.summary,
      notes: data.notes,
      note_stats: data.stats,
      definitions: Catalog.trait_definitions()
    )
  end

  # -- rendering -------------------------------------------------------------------

  @tab_states %{"ready" => :ready, "needs" => :needs, "approved" => :approved}

  @impl true
  def render(assigns) do
    state = Map.fetch!(@tab_states, assigns.tab)
    shown = Enum.filter(assigns.notes, &(&1.state == state))
    ticked = assigns |> ticked() |> MapSet.new(& &1.id)

    groups =
      for group <- Notes.groups(),
          rows = Enum.filter(shown, &(&1.group == group.id)),
          rows != [] do
        %{group: group, rows: rows, ticked: Enum.count(rows, &MapSet.member?(ticked, &1.id))}
      end

    assigns = assign(assigns, groups: groups, ticked: ticked)

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <.page_header>
        <:crumb navigate={~p"/admin/review"}>Sources to review</:crumb>
        <:title>{@summary.title}</:title>
      </.page_header>

      <.panel id="source-head" class="mt-2 gap-3">
        <div class="flex flex-wrap items-start gap-3">
          <div class="flex-1 min-w-72">
            <p :if={@summary.citation} class="text-meta text-muted">{@summary.citation}</p>
            <div class="mt-1.5 flex flex-wrap gap-1.5">
              <.review_tag>Gallformers' own notes</.review_tag>
            </div>
            <.review_source_link source_id={@source_id} class="mt-1.5" />
          </div>
          <div class="flex flex-col items-start md:items-end gap-1">
            <.button
              id="approve-notes"
              phx-click="approve_notes"
              variant="primary"
              disabled={MapSet.size(@ticked) == 0}
            >
              {ticked_text(MapSet.size(@ticked), "notes")}
            </.button>
            <p class="text-caption text-muted md:text-right max-w-xs">
              Approves the ticked notes in the Ready list. Each note is approved on its own.
            </p>
          </div>
        </div>

        <div id="source-stats" class="flex flex-wrap gap-2">
          <.review_stat value={@note_stats.notes} label="notes" />
          <.review_stat value={@note_stats.read} label="read so far" />
          <.review_stat value={@note_stats.ready} label="ready" />
          <.review_stat value={@note_stats.needs} label="to decide" />
          <.review_stat value={@note_stats.approved} label="approved" />
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <div class="flex flex-wrap gap-2" role="tablist">
            <.button
              :for={
                {tab, label, n} <- [
                  {"ready", "Ready, nothing to decide", @note_stats.ready},
                  {"needs", "Needs you", @note_stats.needs},
                  {"approved", "Approved", @note_stats.approved}
                ]
              }
              id={"tab-#{tab}"}
              phx-click="tab"
              phx-value-tab={tab}
              size="sm"
              variant={if @tab == tab, do: "primary", else: "secondary"}
              aria-pressed={to_string(@tab == tab)}
            >
              {label} ({n})
            </.button>
          </div>
          <span class="flex-1"></span>
          <span class="text-meta text-muted">Grouped by what the note holds</span>
        </div>
      </.panel>

      <div id="notes">
        <.empty_state :if={@groups == []} title={empty_tab_text(@tab)} />
        <.review_section
          :for={g <- @groups}
          id={"note-group-#{g.group.id}"}
          section={Atom.to_string(g.group.id)}
          title={g.group.title}
          count={"· #{length(g.rows)} #{notes_word(length(g.rows))}"}
          explanation={g.group.explanation}
          closed={MapSet.member?(@closed, Atom.to_string(g.group.id))}
          on_toggle="toggle_section"
        >
          <:actions :if={@tab == "ready" and g.ticked > 0}>
            <.button
              id={"approve-group-#{g.group.id}"}
              phx-click="approve_notes"
              phx-value-group={g.group.id}
              size="sm"
              variant="secondary"
            >
              {ticked_text(g.ticked, "here")}
            </.button>
          </:actions>
          <.note_line
            :for={note <- g.rows}
            note={note}
            ticked={MapSet.member?(@ticked, note.id)}
            actor={@actor}
            definitions={@definitions}
          />
        </.review_section>
      </div>
    </Layouts.admin>
    """
  end

  defp ticked_text(0, _where), do: "Nothing ticked"
  defp ticked_text(n, "here"), do: "Approve #{n} ticked here"
  defp ticked_text(n, "notes"), do: "Approve #{n} ticked #{notes_word(n)}"

  defp empty_tab_text("ready"), do: "No note is ready to approve."
  defp empty_tab_text("needs"), do: "No note needs you."
  defp empty_tab_text("approved"), do: "No notes approved yet."

  # One note on one line: a tick (Ready), a ✓ (Approved) or what holds it
  # (Needs you, its items' rows under it); the Gall's name; what it adds;
  # and a link to its package's page.
  attr :note, :map, required: true
  attr :ticked, :boolean, required: true
  attr :actor, :any, required: true
  attr :definitions, :map, required: true

  defp note_line(assigns) do
    ~H"""
    <div id={"note-#{@note.id}"}>
      <div class="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-2">
        <%= case @note.state do %>
          <% :ready -> %>
            <input
              type="checkbox"
              id={"tick-#{@note.id}"}
              class="gf-checkbox"
              checked={@ticked}
              phx-click="tick"
              phx-value-id={@note.id}
              aria-label={"Approve #{@note.name}"}
            />
          <% :approved -> %>
            <.icon name="ph-check" class="size-4 shrink-0 text-ok" />
          <% :needs -> %>
            <.icon name="ph-warning" class="size-4 shrink-0 text-warn" />
        <% end %>
        <label
          for={@note.state == :ready && "tick-#{@note.id}"}
          class="min-w-0 grow basis-48 font-medium italic text-ink break-words"
        >
          {@note.name}
        </label>
        <.review_chips adds={@note.adds} aside={@note.aside} class="min-w-0 grow-2 basis-64" />
        <div class="ml-auto flex flex-wrap items-center gap-2 md:justify-end">
          <.chip :if={@note.state == :needs and @note.holding > 0} variant={:warn}>
            {@note.holding} to decide
          </.chip>
          <.chip :if={@note.state == :needs and @note.holding == 0} variant={:info}>
            Resolving
          </.chip>
          <.link navigate={~p"/admin/review/packages/#{@note.id}"} class="text-meta">
            View the note
          </.link>
        </div>
      </div>
      <div
        :if={@note.entries != []}
        class="border-t border-dashed border-line divide-y divide-line"
      >
        <.live_component
          :for={entry <- @note.entries}
          module={ItemRow}
          id={"item-row-#{entry.item.id}"}
          entry={entry}
          actor={@actor}
          definitions={@definitions}
          source_name="The note"
        />
      </div>
    </div>
    """
  end
end
