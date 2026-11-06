defmodule GallformersWeb.Admin.ReviewLive.Facts do
  @moduledoc """
  A Source's Facts in its review (matter `f14c`, item 4):
  `/admin/review/sources/:id/facts` (or `/admin/review/packages/:id/facts`),
  beside the five steps (`GallformersWeb.Admin.ReviewLive.Step`), optional,
  in the step bar after them.

  While the Source awaits review, the page shows what approving would
  write given the answers so far (`Gallformers.Import.preview_package/2`,
  each package awaiting review): whether it is ready to approve (else how
  many questions hold it, by step, each a link), the counts as filter
  chips, the taxonomy changes, then the Facts by Gall and category
  (`GallformersWeb.FactsComponents`), each marked new, held, in conflict,
  waiting (a link to its question on its step page) or dropped. Each Fact
  has a small menu of edits (`Gallformers.Import.edit_fact/5`): Drop,
  Change Host (a plant of any rank, sections too), Change value (one or
  several of its Trait's values), Note; each edit shows under its Fact,
  with Undo.

  The preview takes up to a second on a large Source, so it runs in the
  background (`start_async/3`) on mount and after each edit or approval,
  the Facts shown staying in place meanwhile, so the page keeps its scroll.

  Once approved (nothing awaiting review, a Source Gallformers holds), the
  page shows the Source's applied Facts (`Gallformers.Import.facts_for_source/1`),
  read-only.
  """
  use GallformersWeb, :live_view

  import GallformersWeb.FactsComponents
  import GallformersWeb.ReviewComponents

  alias Gallformers.Import
  alias Gallformers.Taxa
  alias GallformersWeb.Admin.Review.Steps
  alias GallformersWeb.Admin.ReviewLive.Document
  alias GallformersWeb.Admin.ReviewLive.Loader
  alias GallformersWeb.Admin.ReviewLive.SourcePage

  @results 10
  @statuses ~w(new held conflict waiting dropped)

  @impl true
  def mount(params, _session, socket) do
    mode = SourcePage.mode(params)
    base = SourcePage.base_path(mode)

    if notes?(mode) do
      {:ok, push_navigate(socket, to: base)}
    else
      socket =
        socket
        |> assign(
          mode: mode,
          base: base,
          keep: [],
          confirm_approve: false,
          facts: nil,
          loading: false,
          failed: nil,
          filter: nil,
          editing: nil,
          edit_kind: nil,
          pick: empty_pick(),
          edit_error: nil,
          passages: %{}
        )
        |> SourcePage.load()
        |> Document.mount()
        |> assign_view()

      {:ok, if(connected?(socket), do: compute(socket), else: socket)}
    end
  end

  # The Gallformers notes keep their own page.
  defp notes?({:source, id}), do: Loader.notes_page(id) != nil
  defp notes?(_mode), do: false

  # What the page shows: the preview of the packages awaiting review, the
  # Source's applied Facts once nothing is, or nothing yet.
  defp assign_view(socket) do
    %{mode: mode, packages: packages} = socket.assigns
    awaiting = for p <- packages, p.package.status == :awaiting_review, do: p.package
    source_id = source_id(mode, packages)

    view =
      cond do
        awaiting != [] ->
          {:preview, awaiting}

        source_id && Enum.all?(packages, &(&1.package.status == :approved)) ->
          {:applied, source_id}

        true ->
          :none
      end

    batch_package =
      for p <- packages, b <- p.batches, into: %{}, do: {b.id, p.package.id}

    assign(socket, view: view, batch_package: batch_package)
  end

  defp source_id({:source, id}, _packages), do: id
  defp source_id({:package, _id}, packages), do: Enum.find_value(packages, & &1.package.source_id)

  # -- computing -------------------------------------------------------------------

  defp compute(%{assigns: %{view: :none}} = socket), do: assign(socket, loading: false)

  defp compute(socket) do
    %{view: view, actor: actor} = socket.assigns

    socket
    |> assign(loading: true)
    |> start_async(:facts, fn -> load_facts(view, actor) end)
  end

  defp load_facts({:applied, source_id}, _actor),
    do: {:ok, %{galls: Import.facts_for_source(source_id), taxonomy: %{new_taxa: [], acts: []}}}

  # The preview runs as the curator viewing it (its transaction is
  # audited, then rolled back).
  defp load_facts({:preview, packages}, actor) do
    results = Enum.map(packages, &Import.preview_package(&1, actor))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, merge(for {:ok, preview} <- results, do: preview)}
      error -> error
    end
  end

  # The previews of a Source's packages under review, as one.
  defp merge([one]), do: one

  defp merge(previews) do
    sum = fn maps -> Enum.reduce(maps, %{}, &Map.merge(&2, &1, fn _k, a, b -> a + b end)) end

    %{
      ready?: Enum.all?(previews, & &1.ready?),
      galls: Enum.flat_map(previews, & &1.galls),
      taxonomy: %{
        new_taxa: Enum.flat_map(previews, & &1.taxonomy.new_taxa),
        acts: Enum.flat_map(previews, & &1.taxonomy.acts)
      },
      counts: sum.(Enum.map(previews, & &1.counts)),
      blocking: %{
        count: previews |> Enum.map(& &1.blocking.count) |> Enum.sum(),
        by_kind: sum.(Enum.map(previews, & &1.blocking.by_kind)),
        items: Enum.flat_map(previews, & &1.blocking.items),
        blocked_batches: Enum.flat_map(previews, & &1.blocking.blocked_batches)
      },
      errors: Enum.flat_map(previews, & &1.errors),
      applied: Enum.flat_map(previews, & &1.applied)
    }
  end

  @impl true
  def handle_async(:facts, {:ok, {:ok, facts}}, socket),
    do: {:noreply, assign(socket, facts: facts, loading: false, failed: nil)}

  def handle_async(:facts, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, loading: false, failed: inspect(reason))}

  def handle_async(:facts, {:exit, reason}, socket),
    do: {:noreply, assign(socket, loading: false, failed: inspect(reason))}

  # -- events ------------------------------------------------------------------------

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    filter =
      cond do
        status not in @statuses -> nil
        socket.assigns.filter == String.to_existing_atom(status) -> nil
        true -> String.to_existing_atom(status)
      end

    {:noreply, assign(socket, filter: filter)}
  end

  # The passage around a quote, read from the package's document on request.
  def handle_event("fact_passage", %{"key" => key}, socket) do
    with [batch_id, item] <- String.split(key, "|", parts: 2),
         {batch_id, ""} <- Integer.parse(batch_id),
         package_id when is_integer(package_id) <- socket.assigns.batch_package[batch_id],
         %{} = doc <- socket.assigns.documents[package_id] do
      blocks = Document.passage(doc, %{item: item})
      {:noreply, update(socket, :passages, &Map.put(&1, key, blocks))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit_open", %{"key" => key, "kind" => kind}, socket)
      when kind in ~w(drop host values note) do
    case entry(socket, key) do
      nil ->
        {:noreply, socket}

      entry ->
        pick = %{
          empty_pick()
          | values: current_values(socket, entry),
            note: current_note(entry, kind)
        }

        {:noreply, assign(socket, editing: key, edit_kind: kind, pick: pick, edit_error: nil)}
    end
  end

  def handle_event("edit_cancel", _params, socket), do: {:noreply, close_editor(socket)}

  def handle_event("retry", _params, socket),
    do: {:noreply, socket |> assign(failed: nil) |> compute()}

  def handle_event("search_plant", %{"value" => query}, socket) do
    query = String.trim(query)
    socket = update(socket, :pick, &%{&1 | query: query})

    results = if String.length(query) < 2, do: [], else: plants(query)
    {:noreply, update(socket, :pick, &%{&1 | results: results})}
  end

  def handle_event("select_plant", %{"id" => id}, socket) do
    selected = Enum.find(socket.assigns.pick.results, &(to_string(&1.id) == id))

    {:noreply,
     update(socket, :pick, &%{&1 | selected: selected, query: "", results: []})
     |> assign(edit_error: nil)}
  end

  def handle_event("clear_plant", _params, socket),
    do: {:noreply, update(socket, :pick, &%{&1 | selected: nil, query: "", results: []})}

  def handle_event("toggle_value", %{"value" => value}, socket) do
    values = socket.assigns.pick.values

    values =
      if value in values, do: List.delete(values, value), else: values ++ [value]

    {:noreply, socket |> update(:pick, &%{&1 | values: values}) |> assign(edit_error: nil)}
  end

  def handle_event("edit_save", params, socket) do
    %{editing: key, edit_kind: kind, pick: pick} = socket.assigns
    note = params |> Map.get("note", "") |> String.trim()
    pick = %{pick | note: note}

    with %{} = entry <- entry(socket, key),
         {:ok, edit} <- edit(kind, pick, note),
         batch = Import.get_batch!(entry.batch_id),
         package = Import.get_package!(batch.package_id),
         {:ok, _stored} <-
           Import.edit_fact(socket.assigns.actor, package, batch, base_ref(entry.ref), edit) do
      {:noreply, socket |> close_editor() |> put_flash(:info, "Edit saved.") |> compute()}
    else
      nil ->
        {:noreply, close_editor(socket)}

      {:error, reason} ->
        {:noreply, assign(socket, pick: pick, edit_error: refusal(reason))}
    end
  end

  def handle_event("edit_undo", %{"id" => id}, socket) do
    id = String.to_integer(id)

    edit =
      Enum.find_value(packages_in_view(socket), fn package ->
        Enum.find(Import.list_fact_edits(package), &(&1.id == id))
      end)

    case edit && Import.remove_fact_edit(socket.assigns.actor, edit) do
      {:ok, _removed} ->
        {:noreply, socket |> put_flash(:info, "Edit undone.") |> compute()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "The edit could not be undone: #{refusal(reason)}")}

      nil ->
        {:noreply, compute(socket)}
    end
  end

  def handle_event("approve_ask", _params, socket),
    do: {:noreply, assign(socket, confirm_approve: true)}

  def handle_event("approve_cancel", _params, socket),
    do: {:noreply, assign(socket, confirm_approve: false)}

  def handle_event("approve", _params, socket) do
    {:noreply,
     socket
     |> SourcePage.approve()
     |> assign(confirm_approve: false, editing: nil)
     |> SourcePage.load()
     |> assign_view()
     |> compute()}
  end

  defp packages_in_view(%{assigns: %{view: {:preview, packages}}}), do: packages
  defp packages_in_view(_socket), do: []

  defp close_editor(socket),
    do: assign(socket, editing: nil, edit_kind: nil, pick: empty_pick(), edit_error: nil)

  defp empty_pick, do: %{query: "", results: [], selected: nil, values: [], note: ""}

  # The edit as `Gallformers.Import.edit_fact/5` takes it.
  defp edit(kind, pick, note) do
    edit =
      case kind do
        "drop" -> {:ok, %{"drop" => true}}
        "host" when pick.selected != nil -> {:ok, %{"host_taxon_id" => pick.selected.id}}
        "host" -> {:error, "Pick a plant from the search."}
        "values" when pick.values != [] -> {:ok, %{"values" => pick.values}}
        "values" -> {:error, "Pick one value or more."}
        "note" when note != "" -> {:ok, %{}}
        "note" -> {:error, "Write the note first."}
      end

    with {:ok, edit} <- edit do
      {:ok, if(note != "", do: Map.put(edit, "note", note), else: edit)}
    end
  end

  defp refusal(:not_editable), do: "This Source can no longer be edited here."
  defp refusal(:no_statement), do: "This Fact is no longer in the Source."
  defp refusal(:not_found), do: "The edit is gone."
  defp refusal(reason) when is_binary(reason), do: reason
  defp refusal(%Ecto.Changeset{} = changeset), do: inspect(changeset.errors)
  defp refusal(reason), do: inspect(reason)

  # A Trait entry's ref ("f6+globular") names its statement ("f6").
  defp base_ref(ref), do: ref |> String.split("+") |> hd()

  defp entry(%{assigns: %{facts: nil}}, _key), do: nil

  defp entry(socket, key) do
    facts = socket.assigns.facts

    Enum.find(entries(facts.galls) ++ facts.taxonomy.acts, &(fact_key(&1) == key))
  end

  # The values a Trait statement is written on now: each of its entries'.
  defp current_values(socket, %{kind: :trait, ref: ref, batch_id: batch_id}) do
    base = base_ref(ref)

    for e <- entries(socket.assigns.facts.galls),
        e.batch_id == batch_id,
        is_binary(e.ref),
        base_ref(e.ref) == base,
        v = e.value[:value] || e.value[:suggested],
        is_binary(v),
        uniq: true,
        do: v
  end

  defp current_values(_socket, _entry), do: []

  defp current_note(entry, "note") do
    Enum.find_value(entry.edits, "", &(&1.kind == :note && &1.note))
  end

  defp current_note(_entry, _kind), do: ""

  # Plants of any rank, and genera and sections, a Host may be.
  defp plants(query) do
    species =
      for p <- Taxa.search_plants(query, @results),
          do: %{id: p.id, name: p.name, meta: meta(p.rank, p.aliases), group: "Plants"}

    groups =
      for g <- Taxa.search_genera_and_sections(query, @results, kingdom: "Plantae"),
          do: %{id: g.id, name: g.name, meta: meta(g.rank, []), group: "Genera and sections"}

    species ++ groups
  end

  defp meta(rank, aliases) do
    [rank && to_string(rank), aliases != [] && "also " <> Enum.join(Enum.take(aliases, 3), ", ")]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  # -- what the page shows -------------------------------------------------------------

  # Each open question's place: its step page and its row there.
  defp questions(entries, base) do
    for e <- entries,
        id <- [e.item.id | for(m <- Map.get(e, :members) || [], do: m.item.id)],
        into: %{} do
      case step(e) do
        nil -> {id, %{title: "the overview", path: base}}
        step -> {id, %{title: step.title, path: "#{base}/#{step.slug}#item-row-#{e.item.id}"}}
      end
    end
  end

  defp step(entry) do
    case Steps.step_of(entry.question.section.id) do
      nil -> nil
      id -> Enum.find(Steps.all(), &(&1.id == id))
    end
  end

  # The questions holding approval, by step, in the steps' order.
  defp readiness_steps(blocking, entries, base) do
    step_of =
      for e <- entries,
          id <- [e.item.id | for(m <- Map.get(e, :members) || [], do: m.item.id)],
          into: %{},
          do: {id, step(e)}

    blocking.items
    |> Enum.group_by(&Map.get(step_of, &1.id))
    |> Enum.sort_by(fn {step, _items} -> (step && step.n) || 0 end)
    |> Enum.map(fn
      {nil, items} -> %{title: "Overview", path: base, n: length(items)}
      {step, items} -> %{title: step.title, path: "#{base}/#{step.slug}", n: length(items)}
    end)
  end

  defp trait_values(definitions, trait) do
    definitions |> Map.get(trait, %{}) |> Enum.sort()
  end

  defp editor_title("drop"), do: "Drop this Fact: approving won't write it."
  defp editor_title("host"), do: "Change the Host: the plant this Fact is written on."
  defp editor_title("values"), do: "Change the value: one or several of the Trait's values."
  defp editor_title("note"), do: "A note on this Fact."

  defp save_text("drop"), do: "Drop it"
  defp save_text("note"), do: "Save the note"
  defp save_text(_kind), do: "Save"

  # -- rendering -------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        questions: questions(assigns.entries, assigns.base),
        on_passage: if(assigns.documents != %{}, do: "fact_passage")
      )

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <.page_header>
        <:crumb navigate={~p"/admin/review"}>Sources to review</:crumb>
        <:crumb navigate={@base}>{@name}</:crumb>
        <:title>Facts</:title>
      </.page_header>

      <.review_source_head
        name={@name}
        title={@summary.title}
        citation={@summary.citation}
        kind={@summary.kind}
      />

      <.review_step_bar
        base={@base}
        current={:facts}
        summaries={@summaries}
        approval={@approval}
        confirm={@confirm_approve}
      />

      <div id="facts-head" class="mt-4 flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <h2 class="text-section text-ink">Facts</h2>
        <p class="text-meta text-ink-2">
          <%= case @view do %>
            <% {:preview, _} -> %>
              Every Fact approving would write, given the answers so far, by Gall. Looking is optional.
            <% {:applied, _} -> %>
              The Facts this Source states in Gallformers, by Gall.
            <% :none -> %>
              What approving would write shows here once the Source awaits review.
          <% end %>
        </p>
        <span
          :if={@loading and @facts}
          id="facts-updating"
          class="inline-flex items-center gap-1 text-caption text-muted"
        >
          <.loading_spinner size="sm" label="Updating" /> Updating…
        </span>
      </div>

      <div
        :if={@facts == nil and @loading}
        id="facts-loading"
        class="mt-6 flex items-center gap-2 text-meta text-ink-2"
      >
        <.loading_spinner size="sm" /> Working out what approving writes…
      </div>

      <.notice
        :if={@failed}
        id="facts-failed"
        kind={:danger}
        class="mt-4"
        title="The Facts could not be worked out"
      >
        {@failed}
        <:action>
          <.button size="sm" icon="ph-arrows-clockwise" phx-click={JS.push("retry")}>
            Retry
          </.button>
        </:action>
      </.notice>

      <%= if @facts do %>
        <%= case @view do %>
          <% {:preview, _} -> %>
            <.facts_readiness
              ready={@facts.ready?}
              count={@facts.blocking.count}
              steps={readiness_steps(@facts.blocking, @entries, @base)}
              blocked={@facts.blocking.blocked_batches}
            />
            <.notice :if={@facts.errors != []} id="facts-errors" kind={:danger} class="mt-3">
              <p :for={e <- @facts.errors}>{e.file} could not be worked out: {inspect(e.reason)}</p>
            </.notice>
            <.facts_filter counts={@facts.counts} filter={@filter} on_filter="filter" />
            <div class="mt-3 grid gap-3">
              <.facts_taxonomy
                taxonomy={@facts.taxonomy}
                editable
                filter={@filter}
                questions={@questions}
                editing={@editing}
                passages={@passages}
                on_passage={@on_passage}
              >
                <:editor :let={entry}>
                  <.fact_editor
                    entry={entry}
                    kind={@edit_kind}
                    pick={@pick}
                    error={@edit_error}
                    definitions={@definitions}
                  />
                </:editor>
              </.facts_taxonomy>
              <.facts_view
                galls={@facts.galls}
                editable
                filter={@filter}
                questions={@questions}
                editing={@editing}
                passages={@passages}
                on_passage={@on_passage}
                empty={
                  if @filter, do: "No Facts here.", else: "This Source adds no Facts about Galls."
                }
              >
                <:editor :let={entry}>
                  <.fact_editor
                    entry={entry}
                    kind={@edit_kind}
                    pick={@pick}
                    error={@edit_error}
                    definitions={@definitions}
                  />
                </:editor>
              </.facts_view>
            </div>
          <% {:applied, _} -> %>
            <.notice id="facts-applied" kind={:ok} class="mt-4">
              This Source is approved and applied: these are its Facts in Gallformers. Read-only.
            </.notice>
            <.facts_view
              galls={@facts.galls}
              mode={:applied}
              passages={@passages}
              on_passage={@on_passage}
              empty="This Source states no Facts about Galls."
            />
          <% :none -> %>
        <% end %>
      <% end %>
    </Layouts.admin>
    """
  end

  # The open edit's form, under its Fact.
  attr :entry, :map, required: true
  attr :kind, :string, required: true
  attr :pick, :map, required: true
  attr :error, :string, default: nil
  attr :definitions, :map, required: true

  defp fact_editor(assigns) do
    ~H"""
    <.form
      for={%{}}
      id="fact-editor"
      phx-submit="edit_save"
      class="grid gap-2 rounded-panel border border-line bg-surface-2 p-2"
    >
      <p class="text-caption font-semibold text-ink-2">{editor_title(@kind)}</p>
      <.typeahead
        :if={@kind == "host"}
        id="fact-editor-plant"
        label="The plant: species and below, genera, sections"
        placeholder="Type a name…"
        search_event="search_plant"
        select_event="select_plant"
        clear_event="clear_plant"
        query={@pick.query}
        results={@pick.results}
        selected={@pick.selected}
        display_fn={& &1.name}
        group_key={:group}
      >
        <:result :let={result}>
          <span class="italic">{result.name}</span>
          <span :if={result.meta != ""} class="text-caption text-muted ml-1">{result.meta}</span>
        </:result>
      </.typeahead>
      <.review_value_list
        :if={@kind == "values"}
        id="fact-editor-values"
        type="checkbox"
        values={trait_values(@definitions, @entry.value.trait)}
        selected={@pick.values}
        on_pick="toggle_value"
      />
      <div class="grid gap-0.5">
        <label for="fact-editor-note" class="gf-label-sm">
          Note{if @kind != "note", do: " (optional)"}
        </label>
        <textarea id="fact-editor-note" name="note" rows="2" class="gf-textarea text-ui">{@pick.note}</textarea>
      </div>
      <p :if={@error} id="fact-editor-error" class="text-caption text-danger">{@error}</p>
      <div class="flex flex-wrap gap-2">
        <.button id="fact-editor-save" type="submit" size="sm" variant="primary">
          {save_text(@kind)}
        </.button>
        <.button
          id="fact-editor-cancel"
          type="button"
          phx-click="edit_cancel"
          size="sm"
          variant="ghost"
        >
          Cancel
        </.button>
      </div>
    </.form>
    """
  end
end
