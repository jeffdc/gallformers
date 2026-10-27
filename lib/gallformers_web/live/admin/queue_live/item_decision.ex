defmodule GallformersWeb.Admin.QueueLive.ItemDecision do
  @moduledoc """
  One review-queue item (`Gallformers.Import.QueueItem`) with its decision
  controls, on the queue and package pages (matter a856, Task 3).

  What an item may be decided as follows its kind and what it is about
  (`Gallformers.Import.Queue`): a taxon picks a candidate (or another taxon
  by ID) or is skipped; a Gall picks a candidate, is new or is skipped; the
  package's Source picks a candidate or is new; the Source a notice
  retracts picks a candidate or is skipped; a dispute keeps or drops the
  statement; a rename proposal is accepted or rejected; the rest are
  acknowledged. Any decision may carry a note.

  Decisions go through `Gallformers.Import.decide_queue_item/3` as the
  page's actor. A decided item tells the page (`{__MODULE__, {:decided,
  item}}`) and shows its decision; a refused one shows why.

  Attributes: `item`, `actor`, `names` (from `names/2`: the names of the
  taxa, Galls and Sources the items speak of) and `show_package` (link to
  the item's package).
  """
  use GallformersWeb, :live_component

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Sources
  alias Gallformers.Taxa

  @kind_labels %{
    ambiguous_match: "Ambiguous match",
    unresolved_name: "Unresolved name",
    unresolved_host: "Unresolved Host",
    undescribed_gall: "Undescribed-Gall candidate",
    dispute: "Dispute",
    same_date_conflict: "Same-date conflict",
    taxonomy_disagreement: "Taxonomy disagreement",
    generation_outside_group: "Generation outside its group",
    gall_rename: "Gall rename proposal"
  }

  # How a decided item's choice reads (the rest are named in choice_text/3).
  @choice_texts %{
    "new" => "new",
    "keep" => "statement kept",
    "accept" => "rename accepted",
    "reject" => "rename rejected"
  }

  @typedoc "Names by ID of the taxa, Galls and Sources a page's items speak of."
  @type names :: %{
          taxa: %{integer() => String.t()},
          galls: %{integer() => String.t()},
          sources: %{integer() => String.t()}
        }

  @doc "A queue item kind's label."
  @spec kind_label(QueueItem.kind()) :: String.t()
  def kind_label(kind), do: Map.fetch!(@kind_labels, kind)

  @doc """
  The names of the taxa, Galls and Sources that `items` and `statements`
  (`Gallformers.Import.BatchStatement`s) speak of, by ID: three queries.
  """
  @spec names([QueueItem.t()], [map()]) :: names()
  def names(items, statements \\ []) do
    ids = Enum.reduce(items, %{taxa: [], galls: [], sources: []}, &item_ids/2)
    ids = Enum.reduce(statements, ids, &statement_ids/2)

    %{
      taxa:
        ids.taxa
        |> Enum.uniq()
        |> Taxa.lineages()
        |> Map.new(fn {id, lineage} -> {id, List.last(lineage).name} end),
      galls: ids.galls |> Catalog.list_galls_by_id() |> Map.new(&{&1.id, display_name(&1)}),
      sources:
        ids.sources |> Enum.uniq() |> Sources.list_sources_by_id() |> Map.new(&{&1.id, &1.title})
    }
  end

  defp display_name(%{name_override: override}) when is_binary(override), do: override
  defp display_name(%{name: name}), do: name

  defp item_ids(%QueueItem{} = item, acc) do
    candidates = ints([item.proposal["proposed"] | List.wrap(item.proposal["candidate_ids"])])

    acc =
      case pick(item) do
        nil -> acc
        :taxon -> add(acc, :taxa, candidates)
        :gall -> add(acc, :galls, candidates)
        :source -> add(acc, :sources, candidates)
      end

    decision = item.decision || %{}

    acc
    |> add(:galls, ints([item.subject["gall_id"], decision["gall_id"]]))
    |> add(:taxa, ints([item.subject["inducer_id"], decision["taxon_id"]]))
    |> add(:sources, ints([decision["source_id"]]))
  end

  defp statement_ids(%{kind: :taxon} = s, acc),
    do: add(acc, :taxa, ints([s.taxon_id | s.candidate_ids]))

  defp statement_ids(%{kind: :gall} = s, acc),
    do: add(acc, :galls, ints([s.gall_id | s.candidate_ids]))

  defp statement_ids(_statement, acc), do: acc

  defp add(acc, key, ids), do: Map.update!(acc, key, &(ids ++ &1))
  defp ints(values), do: Enum.filter(values, &is_integer/1)

  # -- what an item may be decided as -------------------------------------------

  # What a decision picks among (nil: nothing to pick), as in
  # Gallformers.Import.Queue.
  defp pick(%QueueItem{statement_ref: ref}) when ref in ["source", "retracts"], do: :source
  defp pick(%QueueItem{kind: kind}) when kind in [:dispute, :gall_rename], do: nil

  defp pick(%QueueItem{kind: kind})
       when kind in [:same_date_conflict, :generation_outside_group],
       do: nil

  defp pick(%QueueItem{statement_ref: "t" <> _}), do: :taxon
  defp pick(%QueueItem{kind: :taxonomy_disagreement}), do: nil
  defp pick(%QueueItem{statement_ref: "g" <> _}), do: :gall
  defp pick(_item), do: nil

  # The other choices, as {value, label}.
  defp options(%QueueItem{statement_ref: "source"}), do: [{"new", "New Source"}]
  defp options(%QueueItem{statement_ref: "retracts"}), do: [{"skip", "Skip"}]

  defp options(%QueueItem{kind: :dispute}),
    do: [{"keep", "Keep the statement"}, {"skip", "Drop the statement"}]

  defp options(%QueueItem{kind: :gall_rename}),
    do: [{"accept", "Accept the rename"}, {"reject", "Reject (keep the name)"}]

  defp options(%QueueItem{kind: :taxonomy_disagreement, statement_ref: "t" <> _}),
    do: [{"ack", "Acknowledge"}, {"skip", "Skip"}]

  defp options(%QueueItem{kind: kind} = item)
       when kind not in [:same_date_conflict, :generation_outside_group] do
    case pick(item) do
      :taxon -> [{"skip", "Skip"}]
      :gall -> [{"new", "New Gall"}, {"skip", "Skip"}]
      _ -> [{"ack", "Acknowledge"}]
    end
  end

  defp options(_item), do: [{"ack", "Acknowledge"}]

  # -- the component -------------------------------------------------------------

  @impl true
  def mount(socket), do: {:ok, assign(socket, error: nil)}

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:show_package, fn -> false end)
     |> assign_new(:form, fn -> decision_form(assigns.item, %{"note" => "", "other_id" => ""}) end)
     |> assign(:pick, pick(assigns.item))
     |> assign(:options, options(assigns.item))}
  end

  # Each item's form has its own input IDs.
  defp decision_form(item, fields), do: to_form(fields, as: :decision, id: "decision-#{item.id}")

  @impl true
  def handle_event("decide", %{"choice" => choice} = params, socket) do
    fields = Map.get(params, "decision", %{})

    with {:ok, decision} <- parse(choice, fields),
         {:ok, item} <-
           Import.decide_queue_item(socket.assigns.actor, socket.assigns.item, decision) do
      send(self(), {__MODULE__, {:decided, item}})
      {:noreply, assign(socket, item: item, error: nil)}
    else
      {:error, :already_decided} ->
        {:noreply, assign(socket, error: "This item has been decided already; reload to see it.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           error: changeset_error(changeset),
           form: decision_form(socket.assigns.item, fields)
         )}

      {:error, message} when is_binary(message) ->
        {:noreply,
         assign(socket, error: message, form: decision_form(socket.assigns.item, fields))}
    end
  end

  def handle_event("decide", _params, socket),
    do: {:noreply, assign(socket, error: "Choose a decision.")}

  defp parse(choice, fields) do
    with {:ok, decision} <- parse_choice(choice, fields) do
      case String.trim(fields["note"] || "") do
        "" -> {:ok, decision}
        note -> {:ok, Map.put(decision, "note", note)}
      end
    end
  end

  defp parse_choice(choice, _fields) when choice in ~w(new skip keep accept reject),
    do: {:ok, %{choice => true}}

  defp parse_choice("ack", _fields), do: {:ok, %{}}

  defp parse_choice(choice, fields) do
    with [key, value] when key in ~w(taxon_id gall_id source_id) <-
           String.split(choice, ":", parts: 2),
         value = if(value == "other", do: String.trim(fields["other_id"] || ""), else: value),
         {id, ""} <- Integer.parse(value) do
      {:ok, %{key => id}}
    else
      _ -> {:error, "Enter an ID (a whole number) for the choice."}
    end
  end

  defp changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> Enum.join("; ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"queue-item-#{@item.id}"}
      class="border border-gray-200 rounded-lg p-4 space-y-3 bg-white"
    >
      <div class="flex flex-wrap items-center gap-2">
        <.badge variant={if @item.status == :open, do: "warning", else: "success"}>
          {kind_label(@item.kind)}
        </.badge>
        <span :if={@item.statement_ref} class="font-mono text-sm text-gray-600">
          {@item.statement_ref}
        </span>
        <.link
          :if={@show_package && @item.package_id}
          navigate={~p"/admin/queue/packages/#{@item.package_id}"}
          class="text-sm text-gf-maroon hover:underline"
        >
          {package_label(@item)}
        </.link>
      </div>

      <p :if={@item.reason} class="text-sm text-gray-700">{@item.reason}</p>

      <.subject item={@item} names={@names} />

      <%= if @item.status == :open do %>
        <.form
          for={@form}
          id={"decide-#{@item.id}"}
          phx-submit="decide"
          phx-target={@myself}
          class="space-y-3"
        >
          <div :if={@pick} class="space-y-2">
            <p :if={candidates(@item) != []} class="text-sm font-medium text-gray-700">
              {pick_label(@pick)}
            </p>
            <div class="flex flex-wrap gap-2">
              <.button
                :for={id <- candidates(@item)}
                type="submit"
                name="choice"
                value={"#{pick_key(@pick)}:#{id}"}
                size="sm"
              >
                {name_of(@names, @pick, id)}
                <span :if={@item.proposal["proposed"] == id} class="text-xs">(proposed)</span>
              </.button>
            </div>
            <div class="flex flex-wrap items-end gap-2">
              <div class="w-48">
                <.input
                  field={@form[:other_id]}
                  type="number"
                  label={"Another #{pick_noun(@pick)} by ID"}
                />
              </div>
              <.button type="submit" name="choice" value={"#{pick_key(@pick)}:other"} size="sm">
                Use this ID
              </.button>
            </div>
          </div>

          <.input field={@form[:note]} type="textarea" label="Note (optional)" rows="2" />

          <div class="flex flex-wrap gap-2">
            <.button
              :for={{value, label} <- @options}
              type="submit"
              name="choice"
              value={value}
              size="sm"
              variant={if value in ~w(accept keep ack), do: "primary", else: "secondary"}
            >
              {label}
            </.button>
          </div>

          <.alert :if={@error} variant="error">{@error}</.alert>
        </.form>
      <% else %>
        <p class="text-sm text-gray-700">
          <span class="font-medium">Decided:</span>
          {describe_decision(@item, @names)}
          <span :if={@item.decided_by_name}>by {@item.decided_by_name}</span>
          <span :if={@item.decided_at}>on {format_date(@item.decided_at, :short)}</span>
        </p>
      <% end %>
    </div>
    """
  end

  attr :item, QueueItem, required: true
  attr :names, :map, required: true

  defp subject(%{item: %QueueItem{kind: :gall_rename}} = assigns) do
    ~H"""
    <div class="text-sm space-y-2">
      <p>
        <.link
          navigate={~p"/gall/#{@item.proposal["gall_id"]}"}
          class="text-gf-maroon hover:underline"
        >
          {@item.proposal["from"]}
        </.link>
        <.icon name="ph-arrow-right" class="size-4 inline" />
        <span class="font-medium">{@item.proposal["to"]}</span>
      </p>
      <.alert :if={@item.proposal["collision"]} id={"collision-#{@item.id}"} variant="warning">
        {@item.proposal["to"]} is already the name of another Gall (ignoring case): accepting is
        refused until that Gall's name changes.
      </.alert>
    </div>
    """
  end

  defp subject(%{item: %QueueItem{kind: :dispute}} = assigns) do
    ~H"""
    <ul class="text-sm space-y-2">
      <li
        :for={finding <- List.wrap(@item.subject["findings"])}
        class="border-l-2 border-gray-200 pl-3"
      >
        <p :if={finding["problem"]}>
          <span class="font-medium">{finding["problem"]}</span>
          <span :if={finding["reviewer"]} class="text-gray-500">({finding["reviewer"]})</span>
        </p>
        <p :if={finding["reason"]}>Reviewer: {finding["reason"]}</p>
        <p :if={finding["suggestion"]}>Suggestion: {finding["suggestion"]}</p>
        <p :if={get_in(finding, ["response", "reason"])}>
          Producer: {get_in(finding, ["response", "reason"])}
        </p>
      </li>
    </ul>
    """
  end

  defp subject(assigns) do
    assigns = assign(assigns, :rows, subject_rows(assigns.item, assigns.names))

    ~H"""
    <dl :if={@rows != []} class="text-sm grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1">
      <%= for {label, value} <- @rows do %>
        <dt class="text-gray-500">{label}</dt>
        <dd>{value}</dd>
      <% end %>
    </dl>
    """
  end

  defp subject_rows(%QueueItem{subject: subject}, names) do
    subject
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Enum.flat_map(fn
      {"gall_id", id} ->
        [{"Gall", name_of(names, :gall, id)}]

      {"inducer_id", id} ->
        [{"Inducer", name_of(names, :taxon, id)}]

      {key, value} when is_binary(value) or is_number(value) ->
        [{humanize(key), to_string(value)}]

      {key, true} ->
        [{humanize(key), "yes"}]

      {key, values} when is_list(values) ->
        list_row(key, values)

      _other ->
        []
    end)
  end

  defp list_row(key, values) do
    if values != [] and Enum.all?(values, &(is_binary(&1) or is_number(&1))),
      do: [{humanize(key), Enum.join(values, ", ")}],
      else: []
  end

  defp humanize(key), do: key |> String.replace("_", " ") |> String.capitalize()

  defp candidates(%QueueItem{proposal: proposal}),
    do: proposal |> Map.get("candidate_ids", []) |> List.wrap() |> Enum.filter(&is_integer/1)

  defp pick_key(:taxon), do: "taxon_id"
  defp pick_key(:gall), do: "gall_id"
  defp pick_key(:source), do: "source_id"

  defp pick_noun(:taxon), do: "taxon"
  defp pick_noun(:gall), do: "Gall"
  defp pick_noun(:source), do: "Source"

  defp pick_label(:taxon), do: "It is this taxon:"
  defp pick_label(:gall), do: "It is this Gall:"
  defp pick_label(:source), do: "It is this Source:"

  defp name_of(names, :taxon, id), do: Map.get(names.taxa, id, "taxon #{id}")
  defp name_of(names, :gall, id), do: Map.get(names.galls, id, "Gall #{id}")
  defp name_of(names, :source, id), do: Map.get(names.sources, id, "Source #{id}")

  defp package_label(%QueueItem{package: %{key: key}}), do: "Package #{key}"
  defp package_label(%QueueItem{package_id: id}), do: "Package #{id}"

  defp describe_decision(%QueueItem{decision: decision} = item, names) do
    {note, choice} = Map.pop(decision || %{}, "note")

    text = choice_text(Map.to_list(choice), item.kind, names)
    if note, do: "#{text} (#{note})", else: text
  end

  defp choice_text([], _kind, _names), do: "acknowledged"
  defp choice_text([{"taxon_id", id}], _kind, names), do: name_of(names, :taxon, id)
  defp choice_text([{"gall_id", id}], _kind, names), do: name_of(names, :gall, id)
  defp choice_text([{"source_id", id}], _kind, names), do: name_of(names, :source, id)
  defp choice_text([{"skip", true}], :dispute, _names), do: "statement dropped"
  defp choice_text([{"skip", true}], _kind, _names), do: "skipped"

  defp choice_text([{key, true}], _kind, _names) when is_map_key(@choice_texts, key),
    do: @choice_texts[key]

  defp choice_text(choice, _kind, _names), do: inspect(Map.new(choice))
end
