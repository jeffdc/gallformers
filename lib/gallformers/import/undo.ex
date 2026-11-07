defmodule Gallformers.Import.Undo do
  @moduledoc """
  Undo of a decided review question (matter `f14c`, "Undo rule"): allowed
  only while nothing depends on the decision. `Gallformers.Import.undo_decision/2`
  carries it out; this module holds the rule, what each kind's undo puts
  back, and the refusals in words.

  ## The rule

    * **The Source isn't approved yet.** A package's question is undone
      only while its package can still be resolved and the question's
      batch is not applied (`:source_approved`) or denied
      (`:package_denied`). The cross-Source questions (a taxonomic
      statement, a split's answer, a rename proposal, a merge's same-date
      question) never hold an approval, so this part does not apply.
    * **Nothing it changed has been edited since, per the audit log.** The
      decision's audit transaction is the one that set the item decided
      (Carbonite's `changes` on `queue_items`). Any later change, by
      anyone, to a record row that transaction changed (the import's own
      tables left out: they are worked out again), to a row naming a taxon
      it created (a synonym added to a plant it added, a taxon placed under
      it), or a decision on a question it raised, blocks the undo with who
      and when (`{:edited, edit}`), pointing to the taxonomy admin (or the
      Gall's page) for the record.

  ## What undo puts back, by kind

    * Tree edits a decision made (a Host's synonym, a plant from WCVP with
      the genus and family it was added under, a synonym question's split
      or move) are what it logged for replay before itself; the decision's
      `:queue_decision` entry keeps them (`"carried_out"`), and undo makes
      the reverse edits (`reversal/1`), the newest first: a synonym added
      is removed, a synonym removed is added back (its sensu and
      authorship kept), a taxon created is deleted (its range cleared
      first; refused while anything else names it,
      `Gallformers.Import.TaxonomyEdits`). A decision made before
      decisions kept them, which may have changed the tree, can't be
      undone here.
    * A dispute dropped: the Trait words it kept as text go.
    * The Source's identity: the package's Source is unset (resolving
      again finds it, if it can).
    * A Trait term's question: only a decision that changed no vocabulary
      ("keep") is undone; the vocabulary page changes the rest.
    * A rename proposal: an accepted one's Gall takes back the name it
      showed and loses the former-label alias; a rejected one's name
      override goes.
    * A split question's answer: a daughter's answer keeps what it moved
      (`"carried_out"`, `Gallformers.Import.SplitQuestions.moved/5`), and
      exactly that goes back to the split taxon, by its reverse edit
      (`"return_inducer"`): each attribution and note it moved, not the
      statements the Gall's Fact naming the daughter held before; then the
      rename proposal is worked out again. Refused when the answer joined
      a Source's statement of the split taxon to its statement of the
      daughter (`{:cannot_undo, :joined}`). "Not known yet" loses its
      broad-sense mark.
    * A taxonomic statement accepted or declined is reopened
      (`Gallformers.Import.TaxonomicDecisions`): the tree follows the
      statements that count again, and its question opens again
      (`Gallformers.Import.TaxonomyQueue`). A question closed as history
      is undone through the newer statement's. An accepted split (it
      re-pointed Galls) or a lump (a taxon merged away) is not undone by
      reopening it: refused.
    * Any other kind's decision changes nothing beyond its item.

  Then the item opens again (`status` open, its decision cleared; its notes
  and ID kept), and a package is resolved again.

  ## The replay log

  An undo is one `:queue_decision_undone` entry, keyed as the decision's
  `:queue_decision` entry, with the reverse tree edits by stable
  reference (`"reverse"`); the edits themselves log nothing of their own,
  so a replay makes them once, in the same order, with the item reopened
  first. A taxonomic statement's undo is its `:taxonomic_decision`
  `"reopen"` entry.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.BatchUnmapped
  alias Gallformers.Import.Disputes
  alias Gallformers.Import.GallDecisions
  alias Gallformers.Import.GallRenames
  alias Gallformers.Import.HostDecisions
  alias Gallformers.Import.Package
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.StableRef
  alias Gallformers.Import.SynonymDecisions
  alias Gallformers.Import.TaxonomyEdits
  alias Gallformers.Ranges
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.TaxonName

  @typedoc "A later change that blocks an undo: what, by whom, when, and where to change it."
  @type edit :: %{
          what: String.t(),
          question: boolean(),
          by: String.t(),
          at: NaiveDateTime.t(),
          link: {:taxon, integer()} | {:gall, integer()} | nil
        }

  @typedoc "Why an undo is refused."
  @type refusal ::
          :not_decided
          | :gone
          | :source_approved
          | :package_denied
          | :no_trail
          | {:edited, edit()}
          | {:cannot_undo, atom()}
          | {:referenced, [map()]}

  # The cross-Source kinds: they never hold an approval.
  @no_approval [:taxonomy_acceptance, :split_inducer, :gall_rename, :same_date_conflict]

  # The import's own tables, worked out again by an undo: a later change
  # to them depends on nothing the decision changed.
  @machinery ~w(queue_items queue_item_notes import_batches import_packages
                package_statement_edits replay_log pending_trait_terms vocab_requests
                trait_term_candidates)

  # -- the rule ------------------------------------------------------------------

  @doc """
  Whether decided `item` (of `package`, locked, or nil) may be undone as
  far as its Source and kind go: `:ok`, or why not.
  """
  @spec check(QueueItem.t(), Package.t() | nil, atom() | nil) :: :ok | {:error, refusal()}
  def check(%QueueItem{} = item, package, batch_status) do
    cond do
      item.kind == :taxonomy_acceptance and item.decision["history"] == true ->
        {:error, {:cannot_undo, :history}}

      item.kind == :trait_term and changes_vocabulary?(item.decision) ->
        {:error, {:cannot_undo, :vocabulary}}

      item.kind in @no_approval or package == nil ->
        :ok

      true ->
        source_check(package, batch_status)
    end
  end

  defp source_check(%Package{status: :denied}, _batch_status), do: {:error, :package_denied}
  defp source_check(_package, :denied), do: {:error, :package_denied}
  defp source_check(_package, :applied), do: {:error, :source_approved}

  defp source_check(%Package{status: status}, _batch_status)
       when status in [:validated, :resolving, :awaiting_review],
       do: :ok

  defp source_check(_package, _batch_status), do: {:error, :source_approved}

  # A Trait term's decision that placed it or marked it (`TraitTerms.change_term/2`).
  defp changes_vocabulary?(decision) do
    choice = Map.delete(decision || %{}, "note")

    Map.has_key?(choice, "place") or choice["no_fit"] == true or
      Map.has_key?(choice, "category") or
      (is_map(choice["categories"]) and Enum.any?(Map.values(choice["categories"]), &is_binary/1))
  end

  @doc """
  Whether `decision` may have changed the tree (a Host's synonym or plant,
  a Host read in the Source's sense, a synonym question's split or move):
  its decision keeps what it changed (`"carried_out"`).
  """
  @spec tree_changing?(map()) :: boolean()
  def tree_changing?(decision) when is_map(decision) do
    HostDecisions.adds?(decision) or SynonymDecisions.changes_tree?(decision) or
      Map.has_key?(decision, "host_reading")
  end

  def tree_changing?(_decision), do: false

  @doc """
  Whether `item`'s decision may have changed the tree (`tree_changing?/1`),
  or (a split question's answer naming a daughter) re-pointed a Gall's
  Inducer: either keeps what it changed (`"carried_out"`).
  """
  @spec tree_item?(QueueItem.t()) :: boolean()
  def tree_item?(%QueueItem{kind: :split_inducer, subject: subject, decision: decision}) do
    case decision do
      %{"taxon_id" => id} -> id != subject["taxon_id"]
      _ -> false
    end
  end

  def tree_item?(%QueueItem{decision: decision} = item) do
    (HostDecisions.host?(item) or GallDecisions.gall?(item) or Disputes.host?(item) or
       SynonymDecisions.synonym?(item)) and tree_changing?(decision)
  end

  # -- the audit trail ---------------------------------------------------------

  @doc """
  The audit transaction (Carbonite's) that decided item `item_id` last, or
  nil when the audit trail holds none.
  """
  @spec decision_transaction(integer()) :: integer() | nil
  def decision_transaction(item_id) when is_integer(item_id) do
    sql = """
    SELECT c.transaction_id
    FROM carbonite_default.changes c
    WHERE c.table_prefix = 'public' AND c.table_name = 'queue_items' AND c.table_pk = $1
      AND c.op = 'update' AND c.data->>'status' = 'decided' AND 'status' = ANY(c.changed)
    ORDER BY c.transaction_id DESC
    LIMIT 1
    """

    case Repo.query!(sql, [[Integer.to_string(item_id)]]) do
      %{rows: [[id]]} -> id
      %{rows: []} -> nil
    end
  end

  @doc """
  Whether the taxonomic statement `item` decided, in audit transaction
  `transaction_id`, did what reopening it can't undo: an accepted split
  (it re-pointed the Galls of the split taxon and asked about the rest),
  or a lump (a taxon merged into another and deleted).
  """
  @spec reversible(QueueItem.t(), integer()) :: :ok | {:error, refusal()}
  def reversible(%QueueItem{kind: :taxonomy_acceptance} = item, transaction_id) do
    sql = """
    SELECT 1 FROM carbonite_default.changes
    WHERE transaction_id = $1 AND table_name = 'taxa' AND op = 'delete'
    LIMIT 1
    """

    cond do
      item.decision["accept"] == true and item.subject["kind"] == "split" ->
        {:error, {:cannot_undo, :split}}

      item.decision["accept"] == true and Repo.query!(sql, [transaction_id]).rows != [] ->
        {:error, {:cannot_undo, :lump}}

      true ->
        :ok
    end
  end

  def reversible(_item, _transaction_id), do: :ok

  @doc """
  The first change, after audit transaction `transaction_id`, that depends
  on what it changed (see "The rule"), or nil.
  """
  @spec edited_since(integer()) :: edit() | nil
  def edited_since(transaction_id) when is_integer(transaction_id) do
    sql = """
    WITH mine AS (
      SELECT table_name, table_pk, op, data
      FROM carbonite_default.changes
      WHERE transaction_id = $1
    ), created AS (
      SELECT data->>'id' AS id FROM mine WHERE table_name = 'taxa' AND op = 'insert'
    ), later AS (
      SELECT c.id, c.transaction_id, c.table_name, c.op, c.data
      FROM mine m
      JOIN carbonite_default.changes c
        ON c.table_prefix = 'public' AND c.table_name = m.table_name AND c.table_pk = m.table_pk
      WHERE m.table_name <> ALL($2) AND c.transaction_id > $1
      UNION ALL
      SELECT c.id, c.transaction_id, c.table_name, c.op, c.data
      FROM carbonite_default.changes c
      WHERE c.transaction_id > $1 AND c.table_name <> ALL($2)
        AND (c.data->>'taxon_id' IN (SELECT id FROM created)
          OR (c.table_name = 'taxa' AND c.data->>'parent_id' IN (SELECT id FROM created)))
      UNION ALL
      SELECT c.id, c.transaction_id, c.table_name, c.op, c.data
      FROM mine m
      JOIN carbonite_default.changes c
        ON c.table_prefix = 'public' AND c.table_name = 'queue_items' AND c.table_pk = m.table_pk
      WHERE m.table_name = 'queue_items' AND m.op = 'insert' AND c.transaction_id > $1
        AND c.op = 'update' AND c.data->>'status' = 'decided'
    )
    SELECT l.table_name, l.data, t.meta->'actor'->>'name', t.inserted_at
    FROM later l
    JOIN carbonite_default.transactions t ON t.id = l.transaction_id
    WHERE t.xact_id <> pg_current_xact_id()
    ORDER BY l.transaction_id, l.id
    LIMIT 1
    """

    case Repo.query!(sql, [transaction_id, @machinery]) do
      %{rows: [[table, data, by, at]]} -> describe(table, data) |> Map.merge(%{by: by, at: at})
      %{rows: []} -> nil
    end
  end

  defp describe("queue_items", _data),
    do: %{what: "a question it raised", question: true, link: nil}

  defp describe("galls", %{"id" => id} = data),
    do: %{what: gall_name(id, data), question: false, link: {:gall, id}}

  defp describe("taxon_names", %{"taxon_id" => id} = data),
    do: %{what: data["name"] || taxon_name(id, data), question: false, link: {:taxon, id}}

  defp describe("taxa", %{"id" => id} = data),
    do: %{what: taxon_name(id, data), question: false, link: {:taxon, id}}

  defp describe(_table, %{"taxon_id" => id} = data) when is_integer(id),
    do: %{what: taxon_name(id, data), question: false, link: {:taxon, id}}

  defp describe(_table, %{"gall_id" => id} = data) when is_integer(id),
    do: %{what: gall_name(id, data), question: false, link: {:gall, id}}

  defp describe(_table, _data), do: %{what: "a record it changed", question: false, link: nil}

  defp taxon_name(id, data) do
    case Taxa.get_taxon(id) do
      nil -> data["name"] || "a taxon"
      taxon -> Taxa.accepted_name(taxon)
    end
  end

  defp gall_name(id, data) do
    case Catalog.get_gall(id) do
      nil -> data["name"] || "a Gall"
      gall -> Catalog.Gall.display_name(gall)
    end
  end

  # -- the tree's edits ----------------------------------------------------------

  @doc """
  The reverse tree edits of `carried_out` (the entries a decision logged
  before itself, as `%{"kind", "key", "payload"}`), the newest first, by
  stable reference: `%{"op" => "remove_synonym" | "add_synonym", "taxon",
  "name", "sensu"}` (`"add_synonym"` with the synonym's `"authorship"`
  too) and `%{"op" => "delete_taxon", "taxon"}`. A taxon's range or WCVP
  link set when it was created goes with it. A split's answer
  (`"inducer_moved"`, `Gallformers.Import.SplitQuestions.moved/5`) is
  reversed by `%{"op" => "return_inducer", "gall", "from", "to",
  "statements", "reason"}`: exactly the attributions and notes it moved
  go back (the daughter's own statements stay). `{:error, {:cannot_undo,
  :edit}}` for an edit with no reverse here; `{:error, {:cannot_undo,
  :joined}}` for a split's answer that joined a Source's statement of the
  split taxon to its statement of the daughter (what it joined is not
  kept apart).
  """
  @spec reversal([map()]) :: {:ok, [map()]} | {:error, refusal()}
  def reversal(carried_out) when is_list(carried_out) do
    entries = Enum.map(carried_out, &entry_map/1)
    created = for e <- entries, ref = created_ref(e), do: ref

    entries
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, ops} ->
      case reverse(entry, created) do
        :skip -> {:cont, {:ok, ops}}
        {:ok, op} -> {:cont, {:ok, ops ++ [op]}}
        :error -> {:halt, {:error, {:cannot_undo, :edit}}}
        {:error, why} -> {:halt, {:error, {:cannot_undo, why}}}
      end
    end)
  end

  defp entry_map(%{kind: kind, key: key, payload: payload}),
    do: %{"kind" => to_string(kind), "key" => key, "payload" => payload || %{}}

  defp entry_map(%{"kind" => _} = entry), do: entry

  defp created_ref(%{"kind" => "plant_added", "key" => %{"name" => n, "rank" => r}}),
    do: %{"name" => n, "rank" => r, "kingdom" => "Plantae"}

  defp created_ref(%{
         "kind" => "taxonomy_edit",
         "key" => %{"op" => "create_taxon", "name" => n, "rank" => r},
         "payload" => payload
       }),
       do: %{"name" => n, "rank" => r, "kingdom" => payload["kingdom"]}

  defp created_ref(_entry), do: nil

  defp reverse(%{"kind" => "synonym_added", "key" => key, "payload" => payload}, _created),
    do:
      {:ok,
       %{
         "op" => "remove_synonym",
         "taxon" => key["taxon"],
         "name" => key["name"],
         "sensu" => payload["sensu"]
       }}

  defp reverse(
         %{"kind" => "taxonomy_edit", "key" => %{"op" => "remove_synonym"} = key} = entry,
         _created
       ),
       do:
         {:ok,
          %{
            "op" => "add_synonym",
            "taxon" => key["taxon"],
            "name" => key["name"],
            "sensu" => entry["payload"]["sensu"],
            "authorship" => entry["payload"]["authorship"]
          }}

  # A split's answer moved the Inducer from the split taxon to the daughter:
  # back, from the daughter to the split taxon.
  defp reverse(%{"kind" => "inducer_moved", "key" => key, "payload" => payload}, _created) do
    statements = List.wrap(payload["statements"])

    if Enum.any?(statements, &(List.wrap(&1["joined"]) != [])) do
      {:error, :joined}
    else
      {:ok,
       %{
         "op" => "return_inducer",
         "gall" => key["gall"],
         "from" => key["to"],
         "to" => key["from"],
         "statements" => statements,
         "reason" => payload["reason"]
       }}
    end
  end

  defp reverse(%{"kind" => "taxonomy_edit", "key" => %{"op" => op} = key}, created)
       when op in ["set_host_range", "set_wcvp"] do
    if Enum.any?(created, &same_ref?(&1, key["taxon"])), do: :skip, else: :error
  end

  defp reverse(entry, _created) do
    case created_ref(entry) do
      nil -> :error
      ref -> {:ok, %{"op" => "delete_taxon", "taxon" => ref}}
    end
  end

  defp same_ref?(a, b) when is_map(a) and is_map(b),
    do: a["name"] == b["name"] and a["rank"] == b["rank"]

  defp same_ref?(_a, _b), do: false

  @doc "The taxa the reverse edits `ops` delete, found by their stable references now."
  @spec deleted_taxa([map()]) :: [integer()]
  def deleted_taxa(ops) do
    for %{"op" => "delete_taxon", "taxon" => ref} <- ops,
        {:ok, id} <- [StableRef.resolve_taxon(ref)],
        do: id
  end

  @doc """
  Makes the reverse tree edits `ops`, inside the caller's transaction, in
  order; an edit found done already (a replay) is skipped. Rolls back
  with why a taxon can't be deleted (`{:referenced, references}`).
  """
  @spec run(Actor.t(), [map()]) :: :ok
  def run(%Actor{} = actor, ops) do
    Enum.each(ops, &run_op(actor, &1))
  end

  defp run_op(actor, %{"op" => "remove_synonym", "taxon" => ref, "name" => name} = op) do
    with {:ok, taxon_id} <- StableRef.resolve_taxon(ref),
         %TaxonName{} = synonym <- held(taxon_id, name, op["sensu"]) do
      actor |> Taxa.remove_synonym(synonym) |> ok_or_rollback()
    end
  end

  defp run_op(actor, %{"op" => "add_synonym", "taxon" => ref, "name" => name} = op) do
    with {:ok, taxon_id} <- StableRef.resolve_taxon(ref),
         nil <- held(taxon_id, name, op["sensu"]) do
      actor
      |> Taxa.add_synonym(taxon_id, name, sensu: op["sensu"], authorship: op["authorship"])
      |> ok_or_rollback()
    end
  end

  defp run_op(actor, %{"op" => "delete_taxon", "taxon" => ref}) do
    with {:ok, taxon_id} <- StableRef.resolve_taxon(ref) do
      {:ok, _} = Ranges.update_taxon_places(actor, taxon_id, [])
      actor |> TaxonomyEdits.run({:delete_taxon, taxon_id}) |> ok_or_rollback()
    end
  end

  # The Gall's Inducer goes back to the split taxon (exactly what moved),
  # and its rename proposal is worked out again.
  defp run_op(actor, %{"op" => "return_inducer"} = op) do
    with {:ok, gall_id} <- StableRef.resolve_gall(op["gall"]),
         {:ok, from_id} <- StableRef.resolve_taxon(op["from"]),
         {:ok, to_id} <- StableRef.resolve_taxon(op["to"]),
         {:ok, facts} <- inducer_facts(op["statements"]) do
      actor |> Catalog.return_inducer(gall_id, from_id, to_id, facts) |> ok_or_rollback()
      GallRenames.propose_for_galls([gall_id], op["reason"] || "The Gall's Inducer changed.")
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # The statements a split's answer moved, as `Gallformers.Catalog.return_inducer/5` takes them.
  defp inducer_facts(statements) do
    statements
    |> List.wrap()
    |> Enum.reduce_while({:ok, []}, fn statement, {:ok, facts} ->
      with {:ok, context_id} <- optional_gall(statement["context"]),
           {:ok, source_ids} <- source_ids(statement["sources"]) do
        fact = %{
          qualifier:
            statement["qualifier"] &&
              {statement["qualifier"]["qualifier"], statement["qualifier"]["value"]},
          gall_context_id: context_id,
          source_ids: source_ids,
          notes:
            for(
              n <- List.wrap(statement["notes"]),
              do: %{text: n["text"], author_name: n["author_name"]}
            )
        }

        {:cont, {:ok, facts ++ [fact]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp optional_gall(nil), do: {:ok, nil}
  defp optional_gall(ref), do: StableRef.resolve_gall(ref)

  defp source_ids(refs) do
    refs
    |> List.wrap()
    |> Enum.reduce_while({:ok, []}, fn ref, {:ok, ids} ->
      case StableRef.resolve_source(ref) do
        {:ok, id} -> {:cont, {:ok, ids ++ [id]}}
        error -> {:halt, error}
      end
    end)
  end

  defp held(taxon_id, name, sensu) do
    normalized = NameNormalizer.normalize(name)

    Repo.one(
      from(n in TaxonName,
        where:
          n.taxon_id == ^taxon_id and n.status == :synonym and n.normalized_name == ^normalized,
        limit: 1
      )
      |> with_sensu(sensu)
    )
  end

  defp with_sensu(query, nil), do: from(n in query, where: is_nil(n.sensu))
  defp with_sensu(query, sensu), do: from(n in query, where: n.sensu == ^sensu)

  @doc """
  Clears the taxa `taxon_ids` (about to be deleted) from `package`'s
  statements not yet applied, inside the caller's transaction: resolving
  the package again works them out afresh.
  """
  @spec clear_statements(Package.t(), [integer()]) :: :ok
  def clear_statements(_package, []), do: :ok

  def clear_statements(%Package{id: package_id}, taxon_ids) do
    statements =
      Repo.all(
        from(s in BatchStatement,
          join: b in assoc(s, :batch),
          where:
            b.package_id == ^package_id and b.status not in [:applied, :denied] and
              (s.taxon_id in ^taxon_ids or
                 fragment("? && ?", s.candidate_ids, type(^taxon_ids, {:array, :integer})))
        )
      )

    for s <- statements do
      s
      |> Ecto.Changeset.change(
        taxon_id: if(s.taxon_id in taxon_ids, do: nil, else: s.taxon_id),
        resolution: if(s.taxon_id in taxon_ids, do: :unresolved, else: s.resolution),
        candidate_ids: s.candidate_ids -- taxon_ids
      )
      |> Repo.update!()
    end

    :ok
  end

  # -- each kind -----------------------------------------------------------------

  @doc """
  Puts back what decided `item`'s decision changed besides the tree's
  edits (see the module doc), inside the caller's transaction. Rolls back
  with a refusal when it can't.
  """
  @spec put_back(Actor.t(), QueueItem.t(), Package.t() | nil) :: :ok
  def put_back(actor, %QueueItem{kind: :gall_rename, decision: decision} = item, _package) do
    gall_id = item.proposal["gall_id"]
    gall = Catalog.get_gall!(gall_id)

    case Map.delete(decision, "note") do
      %{"accept" => true} ->
        if gall.name == item.proposal["to"] and gall.name != item.proposal["from"],
          do: revert_name(actor, gall_id, item.proposal["from"])

        :ok

      # The override goes; the stored name stays the one it showed.
      %{"reject" => true} ->
        actor |> Catalog.update_name_parts(gall, %{name_override: nil}) |> ok_or_rollback()
        revert_name(actor, gall_id, item.proposal["from"])
    end
  end

  # A daughter's answer is put back by its reverse tree edit
  # (`"return_inducer"`), after the item is reopened.
  def put_back(actor, %QueueItem{kind: :split_inducer, subject: subject} = item, _package) do
    %{"gall_id" => gall_id, "taxon_id" => split_id} = subject

    case Map.delete(item.decision, "note") do
      %{"not_known" => true} ->
        {:ok, _} = Catalog.mark_broad_sense(actor, gall_id, split_id, nil)

      %{"taxon_id" => _taxon_id} ->
        :ok
    end

    :ok
  end

  # The Trait words a dropped dispute kept as text.
  def put_back(_actor, %QueueItem{kind: :dispute, decision: %{"skip" => true}} = item, _package) do
    batch = Repo.get!(Gallformers.Import.Batch, item.batch_id)

    for text <- Disputes.texts(item, batch.content) do
      Repo.delete_all(
        from(u in BatchUnmapped,
          where:
            u.batch_id == ^batch.id and u.term == ^text.term and u.slot == ^text.slot and
              u.note == ^text.note
        )
      )
    end

    :ok
  end

  # The Source's identity: resolving again finds it, if it can.
  def put_back(_actor, %QueueItem{statement_ref: "source", batch_id: nil}, %Package{} = package) do
    package |> Ecto.Changeset.change(source_id: nil) |> Repo.update!()
    :ok
  end

  def put_back(_actor, _item, _package), do: :ok

  defp revert_name(actor, gall_id, former) do
    case Catalog.revert_gall_rename(actor, gall_id, former) do
      {:ok, _} -> :ok
      {:error, :collision} -> Repo.rollback({:cannot_undo, :collision})
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc """
  Opens decided `item` again, inside the caller's transaction: its decision
  and who made it cleared, its ID and notes kept. Rolls back
  (`{:cannot_undo, :open_again}`) when a question about the same Gall is
  open already (one at a time).
  """
  @spec reopen(QueueItem.t()) :: QueueItem.t()
  def reopen(%QueueItem{} = item) do
    if other_open?(item), do: Repo.rollback({:cannot_undo, :open_again})

    item
    |> Ecto.Changeset.change(
      status: :open,
      decision: nil,
      decided_by_user_id: nil,
      decided_by_name: nil,
      decided_at: nil
    )
    |> Repo.update!()
  end

  defp other_open?(%QueueItem{kind: kind, subject: %{"gall_id" => gall_id}} = item)
       when kind in [:gall_rename, :split_inducer] do
    Repo.exists?(
      from(q in QueueItem,
        where:
          q.kind == ^kind and q.status == :open and q.id != ^item.id and
            fragment("(?->>'gall_id')", q.subject) == ^"#{gall_id}"
      )
    )
  end

  defp other_open?(_item), do: false

  # -- in words ------------------------------------------------------------------

  @doc """
  Why an undo was refused, in words, and the record to change instead
  (`link`: `{:taxon, id}` for the taxonomy admin, `{:gall, id}` for the
  Gall's page, or nil).
  """
  @spec refusal(term()) :: %{text: String.t(), link: {:taxon | :gall, integer()} | nil}
  def refusal({:edited, %{question: true} = edit}) do
    text(
      "Can't undo: #{edit.what} was decided by #{edit.by} on #{date(edit.at)} since. " <>
        "Undo that first."
    )
  end

  def refusal({:edited, %{link: {:gall, _}} = edit}) do
    %{
      text:
        "Can't undo: #{edit.what} was edited by #{edit.by} on #{date(edit.at)} since. " <>
          "Change it on the Gall's page.",
      link: edit.link
    }
  end

  def refusal({:edited, edit}) do
    %{
      text:
        "Can't undo: #{edit.what} was edited by #{edit.by} on #{date(edit.at)} since. " <>
          "Change it in the taxonomy admin.",
      link: edit.link
    }
  end

  def refusal(:source_approved),
    do:
      text(
        "Can't undo: the Source is approved, so its Facts rest on this decision. " <>
          "Change what it decided in the taxonomy admin."
      )

  def refusal(:package_denied), do: text("Can't undo: the package was denied.")
  def refusal(:not_decided), do: text("This question is open: there is nothing to undo.")
  def refusal(:gone), do: text("This question is gone; reload to see what is left.")

  def refusal(:no_trail),
    do: text("Can't undo: the audit trail holds no record of this decision.")

  def refusal({:cannot_undo, :history}),
    do:
      text(
        "Can't undo: a newer paper's acceptance closed this as history. " <>
          "Undo that one instead."
      )

  def refusal({:cannot_undo, :split}),
    do:
      text(
        "Can't undo: accepting this split changed which taxon induces its Galls. " <>
          "Change them on the Galls' pages and the tree in the taxonomy admin."
      )

  def refusal({:cannot_undo, :lump}),
    do:
      text(
        "Can't undo: accepting this statement merged one taxon into another. " <>
          "Change the tree in the taxonomy admin."
      )

  def refusal({:cannot_undo, :vocabulary}),
    do:
      text(
        "Can't undo: this decision changed the Trait vocabulary for every Source. " <>
          "Change the term on the vocabulary page."
      )

  def refusal({:cannot_undo, :no_record}),
    do:
      text(
        "Can't undo: this decision was made before decisions kept what they change in the " <>
          "tree. Change it in the taxonomy admin."
      )

  def refusal({:cannot_undo, :joined}),
    do:
      text(
        "Can't undo: answering joined a Source's statement of the split taxon to its " <>
          "statement of the daughter, and they can't be told apart now. " <>
          "Change the Inducer on the Gall's page."
      )

  def refusal({:cannot_undo, :edit}),
    do: text("Can't undo: this decision made a change to the tree that Undo can't reverse.")

  def refusal({:cannot_undo, :collision}),
    do: text("Can't undo: the Gall's old name is another Gall's name now.")

  def refusal({:cannot_undo, :open_again}),
    do: text("Can't undo: another question about this Gall is open now. Decide that one first.")

  def refusal({:referenced, references}) do
    what = Enum.map_join(references, ", ", &"#{&1.count} in #{&1.table}")

    text(
      "Can't undo: a taxon this decision created is used since (#{what}). " <>
        "Change it in the taxonomy admin."
    )
  end

  def refusal(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> Enum.join("; ")
    |> then(&text("Can't undo: #{&1}."))
  end

  def refusal(reason), do: text("Can't undo: #{inspect(reason)}.")

  defp text(text), do: %{text: text, link: nil}

  defp date(%NaiveDateTime{} = at), do: Calendar.strftime(at, "%-d %b %Y")
  defp date(%DateTime{} = at), do: Calendar.strftime(at, "%-d %b %Y")
  defp date(_at), do: "an unknown date"

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
