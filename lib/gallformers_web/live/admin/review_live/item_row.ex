defmodule GallformersWeb.Admin.ReviewLive.ItemRow do
  @moduledoc """
  One question on a Source's step page (matter `d213`, Task 16, after the
  design's question layout): a row, a button with a chevron, the Source's
  words and the answer (recommended or decided), that opens on a click
  (Enter or Space) into the question and its scope, the quotes it rests
  on, the evidence its kind has, and its options as radio cards
  (`GallformersWeb.ReviewComponents.review_option/1`), the recommended one
  tagged. No row starts open and none is chosen; an option that needs an
  input (a name search, a value list, a category per Gall) shows it under
  itself once chosen. The Decide bar says what the chosen option does, or
  what is still missing, Decide disabled until the answer is complete;
  deciding closes the row. Details (what the readers said, the technical
  details) are behind disclosures.

  Notes (matter `d213`, Task 7) are apart from the decision: an open row
  always shows a note box with "Save note" (`Gallformers.Import.add_note/3`),
  which saves the note without deciding. The item's notes
  (`Gallformers.Import.notes_by_item/1`, an older decision's note among
  them) are listed under the row, open or not. A decided row opens onto
  what it was decided as, and its notes.

  Choices the backend doesn't take yet (`pending`) are left out. Decisions
  go through `Gallformers.Import.decide_queue_item/3` as the page's actor;
  a decided item tells the page (`{__MODULE__, {:decided, item}}`), which
  loads again (deciding resolves the package again). A refused decision
  shows why in the row.

  A Trait term's question (`Gallformers.Import.TraitTerms`, matter
  `d213`, Traits step) shows each Gall it covers
  (`GallformersWeb.ReviewComponents.review_term_gall/1`) under "Galls and
  what each reader said", and each option with who chose it. "Another
  <trait>" searches the Trait's values, each defined; "More than one"
  ticks several (the readers' first, ticked to start with; at least two),
  deciding `%{"place" => [values]}`; "It depends on the Gall" gives each
  Gall a row of choices, what most of its readers chose marked, and fills
  in the recommended ones on request, deciding `%{"categories" =>
  %{gall_ref => category | nil}}` ("keep as text" being nil). A term used
  in more than one sense opens on its per-Gall choices. Traits has no
  "Reject": there is no accepting all.

  A dispute shows both sides in a sentence each, the full arguments behind
  "The full arguments". Identical disputes are one row (the entry's
  `members`): "Keep it" lists every Gall with its quotes, each ticked,
  and an unticked Gall is dropped; they are decided together
  (`Gallformers.Import.decide_group/3`). A Host dispute (one or a group)
  may be kept with its Host read as another plant, searched among the
  tree's plants and sections; when the disputed Host is a genus, its
  sections are listed first, and the plant picked goes in for these Galls
  only (`Gallformers.Import.Disputes`). A Host named by a common name may be a
  section of its genus, picked from the genus's sections, each with its
  common name.

  The Names and Galls steps' answers (matter `d213`, Tasks 18 and 19) show
  more under their labels: a taxon's identity line and whether it already
  holds the Source's name; a candidate Gall's side-by-side comparison with
  what the Source says, tagged as the best match or with what it conflicts
  on. A Host's row, once opened, reads what WCVP holds for its name
  (`Gallformers.Import.ReviewContext.host/2`, in the background: it runs the
  Host suggestions) and shows it above the options. A Host neither
  Gallformers nor WCVP holds links to the New Taxon page in a new tab,
  started with the Source's name for it (beside the WCVP panel when WCVP
  has nothing, and under "Another plant…"'s search, which searches the tree
  live, so it then finds the plant created there; matter f14c). Follow-ups: what a
  synonym becomes when the Source is right (a species of its own again, or
  a synonym of a taxon picked); the Source's statements a chosen Gall
  disagrees with, each kept or left out, a Host also read as another plant
  picked, or (a genus Host) put "On another plant" for this Gall only, the
  genus's sections listed first (Decide waits until each is settled); a new Gall's generation; a
  new taxon's parent (a new species' genus, when the tree holds it, picked
  to start with; else searched among the ranks above it; none picked, it
  is added unplaced). The
  search of a question with more candidates than it offers lists those
  first.

  A taxonomic statement to accept or decline (matter `f923` Task 6,
  `Gallformers.Import.TaxonomyQueue`): Accept is recommended; Decline asks
  for its reason under itself once chosen, Decide waiting until there is
  one. A refusal from the tree (a cycle, a rank inversion, a lump it can't
  make) shows its reason in the row.

  A decided row, opened, offers Undo beside what it was decided as
  (matter `f14c`, "Undo rule"; `Gallformers.Import.undo_decision/2`, a
  group of disputes all together, `undo_decisions/2`): the question opens
  again and the page loads again (`{__MODULE__, {:undone, item}}`). When
  something since depends on the decision (the Source approved, a record
  it changed edited by someone), the row says why under it, with a link to
  the record in the taxonomy admin (or the Gall's page) where there is one.

  Reject sets the recommendation aside (`Gallformers.Import.reject_proposal/2`;
  Undo restores it, `restore_proposal/2`); the page loads again after
  either (`{__MODULE__, {:proposal, item}}`).

  Picking, searching, deciding and the follow-up inputs are
  `GallformersWeb.Admin.ReviewLive.Answer`'s, which the one-at-a-time
  review's card shares.

  Attributes: `entry` (`GallformersWeb.Admin.ReviewLive.Loader.entry/0`),
  `actor`, `definitions` (the Trait values' definitions by Trait and
  value), `source_name` (what the page calls the Source, "Ashmead 1897").
  """
  use GallformersWeb, :live_component

  import GallformersWeb.ReviewComponents

  import GallformersWeb.Admin.ReviewLive.Answer

  alias Gallformers.Import
  alias GallformersWeb.Admin.Review.Steps
  alias GallformersWeb.Admin.ReviewLive.Answer
  alias GallformersWeb.Admin.ReviewLive.Document

  @hedge_sections Steps.get("hedges").sections

  @answer_events Answer.events()

  @impl true
  def mount(socket) do
    {:ok, assign(socket, Answer.state() ++ [open: false, undo_refusal: nil, document: nil])}
  end

  # Every row's notes in one query.
  @impl true
  def update_many(assigns_sockets) do
    notes =
      assigns_sockets |> Enum.map(fn {a, _socket} -> a.entry.item end) |> Import.notes_by_item()

    Enum.map(assigns_sockets, fn {assigns, socket} ->
      assigns
      |> update_one(socket)
      |> assign(notes: Map.get(notes, assigns.entry.item.id, []))
    end)
  end

  defp update_one(assigns, socket) do
    socket = assign(socket, assigns)
    choices = visible_choices(socket.assigns.entry)

    # A choice the item no longer offers is dropped. A term used in more
    # than one sense opens with its per-Gall choices (d213).
    choice =
      case socket.assigns.choice do
        i when is_integer(i) and i < length(choices) -> i
        _ -> opening_choice(socket.assigns.entry, choices)
      end

    assign(socket, choices: choices, choice: choice)
  end

  defp opening_choice(%{item: %{kind: :trait_term, status: :open, subject: subject}}, choices)
       when is_map(subject) do
    if subject["status"] == "ambiguous", do: Enum.find_index(choices, &(&1.picker == :galls))
  end

  defp opening_choice(_entry, _choices), do: nil

  # The decided disputes of a grouped question, undone together.
  defp decided_members(%{members: [_ | _] = members}),
    do: for(m <- members, m.item.status == :decided, do: m.item)

  defp decided_members(_entry), do: []

  # -- events ------------------------------------------------------------------

  @impl true
  def handle_event("toggle", _params, socket) do
    socket = assign(socket, open: not socket.assigns.open, error: nil, undo_refusal: nil)
    {:noreply, read_host(socket)}
  end

  def handle_event("reject", _params, socket) do
    %{actor: actor, entry: entry} = socket.assigns

    case Import.reject_proposal(actor, entry.item) do
      {:ok, item} ->
        send(self(), {__MODULE__, {:proposal, item}})
        {:noreply, assign(socket, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: refusal(reason))}
    end
  end

  def handle_event("restore", _params, socket) do
    %{actor: actor, entry: entry} = socket.assigns

    case Import.restore_proposal(actor, entry.item) do
      {:ok, item} ->
        send(self(), {__MODULE__, {:proposal, item}})
        {:noreply, assign(socket, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: refusal(reason))}
    end
  end

  # Undo of a decided question (matter `f14c`): refused with why, inline.
  def handle_event("undo", _params, socket) do
    %{actor: actor, entry: entry} = socket.assigns

    result =
      case decided_members(entry) do
        [_, _ | _] = items ->
          with {:ok, [item | _]} <- Import.undo_decisions(actor, items), do: {:ok, item}

        _one ->
          Import.undo_decision(actor, entry.item)
      end

    case result do
      {:ok, item} ->
        send(self(), {__MODULE__, {:undone, item}})
        {:noreply, assign(socket, open: false, undo_refusal: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, undo_refusal: Import.undo_refusal(reason))}
    end
  end

  def handle_event("search_" <> _what = event, params, socket),
    do: Answer.handle_event(event, params, socket)

  def handle_event(event, params, socket) when event in @answer_events,
    do: Answer.handle_event(event, params, socket)

  def handle_event("decide", _params, socket) do
    case decision(socket.assigns) do
      {:ok, decision} -> decide(socket, decision, __MODULE__)
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  @impl true
  def handle_async(name, result, socket), do: Answer.handle_async(name, result, socket)

  # -- rendering -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    entry = assigns.entry
    {ok, effect} = effect(assigns)

    assigns =
      assign(assigns,
        item: entry.item,
        q: entry.question,
        decided: entry.item.status == :decided,
        accept: entry.accept,
        chosen: chosen(assigns),
        ok: ok,
        effect: effect,
        evidence: evidence(entry),
        text: Answer.text_value()
      )

    ~H"""
    <div id={"item-row-#{@item.id}"}>
      <.review_question_row
        id={"item-#{@item.id}"}
        open={@open}
        decided={@decided}
        on_toggle="toggle"
        target={@myself}
      >
        <:written>
          <span
            :if={@q.trait}
            class="mr-1 text-meta text-muted"
          >
            {humanize(@q.trait)}
          </span>
          {@q.written}
          <span :if={@q.tag} class="ml-1 align-middle">
            <.review_tag>{@q.tag}</.review_tag>
          </span>
          <.chip :if={@q.covers > 1} variant={:info} size="sm" class="ml-1 align-middle">
            {@q.covers} Galls
          </.chip>
          <span :if={@q.context} class="block text-meta font-normal text-muted line-clamp-2">
            {@q.context}
          </span>
        </:written>
        <:answer>
          <.answer entry={@entry} decided={@decided} />
        </:answer>
        <p :if={@error} id={"item-#{@item.id}-error"} class="px-4 pb-2 text-meta text-danger">
          {@error}
        </p>
        <.review_note_list
          :if={!@open and @notes != []}
          id={"item-#{@item.id}-notes"}
          notes={@notes}
          class="px-4 pb-2 md:pl-11"
        />
        <:detail>
          <%= if @decided do %>
            <.review_decided
              id={"item-#{@item.id}-decided"}
              text={@entry.decided || "Decided"}
              by={@item.decided_by_name}
            >
              <:action>
                <.button
                  id={"item-#{@item.id}-undo"}
                  phx-click="undo"
                  phx-target={@myself}
                  size="sm"
                  variant="ghost"
                >
                  Undo
                </.button>
              </:action>
            </.review_decided>
            <.notice :if={@undo_refusal} id={"item-#{@item.id}-undo-refusal"} kind={:warn}>
              {@undo_refusal.text}
              <:action :if={@undo_refusal.link}>
                <.button size="sm" navigate={record_path(@undo_refusal.link)}>
                  {record_label(@undo_refusal.link)}
                </.button>
              </:action>
            </.notice>
          <% else %>
            <.review_ask question={@q.question} scope={scope(@q)}>
              <:action :if={@document}>
                <.review_read_source
                  id={"item-#{@item.id}-read-source"}
                  item={@item.id}
                  on_read="reader_open"
                />
              </:action>
            </.review_ask>
            <.notice :if={@q.warning} kind={:danger}>{@q.warning}</.notice>
            <div :if={@evidence.quotes != []} id={"item-#{@item.id}-quotes"} class="grid gap-2">
              <.review_quote :for={quote <- @evidence.quotes} text={quote.text} where={quote.where}>
                <:passage :if={@document}>
                  <.review_passage blocks={Document.passage(@document, quote)} />
                </:passage>
              </.review_quote>
              <p :if={@evidence.more > 0} class="text-meta text-muted">
                Used for {@evidence.more} more {if @evidence.more == 1, do: "Gall", else: "Galls"}; {@evidence.see}
              </p>
            </div>
            <.review_wcvp_panel
              :if={wcvp_panel?(@entry) and @host != :failed}
              id={"item-#{@item.id}-wcvp"}
              written={@q.written}
              host={if is_map(@host), do: @host}
              new_plant={new_plant(@entry)}
            />
            <.review_comparison
              :if={@entry.comparison != []}
              id={"item-#{@item.id}-comparison"}
              source={%{who: @source_name, written: @q.written, quote: first_quote(@entry)}}
              candidates={@entry.comparison}
            />
            <.review_voices
              :if={@q.sides}
              id={"item-#{@item.id}-sides"}
              producer={@q.sides.producer}
              checker={@q.sides.checker}
              producer_title="The producer kept it"
              checker_title="A checker questioned it"
            />

            <div
              id={"item-#{@item.id}-choices"}
              role="radiogroup"
              aria-label={@q.question}
              class="grid gap-1.5"
            >
              <.review_option
                :for={{choice, i} <- Enum.with_index(@choices)}
                id={"item-#{@item.id}-choice-#{i}"}
                name={"item-#{@item.id}-choice"}
                value={i}
                checked={@choice == i}
                recommended={choice.proposed and not @entry.rejected}
                by={recommended_by(@q.proposal)}
                label={choice.label}
                summary={choice.hint}
                tags={choice.tags}
                tally={choice.tally}
                on_pick="pick"
                target={@myself}
              >
                <:extra :if={choice.holding || choice.identity || choice.comparison}>
                  <.review_alias :if={choice.holding} holding={choice.holding} />
                  <.review_identity :if={choice.identity} identity={choice.identity} />
                  <.review_gall_comparison
                    :if={choice.comparison}
                    id={"item-#{@item.id}-comparison-#{i}"}
                    comparison={choice.comparison}
                  />
                </:extra>
                <:follow :if={choice.note && is_nil(choice.picker)}>
                  <p class="text-meta text-ink-2" data-role="note">{choice.note}</p>
                </:follow>
                <:follow :if={choice.picker == :galls}>
                  <.term_galls
                    id={"item-#{@item.id}"}
                    q={@q}
                    galls={@galls}
                    text={Answer.text_value()}
                    target={@myself}
                    document={@document}
                  />
                </:follow>
                <:follow :if={choice.picker == :keep_galls}>
                  <.keep_galls
                    id={"item-#{@item.id}-keep"}
                    members={@entry.members}
                    unticked={@unticked}
                    target={@myself}
                    document={@document}
                  />
                </:follow>
                <:follow :if={choice.picker && choice.picker not in [:galls, :keep_galls]}>
                  <.picker
                    id={"item-#{@item.id}-picker"}
                    picker={choice.picker}
                    pick={@pick}
                    definitions={@definitions}
                    target={@myself}
                    choice={choice}
                    settled={@settled}
                    who={@source_name}
                  />
                  <.review_new_plant
                    :if={choice.picker == :plant and new_plant(@entry) != nil}
                    id={"item-#{@item.id}-new-plant"}
                    prefill={new_plant(@entry)}
                  />
                </:follow>
              </.review_option>
            </div>
            <p :if={@q.more} id={"item-#{@item.id}-more"} class="text-meta text-muted">
              {@q.more}
            </p>

            <p
              :if={@accept != nil and @q.section.id != :trait_terms}
              class="flex flex-wrap items-center gap-2 text-meta text-muted"
            >
              Not right?
              <.button
                id={"item-#{@item.id}-reject"}
                phx-click="reject"
                phx-target={@myself}
                size="sm"
                variant="ghost"
              >
                Reject the recommendation
              </.button>
              It stays open, out of “{bulk_action(@q.section.id)}”.
            </p>
            <p :if={@entry.rejected} class="flex flex-wrap items-center gap-2 text-meta text-muted">
              You rejected the recommendation.
              <.button
                id={"item-#{@item.id}-restore"}
                phx-click="restore"
                phx-target={@myself}
                size="sm"
                variant="ghost"
              >
                Undo
              </.button>
            </p>

            <.review_decide_bar
              id={"item-#{@item.id}"}
              ok={@ok}
              effect={@effect}
              on_decide="decide"
              target={@myself}
            />
          <% end %>

          <.review_notes
            id={"item-#{@item.id}"}
            notes={@notes}
            draft={@note}
            target={@myself}
          />

          <.review_disclosure
            :if={@q.galls != []}
            id={"item-#{@item.id}-readers"}
            summary="Galls and what each reader said"
          >
            <.review_term_gall
              :for={g <- @q.galls}
              id={"item-#{@item.id}-said-#{g.ref}"}
              name={g.name}
              quotes={g.quotes}
              said={g.said}
            >
              <:passage :let={quote} :if={@document}>
                <.review_passage blocks={Document.passage(@document, quote)} />
              </:passage>
            </.review_term_gall>
          </.review_disclosure>
          <.review_disclosure
            :if={@q.voices && (@q.voices.checker != [] or @q.voices.producer != [])}
            id={"item-#{@item.id}-arguments"}
            summary="The full arguments"
          >
            <.review_voices checker={@q.voices.checker} producer={@q.voices.producer} />
          </.review_disclosure>
          <.review_technical text={@q.technical} />
        </:detail>
      </.review_question_row>
    </div>
    """
  end

  # The question's scope: what it covers, then what leaving it means.
  defp scope(q), do: [q.scope, q.leave] |> Enum.filter(&is_binary/1) |> Enum.join(" ")

  # The quotes shown above the options: the item's own, or for a Trait
  # term the first Gall's, with how many more Galls use it.
  # A group of identical disputes: the first Gall's quote; each Gall's is
  # under "Keep it".
  defp evidence(%{members: [first | rest]}) do
    quotes = for q <- Enum.take(first.quotes, 1), do: Map.put(q, :where, first.question.about)
    %{quotes: quotes, more: length(rest), see: "each Gall's quote is under “Keep it”."}
  end

  defp evidence(%{quotes: [_ | _] = quotes}), do: %{quotes: quotes, more: 0, see: nil}

  defp evidence(%{question: %{galls: [first | rest]}}) do
    quotes = for quote <- Enum.take(first.quotes, 1), do: Map.put(quote, :where, first.name)
    %{quotes: quotes, more: length(rest), see: "see “Galls and what each reader said” below."}
  end

  defp evidence(_entry), do: %{quotes: [], more: 0, see: nil}

  # Who recommends the proposal, or why: its reason, or that it is a
  # suggestion to check.
  defp recommended_by(%{firm: true, why: why}), do: why
  defp recommended_by(%{firm: false, why: why}) when is_binary(why), do: "To check: " <> why
  defp recommended_by(%{firm: false}), do: "A suggestion to check"
  defp recommended_by(_proposal), do: nil

  attr :id, :string, required: true
  attr :q, :map, required: true
  attr :galls, :map, required: true
  attr :text, :string, required: true
  attr :target, :any, required: true
  attr :document, :map, default: nil

  # A Trait term's value for each Gall it covers: the values to choose
  # from, each defined once, then a row per Gall with its quote and its
  # choices (what most readers chose marked), and a button filling in the
  # recommended ones.
  defp term_galls(assigns) do
    options =
      for(d <- assigns.q.definitions, do: {d.value, d.value}) ++ [{assigns.text, "keep as text"}]

    recommended = Enum.count(assigns.q.galls, &(&1.default != nil))
    assigns = assign(assigns, options: options, recommended: recommended)

    ~H"""
    <div id={"#{@id}-galls"} class="grid gap-2" data-role="term-galls">
      <.review_definitions definitions={@q.definitions} />
      <.review_term_gall
        :for={g <- @q.galls}
        id={"#{@id}-gall-#{g.ref}"}
        name={g.name}
        quotes={Enum.take(g.quotes, 1)}
      >
        <:passage :let={quote} :if={@document}>
          <.review_passage blocks={Document.passage(@document, quote)} />
        </:passage>
        <.review_segmented
          id={"#{@id}-gall-#{g.ref}-category"}
          key={g.ref}
          label={"#{humanize(@q.trait)} for #{g.name}"}
          options={@options}
          value={Map.get(@galls, g.ref)}
          recommended={g.default && default_value(g.default)}
          on_pick="pick_gall"
          target={@target}
        />
      </.review_term_gall>
      <div :if={@recommended > 0}>
        <.button
          id={"#{@id}-fill"}
          type="button"
          phx-click="fill_galls"
          phx-target={@target}
          size="sm"
          variant="ghost"
        >
          Use the recommended answer for the {@recommended} {if @recommended == 1,
            do: "Gall that has one",
            else: "Galls that have one"}
        </.button>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :decided, :boolean, required: true

  defp answer(%{decided: true} = assigns) do
    ~H"""
    <span class="font-semibold">
      <.icon name="ph-check" class="size-4 inline" /> {@entry.decided}
    </span>
    <span class="block text-caption text-muted">
      Decided<span :if={@entry.item.decided_by_name}> by {@entry.item.decided_by_name}</span>
    </span>
    """
  end

  defp answer(%{entry: %{rejected: true, question: %{proposal: proposal}}} = assigns)
       when is_map(proposal) do
    ~H"""
    <span class="line-through text-muted">{@entry.question.proposal.label}</span>
    <span class="block text-meta text-danger">
      Recommendation rejected: choose another answer
    </span>
    """
  end

  # A Gall only to check: the best match, or one that conflicts.
  defp answer(%{entry: %{question: %{proposal: %{check: check}}}} = assigns)
       when is_binary(check) do
    ~H"""
    <span class="font-medium">{@entry.question.proposal.label}?</span>
    <span class="block text-meta text-muted">{@entry.question.proposal.check}</span>
    """
  end

  defp answer(%{entry: %{question: %{proposal: proposal}}} = assigns) when is_map(proposal) do
    ~H"""
    <span class="font-medium">{@entry.question.proposal.label}</span>
    <span class="block text-meta text-muted">
      <%= if @entry.question.proposal.firm do %>
        Recommended.<span :if={@entry.question.proposal.why}> {@entry.question.proposal.why}</span>
      <% else %>
        A suggestion to check<span :if={@entry.question.proposal.why}>: {@entry.question.proposal.why}</span>
      <% end %>
    </span>
    """
  end

  defp answer(assigns) do
    ~H"""
    <span class="italic text-muted">
      {(@entry.question.undecided && @entry.question.undecided.label) || "No recommendation"}
    </span>
    <span
      :if={@entry.question.undecided && @entry.question.undecided.why}
      class="block text-meta text-muted"
    >
      {@entry.question.undecided.why}
    </span>
    """
  end

  # The step's action accepting recommendations together (`Step`).
  defp bulk_action(section) when section in @hedge_sections, do: "Leave the rest out"
  defp bulk_action(_section), do: "Accept firm matches"

  defp first_quote(%{quotes: [%{text: text} | _]}), do: text
  defp first_quote(_entry), do: nil
end
