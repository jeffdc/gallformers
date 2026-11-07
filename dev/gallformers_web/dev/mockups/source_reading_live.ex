defmodule GallformersWeb.Dev.Mockups.SourceReadingLive do
  @moduledoc """
  Mockup (matters `6611`, `f14c`, `d3b0`): a Source's review as one view,
  "checking our reading of the Source". `/dev/mockups/source-reading/:package_id`.

  One status bar (what's left, what holds approval, Approve with its
  reason); the questions to decide, once each, in the pipeline's order,
  each a compact row with its proposal and one-click Accept; the reading
  (the Source's Facts by Gall, from the approval's dry run) as a collapsed,
  filterable index of Galls, built to hold a Source of ~570 Galls; what the
  Source set aside, collapsed. Selecting a question opens it in the
  inspector beside the page and narrows the reading to the Galls it
  decides.

  Real: the package's questions in the curator's words
  (`ReviewLive.SourcePage.load/1`), the reading
  (`Import.preview_package/2`) and which Facts wait on which question.
  Not real: deciding (recorded on this page only; the reading isn't
  recomputed), notes, search, Approve and Deny.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Import
  alias GallformersWeb.Admin.Review.Steps
  alias GallformersWeb.Admin.ReviewLive.Loader
  alias GallformersWeb.Admin.ReviewLive.SourcePage

  @set_aside ~w(hedge_names hedge_inducer hedge_host hedge_range hedge_gall hedge_other)a

  @impl true
  def mount(%{"package_id" => id}, _session, socket) do
    socket =
      socket
      |> assign(mode: {:package, String.to_integer(id)}, keep: [])
      |> SourcePage.load()

    # The Traits step's context (each Gall a term covers) for its questions.
    traits =
      socket.assigns.packages
      |> Loader.entries(socket.assigns.summary.who, step: :traits)
      |> Map.new(&{&1.item.id, &1})

    socket =
      assign(socket,
        entries:
          Enum.map(
            socket.assigns.entries,
            &(traits |> Map.get(&1.item.id, &1) |> as_trait_card())
          )
      )

    actor = GallformersWeb.Live.UserAuth.curator(socket.assigns.current_user)
    packages = Enum.map(socket.assigns.packages, & &1.package)

    {:ok,
     socket
     |> assign(
       page_title: "Mockup: reading " <> socket.assigns.name,
       decided: %{},
       selected: nil,
       mode: "focus",
       skipped: [],
       singled: MapSet.new(),
       picks: %{},
       stage: nil,
       hedges?: false,
       filter: "needs",
       open_galls: MapSet.new(),
       set_aside_open?: false,
       reading: nil
     )
     |> start_async(:reading, fn ->
       {:ok, preview} =
         Import.preview_package(hd(packages), actor || Gallformers.Audit.Actor.system("preview"))

       preview
     end)}
  end

  # A Trait dispute (the pipeline's AIs disagreed about one Gall's Trait) is
  # the same decision as a Trait term for that one Gall: shown with the same
  # card, nothing preselected.
  defp as_trait_card(%{question: %{tag: "Disputed", trait: trait, galls: []} = q} = e)
       when is_binary(trait) do
    sides = q.sides || %{producer: [], checker: []}

    said =
      Enum.map(sides.producer, &"The producer: #{&1}") ++
        Enum.map(sides.checker, &"A checker: #{&1}")

    voices = q.voices || %{producer: [], checker: []}

    gall = %{
      ref: "dispute",
      name: q.about || "this Gall",
      quotes: Enum.map(e.quotes, &%{text: &1.text}),
      said: said,
      default: :disputed,
      # The mockup reads the producer's value out of its reasoning ("under
      # texture as `succulent`"); the build should carry it as data.
      producer_text: Enum.join(voices.producer ++ sides.producer, " "),
      checker: List.first(sides.checker)
    }

    %{e | question: %{q | galls: [gall]}}
  end

  defp as_trait_card(e), do: e

  @impl true
  def handle_async(:reading, {:ok, preview}, socket),
    do: {:noreply, assign(socket, reading: preview)}

  def handle_async(:reading, _failed, socket), do: {:noreply, socket}

  # -- events ---------------------------------------------------------------------

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = if socket.assigns.selected == id, do: nil, else: id
    {:noreply, assign(socket, selected: selected)}
  end

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, selected: nil)}

  def handle_event("accept", %{"id" => id}, socket) do
    entry = find(socket, String.to_integer(id))
    {:noreply, decide(socket, entry, entry.question.proposal.label)}
  end

  def handle_event("choose", %{"id" => id, "label" => label}, socket),
    do: {:noreply, decide(socket, find(socket, String.to_integer(id)), label)}

  def handle_event("accept_group", %{"section" => section}, socket) do
    entries =
      for e <- open(socket.assigns), to_string(e.question.section.id) == section, firm?(e), do: e

    socket = Enum.reduce(entries, socket, &decide(&2, &1, &1.question.proposal.label, false))
    {:noreply, put_flash(socket, :info, "Accepted #{length(entries)} proposed answers")}
  end

  def handle_event("filter", %{"f" => f}, socket), do: {:noreply, assign(socket, filter: f)}

  def handle_event("stage", %{"id" => id}, socket),
    do: {:noreply, assign(socket, stage: String.to_existing_atom(id), skipped: [])}

  def handle_event("hedges", _params, socket),
    do: {:noreply, assign(socket, hedges?: !socket.assigns.hedges?, mode: "focus")}

  def handle_event("mode", %{"m" => m}, socket),
    do: {:noreply, assign(socket, mode: m, selected: nil)}

  def handle_event("skip", %{"key" => key}, socket),
    do: {:noreply, assign(socket, skipped: (socket.assigns.skipped -- [key]) ++ [key])}

  # A batch's proposals taken one by one, or one of them taken out of it.
  def handle_event("one_by_one", %{"ids" => ids}, socket) do
    ids = ids |> String.split(",") |> Enum.map(&String.to_integer/1)
    {:noreply, assign(socket, singled: MapSet.union(socket.assigns.singled, MapSet.new(ids)))}
  end

  def handle_event("not_this", %{"id" => id}, socket) do
    id = String.to_integer(id)
    toggle = fn set -> if id in set, do: MapSet.delete(set, id), else: MapSet.put(set, id) end
    {:noreply, update(socket, :singled, toggle)}
  end

  # A Gall's answer in a per-Gall Trait question: keep the words as text, or
  # map them to values (starting from the pipeline's suggestion).
  def handle_event("pick_mode", %{"id" => id, "ref" => ref, "mode" => mode} = params, socket) do
    next =
      case {mode, default_pick(params["default"] || "")} do
        {"text", _} -> :text
        {"values", %MapSet{} = suggested} -> suggested
        {"values", _} -> MapSet.new()
      end

    {:noreply, update(socket, :picks, &Map.put(&1, {String.to_integer(id), ref}, next))}
  end

  # `v`, not `value`: a checkbox's click sends its own value ("on") as `value`.
  def handle_event("pick_value", %{"id" => id, "ref" => ref, "v" => value} = params, socket) do
    key = {String.to_integer(id), ref}
    current = Map.get(socket.assigns.picks, key) || default_pick(params["default"] || "")

    toggle = fn
      %MapSet{} = set ->
        if value in set, do: MapSet.delete(set, value), else: MapSet.put(set, value)

      _ ->
        MapSet.new([value])
    end

    {:noreply, update(socket, :picks, &Map.put(&1, key, toggle.(current)))}
  end

  def handle_event("accept_batch", %{"ids" => ids}, socket) do
    ids = ids |> String.split(",") |> Enum.map(&String.to_integer/1) |> MapSet.new()
    entries = Enum.filter(open(socket.assigns), &(&1.item.id in ids))
    socket = Enum.reduce(entries, socket, &decide(&2, &1, &1.question.proposal.label, false))
    {:noreply, put_flash(socket, :info, "Accepted #{length(entries)} proposed answers")}
  end

  def handle_event("toggle_gall", %{"key" => key}, socket) do
    open = socket.assigns.open_galls
    open = if key in open, do: MapSet.delete(open, key), else: MapSet.put(open, key)
    {:noreply, assign(socket, open_galls: open)}
  end

  def handle_event("toggle_set_aside", _params, socket),
    do: {:noreply, assign(socket, set_aside_open?: !socket.assigns.set_aside_open?)}

  defp find(socket, id), do: Enum.find(socket.assigns.entries, &(&1.item.id == id))

  # The next open question in the list after `entry`, so deciding moves on.
  defp decide(socket, entry, label, advance? \\ true) do
    rest = open(socket.assigns) |> Enum.reject(&(&1.item.id == entry.item.id))
    next = if advance?, do: next_after(socket.assigns, entry, rest)

    socket
    |> assign(decided: Map.put(socket.assigns.decided, entry.item.id, label), selected: next)
    |> put_flash(:info, "Decided: #{label}")
  end

  defp next_after(assigns, entry, rest) do
    order = Enum.map(to_decide(assigns), & &1.item.id)
    i = Enum.find_index(order, &(&1 == entry.item.id)) || 0
    ids = MapSet.new(rest, & &1.item.id)
    Enum.find(Enum.drop(order, i + 1), &(&1 in ids))
  end

  # -- the questions ----------------------------------------------------------------

  defp open(assigns),
    do:
      Enum.filter(
        assigns.entries,
        &(&1.item.status == :open and not Map.has_key?(assigns.decided, &1.item.id))
      )

  defp set_aside?(e), do: e.question.section.id in @set_aside

  defp to_decide(assigns),
    do: assigns |> open() |> Enum.reject(&set_aside?/1) |> Enum.sort_by(&order/1)

  defp set_aside(assigns), do: assigns |> open() |> Enum.filter(&set_aside?/1)

  defp order(e) do
    id = Steps.step_of(e.question.section.id)
    step = Enum.find(Steps.all(), &(&1.id == id))
    {(step && step.n) || 9, e.question.section.title}
  end

  defp groups(entries),
    do:
      entries
      |> Enum.chunk_by(& &1.question.section.id)
      |> Enum.map(&{hd(&1).question.section, &1})

  defp proposed_choice?(%{question: %{proposal: %{decision: d}}}, %{decision: d}) when d != nil,
    do: true

  defp proposed_choice?(_entry, _choice), do: false

  defp firm?(%{question: %{proposal: %{firm: true}}}), do: true
  defp firm?(_e), do: false

  defp confidence(%{question: %{proposal: %{firm: true}}}), do: :proposed
  defp confidence(%{question: %{proposal: %{}}}), do: :check
  defp confidence(_e), do: :none

  # -- the work, one unit at a time (focus mode) ------------------------------------------

  # Each group's firm proposals as one batch (two or more), then each question
  # that needs the curator; skipped units go to the end.
  defp units(assigns) do
    units =
      for {section, entries} <- groups(to_decide(assigns)),
          {batch, rest} = Enum.split_with(entries, &batchable?/1),
          {singled, active} = Enum.split_with(batch, &(&1.item.id in assigns.singled)),
          unit <-
            if(length(batch) >= 2 and active != [],
              do: [{:batch, section, batch}] ++ Enum.map(singled, &{:one, section, &1}),
              else: Enum.map(batch, &{:one, section, &1})
            ) ++ Enum.map(rest, &{:one, section, &1}),
          do: unit

    # A stage chosen in the rail comes first; the rest keep their order.
    units =
      if assigns.stage,
        do: Enum.sort_by(units, &(Steps.step_of(elem(&1, 1).id) != assigns.stage)),
        else: units

    {skipped, rest} = Enum.split_with(units, &(unit_key(&1) in assigns.skipped))

    rest ++
      Enum.sort_by(skipped, &Enum.find_index(assigns.skipped, fn k -> k == unit_key(&1) end))
  end

  # A firm proposal, but never "create a new Gall": a Gall the matcher missed
  # would be created twice (Nastasi & Davis's toothed rosinweed gall).
  # Nor "it depends on the Gall": that isn't an answer until each Gall has its value.
  defp batchable?(e), do: firm?(e) and not create_new?(e) and not per_gall?(e)
  defp per_gall?(e), do: String.starts_with?(e.question.proposal.label, "It depends")
  defp create_new?(e), do: String.starts_with?(e.question.proposal.label, "Create it")

  # One count for every view: questions settled and left (what was set aside
  # is counted apart: it stays out unless stated).
  defp tally(assigns) do
    left = to_decide(assigns)
    done = map_size(assigns.decided)

    %{
      done: done,
      left: length(left),
      total: done + length(left),
      holding: Enum.count(left, & &1.holds),
      set_aside: length(set_aside(assigns))
    }
  end

  defp unit_key({:batch, section, _}), do: "batch-#{section.id}"
  defp unit_key({:one, _section, e}), do: "q-#{e.item.id}"

  defp ids(entries), do: Enum.map_join(entries, ",", & &1.item.id)

  # The pipeline's stages, each done, current or to come.
  defp stages(assigns, current) do
    left = assigns |> to_decide() |> Enum.frequencies_by(&Steps.step_of(&1.question.section.id))
    current_step = current && Steps.step_of(elem(current, 1).id)

    for step <- Steps.all(), step.id != :hedges do
      n = Map.get(left, step.id, 0)

      state =
        cond do
          step.id == current_step -> :current
          n > 0 -> :todo
          true -> :done
        end

      {step.id, step.title, state, n}
    end
  end

  # The Facts in the reading that wait on question `id`, with their Gall.
  defp waiting_on(nil, _id), do: []

  defp waiting_on(reading, id) do
    for g <- reading.galls, decides?(g, id) do
      {g, Enum.filter(all_facts(g), &match?(%{id: ^id}, &1.question))}
    end
  end

  # -- the reading ---------------------------------------------------------------------

  defp galls(nil), do: []
  defp galls(reading), do: reading.galls

  defp facts(gall) do
    for {category, entries} <- gall.facts, category != :traits, e <- entries, do: e
  end

  defp trait_facts(gall),
    do: for({_trait, entries} <- Map.get(gall.facts, :traits, %{}), e <- entries, do: e)

  defp all_facts(gall), do: facts(gall) ++ trait_facts(gall)

  defp counts(gall), do: Enum.frequencies_by(all_facts(gall), & &1.status)

  # The Galls question `id` decides: the Gall itself waits on it, or one of its Facts.
  defp decides?(gall, id),
    do:
      match?(%{id: ^id}, gall.question) or
        Enum.any?(all_facts(gall), &match?(%{id: ^id}, &1.question))

  defp waiting?(gall), do: gall.question != nil or Map.get(counts(gall), :waiting, 0) > 0
  defp conflict?(gall), do: Map.get(counts(gall), :conflict, 0) > 0

  defp shown(galls, nil, "needs"), do: Enum.filter(galls, &(waiting?(&1) or conflict?(&1)))
  defp shown(galls, nil, "new"), do: Enum.filter(galls, &(Map.get(counts(&1), :new, 0) > 0))
  defp shown(galls, nil, _all), do: galls
  defp shown(galls, id, _filter), do: Enum.filter(galls, &decides?(&1, id))

  defp fact_label(%{kind: :relationship, value: v}) do
    [v[:subject], v[:object]]
    |> Enum.find(&(is_map(&1) and is_binary(&1[:name]) and not Map.has_key?(&1, :gall_id)))
    |> case do
      %{name: name} -> name
      _ -> v[:label] || "relationship"
    end
  end

  defp fact_label(%{kind: :trait, value: v}), do: "#{v[:trait]}: #{v[:value]}"
  defp fact_label(%{kind: :occurrence, value: v}), do: "recorded in #{place(v)}"
  defp fact_label(%{kind: :range, value: v}), do: "#{v[:adjustment] || "in"} #{place(v)}"
  defp fact_label(%{kind: :alias, value: v}), do: "“#{v[:name]}”"
  defp fact_label(%{kind: :description}), do: "a description"
  defp fact_label(%{kind: kind}), do: to_string(kind)

  defp place(%{place: %{name: name}}) when is_binary(name), do: name
  defp place(_v), do: "?"

  defp gkey(gall), do: inspect(gall.key)

  defp gall_title(gall), do: gall.name || gall.name_as_written || "A Gall"

  # -- the page ---------------------------------------------------------------------

  @impl true
  def render(%{mode: "focus"} = assigns), do: focus(assigns)

  def render(assigns) do
    assigns =
      assign(assigns,
        to_decide: to_decide(assigns),
        set_aside: set_aside(assigns),
        tally: tally(assigns),
        current: Enum.find(assigns.entries, &(&1.item.id == assigns.selected)),
        galls: galls(assigns.reading)
      )

    assigns =
      assign(assigns,
        shown: shown(assigns.galls, assigns.selected, assigns.filter),
        holding: assigns.tally.holding
      )

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={"Reviewing " <> @name}>
      <div class="flex flex-col gap-block">
        <.notice kind={:warn} title="Mockup: a Source's review as one view">
          Real: this package's questions, its reading (the approval's dry run) and which Facts wait on which question.
          Not real: deciding (kept on this page; the reading isn't recomputed), notes, search, Approve.
          PROPOSED: the status bar, question rows with Accept, the reading index, the question inspector.
        </.notice>

        <.segmented_switch label="View" value={@mode} event="mode" param="m" class="self-start">
          <:option value="focus">One at a time</:option>
          <:option value="all">Everything</:option>
        </.segmented_switch>

        <%!-- PROPOSED: the Source's status bar: what it is, what's left, Approve with its reason --%>
        <section class="sticky top-0 z-30 flex flex-wrap items-center gap-x-6 gap-y-2 rounded-panel border border-line bg-surface p-panel">
          <div class="min-w-0 flex-1">
            <p class="truncate text-ui text-ink-2" title={@summary.title}>{@summary.title}</p>
            <p class="text-meta text-muted">
              {@summary.kind} · {@stats.galls} Galls · {@stats.facts} statements · {@stats.acts} taxonomic acts
            </p>
          </div>
          <div class="flex w-56 flex-col gap-1">
            <p class="text-meta text-ink-2">
              <span class="font-semibold text-ink tabular-nums">{@tally.done}</span>
              of {@tally.total} answered · {@tally.left} to go ·
              <span class={[@holding > 0 && "font-semibold text-autumn-ink"]}>
                {@holding} needed before you can approve
              </span>
            </p>
            <.progress_bar value={@tally.done} max={max(@tally.total, 1)} />
          </div>
          <div class="flex items-center gap-2">
            <.button
              variant="primary"
              disabled={@holding > 0}
              title={@holding > 0 && "Answer the #{@holding} marked questions first"}
            >
              Approve
            </.button>
            <.button variant="ghost">Deny…</.button>
          </div>
        </section>

        <div class="grid items-start gap-section lg:grid-cols-12">
          <div class="flex min-w-0 flex-col gap-section lg:col-span-8">
            <.section title="To decide" count={length(@to_decide)}>
              <div :for={{section, entries} <- groups(@to_decide)} class="mb-block">
                <div class="flex items-baseline justify-between gap-3 border-b border-line py-1">
                  <h3 class="text-meta font-semibold text-muted">
                    {section.title} <span class="font-normal">{length(entries)}</span>
                    <span
                      :if={section.holds_approval}
                      class="ml-1 inline-block size-2 rounded-full bg-autumn"
                      title="Holds approval"
                    >
                    </span>
                  </h3>
                  <.button
                    :if={Enum.count(entries, &firm?/1) > 1}
                    size="sm"
                    variant="ghost"
                    phx-click="accept_group"
                    phx-value-section={section.id}
                  >
                    Accept the {Enum.count(entries, &firm?/1)} suggested
                  </.button>
                </div>
                <%!-- PROPOSED: a question row: the Source's words, the proposal and its confidence, one-click Accept --%>
                <div
                  :for={e <- entries}
                  class={[
                    "group grid cursor-pointer grid-cols-[1fr_auto] items-center gap-x-3 border-b border-line py-1.5 pl-2 hover:bg-sky-soft",
                    @selected == e.item.id && "bg-sky-soft"
                  ]}
                  phx-click="select"
                  phx-value-id={e.item.id}
                >
                  <div class="flex min-w-0 flex-wrap items-baseline gap-x-2 text-ui">
                    <span class="truncate font-semibold text-ink">
                      {e.question.written || e.question.question}
                    </span>
                    <span class="text-muted">→</span>
                    <span :if={e.question.proposal} class="truncate text-ink-2">
                      {e.question.proposal.label}
                    </span>
                    <span :if={!e.question.proposal} class="italic text-muted">
                      {(e.question.undecided && e.question.undecided.label) || "no proposal"}
                    </span>
                    <span :if={e.question.covers > 1} class="text-meta text-muted">
                      · {e.question.covers} Galls
                    </span>
                  </div>
                  <div class="flex items-center gap-2">
                    <.chip :if={confidence(e) == :proposed} variant={:ok} size="sm">Suggested</.chip>
                    <.chip :if={confidence(e) == :check} variant={:info} size="sm">Best guess</.chip>
                    <.button
                      :if={confidence(e) != :none}
                      size="sm"
                      phx-click="accept"
                      phx-value-id={e.item.id}
                    >
                      Accept
                    </.button>
                    <span :if={confidence(e) == :none} class="text-meta text-link">Answer…</span>
                  </div>
                </div>
              </div>
              <p :if={@to_decide == []} class="text-ui text-ink-2">Nothing left to decide.</p>
            </.section>

            <.section title="The reading" count={length(@galls)}>
              <:aside>
                <span class="text-meta text-muted">what approving writes, by Gall</span>
              </:aside>
              <%!-- PROPOSED: the reading as an index of Galls: one line each, filtered, opened on demand --%>
              <div :if={@selected} class="mb-2 text-meta text-ink-2">
                Showing the {if length(@shown) == 1, do: "Gall", else: "#{length(@shown)} Galls"} this question decides.
                <button type="button" class="text-link hover:underline" phx-click="close">
                  Show all
                </button>
              </div>
              <div :if={!@selected} class="mb-2 flex flex-wrap gap-2">
                <.filter_chip f="needs" filter={@filter} n={length(shown(@galls, nil, "needs"))}>
                  Waiting or in conflict
                </.filter_chip>
                <.filter_chip f="new" filter={@filter} n={length(shown(@galls, nil, "new"))}>
                  With new Facts
                </.filter_chip>
                <.filter_chip f="all" filter={@filter} n={length(@galls)}>All</.filter_chip>
              </div>
              <p :if={@reading == nil} class="text-ui text-muted">
                Working out what approving writes…
              </p>
              <div :for={g <- @shown} class="border-b border-line">
                <button
                  type="button"
                  phx-click="toggle_gall"
                  phx-value-key={gkey(g)}
                  class="flex w-full items-center gap-3 py-1.5 text-left text-ui hover:bg-sky-soft"
                >
                  <.icon
                    name={if gkey(g) in @open_galls, do: "ph-caret-down", else: "ph-caret-right"}
                    class="size-3.5 text-muted"
                  />
                  <span class="min-w-0 flex-1 truncate">
                    <.gall_name :if={g.gall_id} name={gall_title(g)} />
                    <span :if={!g.gall_id}>{gall_title(g)}</span>
                  </span>
                  <span :if={g.new} class="text-meta text-muted">new Gall</span>
                  <.status_counts counts={counts(g)} />
                </button>
                <div :if={gkey(g) in @open_galls} class="flex flex-col gap-0.5 pb-2 pl-7">
                  <p
                    :for={f <- all_facts(g)}
                    class={[
                      "flex items-baseline gap-2 text-meta",
                      f.status == :dropped && "line-through text-muted"
                    ]}
                  >
                    <span class="w-14 shrink-0 text-muted">{f.category}</span>
                    <span class="text-ink">{fact_label(f)}</span>
                    <.status_chip status={f.status} />
                    <span :if={f.question} class="text-autumn-ink">waits on a question</span>
                  </p>
                </div>
              </div>
            </.section>

            <section>
              <button
                type="button"
                phx-click="toggle_set_aside"
                class="flex w-full items-baseline gap-2 border-b border-line-strong pb-1 text-left"
              >
                <.icon
                  name={if @set_aside_open?, do: "ph-caret-down", else: "ph-caret-right"}
                  class="size-3.5 text-muted"
                />
                <span class="font-brand text-section text-ink">Set aside</span>
                <span class="text-meta text-muted">{length(@set_aside)}</span>
                <span class="ml-auto text-meta text-muted">
                  left out because the Source hedges them; add any that should go in
                </span>
              </button>
              <div :if={@set_aside_open?} class="flex flex-col">
                <p :for={e <- @set_aside} class="border-b border-line py-1 text-ui text-ink-2">
                  {e.question.written || e.question.question}
                  <span class="text-meta text-muted">· {e.question.section.title}</span>
                </p>
              </div>
            </section>
          </div>

          <%!-- PROPOSED: the question inspector, the Fact inspector's question state --%>
          <aside class="flex flex-col gap-block lg:sticky lg:top-24 lg:col-span-4">
            <p :if={!@current} class="text-meta text-muted">
              Pick a question to see the evidence and the answers here. The list below then shows just the Galls it affects.
            </p>
            <section
              :if={@current}
              id="question-inspector"
              class="fixed inset-x-0 bottom-0 z-40 flex max-h-[70vh] flex-col gap-3 overflow-y-auto rounded-t-panel border-t border-line bg-surface p-panel shadow-float lg:static lg:max-h-[calc(100vh-8rem)] lg:rounded-panel lg:border lg:shadow-none"
            >
              <div class="flex items-center justify-between">
                <span class="text-meta font-semibold text-muted">
                  {@current.question.section.title}
                </span>
                <.button
                  size="sm"
                  variant="ghost"
                  icon="ph-x"
                  icon_only
                  label="Close"
                  phx-click="close"
                />
              </div>
              <p class="font-brand text-subsection text-ink">{@current.question.question}</p>
              <p :if={@current.question.scope} class="text-meta text-ink-2">
                {@current.question.scope}
              </p>
              <blockquote
                :for={q <- Enum.take(@current.quotes, 2)}
                class="border-l-2 border-line-strong pl-3 font-serif text-meta text-ink-2"
              >
                <span class="line-clamp-4">“{q.text}”</span>
                <span :if={q.where} class="block font-sans text-caption text-muted">{q.where}</span>
              </blockquote>

              <div class="flex flex-col gap-2">
                <div
                  :for={c <- @current.question.choices}
                  class={[
                    "flex items-start justify-between gap-3 rounded-ctl border p-2",
                    proposed_choice?(@current, c) &&
                      "border-brand",
                    !proposed_choice?(@current, c) &&
                      "border-line"
                  ]}
                >
                  <div class="flex min-w-0 flex-col">
                    <span class="text-ui text-ink">{c.label}</span>
                    <span :if={c.hint} class="text-meta text-muted">{c.hint}</span>
                  </div>
                  <.button
                    size="sm"
                    variant={
                      if proposed_choice?(@current, c),
                        do: "primary",
                        else: "default"
                    }
                    phx-click="choose"
                    phx-value-id={@current.item.id}
                    phx-value-label={c.label}
                  >
                    {if c.picker, do: "Search…", else: "Use this"}
                  </.button>
                </div>
              </div>

              <p :if={@current.question.leave} class="text-meta text-muted">
                Left open: {@current.question.leave}
              </p>
              <div class="flex gap-4 border-t border-line pt-2 text-meta">
                <button type="button" class="text-link hover:underline">Add a note…</button>
                <button type="button" class="text-link hover:underline">Read the Source</button>
                <details class="ml-auto text-muted">
                  <summary class="cursor-pointer">Details</summary>
                  <p class="mt-1 whitespace-pre-wrap text-caption">{@current.question.technical}</p>
                </details>
              </div>
            </section>
          </aside>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  # PROPOSED: the review one unit at a time, in the admin shell at the Reading
  # sizes (`gf-density-reading`).
  defp focus(assigns) do
    units = units(assigns)
    unit = List.first(units)

    assigns =
      assign(assigns,
        unit: unit,
        next: units |> Enum.drop(1) |> Enum.take(3),
        stages: stages(assigns, unit),
        tally: tally(assigns)
      )

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={"Reviewing " <> @name}>
      <div class="gf-density-reading grid items-start gap-section pb-section lg:grid-cols-12">
        <div class="flex min-w-0 flex-col gap-block lg:col-span-8">
          <.segmented_switch label="View" value={@mode} event="mode" param="m" class="self-start">
            <:option value="focus">One at a time</:option>
            <:option value="all">Everything</:option>
          </.segmented_switch>

          <.notice kind={:warn} title="Mockup: the review, one thing at a time">
            The same questions and reading as "Everything", one unit of work at a time. Deciding is kept on this page only.
          </.notice>

          <.hedges_panel :if={@hedges?} entries={set_aside(assigns)} />
          <.batch_unit
            :if={!@hedges? and match?({:batch, _, _}, @unit)}
            unit={@unit}
            singled={@singled}
            stages={@stages}
          />
          <.trait_unit
            :if={
              !@hedges? and match?({:one, %{id: :trait_terms}, %{question: %{galls: [_ | _]}}}, @unit)
            }
            unit={@unit}
            picks={@picks}
            vocab={@definitions}
          />
          <.question_unit
            :if={
              !@hedges? and match?({:one, _, _}, @unit) and
                not match?({:one, %{id: :trait_terms}, %{question: %{galls: [_ | _]}}}, @unit)
            }
            unit={@unit}
            reading={@reading}
          />

          <section
            :if={!@hedges? and @unit == nil}
            class="flex flex-col gap-3 rounded-panel border border-line bg-surface p-6"
          >
            <h2 class="font-brand text-section text-ink">All answered</h2>
            <p class="text-body text-ink-2">
              Have a look at what approving will add, then approve it.
            </p>
          </section>
        </div>

        <%!-- PROPOSED: the review's status rail: where you are, the stages to move between, what's next --%>
        <aside class="flex flex-col gap-4 rounded-panel border border-line bg-surface p-panel lg:sticky lg:top-4 lg:col-span-4">
          <div class="flex flex-col gap-1">
            <p class="text-ui text-ink-2">{@summary.title}</p>
            <p class="text-body text-ink">
              <span class="font-semibold tabular-nums">{@tally.done}</span> of {@tally.total} answered
            </p>
            <.progress_bar value={@tally.done} max={max(@tally.total, 1)} />
            <p class="text-meta text-ink-2">
              {@tally.left} to go.<span :if={@tally.holding > 0}>
                <span class="text-autumn-ink">{@tally.holding} of them</span> must be answered before you can approve.
              </span>
            </p>
          </div>

          <nav aria-label="Stages" class="flex flex-col">
            <button
              :for={{id, title, state, left} <- @stages}
              type="button"
              phx-click="stage"
              phx-value-id={id}
              disabled={left == 0}
              aria-current={state == :current && "step"}
              class={[
                "flex items-center gap-2 rounded-ctl px-2 py-1.5 text-left text-ui",
                state == :current && "bg-sky-soft font-semibold text-ink",
                state == :todo && "text-ink-2 hover:bg-surface-2",
                state == :done && "text-ok"
              ]}
            >
              <.icon :if={state == :done} name="ph-check" class="size-4" />
              <span :if={state == :current} class="inline-block size-2 rounded-full bg-autumn"></span>
              <span
                :if={state == :todo}
                class="inline-block size-2 rounded-full border border-line-strong"
              >
              </span>
              <span class="flex-1">{title}</span>
              <span class="text-meta tabular-nums text-muted">
                {if left == 0, do: "done", else: "#{left} left"}
              </span>
            </button>
          </nav>

          <button
            type="button"
            phx-click="hedges"
            class="text-left text-meta text-link hover:underline"
          >
            {@tally.set_aside} hedged statements were left out. Review them
          </button>

          <div :if={@next != []} class="flex flex-col gap-1 border-t border-line pt-3">
            <p class="text-meta text-muted">Up next</p>
            <p :for={u <- @next} class="text-meta text-ink-2">{unit_line(u)}</p>
          </div>

          <div class="flex flex-col gap-1 border-t border-line pt-3">
            <div><.button variant="primary" disabled={@tally.holding > 0}>Approve</.button></div>
            <p :if={@tally.holding > 0} class="text-meta text-muted">
              You can approve once the {@tally.holding} marked questions are answered.
            </p>
          </div>
        </aside>
      </div>
    </Layouts.admin>
    """
  end

  attr :entries, :list, required: true

  # PROPOSED: the hedged statements the Source's review left out, to look over.
  defp hedges_panel(assigns) do
    assigns = assign(assigns, groups: Enum.group_by(assigns.entries, & &1.question.section.title))

    ~H"""
    <section class="flex flex-col gap-4 rounded-panel border border-line bg-surface p-6">
      <div class="flex items-baseline justify-between gap-3">
        <h2 class="font-brand text-section text-ink">Hedged statements</h2>
        <button type="button" class="text-ui text-link hover:underline" phx-click="hedges">
          Back to the questions
        </button>
      </div>
      <p class="text-body text-ink-2">
        The Source hedges these (“may”, “possibly”, “presumed”), so we left them out. Add any you think should go in.
      </p>
      <div :for={{title, entries} <- @groups} class="flex flex-col">
        <h3 class="border-b border-line pb-1 text-meta font-semibold text-muted">
          {title} <span class="font-normal">{length(entries)}</span>
        </h3>
        <div
          :for={e <- entries}
          class="flex items-baseline justify-between gap-3 border-b border-line py-2"
        >
          <span class="min-w-0 text-body text-ink">{e.question.written || e.question.question}</span>
          <button type="button" class="shrink-0 text-meta text-link hover:underline">Add it…</button>
        </div>
      </div>
    </section>
    """
  end

  defp unit_line({:batch, s, es}), do: "#{s.title}: #{length(es)} suggested answers to look over"
  defp unit_line({:one, s, e}), do: "#{s.title}: #{e.question.written || e.question.question}"

  # What a waiting Fact is, before the answer names it.
  defp decides_label(%{category: :hosts}), do: "its Host"
  defp decides_label(%{category: :inducer}), do: "its Inducer"

  defp decides_label(%{category: :traits, value: %{trait: t}}),
    do: "its #{String.replace(t, "_", " ")}"

  defp decides_label(%{category: :range}), do: "its range"
  defp decides_label(%{category: :aliases}), do: "a common name"
  defp decides_label(%{category: c}), do: "its #{c}"

  attr :unit, :any, required: true
  attr :singled, :any, required: true
  attr :stages, :list, required: true

  # One unit: a group's firm proposals to look over and accept together.
  defp batch_unit(assigns) do
    {:batch, section, entries} = assigns.unit
    active = Enum.reject(entries, &(&1.item.id in assigns.singled))
    step = Steps.step_of(section.id)
    {_id, stage, _state, in_stage} = Enum.find(assigns.stages, &(elem(&1, 0) == step))

    assigns =
      assign(assigns,
        section: section,
        entries: entries,
        active: active,
        stage: stage,
        in_stage: in_stage,
        others: in_stage - length(entries)
      )

    ~H"""
    <section class="flex flex-col gap-4 rounded-panel border border-line bg-surface p-6">
      <p class="text-meta font-semibold text-muted">{@section.title}</p>
      <h2 class="font-brand text-section text-ink text-wrap">
        {length(@entries)} of the {@in_stage} {@stage} questions have suggested answers
      </h2>
      <p class="text-body text-ink-2">
        They look right to us. Untick any you want to check yourself.
        <span :if={@others > 0}>
          After these, the other {@others} come up one at a time, along with any you untick.
        </span>
      </p>
      <ul class="flex flex-col">
        <li :for={e <- @entries} class="border-b border-line">
          <label class="flex cursor-pointer items-baseline gap-3 py-2 text-body">
            <input
              type="checkbox"
              class="gf-checkbox shrink-0 translate-y-0.5"
              checked={e.item.id not in @singled}
              phx-click="not_this"
              phx-value-id={e.item.id}
            />
            <span class={["min-w-0", e.item.id in @singled && "text-muted"]}>
              <span :if={e.question.trait} class="text-muted">{e.question.trait}: </span>
              <span class={if e.item.id in @singled, do: "text-muted", else: "text-ink"}>
                {e.question.written || e.question.question}
              </span>
              <span class="text-muted"> → </span>
              <span class="text-ink-2">{e.question.proposal.label}</span>
              <span :if={e.question.covers > 1} class="text-meta text-muted">
                ({e.question.covers} Galls)
              </span>
            </span>
          </label>
        </li>
      </ul>
      <div class="flex flex-wrap items-center gap-3">
        <.button
          variant="primary"
          phx-click="accept_batch"
          phx-value-ids={ids(@active)}
          disabled={@active == []}
        >
          {if length(@active) == length(@entries),
            do: "Accept all #{length(@active)}",
            else: "Accept the #{length(@active)} ticked"}
        </.button>
        <button
          type="button"
          class="ml-auto text-ui text-link hover:underline"
          phx-click="skip"
          phx-value-key={unit_key(@unit)}
        >
          Skip for now
        </button>
      </div>
    </section>
    """
  end

  attr :unit, :any, required: true
  attr :reading, :any, required: true

  # One unit: a question that needs the curator.
  defp question_unit(assigns) do
    {:one, section, e} = assigns.unit

    assigns =
      assign(assigns,
        section: section,
        e: e,
        decides: waiting_on(assigns.reading, e.item.id),
        choices: choices(section, e),
        same_genus: same_genus(section, e)
      )

    ~H"""
    <section class="flex flex-col gap-4 rounded-panel border border-line bg-surface p-6">
      <p class="flex items-center gap-2 text-meta font-semibold text-muted">
        {@section.title}
        <span :if={@e.holds} class="font-normal text-autumn-ink">
          · needed before you can approve
        </span>
      </p>

      <%!-- What it decides, first: what this question is about --%>
      <div :if={@decides != []} class="flex flex-col gap-0.5 rounded-ctl bg-surface-2 px-3 py-2">
        <p class="text-meta text-muted">Affects</p>
        <p :for={{g, facts} <- @decides} class="text-ui">
          <span class="text-ink">
            <.gall_name :if={g.gall_id} name={gall_title(g)} />
            <span :if={!g.gall_id}>{gall_title(g)}</span>
          </span>
          <span class="text-muted">
            · {if facts == [],
              do: "the Gall itself",
              else: facts |> Enum.map(&decides_label/1) |> Enum.uniq() |> Enum.join(", ")}
          </span>
        </p>
      </div>

      <h2 class="font-brand text-section text-ink text-wrap">{@e.question.question}</h2>
      <p :if={@e.question.scope} class="text-body text-ink-2">{@e.question.scope}</p>
      <blockquote
        :for={q <- Enum.take(@e.quotes, 2)}
        class="border-l-2 border-line-strong pl-4 font-serif text-body text-ink-2"
      >
        “{q.text}” <span :if={q.where} class="block font-sans text-meta text-muted">{q.where}</span>
      </blockquote>

      <%!-- PROPOSED: an undescribed Gall's likely matches, so "create new" is never the easy answer --%>
      <div :if={@same_genus != []} class="flex flex-col gap-2">
        <p class="text-body text-ink">Is it one of these Galls we already have?</p>
        <div
          :for={{id, name, hint} <- @same_genus}
          class={[
            "flex items-center justify-between gap-4 rounded-ctl border p-3",
            if(hint, do: "border-brand", else: "border-line")
          ]}
        >
          <span class="flex min-w-0 flex-col">
            <span class="text-body text-ink"><.gall_name name={name} undescribed /></span>
            <span class="text-meta text-muted">{name}</span>
            <span :if={hint} class="text-meta text-ink-2">{hint}</span>
          </span>
          <.button
            variant={if hint, do: "primary", else: "default"}
            phx-click="choose"
            phx-value-id={@e.item.id}
            phx-value-label={"It's Gall #{id}"}
          >
            It's this one
          </.button>
        </div>
      </div>

      <div class="flex flex-col gap-2">
        <p :if={@same_genus != []} class="text-body text-ink">If not:</p>
        <div
          :for={c <- @choices}
          class={[
            "flex items-center justify-between gap-4 rounded-ctl border p-3",
            if(proposed_choice?(@e, c) and @same_genus == [], do: "border-brand", else: "border-line")
          ]}
        >
          <div class="flex min-w-0 flex-col">
            <span class="text-body text-ink">
              {c.label}
              <.chip
                :if={proposed_choice?(@e, c)}
                variant={if firm?(@e) and @same_genus == [], do: :ok, else: :info}
                size="sm"
              >
                {if firm?(@e) and @same_genus == [], do: "Suggested", else: "Best guess"}
              </.chip>
            </span>
            <span :if={c.hint} class="text-meta text-muted">{c.hint}</span>
          </div>
          <.link
            :if={Map.get(c, :add)}
            href={c.add}
            target="_blank"
            class="inline-flex h-ctl shrink-0 items-center rounded-ctl border border-line-strong bg-surface px-3 text-ui text-ink hover:no-underline"
          >
            Add… ↗
          </.link>
          <.button
            :if={!Map.get(c, :add)}
            variant={if proposed_choice?(@e, c) and @same_genus == [], do: "primary", else: "default"}
            phx-click={if c.picker, do: nil, else: "choose"}
            phx-value-id={@e.item.id}
            phx-value-label={c.label}
          >
            {if c.picker, do: "Search…", else: "Use this"}
          </.button>
        </div>
      </div>
      <div class="flex flex-wrap items-center gap-4 text-ui">
        <button type="button" class="text-link hover:underline">Add a note…</button>
        <button type="button" class="text-link hover:underline">Read the Source</button>
        <button
          type="button"
          class="ml-auto text-link hover:underline"
          phx-click="skip"
          phx-value-key={unit_key(@unit)}
        >
          Skip for now
        </button>
      </div>
    </section>
    """
  end

  # A Host the Source names and nothing matches: search, add, or leave out,
  # in that order. (Matter f14c built "Create a new plant ↗"; here it is one
  # of the three answers.)
  defp choices(%{id: :hosts}, e) do
    {leave, rest} = Enum.split_with(e.question.choices, &String.starts_with?(&1.label, "Leave"))
    name = e.question.written || ""

    add = %{
      label: "Add a new plant",
      hint: "Not in Gallformers or WCVP? Add it, then search for it here.",
      picker: nil,
      decision: nil,
      add: "/admin/taxonomy/new?name=#{URI.encode_www_form(name)}"
    }

    rest ++ [add] ++ leave
  end

  defp choices(_section, e), do: e.question.choices

  # An undescribed Gall's genus ("Antistrophus sp.") and the Galls Gallformers
  # holds of it, a Host the Source names in its text first ("S. dentatum").
  defp same_genus(%{id: :undescribed_galls}, e) do
    import Ecto.Query, only: [from: 2]

    with [_, genus] <- Regex.run(~r/\(([A-Z][a-z]+) spp?\./, e.question.written || "") do
      text = Enum.map_join(e.quotes, " ", & &1.text) <> " " <> (e.question.written || "")

      from(g in Gallformers.Catalog.Gall,
        where: ilike(g.name, ^"#{genus} %"),
        select: {g.id, g.name},
        order_by: g.name
      )
      |> Gallformers.Repo.all()
      |> Enum.filter(fn {_id, name} -> String.match?(name, ~r/^\S+ [a-z]-/) end)
      |> Enum.map(fn {id, name} -> {id, name, host_hint(name, text)} end)
      |> Enum.sort_by(fn {_id, _name, hint} -> if hint, do: 0, else: 1 end)
      |> Enum.take(6)
    else
      _ -> []
    end
  end

  defp same_genus(_section, _e), do: []

  # "Antistrophus s-dentatum-cryptic-stem-gall" and the Source's "(S. dentatum)".
  defp host_hint(name, text) do
    case Regex.run(~r/^\S+ ([a-z])-([a-z]+)-/, name) do
      [_, initial, epithet] ->
        if String.contains?(String.downcase(text), "#{initial}. #{epithet}"),
          do: "Same host as the Source names (#{String.upcase(initial)}. #{epithet})",
          else: nil

      _ ->
        nil
    end
  end

  attr :unit, :any, required: true
  attr :picks, :map, required: true
  attr :vocab, :map, required: true

  # PROPOSED: a Trait term decided Gall by Gall. For each Gall: what the
  # pipeline made of it, then two choices, keep the words as text or map them
  # to any number of the Trait's values.
  defp trait_unit(assigns) do
    {:one, section, e} = assigns.unit
    trait = e.question.trait || ""
    all = assigns.vocab |> Map.get(trait, %{}) |> Map.keys() |> Enum.sort()
    n = length(e.question.galls)
    picks = Map.new(e.question.galls, &{&1.ref, picked(assigns.picks, e, &1)})

    assigns =
      assign(assigns,
        section: section,
        e: e,
        all: all,
        gall_picks: picks,
        term: e.question.written || "",
        trait: String.replace(trait, "_", " "),
        galls: if(n == 1, do: "this Gall", else: "these #{n} Galls"),
        n: n,
        ready?: Enum.all?(picks, fn {_ref, p} -> p != :none end)
      )

    ~H"""
    <section class="flex flex-col gap-4 rounded-panel border border-line bg-surface p-6">
      <p class="text-meta font-semibold text-muted">{@section.title}</p>
      <h2 class="font-brand text-section text-ink text-wrap">
        What does “{@term}” mean for {@galls}?
      </h2>

      <div :for={g <- @e.question.galls} class="flex flex-col gap-3 border-t border-line pt-4">
        <% pick = @gall_picks[g.ref] %>
        <% producer = producer_values(g, @all) %>
        <% suggested = suggested_values(g.default) ++ producer %>
        <p class="text-body font-semibold text-ink">{g.name}</p>
        <blockquote
          :for={q <- Enum.take(g.quotes, 1)}
          class="border-l-2 border-line-strong pl-4 font-serif text-ui text-ink-2"
        >
          “{q.text}”
        </blockquote>
        <p class="text-body text-ink-2">
          {dispute_line(g, producer, @term, @trait) || pipeline_line(g.default, @term, @trait)}
          <details :if={g.said != []} class="inline text-meta text-muted">
            <summary class="inline cursor-pointer text-link">What each AI said</summary>
            <span :for={line <- g.said} class="mt-1 block">{line}</span>
          </details>
        </p>

        <div class="flex flex-col gap-2">
          <label class={[
            "flex cursor-pointer items-start gap-3 rounded-ctl border p-3",
            if(pick == :text, do: "border-brand bg-sky-soft", else: "border-line")
          ]}>
            <input
              type="radio"
              class="mt-1"
              checked={pick == :text}
              phx-click="pick_mode"
              phx-value-id={@e.item.id}
              phx-value-ref={g.ref}
              phx-value-mode="text"
            />
            <span class="flex flex-col">
              <span class="text-body text-ink">Keep “{@term}” as text</span>
              <span class="text-meta text-muted">
                The Gall shows the Source's words. The ID tool can't filter on them.
              </span>
            </span>
          </label>

          <div class={[
            "flex flex-col gap-3 rounded-ctl border p-3",
            if(is_struct(pick, MapSet), do: "border-brand", else: "border-line")
          ]}>
            <label class="flex cursor-pointer items-start gap-3">
              <input
                type="radio"
                class="mt-1"
                checked={is_struct(pick, MapSet)}
                phx-click="pick_mode"
                phx-value-id={@e.item.id}
                phx-value-ref={g.ref}
                phx-value-mode="values"
                phx-value-default={default_param(g.default)}
              />
              <span class="flex flex-col">
                <span class="text-body text-ink">Map it to {@trait} values</span>
                <span class="text-meta text-muted">
                  Tick every value that fits; most Galls take more than one.
                </span>
              </span>
            </label>
            <div
              :if={is_struct(pick, MapSet)}
              class="grid grid-cols-2 gap-x-4 gap-y-1 pl-7 sm:grid-cols-3"
            >
              <label
                :for={v <- Enum.uniq(suggested ++ @all)}
                class="flex cursor-pointer items-center gap-2 text-ui text-ink"
              >
                <input
                  type="checkbox"
                  class="gf-checkbox"
                  checked={v in pick}
                  phx-click="pick_value"
                  phx-value-id={@e.item.id}
                  phx-value-ref={g.ref}
                  phx-value-v={v}
                  phx-value-default={default_param(g.default)}
                />
                {v}
                <span :if={v in suggested} class="text-caption text-muted">suggested</span>
              </label>
            </div>
          </div>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-3 border-t border-line pt-4">
        <.button
          variant="primary"
          disabled={!@ready?}
          phx-click="choose"
          phx-value-id={@e.item.id}
          phx-value-label={"“#{@term}” saved for #{@galls}"}
        >
          Save
        </.button>
        <span :if={!@ready?} class="text-meta text-muted">
          Choose one of the two for each Gall first.
        </span>
        <button
          type="button"
          class="ml-auto text-ui text-link hover:underline"
          phx-click="skip"
          phx-value-key={unit_key(@unit)}
        >
          Skip for now
        </button>
      </div>
    </section>
    """
  end

  # The values of the Trait the producer's reasoning names (`succulent`).
  defp producer_values(%{default: :disputed, producer_text: text}, all),
    do: Enum.filter(all, &String.contains?(text, "`#{&1}`"))

  defp producer_values(_g, _all), do: []

  # A dispute in a sentence: what the producer chose, and the checker's objection.
  defp dispute_line(%{default: :disputed, checker: checker}, [_ | _] = values, term, _trait),
    do:
      "The producer mapped “#{term}” to #{Enum.join(values, ", ")}. A checker disagreed: " <>
        (checker || "")

  defp dispute_line(_g, _values, _term, _trait), do: nil

  # What the pipeline made of the term for one Gall, in a sentence.
  defp pipeline_line(:disputed, term, trait),
    do: "The import pipeline's AIs disagreed about whether “#{term}” is a #{trait} value."

  defp pipeline_line(nil, term, trait),
    do: "The import pipeline couldn't agree how to map “#{term}” to a #{trait} value."

  defp pipeline_line(:text, _term, _trait),
    do: "The import pipeline suggests keeping the words as text."

  defp pipeline_line(default, _term, _trait),
    do: "The import pipeline suggests: #{Enum.join(suggested_values(default), ", ")}."

  defp suggested_values(v) when is_binary(v), do: [v]
  defp suggested_values(vs) when is_list(vs), do: vs
  defp suggested_values(_), do: []

  # A Gall's answer: the curator's, else the pipeline's suggestion, else
  # `:none` (no consensus: the curator must choose).
  defp picked(picks, e, g),
    do: Map.get(picks, {e.item.id, g.ref}) || default_pick(default_param(g.default))

  defp default_param(:text), do: ":text"
  defp default_param(v) when is_binary(v), do: v
  defp default_param(vs) when is_list(vs), do: Enum.join(vs, "|")
  defp default_param(_), do: ""

  defp default_pick(":text"), do: :text
  defp default_pick(nil), do: :none
  defp default_pick(""), do: :none
  defp default_pick(v), do: v |> String.split("|") |> MapSet.new()

  attr :f, :string, required: true
  attr :filter, :string, required: true
  attr :n, :integer, required: true
  slot :inner_block, required: true

  defp filter_chip(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="filter"
      phx-value-f={@f}
      aria-pressed={to_string(@f == @filter)}
      class={[
        "rounded-full border px-3 py-0.5 text-meta",
        if(@f == @filter,
          do: "border-brand bg-brand-fill text-on-fill",
          else: "border-line text-ink-2 hover:border-line-strong"
        )
      ]}
    >
      {render_slot(@inner_block)} <span class="tabular-nums opacity-80">{@n}</span>
    </button>
    """
  end

  attr :counts, :map, required: true

  defp status_counts(assigns) do
    ~H"""
    <span class="flex shrink-0 items-center gap-2 text-meta tabular-nums">
      <span :if={@counts[:waiting]} class="text-autumn-ink">{@counts[:waiting]} waiting</span>
      <span :if={@counts[:conflict]} class="text-warn">{@counts[:conflict]} conflict</span>
      <span :if={@counts[:new]} class="text-ok">{@counts[:new]} new</span>
      <span :if={@counts[:held]} class="text-muted">{@counts[:held]} held</span>
    </span>
    """
  end

  attr :status, :atom, required: true

  defp status_chip(%{status: :new} = assigns), do: ~H|<.chip variant={:ok} size="sm">new</.chip>|

  defp status_chip(%{status: :held} = assigns),
    do: ~H|<span class="text-caption text-muted">held</span>|

  defp status_chip(%{status: :conflict} = assigns),
    do: ~H|<.chip variant={:warn} size="sm">conflict</.chip>|

  defp status_chip(%{status: :waiting} = assigns), do: ~H|<.chip size="sm">waiting</.chip>|

  defp status_chip(%{status: :dropped} = assigns),
    do: ~H|<span class="text-caption text-muted">dropped</span>|

  defp status_chip(assigns), do: ~H||
end
