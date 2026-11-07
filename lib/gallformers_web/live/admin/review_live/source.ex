defmodule GallformersWeb.Admin.ReviewLive.Source do
  @moduledoc """
  A Source's review overview (`6611` Task 6; steps after matter `d213`,
  Task 15): `/admin/review/sources/:id` is the Source's packages under
  review together; `/admin/review/packages/:id` one package (one not
  matched to a Source yet, or one of the Gallformers notes). Its steps are
  pages of their own (`GallformersWeb.Admin.ReviewLive.Step`).

  The overview shows the Source by its short name ("Ashmead 1897"), with
  its title, kind, status, what it states, and Deny with a reason; the step
  bar, where Approve appears once nothing holds approval
  (`GallformersWeb.Admin.ReviewLive.SourcePage.approval/3`) and asks to
  confirm; "Which Source this is" as a banner (with any question no step
  shows); where it stands in each step, with "Continue" to the first
  step with work left; and the names the Source prints that Gallformers
  holds but no batch declares (`Gallformers.Import.UnusedNames.for_package/1`,
  read after the page loads), for a curator to scan for a taxon the
  producer left out. The head links to the Source in Gallformers
  (`/admin/sources/:id`) once there is one. While any of the Source's
  taxonomic statements awaits a curator in the taxonomy queue (matter
  `f923` Task 6; they come after approval and hold none), it says how many
  and links to them (`/admin/review/taxonomy?source=<id>`).

  The Gallformers Source's page (`6611` Task 7, screen 4 of the design)
  shows its notes instead, built for scanning
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
  (`GallformersWeb.Admin.ReviewLive.Notes`).
  """
  use GallformersWeb, :live_view

  import GallformersWeb.ReviewComponents

  alias Gallformers.Import
  alias Gallformers.Import.UnusedNames
  alias GallformersWeb.Admin.Review.Steps
  alias GallformersWeb.Admin.ReviewLive.ItemRow
  alias GallformersWeb.Admin.ReviewLive.Loader
  alias GallformersWeb.Admin.ReviewLive.Notes
  alias GallformersWeb.Admin.ReviewLive.SourcePage

  @deniable [:received, :invalid, :validated, :resolving, :awaiting_review]

  @tabs ~w(ready needs approved)

  @status_labels %{
    received: "Received",
    invalid: "Invalid",
    validated: "Validated",
    resolving: "Resolving",
    awaiting_review: "Awaiting review",
    approved: "Approved",
    denied: "Denied"
  }

  @impl true
  def mount(params, _session, socket) do
    mode = SourcePage.mode(params)

    {:ok,
     socket
     |> assign(
       mode: mode,
       base: SourcePage.base_path(mode),
       keep: [],
       closed: MapSet.new(),
       confirm_approve: false,
       deny_form: nil,
       tab: "ready",
       unticked: MapSet.new()
     )
     |> load()
     |> unused_names()}
  end

  # The names its text prints that no batch declares, from every package
  # (read once, after the page loads: it reads each package's document).
  defp unused_names(%{assigns: %{notes?: true}} = socket), do: socket

  defp unused_names(socket) do
    packages = Enum.map(socket.assigns.packages, & &1.package)

    assign_async(socket, :unused_names, fn ->
      names = packages |> Enum.flat_map(&package_unused_names/1) |> Enum.uniq_by(& &1.normalized)
      {:ok, %{unused_names: names}}
    end)
  end

  # A package with no text to read has none.
  defp package_unused_names(package) do
    case UnusedNames.for_package(package) do
      {:ok, names} -> names
      {:error, _reason} -> []
    end
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

  def handle_event("approve_ask", _params, socket),
    do: {:noreply, assign(socket, confirm_approve: true)}

  def handle_event("approve_cancel", _params, socket),
    do: {:noreply, assign(socket, confirm_approve: false)}

  def handle_event("approve", _params, socket),
    do: {:noreply, socket |> SourcePage.approve() |> assign(confirm_approve: false) |> load()}

  def handle_event("open_deny", _params, socket),
    do: {:noreply, assign(socket, deny_form: deny_form())}

  def handle_event("cancel_deny", _params, socket),
    do: {:noreply, assign(socket, deny_form: nil)}

  def handle_event("deny", %{"deny" => %{"reason" => reason}}, socket) do
    %{actor: actor, packages: packages} = socket.assigns

    result =
      packages
      |> Enum.filter(&deniable?/1)
      |> Enum.reduce_while(:ok, fn p, :ok ->
        case Import.deny_package(actor, p.package, reason) do
          {:ok, _denied} -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)

    case result do
      :ok ->
        {:noreply,
         socket
         |> assign(deny_form: nil)
         |> put_flash(:info, "The Source was denied; nothing of it is applied.")
         |> load()}

      {:error, %Ecto.Changeset{errors: errors}} ->
        reason_errors = for {:denied_reason, error} <- errors, do: {:reason, error}
        {:noreply, assign(socket, deny_form: deny_form(reason, reason_errors))}

      {:error, :not_deniable} ->
        {:noreply,
         socket
         |> assign(deny_form: nil)
         |> put_flash(:error, "This can no longer be denied.")
         |> load()}
    end
  end

  # -- the Gallformers notes ----------------------------------------------------

  def handle_event("tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:source, id} = socket.assigns.mode

    path =
      if tab == "ready",
        do: ~p"/admin/review/sources/#{id}",
        else: ~p"/admin/review/sources/#{id}?#{[tab: tab]}"

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

  defp deny_form(reason \\ "", errors \\ []),
    do: to_form(%{"reason" => reason}, as: :deny, errors: errors)

  defp deniable?(%{package: package, batches: batches}),
    do: package.status in @deniable and not Enum.any?(batches, &(&1.status == :applied))

  # -- loading -----------------------------------------------------------------

  # The Gallformers Source's page shows its notes; any other, its questions.
  defp load(%{assigns: %{mode: {:source, id}}} = socket) do
    case Loader.notes_page(id) do
      nil -> load_questions(socket)
      data -> load_notes(socket, data)
    end
  end

  defp load(socket), do: load_questions(socket)

  defp load_notes(socket, data) do
    assign(socket,
      page_title: data.summary.title,
      source: data.source,
      summary: data.summary,
      notes?: true,
      notes: data.notes,
      note_stats: data.stats,
      definitions: Loader.definitions()
    )
  end

  defp load_questions(socket) do
    socket = socket |> SourcePage.load() |> assign(notes?: false)
    id = source_id(socket.assigns.mode, socket.assigns.packages)

    assign(socket,
      taxonomy_source_id: id,
      taxonomy_open: if(id, do: Import.count_taxonomy_questions(id), else: 0)
    )
  end

  # -- what the page shows -------------------------------------------------------

  defp status(packages, approval) do
    statuses = packages |> Enum.map(& &1.package.status) |> Enum.uniq()

    cond do
      statuses == [:awaiting_review] and match?({:ready, _}, approval) ->
        {"Ready to approve", "success"}

      statuses == [:approved] ->
        {"Approved", "success"}

      statuses == [:awaiting_review] ->
        {"Awaiting review", "warning"}

      statuses == [] ->
        {"Nothing under review", "info"}

      true ->
        {Enum.map_join(statuses, ", ", &status_label/1), "info"}
    end
  end

  defp status_label(status), do: Map.fetch!(@status_labels, status)

  # The overview's own questions ("Which Source this is", and any no step
  # shows), in sections.
  defp banner(entries, who) do
    unplaced = Steps.unplaced(entries)
    ids = unplaced |> Enum.map(& &1.question.section.id) |> Enum.uniq()
    SourcePage.sections(unplaced, ids, who)
  end

  # -- rendering -------------------------------------------------------------------

  @tab_states %{"ready" => :ready, "needs" => :needs, "approved" => :approved}

  @impl true
  def render(%{notes?: true} = assigns) do
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
            <.review_source_link
              :if={source_id(@mode, [])}
              source_id={source_id(@mode, [])}
              class="mt-1.5"
            />
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

  def render(assigns) do
    {status, status_variant} = status(assigns.packages, assigns.approval)

    assigns =
      assign(assigns,
        status: status,
        status_variant: status_variant,
        banner: banner(assigns.entries, assigns.summary.who),
        next: Steps.first_open(assigns.summaries)
      )

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <.page_header>
        <:crumb navigate={~p"/admin/review"}>Sources to review</:crumb>
        <:title>{@name}</:title>
      </.page_header>

      <.review_source_head
        name={@name}
        title={@summary.title}
        citation={@summary.citation}
        kind={@summary.kind}
        status={@status}
        status_variant={@status_variant}
        source_id={source_id(@mode, @packages)}
      >
        <:actions :if={Enum.any?(@packages, &deniable?/1)}>
          <.button id="deny" phx-click="open_deny" size="sm" variant="secondary">Deny…</.button>
        </:actions>
        <div id="source-stats" class="flex flex-wrap gap-2">
          <.review_stat value={@stats.galls} label="Galls" />
          <.review_stat value={@stats.facts} label="statements about Galls" />
          <.review_stat value={@stats.acts} label="taxonomic acts" />
          <.review_stat value={@stats.set_aside} label="terms and statements set aside" />
        </div>
      </.review_source_head>

      <.review_step_bar
        base={@base}
        current={:overview}
        summaries={@summaries}
        approval={@approval}
        confirm={@confirm_approve}
      />

      <div id="banner">
        <.review_section
          :for={s <- @banner}
          id={"section-#{s.section.id}"}
          section={Atom.to_string(s.section.id)}
          title={s.section.title}
          count={if s.open == [], do: "· all decided", else: "· #{length(s.open)} to decide"}
          explanation={s.section.explanation}
          holds={s.section.holds}
          holds_approval={s.section.holds_approval}
          done={s.open == []}
          closed={MapSet.member?(@closed, Atom.to_string(s.section.id))}
          on_toggle="toggle_section"
          layout={:question}
        >
          <.live_component
            :for={entry <- s.rows}
            module={ItemRow}
            id={"item-row-#{entry.item.id}"}
            entry={entry}
            actor={@actor}
            definitions={@definitions}
            source_name={@name}
          />
        </.review_section>
      </div>

      <.review_step_overview
        base={@base}
        summaries={@summaries}
        next={@next}
        status={SourcePage.approval_text(@approval)}
      />

      <.notice :if={@taxonomy_open > 0} id="taxonomy-questions-open" kind={:info} class="mt-4">
        {@taxonomy_open} taxonomy {if @taxonomy_open == 1, do: "question", else: "questions"} open: this Source's taxonomic statements, newer than what the tree follows, to accept or decline. They don't hold approval.
        <:action>
          <.link navigate={~p"/admin/review/taxonomy?#{[source: @taxonomy_source_id]}"}>
            Open them
          </.link>
        </:action>
      </.notice>

      <.section
        id="unused-names"
        title="Names no batch declares"
        count={@unused_names.ok? && length(@unused_names.result)}
        class="mt-section"
      >
        <p class="mb-2 text-meta text-ink-2">
          The Source prints these names, which Gallformers holds, but none of its batches declares them. Scan them for a taxon the producer left out.
        </p>
        <.async_result :let={names} assign={@unused_names}>
          <:loading>
            <p class="text-ui text-muted">Reading the Source's text…</p>
          </:loading>
          <:failed>
            <p class="text-ui text-muted">The Source's text couldn't be read.</p>
          </:failed>
          <p :if={names == []} class="text-ui text-muted">
            Every name the Source prints that Gallformers holds is declared by a batch.
          </p>
          <.name_list :if={names != []} items={names} columns={3}>
            <:item :let={n}>
              <span data-part="name">
                <.taxon_name name={n.name} />
                <span :if={n.pages != []} class="text-meta text-muted">
                  p. {Enum.join(n.pages, ", ")}
                </span>
              </span>
            </:item>
          </.name_list>
        </.async_result>
      </.section>

      <.dialog
        :if={@deny_form}
        id="deny-modal"
        title={"Deny #{@summary.title}"}
        show
        on_cancel={JS.push("cancel_deny")}
      >
        <.form for={@deny_form} id="deny-form" phx-submit="deny" class="flex flex-col gap-block">
          <p class="text-meta text-ink-2">
            Nothing of a denied Source is applied. The reason is kept with it and in the replay
            log.
          </p>
          <.input field={@deny_form[:reason]} type="textarea" label="Reason" required />
        </.form>
        <:actions>
          <.button type="button" phx-click="cancel_deny">Cancel</.button>
          <.button type="submit" form="deny-form" variant="danger">Deny</.button>
        </:actions>
      </.dialog>
    </Layouts.admin>
    """
  end

  # The Source in Gallformers the page reviews: a package's once matched.
  defp source_id({:source, id}, _packages), do: id
  defp source_id({:package, _id}, packages), do: Enum.find_value(packages, & &1.package.source_id)

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
