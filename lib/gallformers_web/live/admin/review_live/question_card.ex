defmodule GallformersWeb.Admin.ReviewLive.QuestionCard do
  @moduledoc """
  One question of a Source's review, as the one thing on the page (matter
  `6611`, Task 7): a `review_card` with its answers.

  A question's answers are `review_option`s with `use`: one click on "Use
  this" decides; an answer that needs input first ("Search…" for a name,
  "Choose…" for a value) opens it
  (`GallformersWeb.Admin.ReviewLive.Answer.picker/1`), and its own "Use
  this" decides once the input is complete. The suggested answer is marked
  "Suggested" (a firm proposal) or "Best guess" (a weak one). A Host
  nothing matches also offers "Add a new plant" (the New Taxon page, in a
  new tab) before leaving it out. An undescribed Gall lists the Galls it
  could be first ("Is it one of these Galls we already have?"), then "If
  not:" and the rest. A candidate Gall says in a sentence how it compares
  with what the Source says ("Agrees on 2 of 3: Host and where on the
  plant. Conflicts on generation and season."), the side-by-side behind
  "Compare".

  A Trait term, or a dispute about one, is answered Gall by Gall: for each
  Gall, the Source's words, what the import pipeline made of them, and two
  choices, "Keep “…” as text" or "Map it to <trait> values", which opens
  every value of the Trait as checkboxes, each value a reader chose marked
  and what most chose ticked to start with. "Use this for the other N
  Galls" copies one Gall's answer to the rest; Save waits until every Gall
  has one. A term decides `%{"categories" => %{gall_ref => [values] |
  nil}}`; a dispute (one Gall) is kept as text (`skip`), kept as the
  producer placed it (`keep`, exactly the producer's values), or decided as
  the values ticked (`values`, `c8c3` item 11).

  A Host named by its own name says in a line what WCVP has for it
  (`GallformersWeb.ReviewComponents.review_wcvp_panel/1`, `line`), read in
  the background, with POWO and IPNI to search when WCVP has nothing.

  "Another plant…" and "Another taxon…" search iNaturalist too: "Look at
  it" on one of its taxa asks the page to open the import panel on it
  (`GallformersWeb.Admin.InatTaxonPanel`, matter `cb28`), and the taxon it
  brings in answers the question (`send_update/3` with `imported:
  taxon_id`).

  "Add a note…" opens a note box (saved apart from the decision); earlier
  notes are listed under the quotes. Deciding tells the page
  (`{__MODULE__, {:decided, item}}`); a refusal shows in the card.

  Attributes: `entry` (`GallformersWeb.Admin.ReviewLive.Loader.entry/0`),
  `actor`, `definitions`, `source_name`, `affects` (the Galls and Facts it
  settles, for the card's Affects), `skip_key`, `readable` (whether "Read
  the Source" can open its text).
  """
  use GallformersWeb, :live_component

  import GallformersWeb.Admin.ReviewLive.Answer, only: [picker: 1, keep_galls: 1]

  alias Gallformers.Import
  alias GallformersWeb.Admin.ReviewLive.Answer
  alias GallformersWeb.ReviewComponents

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, state() ++ [trait: %{}, passage: []])}

  # The card's searches reach iNaturalist too (matter `cb28`).
  defp state, do: Answer.state() ++ [noting: false, inat: true]

  # The taxon brought in from iNaturalist answers the question (the page
  # sends it once the import panel has brought it in).
  @impl true
  def update(%{imported: taxon_id}, socket) do
    {:noreply, socket} = Answer.decide_imported(socket, taxon_id, __MODULE__)
    {:ok, socket}
  end

  def update(assigns, socket) do
    fresh? =
      socket.assigns[:entry] == nil or socket.assigns.entry.item.id != assigns.entry.item.id

    socket = if fresh?, do: assign(socket, state()), else: socket
    socket = assign(socket, assigns)
    entry = socket.assigns.entry

    socket =
      if fresh?,
        do:
          assign(socket,
            notes: Import.notes_for(entry.item),
            trait: start_trait(entry),
            open: true
          )
          |> Answer.read_host(),
        else: socket

    {:ok, assign(socket, choices: Answer.visible_choices(entry))}
  end

  # -- events ----------------------------------------------------------------------

  @impl true
  def handle_event("use", params, socket) do
    {:noreply, socket} = Answer.handle_event("pick", params, socket)
    if params["use"] == "1", do: decide(socket), else: {:noreply, socket}
  end

  def handle_event("decide", _params, socket), do: decide(socket)

  def handle_event("toggle_note", _params, socket),
    do: {:noreply, assign(socket, noting: not socket.assigns.noting)}

  def handle_event("trait_mode", %{"ref" => ref, "mode" => mode}, socket) do
    answer =
      case {mode, socket.assigns.trait[ref]} do
        {"text", _} -> :text
        {"values", %MapSet{} = set} -> set
        {"values", _} -> MapSet.new(suggested_start(socket.assigns.entry, ref))
      end

    {:noreply, assign(socket, trait: Map.put(socket.assigns.trait, ref, answer), error: nil)}
  end

  def handle_event("trait_value", %{"ref" => ref, "value" => value}, socket) do
    set =
      case socket.assigns.trait[ref] do
        %MapSet{} = set -> set
        _ -> MapSet.new()
      end

    set = if value in set, do: MapSet.delete(set, value), else: MapSet.put(set, value)
    {:noreply, assign(socket, trait: Map.put(socket.assigns.trait, ref, set), error: nil)}
  end

  def handle_event("trait_all", %{"ref" => ref}, socket) do
    answer = socket.assigns.trait[ref]

    trait =
      for g <- socket.assigns.entry.question.galls,
          into: socket.assigns.trait,
          do: {g.ref, answer}

    {:noreply, assign(socket, trait: trait, error: nil)}
  end

  def handle_event("trait_save", _params, socket) do
    case trait_decision(socket.assigns) do
      {:ok, decision} -> Answer.decide(socket, decision, __MODULE__)
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("search_" <> _what = event, params, socket),
    do: Answer.handle_event(event, params, socket)

  def handle_event("save_note", params, socket) do
    {:noreply, socket} = Answer.handle_event("save_note", params, socket)
    {:noreply, assign(socket, noting: socket.assigns.error != nil)}
  end

  def handle_event(event, params, socket),
    do: Answer.handle_event(event, params, socket)

  @impl true
  def handle_async(name, result, socket), do: Answer.handle_async(name, result, socket)

  defp decide(socket) do
    case Answer.decision(socket.assigns) do
      {:ok, decision} -> Answer.decide(socket, decision, __MODULE__)
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  # -- a Trait term, Gall by Gall ------------------------------------------------------

  defp trait?(%{question: %{trait: trait, galls: [_ | _]}}) when is_binary(trait), do: true
  defp trait?(_entry), do: false

  defp dispute?(entry), do: entry.question.topic == :trait_dispute

  # Each Gall's answer to start with: what most of its readers chose.
  defp start_trait(entry) do
    if trait?(entry) and not dispute?(entry) do
      for g <- entry.question.galls,
          answer = start_answer(g.default),
          into: %{},
          do: {g.ref, answer}
    else
      %{}
    end
  end

  defp start_answer(:text), do: :text
  defp start_answer(nil), do: nil
  defp start_answer(values), do: MapSet.new(List.wrap(values))

  # Ticked when "Map it to values" is chosen with nothing ticked yet: what
  # most readers chose, else nothing (a dispute starts with nothing).
  defp suggested_start(entry, ref) do
    case Enum.find(entry.question.galls, &(&1.ref == ref)) do
      %{default: default} when is_binary(default) or is_list(default) -> List.wrap(default)
      _ -> []
    end
  end

  defp trait_decision(%{entry: entry, trait: trait}) do
    galls = entry.question.galls
    missing = Enum.count(galls, &(not answered?(trait[&1.ref])))

    cond do
      missing > 0 ->
        {:error, "Choose one of the two for each Gall first."}

      dispute?(entry) ->
        dispute_decision(entry, trait[hd(galls).ref])

      true ->
        {:ok, %{"categories" => Map.new(galls, &{&1.ref, category(trait[&1.ref])})}}
    end
  end

  defp answered?(:text), do: true
  defp answered?(%MapSet{} = set), do: MapSet.size(set) > 0
  defp answered?(_answer), do: false

  defp category(:text), do: nil
  defp category(set), do: set |> MapSet.to_list() |> Enum.sort()

  defp dispute_decision(_entry, :text), do: {:ok, %{"skip" => true}}

  # Exactly the producer's values keep it as the producer placed it; any
  # others (a checker's, or the curator's own) are decided as those values.
  defp dispute_decision(entry, set) do
    producer = producer_values(entry)

    if producer != [] and set == MapSet.new(producer),
      do: {:ok, %{"keep" => true}},
      else: {:ok, %{"values" => category(set)}}
  end

  defp producer_values(entry),
    do: entry.item.subject |> Map.get("suggestions") |> List.wrap() |> Enum.filter(&is_binary/1)

  # -- rendering --------------------------------------------------------------------

  @impl true
  def render(assigns) do
    entry = assigns.entry
    q = entry.question

    assigns =
      assign(assigns,
        q: q,
        item_id: entry.item.id,
        trait?: trait?(entry),
        quotes: if(trait?(entry), do: [], else: entry.quotes)
      )

    ~H"""
    <div id={@id}>
      <ReviewComponents.review_card
        id={"#{@id}-card"}
        kind={if @trait?, do: :trait, else: :question}
        section={@q.section.title}
        holds={@entry.holds}
        affects={@affects}
        heading={@q.question}
        scope={if @trait?, do: nil, else: @q.scope}
        quotes={@quotes}
        notes={@notes}
        item_id={@item_id}
        skip_key={@skip_key}
        on_note="toggle_note"
        note_target={@myself}
        on_read={@readable && "reader_open"}
        on_skip="skip"
      >
        <ReviewComponents.review_passage :if={@passage != []} blocks={@passage} />
        <ReviewComponents.review_wcvp_panel
          :if={Answer.wcvp_panel?(@entry) and @host != :failed}
          id={"#{@id}-wcvp"}
          written={@q.written}
          host={if is_map(@host), do: @host}
          line
        />
        <.trait_answers :if={@trait?} ctx={ctx(assigns)} />
        <.answers :if={!@trait?} ctx={ctx(assigns)} />
        <.notice :if={@error} kind={:danger}>{@error}</.notice>
        <:note :if={@noting}>
          <.form
            for={%{}}
            id={"#{@id}-note-form"}
            phx-change="note_draft"
            phx-submit="save_note"
            phx-target={@myself}
            class="flex flex-wrap items-end gap-2"
          >
            <label for={"#{@id}-note"} class="sr-only">Note</label>
            <textarea
              id={"#{@id}-note"}
              name="note"
              rows="2"
              class="gf-textarea min-w-64 flex-1"
              placeholder="A note for the next curator: what you checked, what is still unclear."
            >{@note}</textarea>
            <.button type="submit" variant="secondary">Save note</.button>
          </.form>
        </:note>
      </ReviewComponents.review_card>
    </div>
    """
  end

  # What the answers read of the card: its state, as `Answer` reads it.
  defp ctx(assigns),
    do:
      assigns
      |> Map.take([
        :id,
        :choice,
        :choices,
        :pick,
        :settled,
        :galls,
        :unticked,
        :definitions,
        :source_name,
        :entry,
        :myself,
        :trait,
        :q
      ])
      |> Map.put(:add_plant, add_plant(assigns))

  attr :ctx, :map, required: true

  # The answers of a question that isn't a Trait term's.
  defp answers(assigns) do
    ctx = assigns.ctx
    indexed = Enum.with_index(ctx.choices)
    {galls, rest} = Enum.split_with(indexed, fn {c, _i} -> gall_choice?(c) end)
    candidates? = ctx.q.section.id == :undescribed_galls and galls != []

    assigns =
      assign(assigns,
        candidates?: candidates?,
        first: if(candidates?, do: galls, else: indexed),
        rest: if(candidates?, do: rest, else: []),
        firm?: match?(%{firm: true}, ctx.q.proposal)
      )

    ~H"""
    <p :if={@candidates?} class="text-body text-ink">Is it one of these Galls we already have?</p>
    <.answer :for={{c, i} <- @first} c={c} i={i} firm?={@firm?} ctx={@ctx} />
    <p :if={@candidates? and @rest != []} class="text-body text-ink">If not:</p>
    <.answer :for={{c, i} <- @rest} c={c} i={i} firm?={@firm?} ctx={@ctx} />
    """
  end

  attr :c, :any, required: true
  attr :i, :integer, required: true
  attr :firm?, :boolean, required: true
  attr :ctx, :map, required: true

  defp answer(assigns) do
    %{c: c, ctx: ctx} = assigns
    needs_input? = not is_map(c.decision)

    assigns =
      assign(assigns,
        id: ctx.id,
        myself: ctx.myself,
        needs_input?: needs_input?,
        recommended: c.proposed and assigns.firm?,
        tags: answer_tags(c, assigns.firm?),
        effect: if(needs_input? and ctx.choice == assigns.i, do: Answer.effect(ctx))
      )

    ~H"""
    <ReviewComponents.review_option
      :if={@ctx.add_plant && leave_host?(@c)}
      use
      id={"#{@id}-add-plant"}
      name={@id}
      value="add"
      label="Add a new plant"
      summary="Not in Gallformers or WCVP? Add it, then search for it here."
      href={@ctx.add_plant}
      open_label="Add… ↗"
      on_pick="use"
    />
    <ReviewComponents.review_option
      use
      id={"#{@id}-c#{@i}"}
      name={@id}
      value={@i}
      checked={@ctx.choice == @i}
      recommended={@recommended}
      tags={@tags}
      label={@c.label}
      summary={(@c.comparison && @c.comparison[:brief]) || @c.hint}
      tally={@c.tally}
      open_label={open_label(@c.picker)}
      on_pick="use"
      target={@myself}
    >
      <:extra :if={@c.comparison}>
        <ReviewComponents.review_disclosure summary="Compare">
          <ReviewComponents.review_gall_comparison
            id={"#{@id}-compare-#{@i}"}
            comparison={@c.comparison}
          />
        </ReviewComponents.review_disclosure>
      </:extra>
      <:follow :if={@needs_input?}>
        <.keep_galls
          :if={@c.picker == :keep_galls}
          id={"#{@id}-members"}
          members={Map.get(@ctx.entry, :members, [])}
          unticked={@ctx.unticked}
          target={@myself}
        />
        <.picker
          :if={@c.picker not in [:keep_galls, :galls]}
          id={"#{@id}-pick-#{@i}"}
          picker={@c.picker}
          pick={@ctx.pick}
          definitions={@ctx.definitions}
          choice={@c}
          settled={@ctx.settled}
          who={@ctx.source_name}
          entry={@ctx.entry}
          target={@myself}
        />
        <div class="flex flex-wrap items-center gap-3">
          <.button
            variant="primary"
            disabled={!match?({true, _}, @effect)}
            phx-click="decide"
            phx-target={@myself}
          >
            Use this
          </.button>
          <span :if={@effect} data-role="effect" class="text-meta text-ink-2">
            {elem(@effect, 1)}
          </span>
        </div>
      </:follow>
    </ReviewComponents.review_option>
    """
  end

  # What an answer's button says when it needs input first: a search, or a
  # choice among values (a generation, a section, a reason…).
  defp open_label(picker) when picker in [:plant, :taxon, :gall, :place], do: "Search…"
  defp open_label({:reading, _}), do: "Search…"
  # A new taxon: its place in the tree is searched for, or left for later.
  defp open_label({:parent, _}), do: "Add it…"
  defp open_label(_picker), do: "Choose…"

  defp gall_choice?(%{base: %{"gall_id" => _}}), do: true
  defp gall_choice?(%{decision: %{"gall_id" => _}}), do: true
  defp gall_choice?(_choice), do: false

  defp leave_host?(%{label: "Leave this Host out"}), do: true
  defp leave_host?(_choice), do: false

  # The New Taxon page for a Host nothing matches, started with its name.
  defp add_plant(%{q: %{section: %{id: :hosts}}, entry: entry}) do
    case Answer.new_plant(entry) do
      nil -> nil
      prefill -> ReviewComponents.new_plant_href(prefill)
    end
  end

  defp add_plant(_assigns), do: nil

  # A weak suggestion is a best guess; a candidate's own tags follow.
  defp answer_tags(c, firm?) do
    best = if c.proposed and not firm?, do: [%{text: "Best guess", kind: :best}], else: []
    best ++ List.wrap(c.tags)
  end

  attr :ctx, :map, required: true

  defp trait_answers(assigns) do
    ctx = assigns.ctx
    entry = ctx.entry
    q = entry.question
    trait = q.trait
    defs = Map.get(ctx.definitions, trait, %{})
    n = length(q.galls)

    assigns =
      assign(assigns,
        id: ctx.id,
        myself: ctx.myself,
        q: q,
        entry: entry,
        trait: ctx.trait,
        term: q.written || "",
        trait_name: Answer.humanize(trait),
        defs: defs,
        n: n,
        ready?: Enum.all?(q.galls, &answered?(ctx.trait[&1.ref]))
      )

    ~H"""
    <div
      :for={g <- @q.galls}
      id={"#{@id}-gall-#{g.ref}"}
      data-gall={g.ref}
      class="flex flex-col gap-3 border-t border-line pt-4"
    >
      <% answer = @trait[g.ref] %>
      <p class="text-body font-semibold text-ink">{g.name}</p>
      <.source_quote :for={quote <- gall_quotes(g, @entry)} page={quote[:where]}>
        <p>“{quote.text}”</p>
      </.source_quote>
      <p data-role="pipeline" class="text-body text-ink-2">{g.line}</p>
      <ReviewComponents.review_disclosure :if={g.said != []} summary="What each AI said">
        <p :for={line <- g.said}>{line}</p>
      </ReviewComponents.review_disclosure>
      <div role="radiogroup" aria-label={"#{g.name}: “#{@term}”"} class="grid gap-2">
        <.radio_card
          id={"#{@id}-#{g.ref}-text"}
          name={"#{@id}-#{g.ref}"}
          value="text"
          checked={answer == :text}
          summary="The Gall shows the Source's words. The ID tool can't filter on them."
          phx-click="trait_mode"
          phx-value-ref={g.ref}
          phx-value-mode="text"
          phx-target={@myself}
        >
          <:label>Keep “{@term}” as text</:label>
        </.radio_card>
        <.radio_card
          id={"#{@id}-#{g.ref}-values"}
          name={"#{@id}-#{g.ref}"}
          value="values"
          checked={is_struct(answer, MapSet)}
          summary="Tick every value that fits; most Galls take more than one."
          phx-click="trait_mode"
          phx-value-ref={g.ref}
          phx-value-mode="values"
          phx-target={@myself}
        >
          <:label>Map it to {@trait_name} values</:label>
          <:follow>
            <ReviewComponents.review_value_list
              id={"#{@id}-#{g.ref}-list"}
              type="checkbox"
              compact
              values={value_pairs(g.suggested, @defs)}
              selected={if is_struct(answer, MapSet), do: MapSet.to_list(answer), else: []}
              noted={g.suggested}
              note="suggested"
              on_pick="trait_value"
              params={%{ref: g.ref}}
              target={@myself}
            />
          </:follow>
        </.radio_card>
      </div>
      <button
        :if={@n > 1 and answered?(answer)}
        type="button"
        phx-click="trait_all"
        phx-value-ref={g.ref}
        phx-target={@myself}
        class="w-fit text-meta text-link hover:underline"
      >
        Use this for the other {@n - 1} {if @n == 2, do: "Gall", else: "Galls"}
      </button>
    </div>
    <div class="flex flex-wrap items-center gap-3 border-t border-line pt-4">
      <.button variant="primary" disabled={!@ready?} phx-click="trait_save" phx-target={@myself}>
        Save
      </.button>
      <span :if={!@ready?} class="text-meta text-muted">
        Choose one of the two for each Gall first.
      </span>
    </div>
    """
  end

  # A Gall's quote; a dispute's are the entry's own.
  defp gall_quotes(%{quotes: [_ | _] = quotes}, _entry), do: Enum.take(quotes, 1)
  defp gall_quotes(_gall, entry), do: Enum.take(entry.quotes, 1)

  # The Trait's values, those a reader chose first, each with its definition.
  defp value_pairs(suggested, defs) do
    known = Enum.filter(suggested, &Map.has_key?(defs, &1))
    rest = defs |> Map.keys() |> Enum.sort() |> Enum.reject(&(&1 in known))
    for v <- known ++ rest, do: {v, defs[v]}
  end
end
