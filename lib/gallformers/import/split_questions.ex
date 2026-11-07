defmodule Gallformers.Import.SplitQuestions do
  @moduledoc """
  Split questions (matter `f923` Task 7, "Splits"): nearly all Facts are
  about Galls, not the Inducer, so an accepted split of A into daughters
  (A itself may be one, in its narrow sense) changes each affected Gall's
  Inducer and nothing else. Its other Facts and their Sources follow the
  Gall untouched, and its derived name changes through the reviewed rename
  flow (`Gallformers.Import.GallRenames`, `86e7`).

  ## When a split comes into effect

  This module is a "taxon changed" listener (`Gallformers.Taxa.Events`,
  registered in `config/config.exs`): on a `:split` event
  (`Gallformers.Taxa.Sync` emits one when a Source's split statement starts
  to count, with the split Fact), inside the acceptance's transaction, for
  each Gall whose current Inducer is A
  (`Gallformers.Catalog.galls_on_inducer/1`):

    1. **The splitting paper covers it** — its own gall statements state
       one daughter as the Gall's Inducer (`Gallformers.Catalog.stated_inducers/3`):
       the Gall's Inducer becomes that daughter, credited to the paper (its
       statement is there already; the older ones move onto it,
       `Gallformers.Catalog.repoint_inducer/4`), and its rename is
       proposed. No question. A paper stating A itself (narrow) leaves it.
    2. **Otherwise** one question per Gall (never per Fact), a
       `:split_inducer` queue item of no package: "Which taxon induces this
       Gall now?" — each daughter, or not known yet. `subject` is
       `%{"gall_id", "taxon_id", "into_taxon_ids", "fact_id", "source_id"}`
       (A, the daughters, the split Fact and its Source); `proposal` the
       daughter the paper's statements suggest (`%{"taxon_id", "why"}`: its
       Galls share a Host with this one, `Gallformers.Catalog.split_suggestions/3`),
       else empty; a suggestion is never accepted in bulk. A Gall has at
       most one open.

  Older Sources' statements are never rewritten: they move with their
  `name_as_written`, so readers see a 1950 paper said "A" for the broad A.

  ## Answers

  Through `Gallformers.Import.decide_queue_item/3`: `%{"taxon_id" => id}`
  (a daughter) re-points the Gall's Inducer from A to it and proposes the
  rename (A itself keeps it, unmarked), the decision keeping what moved
  (`moved/5`) so that Undo moves back exactly that; `%{"not_known" => true}` keeps it
  on A, marked as following the name in its old broad sense
  (`Gallformers.Catalog.mark_broad_sense/4`), until a later Source settles
  it. Refused when the Gall's Inducer is no longer A. Audited with the
  decision; logged in the replay log as a `:queue_decision` keyed by the
  Gall and A (`replay_key/1`): replaying the acceptance asks again, and
  replay decides it (`find/2`).
  """
  @behaviour Gallformers.Taxa.Events

  import Ecto.Query, only: [from: 2, where: 3]

  alias Ecto.Changeset
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Import.GallRenames
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.StableRef
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Event

  @kind :split_inducer

  # -- when a split comes into effect --------------------------------------------

  @impl true
  def taxon_changed(%Event{type: :split, taxon_id: split_id} = event) do
    {:ok, actor} = Audit.current_actor()
    into = Enum.sort(event.into_taxon_ids)

    sources =
      (event.fact_id && Map.get(Catalog.split_sources([event.fact_id]), event.fact_id)) || []

    source_ids = Enum.map(sources, & &1.source_id)
    galls = Catalog.galls_on_inducer(split_id)
    stated = Catalog.stated_inducers(galls, source_ids, into)

    {covered, asked} =
      Enum.split_with(galls, &match?([_], Map.get(stated, &1)))

    moved =
      for gall_id <- covered, [daughter] = stated[gall_id], daughter != split_id do
        {:ok, _} = Catalog.repoint_inducer(actor, gall_id, split_id, daughter)
        gall_id
      end

    reason = reason(sources, split_id, into)
    :ok = GallRenames.propose_for_galls(moved, reason)

    suggestions = Catalog.split_suggestions(asked, source_ids, into)
    first = List.first(sources)

    Enum.each(asked, fn gall_id ->
      ask(
        %{
          "gall_id" => gall_id,
          "taxon_id" => split_id,
          "into_taxon_ids" => into,
          "fact_id" => event.fact_id,
          "source_id" => first && first.source_id
        },
        proposal(suggestions[gall_id], first),
        reason
      )
    end)
  end

  def taxon_changed(%Event{}), do: :ok

  defp reason(sources, split_id, into) do
    who =
      case sources do
        [%{source: name} | _] when is_binary(name) -> name
        _ -> "A Source"
      end

    "#{who} split #{Taxa.accepted_name(split_id)} into #{and_list(Enum.map(into, &Taxa.accepted_name/1))}."
  end

  defp proposal(nil, _source), do: %{}

  defp proposal(%{taxon_id: taxon_id, hosts: hosts}, source) do
    who = (source && source.source) || "The Source"

    %{
      "taxon_id" => taxon_id,
      "why" =>
        "#{who}'s Galls of #{Taxa.accepted_name(taxon_id)} are on #{and_list(hosts)}, " <>
          "as this one is."
    }
  end

  defp and_list([one]), do: one
  defp and_list([a, b]), do: "#{a} and #{b}"
  defp and_list(names), do: Enum.join(Enum.drop(names, -1), ", ") <> " and " <> List.last(names)

  # One open question per Gall: a new split of its Inducer asks again.
  defp ask(subject, proposal, reason) do
    case Repo.one(from(q in open(subject["gall_id"]), lock: "FOR UPDATE")) do
      nil ->
        %QueueItem{}
        |> QueueItem.create_changeset(%{
          kind: @kind,
          subject: subject,
          proposal: proposal,
          reason: reason
        })
        |> Repo.insert!()

      item ->
        item
        |> Changeset.change(subject: subject, proposal: proposal, reason: reason)
        |> Repo.update!()
    end

    :ok
  end

  defp open, do: from(q in QueueItem, where: q.kind == @kind and q.status == :open)

  defp open(gall_id),
    do: from(q in open(), where: fragment("(?->>'gall_id')", q.subject) == ^"#{gall_id}")

  # -- the queue -----------------------------------------------------------------

  @doc """
  The split questions, oldest first. Options: `:status` (default `:open`;
  `:all`), `:source_id` (the splitting Source's).
  """
  @spec list(keyword()) :: [QueueItem.t()]
  def list(opts \\ []) do
    query = from(q in QueueItem, where: q.kind == @kind, order_by: q.id)

    query =
      case Keyword.get(opts, :status, :open) do
        :all -> query
        status -> where(query, [q], q.status == ^status)
      end

    query =
      case opts[:source_id] do
        nil -> query
        id -> where(query, [q], fragment("(?->>'source_id')::bigint", q.subject) == ^id)
      end

    Repo.all(query)
  end

  @doc "How many split questions are open: every Source's, or `source_id`'s."
  @spec count(integer() | nil) :: non_neg_integer()
  def count(source_id \\ nil) do
    query = open()

    query =
      if source_id,
        do: where(query, [q], fragment("(?->>'source_id')::bigint", q.subject) == ^source_id),
        else: query

    Repo.aggregate(query, :count)
  end

  @doc "How many split questions are open about Galls on split taxon `taxon_id`."
  @spec count_for_taxon(integer()) :: non_neg_integer()
  def count_for_taxon(taxon_id) when is_integer(taxon_id) do
    open()
    |> where([q], fragment("(?->>'taxon_id')::bigint", q.subject) == ^taxon_id)
    |> Repo.aggregate(:count)
  end

  # -- answers -------------------------------------------------------------------

  @doc "Whether `item` is a split question."
  @spec split?(QueueItem.t()) :: boolean()
  def split?(%QueueItem{kind: kind}), do: kind == @kind

  @doc """
  Checks an answer to split question `item`: `%{"taxon_id" => id}`, one of
  the taxa it was split into, or `%{"not_known" => true}`.
  """
  @spec check(QueueItem.t(), map()) :: :ok | {:error, String.t()}
  def check(%QueueItem{subject: subject}, %{"taxon_id" => id} = choice)
      when map_size(choice) == 1 do
    if id in List.wrap(subject["into_taxon_ids"]),
      do: :ok,
      else: {:error, "must be one of the taxa it was split into"}
  end

  def check(_item, %{"not_known" => true} = choice) when map_size(choice) == 1, do: :ok

  def check(_item, _choice),
    do: {:error, "must be a taxon it was split into (taxon_id), or not_known"}

  @doc """
  Carries out answer `decision` on split question `item`, inside
  `Gallformers.Import.decide_queue_item/3`'s transaction (see the module
  doc), with what it moved for Undo to keep (`"carried_out"`): for a
  daughter, one `"inducer_moved"` entry (`moved/5`); else none.
  `{:error, changeset}` (on `:decision`) when the Gall's Inducer is no
  longer the split taxon.
  """
  @spec carry_out(Actor.t(), QueueItem.t(), map()) ::
          {:ok, map(), [map()]} | {:error, Changeset.t()}
  def carry_out(%Actor{} = actor, %QueueItem{subject: subject} = item, decision) do
    %{"gall_id" => gall_id, "taxon_id" => split_id} = subject

    if gall_id in Catalog.galls_on_inducer(split_id) do
      {:ok, carried_out} = answer(actor, subject, item.reason, decision)
      {:ok, decision, carried_out}
    else
      {:error,
       item
       |> Changeset.change()
       |> Changeset.add_error(
         :decision,
         "the Gall's Inducer is no longer #{Taxa.accepted_name(split_id)}; reload"
       )}
    end
  end

  # Not known yet: it stays on the split taxon, in its old broad sense.
  defp answer(actor, subject, _reason, %{"not_known" => true}) do
    %{"gall_id" => gall_id, "taxon_id" => split_id} = subject
    {:ok, _} = Catalog.mark_broad_sense(actor, gall_id, split_id, subject["fact_id"])
    {:ok, []}
  end

  # The split taxon in its narrow sense: it stays, unmarked.
  defp answer(actor, %{"taxon_id" => id} = subject, _reason, %{"taxon_id" => id}) do
    {:ok, _} = Catalog.mark_broad_sense(actor, subject["gall_id"], id, nil)
    {:ok, []}
  end

  defp answer(actor, subject, reason, %{"taxon_id" => daughter}) do
    %{"gall_id" => gall_id, "taxon_id" => split_id} = subject
    reason = reason || "The Gall's Inducer changed."
    facts = Catalog.inducer_facts(gall_id, split_id)
    {:ok, %{moves: moves}} = Catalog.repoint_inducer(actor, gall_id, split_id, daughter)
    :ok = GallRenames.propose_for_galls([gall_id], reason)
    entry = moved(gall_id, split_id, daughter, facts, moves)
    {:ok, [put_in(entry, ["payload", "reason"], reason)]}
  end

  @doc """
  What re-pointing Gall `gall_id`'s Inducer from `split_id` to `daughter`
  moved (`moves`), as a `"carried_out"` entry by stable reference, which
  Undo moves back exactly (`Gallformers.Import.Undo`): keyed by the Gall
  and the two taxa (`"gall"`, `"from"`, `"to"`); its payload's
  `"statements"` are the Facts moved (`facts`, read before the move:
  `Gallformers.Catalog.inducer_facts/2`), each the Fact itself or a
  qualifier of it (`"qualifier"`: `%{"qualifier", "value"}`, else nil),
  with the Gall it is stated in the context of (`"context"`), the Sources
  whose attributions moved (`"sources"`), those whose attribution was
  joined to the one they held on the daughter's Fact already
  (`"joined"`), and its notes (`"notes"`: `%{"text", "author_name"}`).
  """
  @spec moved(integer(), integer(), integer(), [map()], [map()]) :: map()
  def moved(gall_id, split_id, daughter, facts, moves) do
    by_from = Map.new(moves, &{&1.from, &1})

    statements =
      for fact <- facts, %{} = move <- [by_from[fact.fact_id]] do
        %{
          "qualifier" => qualifier_ref(fact.qualifier),
          "context" => fact.gall_context_id && StableRef.gall(fact.gall_context_id),
          "sources" => for(%{outcome: :moved, id: id} <- move.sources, do: StableRef.source(id)),
          "joined" =>
            for(%{outcome: :already_held, id: id} <- move.sources, do: StableRef.source(id)),
          "notes" => Enum.map(fact.notes, &%{"text" => &1.text, "author_name" => &1.author_name})
        }
      end

    %{
      "kind" => "inducer_moved",
      "key" => %{
        "gall" => StableRef.gall(gall_id),
        "from" => StableRef.taxon(split_id),
        "to" => StableRef.taxon(daughter)
      },
      "payload" => %{"statements" => statements}
    }
  end

  defp qualifier_ref(nil), do: nil
  defp qualifier_ref({qualifier, value}), do: %{"qualifier" => qualifier, "value" => value}

  # -- the replay log ----------------------------------------------------------

  @doc """
  A decided split question's replay-log key: the `:queue_decision` key
  fields (no package, batch or statement) with the Gall's and the split
  taxon's stable references.
  """
  @spec replay_key(QueueItem.t()) :: map()
  def replay_key(%QueueItem{kind: @kind, subject: subject}) do
    %{
      "package" => nil,
      "batch_id" => nil,
      "kind" => Atom.to_string(@kind),
      "statement_ref" => nil,
      "gall" => StableRef.gall(subject["gall_id"]),
      "taxon" => StableRef.taxon(subject["taxon_id"])
    }
  end

  @doc """
  The split question about Gall `gall_id` on split taxon `taxon_id` that
  replay decides: the open one, else the latest decided one (already
  replayed), else nil.
  """
  @spec find(integer(), integer()) :: QueueItem.t() | nil
  def find(gall_id, taxon_id) when is_integer(gall_id) and is_integer(taxon_id) do
    items =
      Repo.all(
        from(q in QueueItem,
          where:
            q.kind == @kind and fragment("(?->>'gall_id')", q.subject) == ^"#{gall_id}" and
              fragment("(?->>'taxon_id')", q.subject) == ^"#{taxon_id}",
          order_by: [desc: q.id]
        )
      )

    Enum.find(items, &(&1.status == :open)) || List.first(items)
  end
end
