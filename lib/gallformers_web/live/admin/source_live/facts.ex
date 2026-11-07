defmodule GallformersWeb.Admin.SourceLive.Facts do
  @moduledoc """
  The admin Source page's Facts (matter `f14c`, "The Source's Facts after
  approval"): the Source's applied Facts (`Gallformers.Import.facts_for_source/2`)
  in the Facts view the review's Facts page and the public Source page use
  (`GallformersWeb.FactsComponents`), in its corrections mode, for errors
  made in the original ingestion.

  A correction never edits a Fact (a Fact can hold several Sources'
  attributions): from a Fact's Correct menu the curator withdraws the
  Source's statement where it didn't say it, or moves it to what it did
  say (Change Host, Change value, Change parent, Change accepted taxon),
  each with a required note of why (`Gallformers.Import.correct_source_fact/6`:
  audited, logged for replay). A taxonomic statement moved for a paper
  awaits a curator unless the correcting curator ticks "Accept it now".
  The corrections made are listed under the Facts, newest first, and move
  the Source's Updated date: the page is told (`{:source_corrected, id}`)
  to show it.

  A Source stating more gall Facts than the page shows at once (the legacy
  data: tens of thousands) shows one Gall at a time, found by the Gall
  search (`Gallformers.Import.search_source_galls/3`); a smaller one shows
  them all, and the search narrows them to one Gall. How many it shows at
  once is `all_limit` in this module's application env (default 300).
  The Facts load in the background (`start_async/3`) and stay in place
  while they reload after a correction.

  The plant search and the values list are the review Facts page's
  (`Gallformers.Taxa.search_plants/2` and genera and sections; the
  review's `review_value_list`), its edits being for packages before
  approval.
  """
  use GallformersWeb, :live_component

  import GallformersWeb.FactsComponents
  import GallformersWeb.ReviewComponents, only: [review_value_list: 1]

  alias Gallformers.Import
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias GallformersWeb.Admin.ReviewLive.Loader

  @results 10
  @all_limit 300

  @impl true
  def update(%{source: source, actor: actor} = assigns, socket) do
    first? = not Map.has_key?(socket.assigns, :source)

    socket =
      socket
      |> assign(id: assigns.id, source: source, actor: actor)

    if first? do
      count = Import.source_fact_count(source.id)

      {:ok,
       socket
       |> assign(
         count: count,
         find?: count > all_limit(),
         own?: source.id in Sources.own_source_ids(),
         facts: nil,
         loading: false,
         failed: nil,
         gall_query: "",
         gall_results: [],
         gall: nil,
         corrections: Import.list_source_corrections(source.id),
         definitions: Loader.definitions()
       )
       |> close_editor()
       |> load()}
    else
      {:ok, socket}
    end
  end

  defp all_limit do
    :gallformers |> Application.get_env(__MODULE__, []) |> Keyword.get(:all_limit, @all_limit)
  end

  # -- loading ---------------------------------------------------------------------

  # The Facts shown: all of them, or the chosen Gall's; none until a Gall
  # is chosen when there are too many to show.
  defp load(socket) do
    %{source: source, gall: gall, find?: find?} = socket.assigns

    cond do
      not connected?(socket) ->
        socket

      find? and gall == nil ->
        taxonomy_only(socket)

      true ->
        opts = if gall, do: [gall_ids: [gall.id]], else: []

        socket
        |> assign(loading: true)
        |> start_async(:facts, fn -> Import.facts_for_source(source.id, opts) end)
    end
  end

  # With no Gall chosen, the taxonomic statements are shown, and no Galls.
  defp taxonomy_only(socket) do
    source_id = socket.assigns.source.id

    socket
    |> assign(loading: true)
    |> start_async(:facts, fn ->
      %{Import.facts_for_source(source_id, gall_ids: []) | galls: []}
    end)
  end

  @impl true
  def handle_async(:facts, {:ok, facts}, socket),
    do: {:noreply, assign(socket, facts: facts, loading: false, failed: nil)}

  def handle_async(:facts, {:exit, reason}, socket),
    do: {:noreply, assign(socket, loading: false, failed: inspect(reason))}

  # -- events ------------------------------------------------------------------------

  @impl true
  def handle_event("search_gall", %{"value" => query}, socket) do
    query = String.trim(query)

    results =
      if String.length(query) < 2,
        do: [],
        else: Import.search_source_galls(socket.assigns.source.id, query, @results)

    {:noreply, assign(socket, gall_query: query, gall_results: results)}
  end

  def handle_event("select_gall", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.gall_results, &(to_string(&1.id) == id)) do
      nil ->
        {:noreply, socket}

      gall ->
        {:noreply,
         socket
         |> assign(gall: gall, gall_query: "", gall_results: [])
         |> close_editor()
         |> load()}
    end
  end

  def handle_event("clear_gall", _params, socket) do
    {:noreply,
     socket
     |> assign(gall: nil, gall_query: "", gall_results: [])
     |> close_editor()
     |> load()}
  end

  def handle_event("retry", _params, socket), do: {:noreply, load(socket)}

  def handle_event("edit_open", %{"key" => key, "kind" => kind}, socket)
      when kind in ~w(withdraw host values parent accepted) do
    case entry(socket, key) do
      nil ->
        {:noreply, socket}

      entry ->
        pick = %{empty_pick() | values: current_values(entry)}
        {:noreply, assign(socket, editing: key, edit_kind: kind, pick: pick, edit_error: nil)}
    end
  end

  def handle_event("edit_cancel", _params, socket), do: {:noreply, close_editor(socket)}

  def handle_event("search_taxon", %{"value" => query}, socket) do
    query = String.trim(query)
    results = if String.length(query) < 2, do: [], else: taxa(socket.assigns.edit_kind, query)
    {:noreply, update(socket, :pick, &%{&1 | query: query, results: results})}
  end

  def handle_event("select_taxon", %{"id" => id}, socket) do
    selected = Enum.find(socket.assigns.pick.results, &(to_string(&1.id) == id))

    {:noreply,
     socket
     |> update(:pick, &%{&1 | selected: selected, query: "", results: []})
     |> assign(edit_error: nil)}
  end

  def handle_event("clear_taxon", _params, socket),
    do: {:noreply, update(socket, :pick, &%{&1 | selected: nil, query: "", results: []})}

  def handle_event("toggle_value", %{"value" => value}, socket) do
    values = socket.assigns.pick.values
    values = if value in values, do: List.delete(values, value), else: values ++ [value]
    {:noreply, socket |> update(:pick, &%{&1 | values: values}) |> assign(edit_error: nil)}
  end

  def handle_event("correct", params, socket) do
    %{editing: key, edit_kind: kind, pick: pick, source: source, actor: actor} = socket.assigns
    note = params |> Map.get("note", "") |> String.trim()
    accept = params["accept"] == "true"
    pick = %{pick | note: note, accept: accept}

    with %{} = entry <- entry(socket, key),
         {:ok, correction} <- correction(kind, pick),
         {:ok, _result} <-
           Import.correct_source_fact(actor, source.id, entry.fact_id, correction, note,
             accept: accept
           ) do
      send(self(), {:source_corrected, source.id})

      {:noreply,
       socket
       |> close_editor()
       |> assign(corrections: Import.list_source_corrections(source.id))
       |> put_flash(:info, "Correction saved.")
       |> load()}
    else
      nil -> {:noreply, close_editor(socket)}
      {:error, reason} -> {:noreply, assign(socket, pick: pick, edit_error: refusal(reason))}
    end
  end

  # The correction as `Gallformers.Import.correct_source_fact/6` takes it.
  defp correction("withdraw", _pick), do: {:ok, :withdraw}
  defp correction("host", %{selected: %{id: id}}), do: {:ok, {:host, id}}
  defp correction("host", _pick), do: {:error, "Pick the plant from the search."}
  defp correction("values", %{values: [_ | _] = values}), do: {:ok, {:values, values}}
  defp correction("values", _pick), do: {:error, "Pick one value or more."}
  defp correction("parent", %{selected: %{id: id}}), do: {:ok, {:parent, id}}
  defp correction("parent", _pick), do: {:error, "Pick the parent from the search."}
  defp correction("accepted", %{selected: %{id: id}}), do: {:ok, {:accepted, id}}
  defp correction("accepted", _pick), do: {:error, "Pick the accepted taxon from the search."}

  defp refusal(:note_required), do: "Write the note: say why the Source didn't say this."
  defp refusal(:unchanged), do: "That is what the Source states already."
  defp refusal(:not_found), do: "The Source no longer states this Fact."
  defp refusal(:not_correctable), do: "This correction doesn't fit this Fact."
  defp refusal(reason) when is_binary(reason), do: reason
  defp refusal(%Ecto.Changeset{} = changeset), do: inspect(changeset.errors)
  defp refusal({:rejected, _listener, _reason} = reason), do: Import.taxonomy_refusal(reason)
  defp refusal(reason), do: inspect(reason)

  defp close_editor(socket),
    do: assign(socket, editing: nil, edit_kind: nil, pick: empty_pick(), edit_error: nil)

  defp empty_pick,
    do: %{query: "", results: [], selected: nil, values: [], note: "", accept: false}

  defp entry(%{assigns: %{facts: nil}}, _key), do: nil

  defp entry(socket, key) do
    facts = socket.assigns.facts
    Enum.find(entries(facts.galls) ++ facts.taxonomy.acts, &(fact_key(&1) == key))
  end

  defp current_values(%{kind: :trait, value: %{value: value}}) when is_binary(value), do: [value]
  defp current_values(_entry), do: []

  # Plants of any rank, and genera and sections, for a Host; other taxa
  # for a parent or an accepted taxon.
  defp taxa("host", query) do
    species =
      for p <- Taxa.search_plants(query, @results),
          do: %{id: p.id, name: p.name, meta: meta(p.rank, p.aliases), group: "Plants"}

    groups =
      for g <- Taxa.search_genera_and_sections(query, @results, kingdom: "Plantae"),
          do: %{id: g.id, name: g.name, meta: meta(g.rank, []), group: "Genera and sections"}

    species ++ groups
  end

  defp taxa(_kind, query) do
    query
    |> Taxa.search()
    |> Enum.reject(&(&1.kingdom == "Plantae"))
    |> Enum.take(@results)
    |> Enum.map(&%{id: &1.id, name: &1.name, meta: meta(&1.rank, &1.aliases), group: "Taxa"})
  end

  defp meta(rank, aliases) do
    [rank && to_string(rank), aliases != [] && "also " <> Enum.join(Enum.take(aliases, 3), ", ")]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  defp trait_values(definitions, trait), do: definitions |> Map.get(trait, %{}) |> Enum.sort()

  # A taxonomic statement moved for a Source that needs a curator's
  # acceptance (not Gallformers' own).
  defp acceptance?(kind, own?), do: kind in ["parent", "accepted"] and not own?

  defp editor_title("withdraw"),
    do:
      "Withdraw: the Source doesn't say this. Its statement goes; the Fact and other Sources' statements of it stay."

  defp editor_title("host"), do: "Change the Host: the plant the Source names."
  defp editor_title("values"), do: "Change the value: what the Source says, one value or several."
  defp editor_title("parent"), do: "Change the parent: where the Source places the taxon."

  defp editor_title("accepted"),
    do: "Change the accepted taxon: what the Source says it is a synonym of."

  defp save_text("withdraw"), do: "Withdraw the statement"
  defp save_text(_kind), do: "Save the correction"

  defp taxon_label("host"), do: "The plant: species and below, genera, sections"
  defp taxon_label("parent"), do: "The parent"
  defp taxon_label(_kind), do: "The accepted taxon"

  defp verb(:withdraw), do: "Withdrew"
  defp verb(_kind), do: "Moved"

  # -- rendering -------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-section">
      <.section id="source-facts" title="Facts" count={@count}>
        <:aside>What this Source states in Gallformers</:aside>
        <div class="flex flex-col gap-block">
          <p class="text-meta text-ink-2">
            Correct an error from the Source's ingestion here: withdraw what the Source didn't say, or move its statement to what it did say. The Fact itself, and other Sources' statements of it, stay. Each correction needs a note of why.
          </p>

          <p :if={(@count == 0 and @facts) && @facts.taxonomy.acts == []} class="text-ui text-muted">
            This Source states no Facts in Gallformers.
          </p>

          <div :if={@count > 0} class="flex max-w-form flex-col gap-1">
            <p :if={@find?} class="text-ui text-ink-2">
              This Source states {format_number(@count)} Facts about Galls. Find a Gall to see and correct its Facts.
            </p>
            <.typeahead
              id="source-facts-gall"
              label={if @find?, do: "Find a Gall", else: "Show one Gall"}
              placeholder="Type a Gall's name, an alias or its Inducer…"
              search_event="search_gall"
              select_event="select_gall"
              clear_event="clear_gall"
              query={@gall_query}
              results={@gall_results}
              selected={@gall}
              display_fn={& &1.name}
              target={@myself}
            >
              <:result :let={gall}>
                <span>{gall.name}</span>
              </:result>
            </.typeahead>
          </div>

          <div
            :if={@facts == nil and @loading}
            id="source-facts-loading"
            class="flex items-center gap-2 text-meta text-ink-2"
          >
            <.loading_spinner size="sm" /> Loading the Source's Facts…
          </div>
          <span
            :if={@loading and @facts}
            id="source-facts-updating"
            class="inline-flex items-center gap-1 text-caption text-muted"
          >
            <.loading_spinner size="sm" label="Updating" /> Updating…
          </span>

          <.notice
            :if={@failed}
            id="source-facts-failed"
            kind={:danger}
            title="The Facts could not be loaded"
          >
            {@failed}
            <:action>
              <.button
                size="sm"
                icon="ph-arrows-clockwise"
                phx-click="retry"
                phx-target={@myself}
              >
                Retry
              </.button>
            </:action>
          </.notice>

          <div :if={@facts} class="grid gap-3">
            <.facts_taxonomy
              taxonomy={@facts.taxonomy}
              mode={:applied}
              corrections
              target={@myself}
              editing={@editing}
            >
              <:editor :let={entry}>
                <.correction_editor
                  entry={entry}
                  kind={@edit_kind}
                  pick={@pick}
                  error={@edit_error}
                  definitions={@definitions}
                  acceptance={acceptance?(@edit_kind, @own?)}
                  target={@myself}
                />
              </:editor>
            </.facts_taxonomy>
            <.facts_view
              :if={@count > 0 and (@facts.galls != [] or not @find? or @gall != nil)}
              id="source-facts-galls"
              galls={@facts.galls}
              mode={:applied}
              corrections
              target={@myself}
              editing={@editing}
              empty={if @gall, do: "This Source states no Facts about this Gall.", else: "No Facts."}
            >
              <:editor :let={entry}>
                <.correction_editor
                  entry={entry}
                  kind={@edit_kind}
                  pick={@pick}
                  error={@edit_error}
                  definitions={@definitions}
                  acceptance={false}
                  target={@myself}
                />
              </:editor>
            </.facts_view>
          </div>
        </div>
      </.section>

      <.section
        :if={@corrections != []}
        id="source-corrections"
        title="Corrections"
        count={length(@corrections)}
      >
        <:aside>Newest first</:aside>
        <ul class="divide-y divide-line">
          <li :for={c <- @corrections} id={"source-correction-#{c.id}"} class="py-1.5 text-meta">
            <p class="text-ink">
              <span class="font-semibold">{verb(c.kind)}</span>
              {c.summary}<span :if={c.change}> → {c.change}</span>
              <span class="text-caption text-muted">
                · {c.author_name}, {format_date(c.inserted_at, :short)}
              </span>
            </p>
            <p class="text-caption text-ink-2">{c.note}</p>
          </li>
        </ul>
      </.section>
    </div>
    """
  end

  # The open correction's form, under its Fact.
  attr :entry, :map, required: true
  attr :kind, :string, required: true
  attr :pick, :map, required: true
  attr :error, :string, default: nil
  attr :definitions, :map, required: true
  attr :acceptance, :boolean, default: false
  attr :target, :any, required: true

  defp correction_editor(assigns) do
    ~H"""
    <.form
      for={%{}}
      id="correction-editor"
      phx-submit="correct"
      phx-target={@target}
      class="grid gap-2 rounded-panel border border-line bg-surface-2 p-2"
    >
      <p class="text-caption font-semibold text-ink-2">{editor_title(@kind)}</p>
      <.typeahead
        :if={@kind in ["host", "parent", "accepted"]}
        id="correction-editor-taxon"
        label={taxon_label(@kind)}
        placeholder="Type a name…"
        search_event="search_taxon"
        select_event="select_taxon"
        clear_event="clear_taxon"
        query={@pick.query}
        results={@pick.results}
        selected={@pick.selected}
        display_fn={& &1.name}
        group_key={:group}
        target={@target}
      >
        <:result :let={result}>
          <span class="italic">{result.name}</span>
          <span :if={result.meta != ""} class="text-caption text-muted ml-1">{result.meta}</span>
        </:result>
      </.typeahead>
      <.review_value_list
        :if={@kind == "values"}
        id="correction-editor-values"
        type="checkbox"
        values={trait_values(@definitions, @entry.value.trait)}
        selected={@pick.values}
        on_pick="toggle_value"
        target={@target}
      />
      <.input
        :if={@acceptance}
        type="checkbox"
        id="correction-editor-accept"
        name="accept"
        value={@pick.accept}
        label="Accept it now: the tree follows it where it wins (else it awaits a curator in the taxonomy queue)"
      />
      <div class="grid gap-0.5">
        <label for="correction-editor-note" class="gf-label-sm">Note: why (required)</label>
        <textarea id="correction-editor-note" name="note" rows="2" class="gf-textarea text-ui">{@pick.note}</textarea>
      </div>
      <p :if={@error} id="correction-editor-error" class="text-caption text-danger">{@error}</p>
      <div class="flex flex-wrap gap-2">
        <.button
          id="correction-editor-save"
          type="submit"
          size="sm"
          variant={if @kind == "withdraw", do: "danger", else: "primary"}
        >
          {save_text(@kind)}
        </.button>
        <.button
          id="correction-editor-cancel"
          type="button"
          phx-click="edit_cancel"
          phx-target={@target}
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
