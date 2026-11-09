defmodule GallformersWeb.Admin.ReviewLive.Review do
  @moduledoc """
  One Source's review (matter `6611`, Task 8): `/admin/review/sources/:id`
  (the Source's packages under review together) and
  `/admin/review/packages/:package_id` (one package: one not matched to a
  Source yet, or one Gallformers note). The Gallformers Source's own page,
  its notes, is `/admin/review/notes` (`GallformersWeb.Admin.ReviewLive.Source`).

  **One at a time** (the default) shows one unit of work
  (`GallformersWeb.Admin.Review.Units`) in a `review_card`: a section's
  suggested answers to accept together, one question
  (`GallformersWeb.Admin.ReviewLive.QuestionCard`), or, once nothing is
  left, what approving will add (the approval's dry run,
  `Gallformers.Import.preview_package/2`, computed in the background). The
  `review_rail` beside it says how far along the review is, moves between
  stages, opens the hedged statements, lists what comes next, and holds
  Approve (`SourcePage.approval/3`) and Deny. After each decision the page
  loads again and moves on; the answer just given says so above the card
  ("Saved: …"), with Undo.

  **Everything** lists every open question by section, each with its
  suggestion and Accept; opening one shows its card.

  A question's "Look at it" on an iNaturalist taxon opens the import
  panel (`GallformersWeb.Admin.InatTaxonPanel`, matter `cb28`) in the
  rail's place; the taxon it brings in answers the question, and the
  review moves on as after any answer.

  Params: `view=all`, `stage=<step>` (that stage's work first), `hedges`
  (the hedged statements), `facts` (what approving will add).
  """
  use GallformersWeb, :live_view

  alias Gallformers.Import
  alias GallformersWeb.Admin.InatTaxonPanel
  alias GallformersWeb.Admin.Review.Steps
  alias GallformersWeb.Admin.Review.Units
  alias GallformersWeb.Admin.ReviewLive.Answer
  alias GallformersWeb.Admin.ReviewLive.Document
  alias GallformersWeb.Admin.ReviewLive.Loader
  alias GallformersWeb.Admin.ReviewLive.QuestionCard
  alias GallformersWeb.Admin.ReviewLive.SourcePage
  alias GallformersWeb.ReviewComponents

  import GallformersWeb.FactsComponents, only: [facts_view: 1]

  @deniable [:received, :invalid, :validated, :resolving, :awaiting_review]

  @hedges Steps.get("hedges").sections

  @impl true
  def mount(params, _session, socket) do
    mode = SourcePage.mode(params)

    if notes_source?(mode) do
      {:ok, push_navigate(socket, to: ~p"/admin/review/notes")}
    else
      {:ok,
       socket
       |> assign(
         mode: mode,
         base: SourcePage.base_path(mode),
         keep: [],
         context: :all,
         skipped: [],
         unticked: MapSet.new(),
         saved: nil,
         open_row: nil,
         open_hedge: nil,
         open_missed: nil,
         deny_form: nil,
         preview: nil,
         inat: nil
       )
       |> SourcePage.load()
       |> taxonomy_open()
       |> Document.mount()}
    end
  end

  # The Source in Gallformers (once matched), and its taxonomic statements
  # waiting in the taxonomy queue (matter
  # `f923`): they come after approval and hold none.
  defp taxonomy_open(socket) do
    id =
      case socket.assigns.mode do
        {:source, id} -> id
        {:package, _id} -> Enum.find_value(socket.assigns.packages, & &1.package.source_id)
      end

    assign(socket,
      source_id: id,
      taxonomy_open: if(id, do: Import.count_taxonomy_questions(id), else: 0)
    )
  end

  defp notes_source?({:source, id}), do: Loader.notes_page(id) != nil
  defp notes_source?(_mode), do: false

  @impl true
  def handle_params(params, _url, socket) do
    stage = Enum.find(Steps.all(), &(Atom.to_string(&1.id) == params["stage"]))

    {:noreply,
     socket
     |> assign(
       view: if(params["view"] == "all", do: "all", else: "one"),
       stage: stage && stage.id,
       hedges?: Map.has_key?(params, "hedges"),
       missed?: Map.has_key?(params, "missed"),
       facts?: Map.has_key?(params, "facts")
     )
     |> preview()}
  end

  # -- events ------------------------------------------------------------------

  @impl true
  def handle_event("view", %{"value" => view}, socket),
    do: {:noreply, push_patch(socket, to: review_path(socket, view: view))}

  def handle_event("stage", %{"id" => id}, socket),
    do:
      {:noreply, socket |> assign(skipped: []) |> push_patch(to: review_path(socket, stage: id))}

  def handle_event("hedges", _params, socket) do
    hedges = if socket.assigns.hedges?, do: nil, else: true
    {:noreply, push_patch(socket, to: review_path(socket, hedges: hedges, missed: nil))}
  end

  # The names we didn't read (`c8c3` item 12), and one of them opened.
  def handle_event("missed", _params, socket) do
    missed = if socket.assigns.missed?, do: nil, else: true

    {:noreply,
     push_patch(socket, to: review_path(socket, missed: missed, hedges: nil, facts: nil))}
  end

  def handle_event("open_missed", %{"id" => id}, socket),
    do: {:noreply, assign(socket, open_missed: String.to_integer(id))}

  # A hedged statement's own question, to add it as a Fact.
  def handle_event("add_hedge", %{"id" => id}, socket),
    do: {:noreply, assign(socket, open_hedge: String.to_integer(id))}

  def handle_event("skip", %{"key" => key}, socket),
    do: {:noreply, assign(socket, skipped: (socket.assigns.skipped -- [key]) ++ [key])}

  # A suggestion taken out of its batch (it comes next on its own), or back in.
  def handle_event("tick", %{"id" => id}, socket) do
    id = String.to_integer(id)
    unticked = socket.assigns.unticked

    unticked =
      if MapSet.member?(unticked, id),
        do: MapSet.delete(unticked, id),
        else: MapSet.put(unticked, id)

    {:noreply, assign(socket, unticked: unticked)}
  end

  def handle_event("accept_batch", %{"ids" => ids}, socket) do
    ids = ids |> String.split(",", trim: true) |> Enum.map(&String.to_integer/1)
    accept(socket, Enum.filter(socket.assigns.entries, &(&1.item.id in ids)))
  end

  # One row's suggestion, accepted from the Everything list.
  def handle_event("accept", %{"id" => id}, socket) do
    id = String.to_integer(id)
    accept(socket, Enum.filter(socket.assigns.entries, &(&1.item.id == id)))
  end

  def handle_event("open_row", %{"id" => id}, socket) do
    id = if is_integer(id), do: id, else: String.to_integer(id)
    open = if socket.assigns.open_row == id, do: nil, else: id
    {:noreply, assign(socket, open_row: open)}
  end

  # The answer just given, undone: its question opens again.
  def handle_event("undo", _params, socket) do
    %{actor: actor, saved: saved} = socket.assigns

    case saved && Import.undo_decisions(actor, saved.items) do
      {:ok, _items} ->
        {:noreply, socket |> assign(saved: nil) |> SourcePage.load()}

      {:error, reason} ->
        {:noreply, assign(socket, saved: %{saved | refusal: Import.undo_refusal(reason)})}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("approve", _params, socket),
    do: {:noreply, socket |> SourcePage.approve() |> SourcePage.load()}

  def handle_event("deny_open", _params, socket),
    do: {:noreply, assign(socket, deny_form: deny_form())}

  def handle_event("deny_cancel", _params, socket),
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
         |> put_flash(:info, "The Source was denied. Nothing of it is applied.")
         |> SourcePage.load()}

      {:error, %Ecto.Changeset{errors: errors}} ->
        errors = for {:denied_reason, error} <- errors, do: {:reason, error}
        {:noreply, assign(socket, deny_form: deny_form(reason, errors))}

      {:error, :not_deniable} ->
        {:noreply,
         socket
         |> assign(deny_form: nil)
         |> put_flash(:error, "This can no longer be denied.")
         |> SourcePage.load()}
    end
  end

  def handle_event("reader_" <> _ = event, params, socket),
    do: {:noreply, Document.handle_event(event, params, socket)}

  @impl true
  # A question's iNaturalist taxon: the import panel opens on it.
  def handle_info({Answer, {:inat_open, item_id, inat_id, matched}}, socket),
    do: {:noreply, assign(socket, inat: %{item_id: item_id, start: {:taxon, inat_id, matched}})}

  def handle_info({InatTaxonPanel, :close}, socket), do: {:noreply, assign(socket, inat: nil)}

  # Brought in: its question is answered with it.
  def handle_info({InatTaxonPanel, {:imported, taxon_id}}, socket) do
    %{item_id: item_id} = socket.assigns.inat
    send_update(QuestionCard, id: "q-#{item_id}", imported: taxon_id)
    {:noreply, assign(socket, inat: nil)}
  end

  def handle_info({QuestionCard, {:decided, item}}, socket) do
    entry = Enum.find(socket.assigns.entries, &(&1.item.id == item.id))
    items = if entry, do: decided_items(entry, item), else: [item]

    {:noreply,
     socket
     |> assign(saved: saved(entry, items), open_row: nil, open_hedge: nil, open_missed: nil)
     |> SourcePage.load()
     |> preview()}
  end

  @impl true
  def handle_async(:preview, {:ok, preview}, socket),
    do: {:noreply, assign(socket, preview: preview)}

  def handle_async(:preview, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, preview: :failed)}

  # The suggested answers of `entries`, each decided as the page shows it
  # (`Import.decide_queue_item/3`). A Trait term's suggestion is the readers'
  # majority, worked out for the page (`Questions`), not a proposal the back
  # end stores, so `Import.accept_proposals/2` would take none of them. One
  # refused comes up on its own, as an unticked one does.
  defp accept(socket, entries) do
    %{actor: actor} = socket.assigns

    {decided, refused} =
      Enum.reduce(entries, {[], []}, fn e, {decided, refused} ->
        case Import.decide_queue_item(actor, e.item, e.question.proposal.decision) do
          {:ok, item} -> {[item | decided], refused}
          {:error, reason} -> {decided, [{e.item, Answer.refusal(reason)} | refused]}
        end
      end)

    socket =
      case refused do
        [] ->
          socket

        [{_item, why} | _] ->
          put_flash(
            socket,
            :error,
            "#{length(refused)} could not be accepted (#{why}). Each comes up on its own."
          )
      end

    saved =
      if decided != [],
        do: %{text: accepted_text(length(decided)), items: Enum.reverse(decided), refusal: nil}

    unticked = MapSet.union(socket.assigns.unticked, MapSet.new(refused, fn {i, _} -> i.id end))

    {:noreply,
     socket
     |> assign(saved: saved, unticked: unticked, open_row: nil)
     |> SourcePage.load()
     |> preview()}
  end

  defp accepted_text(1), do: "Accepted 1 suggested answer."
  defp accepted_text(n), do: "Accepted #{n} suggested answers."

  # The items a decision settled: a group of identical disputes all at once.
  defp decided_items(%{members: [_ | _] = members}, _item), do: Enum.map(members, & &1.item)
  defp decided_items(_entry, item), do: [item]

  defp saved(nil, items), do: %{text: "Saved.", items: items, refusal: nil}

  defp saved(entry, items),
    do: %{
      text: "Saved: #{entry.question.written || entry.question.question}",
      items: items,
      refusal: nil
    }

  # What approving will add, worked out in the background once the review
  # reaches it (every package awaiting review).
  defp preview(socket) do
    if facts_now?(socket.assigns) do
      %{actor: actor, packages: packages} = socket.assigns
      awaiting = for p <- packages, p.package.status == :awaiting_review, do: p.package

      socket
      |> assign(preview: nil)
      |> start_async(:preview, fn -> Enum.map(awaiting, &dry_run(&1, actor)) end)
    else
      socket
    end
  end

  defp dry_run(package, actor) do
    {:ok, preview} = Import.preview_package(package, actor)
    preview
  end

  defp facts_now?(%{facts?: true}), do: true

  defp facts_now?(assigns),
    do:
      assigns[:view] == "one" and not assigns[:hedges?] and not assigns[:missed?] and
        units(assigns) == [:facts]

  defp deny_form(reason \\ "", errors \\ []),
    do: to_form(%{"reason" => reason}, as: :deny, errors: errors)

  defp deniable?(%{package: package, batches: batches}),
    do: package.status in @deniable and not Enum.any?(batches, &(&1.status == :applied))

  # The page's URL with `changes` to its params (nil drops one).
  defp review_path(socket, changes) do
    a = socket.assigns

    params =
      [
        view: if(a.view == "all", do: "all"),
        stage: a.stage && Atom.to_string(a.stage),
        hedges: if(a.hedges?, do: true),
        missed: if(a.missed?, do: true),
        facts: if(a.facts?, do: true)
      ]
      |> Keyword.merge(changes)
      |> Keyword.update!(:view, &if(&1 == "one", do: nil, else: &1))
      |> Enum.reject(fn {_key, value} -> value in [nil, false] end)
      |> Enum.map(fn
        {key, true} -> {key, ""}
        pair -> pair
      end)

    if params == [], do: a.base, else: "#{a.base}?#{URI.encode_query(params)}"
  end

  # -- what the page shows ---------------------------------------------------------

  defp units(assigns) do
    Units.units(assigns.entries,
      unticked: assigns.unticked,
      skipped: assigns.skipped,
      stage: assigns.stage
    )
  end

  defp current(assigns) do
    cond do
      assigns.hedges? -> :hedges
      assigns.missed? -> :missed
      assigns.facts? -> :facts
      true -> assigns |> units() |> List.first()
    end
  end

  defp hedge_groups(entries) do
    entries
    |> Enum.filter(&(&1.item.status == :open and &1.question.section.id in @hedges))
    |> Enum.group_by(& &1.question.section.title)
    |> Enum.map(fn {title, entries} ->
      {title,
       Enum.map(entries, &%{id: &1.item.id, text: &1.question.written || &1.question.question})}
    end)
  end

  defp batch_rows(entries) do
    for e <- entries,
        do: %{
          id: e.item.id,
          trait: e.question.trait && Answer.humanize(e.question.trait),
          term: e.question.written || e.question.question,
          answer: e.question.proposal.label,
          covers: e.question.covers || 1
        }
  end

  # The stage a section is in, and how many of its questions are left.
  defp stage_of(section, stages) do
    step = Steps.step_of(section.id)
    Enum.find(stages, &(&1.id == step)) || %{title: section.title, left: 0}
  end

  # The Galls (and their Facts) a question settles, from the dry run, when
  # there is one.
  defp affects(preview, item_id) when is_list(preview) do
    for p <- preview,
        g <- p.galls,
        facts = waiting_on(g, item_id),
        match?(%{id: ^item_id}, g.question) or facts != [] do
      %{
        name: g.name || "a Gall",
        undescribed: undescribed?(g),
        what:
          if(facts == [],
            do: "the Gall itself",
            else: facts |> Enum.map(&what/1) |> Enum.uniq() |> Enum.join(", ")
          )
      }
    end
  end

  defp affects(_preview, _item_id), do: []

  defp waiting_on(gall, id) do
    for {category, entries} <- gall.facts,
        e <- fact_entries(category, entries),
        match?(%{id: ^id}, e.question),
        do: e
  end

  defp fact_entries(:traits, by_trait), do: Enum.flat_map(by_trait, fn {_t, es} -> es end)
  defp fact_entries(_category, entries), do: entries

  # A coded name: "Antistrophus s-gracile-flower-gall", "Unknown (Cynipidae) q-…".
  defp undescribed?(%{name: name}) when is_binary(name),
    do: String.match?(name, ~r/^(Unknown \([^)]+\)|[A-Z][a-z]+) [a-z]+-/)

  defp undescribed?(_gall), do: false

  defp what(%{category: :hosts}), do: "its Host"
  defp what(%{category: :inducer}), do: "its Inducer"
  defp what(%{category: :traits, value: %{trait: t}}), do: "its #{Answer.humanize(t)}"
  defp what(%{category: :range}), do: "its range"
  defp what(%{category: :aliases}), do: "a common name"
  defp what(%{category: c}), do: "its #{c}"

  defp readable?(documents, entry), do: Document.for_item(documents, entry.item) != nil

  # The first passage a missed name appears in, its block marked.
  defp first_passage(documents, entry) do
    case {Document.for_item(documents, entry.item), List.wrap(entry.item.subject["items"])} do
      {nil, _items} -> []
      {_doc, []} -> []
      {doc, [first | _]} -> Document.passage(doc, %{item: first})
    end
  end

  defp suggestion(%{question: %{proposal: %{firm: true}}, rejected: false}), do: :suggested
  defp suggestion(%{question: %{proposal: %{}}, rejected: false}), do: :guess
  defp suggestion(_entry), do: nil

  defp open_sections(entries) do
    entries
    |> Enum.filter(&(&1.item.status == :open and &1.question.section.id not in @hedges))
    |> Units.units()
    |> Enum.flat_map(fn
      {:batch, _section, es} -> es
      {:one, _section, e} -> [e]
      :facts -> []
    end)
    |> Enum.chunk_by(& &1.question.section.id)
    |> Enum.map(fn [first | _] = es -> {first.question.section, es} end)
  end

  # -- rendering ----------------------------------------------------------------------

  @impl true
  def render(assigns) do
    units = units(assigns)
    current = current(assigns)

    assigns =
      assign(assigns,
        units: units,
        current: current,
        tally: Units.tally(assigns.entries),
        stages:
          Units.stages(assigns.entries, if(current in [:hedges, :missed], do: nil, else: current)),
        next: units |> Units.next() |> Enum.map(&Units.label/1)
      )

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <.page_header>
        <:crumb navigate={~p"/admin/review"}>Sources to review</:crumb>
        <:title>{@name}</:title>
      </.page_header>

      <div
        id="review"
        data-reading={@reader != nil}
        class={[
          "gf-density-reading grid items-start gap-section pb-section lg:grid-cols-12",
          @reader && "lg:mr-reader"
        ]}
      >
        <div class="flex min-w-0 flex-col gap-block lg:col-span-8">
          <.segmented_switch label="View" value={@view} event="view" class="self-start">
            <:option value="one" id="view-one">One at a time</:option>
            <:option value="all" id="view-all">Everything</:option>
          </.segmented_switch>

          <.notice :if={@saved} id="saved" kind={:ok}>
            {@saved.text}
            <:action>
              <.button size="sm" variant="ghost" phx-click="undo">Undo</.button>
            </:action>
          </.notice>
          <.notice :if={@saved && @saved.refusal} id="undo-refusal" kind={:warn}>
            {@saved.refusal.text}
          </.notice>

          <.notice :if={@taxonomy_open > 0} id="taxonomy-questions-open" kind={:info}>
            {@taxonomy_open} taxonomy {if @taxonomy_open == 1, do: "question", else: "questions"} open: this Source's taxonomic statements that are newer than the tree, to accept or decline. They don't hold approval.
            <:action>
              <.link navigate={~p"/admin/review/taxonomy?#{[source: @source_id]}"}>
                Open them
              </.link>
            </:action>
          </.notice>

          <%= if @view == "one" do %>
            <.unit
              current={@current}
              entries={@entries}
              stages={@stages}
              unticked={@unticked}
              preview={@preview}
              actor={@actor}
              definitions={@definitions}
              name={@name}
              documents={@documents}
              open_hedge={@open_hedge}
              open_missed={@open_missed}
              missed={@tally.missed}
            />
          <% else %>
            <.everything
              entries={@entries}
              open_row={@open_row}
              preview={@preview}
              actor={@actor}
              definitions={@definitions}
              name={@name}
              documents={@documents}
            />
          <% end %>
        </div>

        <.live_component
          :if={@inat}
          module={InatTaxonPanel}
          id="inat-taxon"
          actor={@actor}
          start={@inat.start}
          back
          answering
          class="lg:col-span-4"
        />

        <ReviewComponents.review_rail
          :if={!@inat}
          title={@summary.title}
          source_id={@source_id}
          tally={@tally}
          stages={@stages}
          next={@next}
          approval={@approval}
          on_stage="stage"
          on_hedges="hedges"
          on_missed="missed"
          on_approve="approve"
          on_deny="deny_open"
          class="lg:sticky lg:top-4 lg:col-span-4"
        />
      </div>

      <ReviewComponents.review_reader
        :if={@reader}
        title={@name}
        question={@reader.question}
        blocks={@reader.blocks}
        cited={@reader.cited}
        find={@reader.find}
        on_find="reader_find"
        on_close="reader_close"
      />

      <.dialog
        :if={@deny_form}
        id="deny-modal"
        title={"Deny #{@summary.title}"}
        show
        on_cancel={JS.push("deny_cancel")}
      >
        <.form for={@deny_form} id="deny-form" phx-submit="deny" class="flex flex-col gap-block">
          <p class="text-meta text-ink-2">
            Nothing of a denied Source is applied. The reason is kept with it.
          </p>
          <.input field={@deny_form[:reason]} type="textarea" label="Reason" required />
        </.form>
        <:actions>
          <.button type="button" phx-click="deny_cancel">Cancel</.button>
          <.button type="submit" form="deny-form" variant="danger">Deny</.button>
        </:actions>
      </.dialog>
    </Layouts.admin>
    """
  end

  attr :current, :any, required: true
  attr :entries, :list, required: true
  attr :stages, :list, required: true
  attr :unticked, :any, required: true
  attr :preview, :any, required: true
  attr :actor, :any, required: true
  attr :definitions, :map, required: true
  attr :name, :string, required: true
  attr :documents, :map, required: true
  attr :open_hedge, :any, default: nil
  attr :open_missed, :any, default: nil
  attr :missed, :integer, default: 0

  defp unit(%{current: :hedges} = assigns) do
    assigns =
      assign(assigns,
        groups: hedge_groups(assigns.entries),
        hedge: Enum.find(assigns.entries, &(&1.item.id == assigns.open_hedge))
      )

    ~H"""
    <.live_component
      :if={@hedge}
      module={QuestionCard}
      id={"q-#{@hedge.item.id}"}
      entry={@hedge}
      actor={@actor}
      definitions={@definitions}
      source_name={@name}
      affects={[]}
      skip_key={nil}
      readable={readable?(@documents, @hedge)}
    />
    <ReviewComponents.review_card
      id="unit"
      kind={:hedges}
      groups={@groups}
      on_add="add_hedge"
      on_back="hedges"
    />
    """
  end

  defp unit(%{current: :missed} = assigns) do
    entries =
      Enum.filter(
        assigns.entries,
        &(&1.item.status == :open and &1.question.section.id == :missed_names)
      )

    rows =
      for e <- entries,
          do: %{
            id: e.item.id,
            text: Enum.join(Enum.filter([e.question.written, e.question.context], & &1), " · ")
          }

    open = Enum.find(entries, &(&1.item.id == assigns.open_missed))

    assigns =
      assign(assigns,
        rows: rows,
        open: open,
        passage: open && first_passage(assigns.documents, open)
      )

    ~H"""
    <.live_component
      :if={@open}
      module={QuestionCard}
      id={"q-#{@open.item.id}"}
      entry={@open}
      actor={@actor}
      definitions={@definitions}
      source_name={@name}
      affects={[]}
      skip_key={nil}
      readable={readable?(@documents, @open)}
      passage={@passage}
    />
    <ReviewComponents.review_card
      id="unit"
      kind={:hedges}
      heading="Names we didn't read"
      intro={"#{@name} prints these names, which we have, but nothing it says with them was read. Look at each: add what it says, or mark it not needed."}
      add_label="Look at it…"
      groups={if @rows == [], do: [], else: [{nil, @rows}]}
      on_add="open_missed"
      on_back="missed"
    />
    """
  end

  defp unit(%{current: :facts} = assigns) do
    ~H"""
    <ReviewComponents.review_card id="unit" kind={:facts} loading={@preview == nil}>
      <:note :if={@missed > 0}>
        <p class="text-body text-ink-2">
          Before you approve:
          <button type="button" phx-click="missed" class="text-link hover:underline">
            {@missed} {if @missed == 1, do: "name", else: "names"} we didn't read. Look them over
          </button>
        </p>
      </:note>
      <p :if={@preview == :failed} class="text-body text-ink-2">
        What approving will add couldn't be worked out. Reload to try again.
      </p>
      <.facts_view
        :if={is_list(@preview)}
        id="facts"
        galls={Enum.flat_map(@preview, & &1.galls)}
        mode={:preview}
        empty="Approving adds nothing new."
      />
    </ReviewComponents.review_card>
    """
  end

  defp unit(%{current: {:batch, section, entries}} = assigns) do
    stage = stage_of(section, assigns.stages)
    assigns = assign(assigns, section: section, rows: batch_rows(entries), stage: stage)

    ~H"""
    <ReviewComponents.review_card
      id="unit"
      kind={:batch}
      section={@section.title}
      stage={@stage.title}
      of={@stage.left}
      rows={@rows}
      unticked={@unticked}
      skip_key={Units.key(@current)}
      on_tick="tick"
      on_accept="accept_batch"
      on_skip="skip"
    />
    """
  end

  defp unit(%{current: {:one, _section, entry}} = assigns) do
    assigns = assign(assigns, entry: entry)

    ~H"""
    <.live_component
      module={QuestionCard}
      id={"q-#{@entry.item.id}"}
      entry={@entry}
      actor={@actor}
      definitions={@definitions}
      source_name={@name}
      affects={affects(@preview, @entry.item.id)}
      skip_key={Units.key(@current)}
      readable={readable?(@documents, @entry)}
    />
    """
  end

  defp unit(assigns) do
    ~H"""
    <section id="unit" class="flex flex-col gap-3 rounded-panel border border-line bg-surface p-6">
      <h2 class="font-brand text-section text-ink">Nothing here is awaiting review</h2>
    </section>
    """
  end

  attr :entries, :list, required: true
  attr :open_row, :any, required: true
  attr :preview, :any, required: true
  attr :actor, :any, required: true
  attr :definitions, :map, required: true
  attr :name, :string, required: true
  attr :documents, :map, required: true

  defp everything(assigns) do
    assigns = assign(assigns, sections: open_sections(assigns.entries))

    ~H"""
    <section id="everything" class="flex flex-col gap-block">
      <p :if={@sections == []} class="text-body text-ink-2">Nothing left to answer.</p>
      <div :for={{section, entries} <- @sections} id={"all-#{section.id}"} class="flex flex-col">
        <h2 class="border-b border-line pb-1 text-meta font-semibold text-muted">
          {section.title} <span class="font-normal tabular-nums">{length(entries)}</span>
        </h2>
        <ReviewComponents.review_question_row
          :for={e <- entries}
          id={"row-#{e.item.id}"}
          open={@open_row == e.item.id}
          on_toggle={JS.push("open_row", value: %{id: e.item.id})}
        >
          <:written>{e.question.written || e.question.question}</:written>
          <:answer>
            <span class="flex flex-wrap items-center gap-2">
              <span :if={e.question.proposal} class="text-ink-2">{e.question.proposal.label}</span>
              <.chip :if={suggestion(e) == :suggested} variant={:ok} size="sm">Suggested</.chip>
              <.chip :if={suggestion(e) == :guess} variant={:info} size="sm">Best guess</.chip>
            </span>
          </:answer>
          <:detail>
            <.live_component
              module={QuestionCard}
              id={"q-#{e.item.id}"}
              entry={e}
              actor={@actor}
              definitions={@definitions}
              source_name={@name}
              affects={affects(@preview, e.item.id)}
              skip_key={Units.key({:one, e.question.section, e})}
              readable={readable?(@documents, e)}
            />
          </:detail>
          <div :if={suggestion(e) != nil} class="flex justify-end pb-2">
            <.button size="sm" phx-click="accept" phx-value-id={e.item.id}>Accept</.button>
          </div>
        </ReviewComponents.review_question_row>
      </div>
    </section>
    """
  end
end
