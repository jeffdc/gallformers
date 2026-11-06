defmodule GallformersWeb.RecordRemoval do
  @moduledoc """
  Delete and merge for a Gall or a taxon, where its page is edited (matter
  `ec2c`, "Deletes"): the Gall page in Edit mode, a plant's page in Edit
  mode and the taxonomy admin's page of a taxon. A `:danger` panel at the
  foot of the rail (patterns.md, "Admin edit page") with Delete… and, for a
  Gall or a plant, Merge into another….

    * **Delete** works out what the delete would do
      (`Gallformers.Import.deletion_impact/1`) when asked: what blocks it,
      each blocker with what to do instead, or the impact itemised in the
      typed-name confirmation (`dangerous_delete_modal`). Deleting
      (`Gallformers.Import.record_deletion/2`) rechecks under the tree lock;
      "already deleted (by another curator)" and a blocker found then are
      said.
    * **Merge** picks the record to keep by name, previews the merge
      (`Gallformers.Import.merge_preview/2`, the real merge rolled back):
      each Fact and what happens to it, the alias, the redirects, the
      photos, the note, what blocks it; then asks for the absorbed name
      typed (`Gallformers.Import.record_merge/2`).

  Assigns: `id`, `subject` (`{:gall, id}` or `{:taxon, id}`), `name` (the
  record's name, for the titles), `actor`, `merge` (`:gall`, `:plant` or
  `nil`), `deleted_path` (where to go after a delete) and `merged_path` (a
  function: the kept record's id → where to go after a merge).
  """
  use GallformersWeb, :live_component

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank

  # Names listed in a consequence before "and N more".
  @listed 12

  @impl true
  def mount(socket) do
    {:ok, assign(socket, delete: nil, merge_state: nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     assign(socket,
       id: assigns.id,
       subject: assigns.subject,
       name: assigns.name,
       actor: assigns.actor,
       merge: Map.get(assigns, :merge),
       deleted_path: assigns.deleted_path,
       merged_path: Map.get(assigns, :merged_path)
     )}
  end

  # -- delete --------------------------------------------------------------------

  @impl true
  def handle_event("open_delete", _params, socket) do
    case Import.deletion_impact(socket.assigns.subject) do
      {:ok, impact} -> {:noreply, assign(socket, delete: %{impact: impact, confirmation: ""})}
      {:error, :not_found} -> {:noreply, gone(socket)}
    end
  end

  def handle_event("update_delete_confirmation", %{"value" => value}, socket),
    do: {:noreply, update(socket, :delete, &%{&1 | confirmation: value})}

  def handle_event(event, _params, socket) when event in ["cancel_delete", "close_delete"],
    do: {:noreply, assign(socket, delete: nil)}

  def handle_event("confirm_delete", %{"confirmation" => typed}, socket) do
    %{delete: %{impact: impact}, actor: actor, subject: subject} = socket.assigns

    if typed != impact.subject.name do
      {:noreply, update(socket, :delete, &%{&1 | confirmation: typed})}
    else
      case Import.record_deletion(actor, subject) do
        {:ok, %{storage_errors: errors}} ->
          {:noreply,
           socket
           |> put_flash(:info, deleted_message(impact, errors))
           |> push_navigate(to: socket.assigns.deleted_path)}

        {:error, {:blocked, blockers}} ->
          blocked = %{impact | blockers: blockers, deletable: false}
          {:noreply, assign(socket, delete: %{impact: blocked, confirmation: ""})}

        {:error, :not_found} ->
          {:noreply, gone(socket)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(delete: nil)
           |> put_flash(:error, "#{impact.subject.name} couldn't be deleted: #{inspect(reason)}.")}
      end
    end
  end

  # -- merge ---------------------------------------------------------------------

  def handle_event("open_merge", _params, socket) do
    {:noreply,
     assign(socket,
       merge_state: %{query: "", results: [], survivor: nil, preview: nil, confirmation: ""}
     )}
  end

  def handle_event("close_merge", _params, socket),
    do: {:noreply, assign(socket, merge_state: nil)}

  def handle_event("search_survivor", %{"value" => query}, socket) do
    results = survivors(socket.assigns, query)
    {:noreply, update(socket, :merge_state, &%{&1 | query: query, results: results})}
  end

  def handle_event("select_survivor", %{"id" => id}, socket) do
    %{merge_state: state} = socket.assigns

    case Enum.find(state.results, &("#{&1.id}" == id)) do
      nil ->
        {:noreply, socket}

      survivor ->
        preview = Import.merge_preview(spec(socket.assigns, survivor.id), socket.assigns.actor)

        {:noreply,
         assign(socket,
           merge_state: %{
             state
             | survivor: survivor,
               query: "",
               results: [],
               preview: preview,
               confirmation: ""
           }
         )}
    end
  end

  def handle_event("clear_survivor", _params, socket) do
    {:noreply,
     update(
       socket,
       :merge_state,
       &%{&1 | survivor: nil, preview: nil, query: "", results: [], confirmation: ""}
     )}
  end

  def handle_event("merge_confirmation", %{"confirmation" => typed}, socket),
    do: {:noreply, update(socket, :merge_state, &%{&1 | confirmation: typed})}

  def handle_event("confirm_merge", %{"confirmation" => typed}, socket) do
    %{merge_state: state, actor: actor} = socket.assigns

    with {:ok, preview} <- state.preview,
         true <- typed == preview.absorbed.name do
      case Import.record_merge(actor, spec(socket.assigns, state.survivor.id)) do
        {:ok, result} ->
          {:noreply,
           socket
           |> put_flash(:info, merged_message(result))
           |> push_navigate(to: socket.assigns.merged_path.(result.survivor.id))}

        {:error, :not_found} ->
          {:noreply, gone(socket)}

        {:error, reason} ->
          {:noreply,
           assign(socket, merge_state: %{state | preview: {:error, reason}, confirmation: ""})}
      end
    else
      _ -> {:noreply, update(socket, :merge_state, &%{&1 | confirmation: typed})}
    end
  end

  defp spec(%{merge: type, subject: {_kind, id}}, survivor_id), do: {type, id, survivor_id}

  defp survivors(%{merge: :gall, subject: {:gall, id}}, query) do
    if long_enough?(query),
      do: query |> Catalog.search_galls() |> Enum.reject(&(&1.id == id)) |> Enum.take(20),
      else: []
  end

  defp survivors(%{merge: :plant, subject: {:taxon, id}}, query) do
    if long_enough?(query) do
      query
      |> Taxa.search_plants(25)
      |> Enum.filter(&(&1.id != id and &1.rank in Rank.species_and_below()))
      |> Enum.take(20)
    else
      []
    end
  end

  defp long_enough?(query), do: String.length(String.trim(query)) >= 2

  # Deleted, or merged away, since the page loaded: by another curator, most
  # likely.
  defp gone(socket) do
    socket
    |> put_flash(
      :error,
      "#{socket.assigns.name} is already gone: another curator deleted or merged it."
    )
    |> push_navigate(to: socket.assigns.deleted_path)
  end

  defp deleted_message(impact, []), do: "Deleted #{impact.subject.name}."

  defp deleted_message(impact, errors),
    do:
      "Deleted #{impact.subject.name}. #{count(length(errors), "stored image file", "stored image files")} couldn't be removed from storage; an operator can remove them."

  defp merged_message(result) do
    questions =
      case result.conflicts do
        [] ->
          ""

        list ->
          " #{count(length(list), "same-date tie waits", "same-date ties wait")} as a question in Review."
      end

    "Merged #{result.absorbed.name} into #{result.survivor.name}.#{questions}"
  end

  # -- words ---------------------------------------------------------------------

  @doc false
  # The impact of a delete, one line each, for the typed-name confirmation.
  def consequences(impact) do
    [
      taxa_line(impact),
      collapse_line(impact),
      galls_line(impact),
      facts_line(impact),
      impact.images != [] &&
        "#{count(length(impact.images), "photo is", "photos are")} deleted and removed from storage.",
      notes_line(impact.notes),
      impact.legacy_citations != [] &&
        "#{count(length(impact.legacy_citations), "legacy citation is", "legacy citations are")} deleted.",
      Enum.map(impact.cleanup, & &1.text),
      "The deletion is audited and recorded in the replay log."
    ]
    |> List.flatten()
    |> Enum.filter(&is_binary/1)
  end

  defp taxa_line(%{operation: :cascade, taxa: [_subject | under]}) when under != [],
    do:
      "#{count(length(under), "taxon under it is", "taxa under it are")} deleted: #{names(under, &rank_name/1)}."

  defp taxa_line(_impact), do: nil

  defp collapse_line(%{operation: :collapse, children: [_ | _] = children, parent: parent}) do
    to = if parent, do: rank_name(parent), else: "the root"

    "Its #{count(length(children), "child moves", "children move")} to #{to}: #{names(children, &rank_name/1)}."
  end

  defp collapse_line(_impact), do: nil

  defp galls_line(%{subject: %{type: :gall}, galls: [_]}), do: nil

  defp galls_line(%{galls: [_ | _] = galls}),
    do: "#{count(length(galls), "Gall is", "Galls are")} deleted: #{names(galls, & &1.name)}."

  defp galls_line(_impact), do: nil

  defp facts_line(%{facts: []}), do: nil

  defp facts_line(%{facts: facts, sources: sources}) do
    by =
      case Enum.map(sources, & &1.name) do
        [] -> ""
        names -> ", stated only by " <> Enum.join(names, " and ")
      end

    "#{count(length(facts), "Fact is", "Facts are")} deleted#{by}."
  end

  defp notes_line([]), do: nil

  defp notes_line(notes) do
    versions = notes |> Enum.map(& &1.versions) |> Enum.sum()
    "#{count(versions, "Gallformers note version is", "Gallformers note versions are")} deleted."
  end

  defp names(items, name) do
    {shown, rest} = Enum.split(items, @listed)
    listed = Enum.map_join(shown, ", ", name)
    if rest == [], do: listed, else: "#{listed} and #{length(rest)} more"
  end

  defp rank_name(%{name: name, rank: rank}) when not is_nil(rank), do: "#{name} (#{rank})"
  defp rank_name(%{name: name}), do: name

  defp count(1, one, _many), do: "1 #{one}"
  defp count(n, _one, many), do: "#{n} #{many}"

  defp kind_word(%{merge: :gall}), do: "Gall"
  defp kind_word(%{merge: :plant}), do: "plant"
  defp kind_word(%{subject: {:gall, _}}), do: "Gall"
  defp kind_word(_assigns), do: "taxon"

  defp outcome(:moved), do: {:ok, "moves over"}
  defp outcome(:combined), do: {:info, "joins the kept Gall's"}
  defp outcome(:dropped), do: {:neutral, "dropped"}
  defp outcome(other), do: {:neutral, to_string(other)}

  defp note_word(:appended), do: "appended to the kept Gall's, under a heading, as a new version"
  defp note_word(:moved), do: "moves over"
  defp note_word(:kept), do: "the kept Gall's stays"
  defp note_word(_none), do: nil

  defp merge_error(:same_record), do: "That is the same record."
  defp merge_error(:not_a_plant), do: "Only plants at species rank or below merge."

  defp merge_error(:not_found),
    do: "One of the two is gone: deleted or merged by another curator."

  defp merge_error(reason), do: "The merge can't be worked out: #{inspect(reason)}."

  # -- render --------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, kind: kind_word(assigns))

    ~H"""
    <div id={@id}>
      <.panel variant={:danger} title={if @merge, do: "Delete or merge", else: "Delete"}>
        <p class="mb-3 text-ui text-ink-2">
          Delete a {@kind} that should never have existed (a test entry, a duplicate typed by mistake).<span :if={
            @merge
          }>
            Merge one recorded twice: its Facts, with their Sources, move to the {@kind} you keep.</span>
        </p>
        <div class="flex flex-wrap gap-2">
          <.button variant="danger" size="sm" phx-click="open_delete" phx-target={@myself}>
            Delete…
          </.button>
          <.button
            :if={@merge}
            variant="secondary"
            size="sm"
            phx-click="open_merge"
            phx-target={@myself}
          >
            Merge into another {@kind}…
          </.button>
        </div>
      </.panel>

      <.dialog
        :if={@delete && !@delete.impact.deletable}
        id={"#{@id}-blocked"}
        title={"#{@delete.impact.subject.name} can't be deleted"}
        size={:md}
        show
        on_cancel={JS.push("close_delete", target: @myself)}
      >
        <ul class="flex flex-col gap-2 text-ui">
          <li :for={blocker <- @delete.impact.blockers} data-part="blocker">
            <p class="text-ink">{blocker.text}</p>
            <p :if={blocker.action} class="text-meta text-ink-2">{blocker.action}</p>
          </li>
        </ul>
        <:actions>
          <.button type="button" variant="secondary" phx-click="close_delete" phx-target={@myself}>
            Close
          </.button>
        </:actions>
      </.dialog>

      <.dangerous_delete_modal
        show={@delete != nil and @delete.impact.deletable}
        item_type={@kind}
        item_name={@delete && @delete.impact.subject.name}
        consequences={(@delete && consequences(@delete.impact)) || []}
        confirmation_value={@delete && @delete.confirmation}
        target={@myself}
      />

      <.dialog
        :if={@merge_state}
        id={"#{@id}-merge"}
        title={"Merge #{@name} into another #{@kind}"}
        size={:lg}
        show
        on_cancel={JS.push("close_merge", target: @myself)}
      >
        <div class="flex flex-col gap-block">
          <p class="text-ui text-ink-2">
            For the same {@kind} recorded twice. {@name} goes; the {@kind} you keep keeps its name<span :if={
              @merge == :gall
            }>, code, completeness and abundance</span>, and {@name}'s ID<span :if={@merge == :gall}> and code</span> redirect to it.
          </p>
          <.typeahead
            id="merge-survivor"
            label={"The #{@kind} to keep"}
            placeholder={"Find a #{@kind} by name"}
            search_event="search_survivor"
            select_event="select_survivor"
            clear_event="clear_survivor"
            query={@merge_state.query}
            results={@merge_state.results}
            selected={@merge_state.survivor}
            display_fn={& &1.name}
            target={@myself}
          />
          <.merge_preview
            :if={@merge_state.preview}
            preview={@merge_state.preview}
            confirmation={@merge_state.confirmation}
            target={@myself}
          />
        </div>
        <:actions>
          <.button type="button" variant="ghost" phx-click="close_merge" phx-target={@myself}>
            Cancel
          </.button>
          <.button
            :if={match?({:ok, %{blockers: []}}, @merge_state.preview)}
            id="merge-submit"
            type="submit"
            form="merge-confirm"
            variant="danger"
            disabled={@merge_state.confirmation != elem(@merge_state.preview, 1).absorbed.name}
          >
            Merge into {elem(@merge_state.preview, 1).survivor.name}
          </.button>
        </:actions>
      </.dialog>
    </div>
    """
  end

  attr :preview, :any, required: true
  attr :confirmation, :string, required: true
  attr :target, :any, required: true

  defp merge_preview(%{preview: {:error, reason}} = assigns) do
    assigns = assign(assigns, text: merge_error(reason))

    ~H"""
    <div id="merge-preview">
      <.notice kind={:danger}>{@text}</.notice>
    </div>
    """
  end

  defp merge_preview(%{preview: {:ok, result}} = assigns) do
    assigns = assign(assigns, r: result)

    ~H"""
    <div id="merge-preview" class="flex flex-col gap-block">
      <.notice :if={@r.blockers != []} kind={:danger} title="It can't be merged">
        <ul class="mt-1 flex flex-col gap-1">
          <li :for={blocker <- @r.blockers} data-part="blocker">
            {blocker.text}<span :if={blocker.action} class="text-ink-2"> {blocker.action}</span>
          </li>
        </ul>
      </.notice>

      <.section title={"Merging into #{@r.survivor.name}"} level={3}>
        <.fact_list layout={:inline} missing_label={nil}>
          <:item :if={@r[:alias]} label="Becomes an alias">{@r.alias}</:item>
          <:item :if={@r[:synonyms] not in [nil, []]} label="Become synonyms">
            {Enum.join(@r.synonyms, ", ")}
          </:item>
          <:item :if={@r[:common_names] not in [nil, []]} label="Common names moved">
            {Enum.join(@r.common_names, ", ")}
          </:item>
          <:item label="Redirects">
            ID {@r.redirects.id}<span :if={@r.redirects[:code]}>, code {@r.redirects.code}</span>
          </:item>
          <:item :if={@r.images > 0} label="Photos moved">{@r.images}</:item>
          <:item :if={note_word(@r[:note])} label="Gallformers note">{note_word(@r.note)}</:item>
          <:item :if={@r[:galls_requalified] not in [nil, []]} label="Galls renamed">
            {length(@r.galls_requalified)} (their names name the plant)
          </:item>
          <:item :if={@r[:range] && @r.range.dropped > 0} label="Range dropped">
            {@r.range.dropped} places (the kept plant's range stands)
          </:item>
          <:item :for={r <- @r[:repointed] || []} label="Re-pointed">{r.text}</:item>
          <:item :if={@r.standings != []} label="Standings change">
            {Enum.map_join(@r.standings, "; ", & &1.text)}
          </:item>
          <:item :if={@r.conflicts != []} label="Questions for Review">
            {Enum.map_join(@r.conflicts, "; ", & &1.text)}
          </:item>
          <:item :for={c <- @r.cleanup} label="Also">{c.text}</:item>
        </.fact_list>
      </.section>

      <.section title="Facts" count={length(@r.facts)} level={3}>
        <.data_table
          :if={@r.facts != []}
          id="merge-facts"
          rows={@r.facts}
          row_id={&"merge-fact-#{&1.from}"}
          compact
        >
          <:col :let={f} label="Fact" grow>{f.text}</:col>
          <:col :let={f} label="What happens">
            <.chip variant={elem(outcome(f.outcome), 0)} size="sm">
              {elem(outcome(f.outcome), 1)}
            </.chip>
          </:col>
          <:col :let={f} label="Sources" wrap>{Enum.map_join(f.sources, ", ", & &1.name)}</:col>
        </.data_table>
        <p :if={@r.facts == []} class="text-ui text-muted">No Facts to move.</p>
      </.section>

      <form
        :if={@r.blockers == []}
        id="merge-confirm"
        phx-submit="confirm_merge"
        phx-change="merge_confirmation"
        phx-target={@target}
      >
        <.field label={"Type #{@r.absorbed.name} to confirm"} for="merge-confirmation">
          <input
            type="text"
            id="merge-confirmation"
            name="confirmation"
            value={@confirmation}
            autocomplete="off"
            autocapitalize="off"
            spellcheck="false"
            class="gf-input"
          />
        </.field>
      </form>
    </div>
    """
  end
end
