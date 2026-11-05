defmodule GallformersWeb.Admin.ReviewLive.Step do
  @moduledoc """
  One step of a Source's review (matter `d213`, Task 15):
  `/admin/review/sources/:id/:step` (or `/admin/review/packages/:id/:step`
  for one package), the step being `names`, `galls`, `disputes`, `traits`
  or `hedges` (`GallformersWeb.Admin.Review.Steps`).

  The page shows the step bar (`GallformersWeb.ReviewComponents.review_step_bar/1`,
  with Approve once nothing holds approval), which step it is and whether
  it holds approval, a panel once it is settled, its sections of questions
  in order (each row a `GallformersWeb.Admin.ReviewLive.ItemRow`, decided
  ones too, none open), and Previous and Next. On Names and Galls a
  section with firm proposals has "Accept firm matches (N)", which asks
  first, listing each ("<written> → <answer>"). Disputes recommend
  nothing, and Traits accepts nothing together, since a recommended
  category can be wrong. Each Hedges group (by topic) has
  "Leave the rest out (N)", which leaves its open hedges out at once (their
  recommended answer). Disputes says how many disputes about Trait terms
  are on Traits. On Names and Galls the questions get
  what their answers show besides (`Loader.entries/3`). After each decision
  the page loads again: deciding resolves the package again, so questions
  it settles go and ones it calls for appear.

  An unknown step, or the Gallformers notes (which keep their own page),
  goes to the overview.
  """
  use GallformersWeb, :live_view

  import GallformersWeb.ReviewComponents

  alias Gallformers.Import
  alias GallformersWeb.Admin.Review.Steps
  alias GallformersWeb.Admin.ReviewLive.Document
  alias GallformersWeb.Admin.ReviewLive.ItemRow
  alias GallformersWeb.Admin.ReviewLive.Loader
  alias GallformersWeb.Admin.ReviewLive.SourcePage

  @hedge_sections Steps.get("hedges").sections

  @impl true
  def mount(%{"step" => slug} = params, _session, socket) do
    mode = SourcePage.mode(params)
    base = SourcePage.base_path(mode)

    case {Steps.get(slug), notes?(mode)} do
      {%{} = step, false} ->
        {:ok,
         socket
         |> assign(
           mode: mode,
           base: base,
           step: step,
           keep: [],
           closed: MapSet.new(),
           confirm_bulk: nil,
           confirm_approve: false
         )
         |> SourcePage.load()
         |> Document.mount()}

      _ ->
        {:ok, push_navigate(socket, to: base)}
    end
  end

  defp notes?({:source, id}), do: Loader.notes_page(id) != nil
  defp notes?(_mode), do: false

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

  # The Source's text: "Read the Source", its find box and Close (Task 22).
  def handle_event("reader_" <> _ = event, params, socket),
    do: {:noreply, Document.handle_event(event, params, socket)}

  def handle_event("approve_ask", _params, socket),
    do: {:noreply, assign(socket, confirm_approve: true)}

  def handle_event("approve_cancel", _params, socket),
    do: {:noreply, assign(socket, confirm_approve: false)}

  def handle_event("approve", _params, socket) do
    {:noreply,
     socket |> SourcePage.approve() |> assign(confirm_approve: false) |> SourcePage.load()}
  end

  def handle_event("confirm_bulk", %{"section" => section}, socket),
    do:
      {:noreply,
       assign(socket,
         confirm_bulk: section,
         closed: MapSet.delete(socket.assigns.closed, section)
       )}

  def handle_event("cancel_bulk", _params, socket),
    do: {:noreply, assign(socket, confirm_bulk: nil)}

  def handle_event("accept_bulk", %{"section" => section}, socket) do
    entries = Enum.filter(socket.assigns.entries, &(section_key(&1) == section))
    proposable = for e <- entries, e.proposable, do: e.item
    open = Enum.count(entries, &(&1.item.status == :open))

    case Import.accept_proposals(socket.assigns.actor, proposable) do
      {:ok, %{decided: decided}} ->
        n = length(decided)

        {:noreply,
         socket
         |> assign(confirm_bulk: nil)
         |> put_flash(:info, "Accepted #{n} proposed #{answers(n)}. #{stay_open(open - n)}")
         |> SourcePage.load()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(confirm_bulk: nil)
         |> put_flash(:error, "The proposals could not be accepted: #{inspect(reason)}")
         |> SourcePage.load()}
    end
  end

  # A hedge group's open hedges left out, as recommended (d213, Hedges step).
  def handle_event("leave_rest", %{"section" => section}, socket) do
    items =
      for e <- socket.assigns.entries, section_key(e) == section, e.proposable, do: e.item

    case Import.accept_proposals(socket.assigns.actor, items) do
      {:ok, %{decided: decided}} ->
        n = length(decided)

        {:noreply,
         socket
         |> put_flash(:info, "Left #{n} #{if n == 1, do: "hedge", else: "hedges"} out.")
         |> SourcePage.load()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "The hedges could not be left out: #{inspect(reason)}")
         |> SourcePage.load()}
    end
  end

  @impl true
  def handle_info({ItemRow, {:decided, _item}}, socket),
    do: {:noreply, socket |> put_flash(:info, "Decision recorded.") |> SourcePage.load()}

  def handle_info({ItemRow, {:proposal, _item}}, socket), do: {:noreply, SourcePage.load(socket)}

  defp section_key(entry), do: Atom.to_string(entry.question.section.id)

  defp answers(1), do: "answer"
  defp answers(_n), do: "answers"

  defp stay_open(0), do: "Nothing stays open in this section."
  defp stay_open(1), do: "1 stays open in this section."
  defp stay_open(n), do: "#{n} stay open in this section."

  defp bulk_rest(0), do: ""

  defp bulk_rest(n),
    do: " The other #{n} (rejected, suggestions to check, or with no proposal) stay open."

  defp count_text([]), do: "· all decided"
  defp count_text(open), do: "· #{length(open)} to decide"

  # Names and Galls accept only firm matches together (d213): never a
  # suggestion to check, a best match or a Gall that conflicts.
  defp firm_matches?(%{id: id}), do: id in [:names, :galls]

  # Each firm match the section would accept: "<written> → <answer>".
  defp firm_list(section) do
    section.open
    |> Enum.filter(& &1.proposable)
    |> Enum.map_join("; ", fn e ->
      "#{e.question.written} → #{(e.question.proposal && e.question.proposal.label) || "the proposal"}"
    end)
  end

  # Only Names and Galls accept firm matches together (d213): Trait terms
  # are accepted each on its own, Hedges have "Leave the rest out" instead.
  defp bulk?(step, %{proposable: n}), do: firm_matches?(step) and n > 0

  defp leave_rest?(%{section: %{id: id}, proposable: n}), do: id in @hedge_sections and n > 0

  # The step's line under its question: on Hedges, what a hedge is.
  defp intro(%{id: :hedges}, name),
    do:
      "#{name} hedges these (“may”, “apparently”, “presumed”), so they are left out unless " <>
        "you state them. They don't hold up approving the Source. State the ones that matter, " <>
        "then leave the rest of each group out."

  defp intro(_step, _name), do: nil

  # On Disputes, the open disputes about Trait terms, which are on Traits.
  defp trait_disputes(%{id: :disputes}, entries),
    do: for(e <- entries, e.question.topic == :trait_dispute, e.item.status == :open, do: e)

  defp trait_disputes(_step, _entries), do: []

  defp moved_text([one]), do: "1 dispute about a Trait term (“#{one.question.written}”) is"

  defp moved_text(disputes) do
    terms = disputes |> Enum.take(2) |> Enum.map_join(", ", &"“#{&1.question.written}”")
    "#{length(disputes)} disputes about Trait terms (#{terms}…) are"
  end

  # Where Previous and Next go: the steps around this one, or the overview.
  defp around(step, base) do
    {prev, next} = Steps.neighbours(step)
    overview = %{title: "Overview", path: base, step?: false}

    {
      if(prev,
        do: %{title: prev.title, path: "#{base}/#{prev.slug}", step?: true},
        else: overview
      ),
      if(next,
        do: %{title: next.title, path: "#{base}/#{next.slug}", step?: true},
        else: overview
      )
    }
  end

  # -- rendering -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    %{step: step, base: base, summaries: summaries} = assigns
    summary = Enum.find(summaries, &(&1.step.id == step.id))
    {prev, next} = around(step, base)

    assigns =
      assign(assigns,
        left: summary.left,
        prev: prev,
        next: next,
        sections: SourcePage.sections(assigns.entries, step.sections, assigns.summary.who),
        moved: trait_disputes(step, assigns.entries)
      )

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <:page_title_html>
        <.link navigate={~p"/admin/review"} class="hover:underline">Sources to review</.link>
        <span class="text-gray-400">›</span>
        <.link navigate={@base} class="hover:underline">{@name}</.link>
        <span class="text-gray-400">›</span> <span>{@step.title}</span>
      </:page_title_html>
      <%!-- Room for the Source's text beside the questions, when open (Task 22). --%>
      <div id="step-page" data-reading={@reader != nil} class={[@reader && "lg:mr-[min(38rem,46vw)]"]}>
        <.review_source_head
          name={@name}
          title={@summary.title}
          citation={@summary.citation}
          kind={@summary.kind}
        />

        <.review_step_bar
          base={@base}
          current={@step.id}
          summaries={@summaries}
          approval={@approval}
          confirm={@confirm_approve}
        />

        <.review_step_head step={@step} of={length(@summaries)} intro={intro(@step, @name)} />

        <.review_step_done :if={@left == 0} step={@step} next={@next} />

        <div id="step-sections">
          <.review_section
            :for={s <- @sections}
            id={"section-#{s.section.id}"}
            section={Atom.to_string(s.section.id)}
            title={s.section.title}
            count={count_text(s.open)}
            explanation={s.section.explanation}
            holds={s.section.holds}
            holds_approval={s.section.holds_approval}
            done={s.open == []}
            closed={MapSet.member?(@closed, Atom.to_string(s.section.id))}
            on_toggle="toggle_section"
            layout={:question}
          >
            <:actions :if={leave_rest?(s)}>
              <.button
                id={"leave-rest-#{s.section.id}"}
                phx-click="leave_rest"
                phx-value-section={s.section.id}
                size="sm"
                variant="soft"
              >
                Leave the rest out ({s.proposable})
              </.button>
            </:actions>
            <:actions :if={bulk?(@step, s)}>
              <.button
                id={"bulk-#{s.section.id}"}
                phx-click="confirm_bulk"
                phx-value-section={s.section.id}
                size="sm"
                variant="soft"
              >
                Accept firm matches ({s.proposable})
              </.button>
            </:actions>
            <:confirm :if={@confirm_bulk == Atom.to_string(s.section.id)}>
              <div
                id={"bulk-confirm-#{s.section.id}"}
                class="flex flex-wrap items-center gap-2 px-4 py-2.5 bg-yellow-50 text-yellow-900 text-sm border-b border-gray-200"
              >
                <span class="flex-1 min-w-[16rem]">
                  Accept {s.proposable} firm {if s.proposable == 1, do: "match", else: "matches"}: {firm_list(
                    s
                  )}.{bulk_rest(length(s.open) - s.proposable)}
                </span>
                <.button
                  id={"bulk-accept-#{s.section.id}"}
                  phx-click="accept_bulk"
                  phx-value-section={s.section.id}
                  size="sm"
                  variant="primary"
                >
                  Accept {s.proposable}
                </.button>
                <.button phx-click="cancel_bulk" size="sm" variant="secondary">Cancel</.button>
              </div>
            </:confirm>
            <.live_component
              :for={entry <- s.rows}
              module={ItemRow}
              id={"item-row-#{entry.item.id}"}
              entry={entry}
              actor={@actor}
              definitions={@definitions}
              source_name={@name}
              document={Document.for_item(@documents, entry.item)}
            />
          </.review_section>
        </div>

        <p :if={@moved != []} id="trait-disputes-moved" class="mt-3 text-sm text-gray-600">
          {moved_text(@moved)} on the <.link
            navigate={"#{@base}/traits"}
            class="text-gf-maroon hover:underline"
          >
            Traits step</.link>, with the other terms.
        </p>

        <.review_step_foot prev={@prev} next={@next} />
      </div>

      <.review_reader
        :if={@reader}
        title={@name}
        question={@reader.question}
        blocks={@reader.blocks}
        cited={@reader.cited}
        find={@reader.find}
        on_find="reader_find"
        on_close="reader_close"
      />
    </Layouts.admin>
    """
  end
end
