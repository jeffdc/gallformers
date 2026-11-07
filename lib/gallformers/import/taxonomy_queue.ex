defmodule Gallformers.Import.TaxonomyQueue do
  @moduledoc """
  The taxonomy queue (matter `f923` Task 6): curators accept or decline
  Sources' taxonomic statements (placement, name, synonymy, split, common
  name) in one queue across all Sources. A statement counts only once
  accepted (`Gallformers.Facts.accept/3`), and the tree follows the
  statements that count (`Gallformers.Taxa.Sync`).

  ## Which statements ask a question

  A `:taxonomy_acceptance` queue item is raised for a Source's statement
  when it differs from the tree (`difference/4`) and is newer than every
  statement that counts in its slot (the volume rule: an older paper's
  differing statement is history, raising nothing). A statement already
  accepted or declined, one of Gallformers' own Sources (which count
  without acceptance), and a plant's (plant data is editorial) raise none.
  A paper that only adds authorship to a name, or names it without one, is
  not a difference. A statement has at most one open question.

  Questions never hold a Source's approval: the Facts attach to taxa, not
  to their place in the tree, so a Source's Gall Facts are right either
  way. Name-resolution questions (which organism a name means) are not
  here; they still hold approval (`Gallformers.Import.Queue`).

  ## Deciding

  Accept (`%{"accept" => true}`: the tree follows) or decline with a
  required reason (`%{"decline" => true, "reason" => text}`), through
  `Gallformers.Import.TaxonomicDecisions`, which logs the decision for
  replay and settles the questions here (`settle/4`) before the decision is
  made: the statement's own question is closed (so it doesn't block the
  lump its acceptance may bring about), and an acceptance closes the open
  questions of older statements in the same slot as history
  (`%{"history" => true}`), whichever Source they came from. A refusal
  from the tree (a cycle, a rank inversion, a lump the tree can't make)
  rolls it all back; `refusal_text/1` says why in words. Reopening a
  statement asks its question again where the rules still call for one,
  from no package.

  "Accept the rest of this paper" (`accept_rest/2`) accepts every open
  question of a Source, in one transaction, after `preview_rest/2` has
  shown what it would do to the tree (moves, renames, merges, Galls whose
  names would change, splits and the Galls they would ask about), by
  running the acceptances in a transaction rolled back. A declined
  statement stays declined: its question is decided.
  """
  import Ecto.Query

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Facts.Fact
  alias Gallformers.Facts.Standing
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.Queue
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.TaxonomicDecisions
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer

  @kind :taxonomy_acceptance

  @typedoc "A decision on a statement, as `Gallformers.Import.TaxonomicDecisions` makes it."
  @type op :: :accept | :decline | :reopen

  # -- the tree's difference -----------------------------------------------------

  @doc """
  Why a statement of act `kind` (`"placement"`, `"name"`, `"synonymy"`,
  `"split"`, `"common_name"`) with `stance` (`"confirm"` | `"deny"`) and
  natural `key` (as `Gallformers.Taxa.act_fact/1` gives it) differs from
  the tree, in words, or nil when it agrees. A name with the tree's name
  and rank differs only by an authorship (or sensu) both give and that
  differ. Options: `first_common_name: :agrees` takes a first common name,
  for a taxon that holds none, as agreeing (new information; phase 1's
  rule, kept for plants), where otherwise it differs.
  """
  @spec difference(String.t(), String.t(), map(), keyword()) :: String.t() | nil
  def difference(kind, stance, key, opts \\ [])

  def difference("placement", stance, key, _opts) do
    taxon = Taxa.get_taxon!(key.taxon_id)
    there? = taxon.parent_id == key.parent_id

    cond do
      stance == "confirm" and there? ->
        nil

      stance == "confirm" ->
        "the tree places #{name(taxon)} #{where(taxon.parent_id)}"

      there? ->
        "the tree places #{name(taxon)} under #{name(key.parent_id)}, which the Source denies"

      true ->
        nil
    end
  end

  def difference("name", stance, key, _opts) do
    taxon = Taxa.get_taxon!(key.taxon_id)
    accepted = Enum.find(taxon.names, &(&1.status == :accepted))

    same? =
      same_name?(accepted.name, key.name) and to_string(taxon.rank) == to_string(key.rank) and
        compatible?(accepted.authorship, Map.get(key, :authorship), &authorship_key/1) and
        compatible?(accepted.sensu, Map.get(key, :sensu), &sensu_key/1)

    cond do
      stance == "confirm" and same? ->
        nil

      stance == "confirm" ->
        "the tree names it #{held_name(taxon, accepted)} at rank #{taxon.rank}"

      same? ->
        "the tree holds #{name(taxon)}, which the Source denies"

      true ->
        nil
    end
  end

  def difference("synonymy", stance, key, _opts) do
    accepted = Taxa.get_taxon!(key.accepted_taxon_id)

    held? =
      Enum.any?(accepted.names, &(&1.status == :synonym and same_name?(&1.name, key.name)))

    cond do
      stance == "confirm" and held? ->
        nil

      stance == "confirm" ->
        "the tree does not hold #{key.name} as a synonym of #{name(accepted)}" <>
          held_elsewhere(key.name, accepted.id)

      held? ->
        "the tree holds #{key.name} as a synonym of #{name(accepted)}, which the Source denies"

      true ->
        nil
    end
  end

  def difference("split", "confirm", key, _opts) do
    "a split of #{name(key.taxon_id)}: each Gall on it then asks which taxon induces it"
  end

  def difference("common_name", stance, key, opts) do
    names = Taxa.list_common_names(key.taxon_id)
    held? = Enum.any?(names, &(String.downcase(&1.name) == String.downcase(key.common_name)))
    first_agrees? = Keyword.get(opts, :first_common_name) == :agrees

    cond do
      stance == "confirm" and names == [] and first_agrees? ->
        nil

      stance == "confirm" and not held? ->
        "the tree does not hold the common name #{key.common_name} for #{name(key.taxon_id)}"

      stance == "deny" and held? ->
        "the tree holds the common name #{key.common_name}, which the Source denies"

      true ->
        nil
    end
  end

  def difference(_kind, _stance, _key, _opts), do: nil

  # An authorship or sensu given on one side only is compatible: a paper
  # that adds one (or leaves it out) doesn't differ.
  defp compatible?(held, stated, key_of) do
    case {blank_nil(held), blank_nil(stated)} do
      {nil, _} -> true
      {_, nil} -> true
      {a, b} -> key_of.(a) == key_of.(b)
    end
  end

  defp authorship_key(authorship), do: NameNormalizer.normalize_authorship(authorship)
  defp sensu_key(sensu), do: sensu |> String.trim() |> String.downcase()

  defp blank_nil(nil), do: nil

  defp blank_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp held_name(taxon, %{authorship: authorship}) when is_binary(authorship),
    do: "#{name(taxon)} #{authorship}"

  defp held_name(taxon, _accepted), do: name(taxon)

  defp held_elsewhere(name, accepted_id) do
    case Taxa.resolve_name(name) do
      {:ok, %{id: id} = other} when id != accepted_id ->
        status =
          if other.matched_name.status == :accepted, do: "the accepted name", else: "a synonym"

        "; it is #{status} of another taxon, #{name(other)}"

      {:ambiguous, _taxa} ->
        "; several taxa have this name"

      _ ->
        ""
    end
  end

  defp same_name?(a, b), do: NameNormalizer.normalize(a) == NameNormalizer.normalize(b)

  defp name(%Taxa.Taxon{} = taxon), do: Taxa.accepted_name(taxon)
  defp name(id) when is_integer(id), do: Taxa.accepted_name(id)

  defp where(nil), do: "at the root"
  defp where(parent_id), do: "under #{name(parent_id)}"

  @doc """
  How the tree differs now from the statement question `item` asks about
  (`difference/4`, read afresh), or nil when it agrees now or the
  statement's taxa are gone.
  """
  @spec tree_now(QueueItem.t()) :: String.t() | nil
  def tree_now(%QueueItem{subject: %{"fact_id" => fact_id, "stance" => stance}})
      when is_integer(fact_id) do
    with {kind, key} <- Taxa.act_fact(fact_id),
         true <- taxa_present?(key) do
      difference(Atom.to_string(kind), stance, key)
    else
      _ -> nil
    end
  end

  def tree_now(%QueueItem{}), do: nil

  defp taxa_present?(key) do
    ids = for k <- [:taxon_id, :parent_id, :accepted_taxon_id], id = Map.get(key, k), do: id
    Enum.all?(ids, &(Taxa.get_taxon(&1) != nil))
  end

  @doc "Whether the taxon a statement of act `key` is about is a plant (editorial: no question)."
  @spec plant?(map()) :: boolean()
  def plant?(key) do
    case Map.get(key, :taxon_id) || Map.get(key, :accepted_taxon_id) do
      id when is_integer(id) -> match?(%{kingdom: "Plantae"}, Taxa.get_taxon(id))
      _ -> false
    end
  end

  # -- raising -------------------------------------------------------------------

  @doc """
  The question attribution `attribution_id` (a statement just written)
  raises, given the tree's `difference` (`difference/4`), as a queue item to
  insert (`%{kind, statement_ref, subject, proposal, reason}`), or nil: no
  difference, a statement that needs no acceptance or is decided, a
  plant's, one older than (or as old as) a statement that counts in its
  slot, or one already asked.
  """
  @spec question(integer(), String.t() | nil, String.t() | nil) :: map() | nil
  def question(_attribution_id, nil, _statement_ref), do: nil

  def question(attribution_id, reason, statement_ref) when is_integer(attribution_id) do
    with %Attribution{} = attribution <- Facts.get_attribution(attribution_id),
         {kind, key} <- Taxa.act_fact(attribution.fact_id),
         true <- askable?(attribution, key) do
      %{
        kind: @kind,
        statement_ref: statement_ref,
        subject: subject(Repo.preload(attribution, :names), kind, key),
        proposal: %{},
        reason: reason
      }
    else
      _ -> nil
    end
  end

  defp askable?(attribution, key) do
    kind = Facts.get_fact!(attribution.fact_id).kind

    Facts.needs_acceptance?(kind, attribution.source_id) and attribution.accepted_at == nil and
      attribution.declined_at == nil and not plant?(key) and newest?(attribution.id) and
      open_for(attribution.id) == []
  end

  @doc """
  Whether attribution `attribution_id` is newer than every statement that
  counts in its slot (`Gallformers.Facts.slot_statements/1`): the volume
  rule. True when none counts.
  """
  @spec newest?(integer()) :: boolean()
  def newest?(attribution_id) do
    case Enum.split_with(Facts.slot_statements(attribution_id), &(&1.id == attribution_id)) do
      {[this], others} ->
        others
        |> Enum.filter(&(&1.counts and not &1.retracted))
        |> Enum.all?(&Standing.newer?(this, &1))

      _ ->
        false
    end
  end

  # What the question is about: the statement, and what it states, its
  # taxa by ID and in the Source's words (by role).
  defp subject(attribution, kind, key) do
    written =
      attribution.names
      |> Enum.group_by(& &1.role, &(&1.name_as_written || &1.name_reading))
      |> Map.new(fn
        {"into", names} -> {"into", names}
        {role, [first | _]} -> {role, first}
      end)

    key
    |> Map.new(fn {k, v} -> {Atom.to_string(k), json(v)} end)
    |> Map.merge(%{
      "kind" => Atom.to_string(kind),
      "stance" => Atom.to_string(attribution.stance),
      "fact_id" => attribution.fact_id,
      "attribution_id" => attribution.id,
      "source_id" => attribution.source_id,
      "status_as_written" => attribution.status_as_written,
      "stated" => stated(attribution),
      "written" => written
    })
    |> Map.reject(fn {_k, v} -> v in [nil, %{}] end)
  end

  defp json(value) when is_atom(value) and not is_nil(value) and not is_boolean(value),
    do: Atom.to_string(value)

  defp json(value), do: value

  defp stated(%Attribution{stated_on: nil}), do: nil
  defp stated(%Attribution{stated_on: date, stated_precision: :year}), do: "#{date.year}"

  defp stated(%Attribution{stated_on: date, stated_precision: :month}),
    do: Calendar.strftime(date, "%Y-%m")

  defp stated(%Attribution{stated_on: date}), do: Date.to_iso8601(date)

  # Asks again about a reopened statement, where the rules still call for
  # it: from no package (the package was applied), under its act's ref.
  defp ask_again(attribution_id) do
    with %Attribution{} = attribution <- Facts.get_attribution(attribution_id),
         {kind, key} <- Taxa.act_fact(attribution.fact_id),
         reason when is_binary(reason) <-
           difference(Atom.to_string(kind), Atom.to_string(attribution.stance), key),
         %{} = item <- question(attribution_id, reason, act_ref(attribution)) do
      now = DateTime.utc_now(:second)

      Repo.insert_all(
        QueueItem,
        [Map.merge(item, %{status: :open, inserted_at: now, updated_at: now})],
        on_conflict: :nothing
      )
    end

    :ok
  end

  # The act's ref in the batch that stated it, when it can be found.
  defp act_ref(%Attribution{batch_id: batch_id, fact_id: fact_id}) when is_integer(batch_id) do
    Repo.one(
      from(s in BatchStatement,
        where: s.batch_id == ^batch_id and s.kind == :act and s.fact_id == ^fact_id,
        select: s.ref,
        limit: 1
      )
    )
  end

  defp act_ref(_attribution), do: nil

  # -- the queue -----------------------------------------------------------------

  @doc """
  The taxonomy questions, oldest first. Options: `:status` (default
  `:open`; `:all`), `:source_id` (one Source's).
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

  @doc "How many taxonomy questions are open: every Source's, or `source_id`'s."
  @spec count(integer() | nil) :: non_neg_integer()
  def count(source_id \\ nil) do
    query = from(q in QueueItem, where: q.kind == @kind and q.status == :open)

    query =
      if source_id,
        do: where(query, [q], fragment("(?->>'source_id')::bigint", q.subject) == ^source_id),
        else: query

    Repo.aggregate(query, :count)
  end

  defp open_for(attribution_id) do
    Repo.all(
      from(q in QueueItem,
        where:
          q.kind == @kind and q.status == :open and
            fragment("(?->>'attribution_id')::bigint", q.subject) == ^attribution_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp open_for_any([]), do: []

  defp open_for_any(attribution_ids) do
    Repo.all(
      from(q in QueueItem,
        where:
          q.kind == @kind and q.status == :open and
            fragment("(?->>'attribution_id')::bigint", q.subject) in ^attribution_ids,
        lock: "FOR UPDATE"
      )
    )
  end

  # -- deciding --------------------------------------------------------------------

  @doc """
  Checks a decision on a taxonomy question: `%{"accept" => true}`, or
  `%{"decline" => true, "reason" => text}` with a reason.
  """
  @spec check(map()) :: :ok | {:error, String.t()}
  def check(%{"accept" => true} = choice) when map_size(choice) == 1, do: :ok

  def check(%{"decline" => true, "reason" => reason} = choice) when map_size(choice) == 2 do
    if is_binary(reason) and String.trim(reason) != "",
      do: :ok,
      else: {:error, "a decline needs a reason"}
  end

  def check(_choice), do: {:error, "must be accept, or decline with a reason"}

  @doc """
  Decides taxonomy question `item` (`Gallformers.Import.decide_queue_item/3`
  calls it): `decision` checked (`check/1`), then made through
  `Gallformers.Import.TaxonomicDecisions` (audited, logged for replay),
  which closes the question. Returns the decided item. Errors as
  `decide_queue_item/3`'s, and the tree's refusal
  (`{:rejected, listener, reason}`; `refusal_text/1`).
  """
  @spec decide(Actor.t(), QueueItem.t(), map()) :: {:ok, QueueItem.t()} | {:error, term()}
  def decide(%Actor{} = actor, %QueueItem{kind: @kind} = item, decision) do
    Audit.transaction(actor, "import.decide_taxonomy_question", fn ->
      item = Repo.one(from(q in QueueItem, where: q.id == ^item.id, lock: "FOR UPDATE"))
      if item == nil, do: Repo.rollback(:gone)
      if item.status == :decided, do: Repo.rollback(:already_decided)

      changeset =
        item
        |> QueueItem.decide_changeset(decision, actor)
        |> Queue.validate_decision(item, decision)

      unless changeset.valid?, do: Repo.rollback(%{changeset | action: :update})

      choice = Map.delete(decision, "note")

      {op, reason} =
        if choice["accept"], do: {:accept, nil}, else: {:decline, choice["reason"]}

      case TaxonomicDecisions.decide(actor, op, statement_id(item), reason) do
        {:ok, _result} -> Repo.get!(QueueItem, item.id)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp statement_id(item), do: find_statement(item) || Repo.rollback(:gone)

  @doc """
  Settles the questions a decision `op` on `attribution` closes, inside
  `Gallformers.Import.TaxonomicDecisions.decide/4`'s transaction, before the
  decision is made: an acceptance closes the statement's own open question
  as accepted and those of older statements in its slot as history; a
  decline closes its own as declined, with `reason`. A reopening closes
  nothing; `asked_again/2` asks again after it.
  """
  @spec settle(Actor.t(), op(), Attribution.t(), String.t() | nil) :: :ok
  def settle(%Actor{} = actor, :accept, %Attribution{} = attribution, _reason) do
    close(actor, open_for(attribution.id), %{"accept" => true})
    close(actor, open_for_any(older_in_slot(attribution.id)), %{"history" => true})
  end

  def settle(%Actor{} = actor, :decline, %Attribution{} = attribution, reason) do
    reason = String.trim(reason || "")

    if reason == "",
      do: :ok,
      else: close(actor, open_for(attribution.id), %{"decline" => true, "reason" => reason})
  end

  def settle(%Actor{}, :reopen, %Attribution{}, _reason), do: :ok

  @doc "After `op` on attribution `attribution_id`: a reopened statement is asked again."
  @spec asked_again(op(), integer()) :: :ok
  def asked_again(:reopen, attribution_id), do: ask_again(attribution_id)
  def asked_again(_op, _attribution_id), do: :ok

  # The statements in the slot that `attribution_id`'s is newer than.
  defp older_in_slot(attribution_id) do
    statements = Facts.slot_statements(attribution_id)

    case Enum.find(statements, &(&1.id == attribution_id)) do
      nil -> []
      this -> for s <- statements, s.id != attribution_id, Standing.newer?(this, s), do: s.id
    end
  end

  defp close(actor, items, decision) do
    Enum.each(items, fn item ->
      item |> QueueItem.decide_changeset(decision, actor) |> Repo.update!()
    end)
  end

  @doc "A refusal of a taxonomic decision (the tree's, most often) in words."
  @spec refusal_text(term()) :: String.t()
  def refusal_text({:rejected, _listener, reason}), do: refusal_text(reason)

  def refusal_text({:tree, _taxon_id, _validation, message}),
    do: "The tree refuses it: #{message}."

  def refusal_text({:blocked, blockers}) when is_list(blockers),
    do:
      "It would merge a taxon that is still being decided: " <>
        Enum.map_join(blockers, "; ", &blocker_text/1) <> "."

  def refusal_text({_item_id, reason}), do: refusal_text(reason)
  def refusal_text(:gone), do: "The statement is gone; reload to see what is left."
  def refusal_text(:not_found), do: "The statement is gone; reload to see what is left."
  def refusal_text(:already_decided), do: "This question has been decided already."
  def refusal_text(:reason_required), do: "A decline needs a reason."
  def refusal_text(reason), do: "The decision was refused (#{inspect(reason)})."

  defp blocker_text(%{text: text, action: action}), do: "#{text}. #{action}"
  defp blocker_text(%{text: text}), do: text
  defp blocker_text(other), do: inspect(other)

  # -- the rest of a paper ----------------------------------------------------------

  @typedoc """
  What accepting the rest of a paper would do (`preview_rest/2`): the
  questions it accepts (`items`), and the tree's `moves` (`%{taxon_id,
  name, from, to}`, parents by name), `renames` (`%{taxon_id, from, to}`),
  `merges` (`%{taxon_id, name, into}`), `details` (rank and authorship,
  `%{taxon_id, name, text}`), `common_names` (`%{taxon_id, name, added,
  removed}`), the Galls whose names would change (`galls`: `%{gall_id,
  from, to, collision}`) and the splits that would come into effect
  (`splits`: `%{taxon_id, name, into, galls}`, `galls` the number of Galls
  that would each ask which taxon induces them). `refused` is nil, or
  `{item_id, reason}` for the question whose acceptance the tree refuses
  (nothing else is said then).
  """
  @type preview :: %{
          items: [QueueItem.t()],
          moves: [map()],
          renames: [map()],
          merges: [map()],
          details: [map()],
          common_names: [map()],
          galls: [map()],
          splits: [map()],
          refused: {integer(), term()} | nil
        }

  @doc """
  What accepting every open question of Source `source_id` would do
  (`t:preview/0`), worked out by making the acceptances in a transaction
  that is always rolled back.
  """
  @spec preview_rest(integer(), Actor.t()) :: {:ok, preview()} | {:error, term()}
  def preview_rest(source_id, %Actor{} = actor) when is_integer(source_id) do
    items = list(source_id: source_id)

    Catalog.without_gall_index_refresh(fn ->
      actor
      |> Audit.transaction("import.preview_taxonomy_rest", fn ->
        Repo.rollback({:preview, preview_in_transaction(actor, items)})
      end)
      |> case do
        {:error, {:preview, preview}} -> {:ok, preview}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp preview_in_transaction(actor, items) do
    touched = touched_taxa(items)
    before = snapshot(touched)
    renames_before = gall_renames()
    empty = %{moves: [], renames: [], merges: [], details: [], common_names: []}

    case accept_all(actor, items) do
      :ok ->
        after_ = snapshot(touched)

        empty
        |> Map.merge(tree_effects(before, after_))
        |> Map.merge(%{
          items: items,
          galls: gall_effects(renames_before, gall_renames()),
          splits: split_effects(items),
          refused: nil
        })

      {:error, item, reason} ->
        Map.merge(empty, %{items: items, galls: [], splits: [], refused: {item.id, reason}})
    end
  end

  @doc """
  Accepts every open question of Source `source_id` (its declined
  statements' questions are decided, so they stay declined), in one
  transaction: all or none. `{:error, {item_id, reason}}` when the tree
  refuses one.
  """
  @spec accept_rest(Actor.t(), integer()) ::
          {:ok, %{accepted: [QueueItem.t()]}} | {:error, term()}
  def accept_rest(%Actor{} = actor, source_id) when is_integer(source_id) do
    Audit.transaction(actor, "import.accept_taxonomy_rest", fn ->
      items = list(source_id: source_id)

      case accept_all(actor, items) do
        :ok ->
          ids = Enum.map(items, & &1.id)
          %{accepted: Repo.all(from(q in QueueItem, where: q.id in ^ids, order_by: q.id))}

        {:error, item, reason} ->
          Repo.rollback({item.id, reason})
      end
    end)
  end

  # Closes every question first, so none of them blocks a lump another's
  # acceptance brings about, then accepts each statement in turn. Stops at
  # the first refusal (the transaction can't go on after it).
  defp accept_all(actor, items) do
    close(actor, items, %{"accept" => true})

    Enum.reduce_while(items, :ok, fn item, :ok ->
      with id when is_integer(id) <- find_statement(item),
           {:ok, _} <- TaxonomicDecisions.decide(actor, :accept, id) do
        {:cont, :ok}
      else
        nil -> {:halt, {:error, item, :gone}}
        {:error, reason} -> {:halt, {:error, item, reason}}
      end
    end)
  end

  # The statement a question is about: by its attribution, else (a lump
  # moved it onto another Fact) by its Fact and Source; nil when gone.
  defp find_statement(%QueueItem{subject: subject}) do
    case Facts.get_attribution(subject["attribution_id"] || -1) do
      %Attribution{id: id} ->
        id

      nil ->
        case Facts.get_attribution(subject["fact_id"] || -1, subject["source_id"] || -1) do
          %Attribution{id: id} -> id
          nil -> nil
        end
    end
  end

  # The taxa the questions' statements are about, and those a synonymy
  # names (a lump's absorbed taxon).
  defp touched_taxa(items) do
    items
    |> Enum.flat_map(fn %QueueItem{subject: s} ->
      ids = [
        s["taxon_id"],
        s["parent_id"],
        s["accepted_taxon_id"] | List.wrap(s["into_taxon_ids"])
      ]

      lumped =
        case s["kind"] == "synonymy" && Taxa.resolve_name(s["name"] || "") do
          {:ok, %{id: id}} -> [id]
          _ -> []
        end

      ids ++ lumped
    end)
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
  end

  defp snapshot(ids) do
    Map.new(ids, fn id ->
      case Taxa.get_taxon(id) do
        nil ->
          {id, nil}

        taxon ->
          accepted = Enum.find(taxon.names, &(&1.status == :accepted))

          {id,
           %{
             name: accepted && accepted.name,
             parent_id: taxon.parent_id,
             rank: taxon.rank,
             authorship: accepted && accepted.authorship,
             common_names: taxon.id |> Taxa.list_common_names() |> Enum.map(& &1.name)
           }}
      end
    end)
  end

  defp tree_effects(before, after_) do
    rows = for {id, was} <- before, was != nil, do: {id, was, Map.get(after_, id)}
    kept = for {id, was, now} <- rows, now != nil, do: {id, was, now}

    %{
      moves: Enum.flat_map(kept, &move/1),
      renames: Enum.flat_map(kept, &rename/1),
      merges: for({id, was, nil} <- rows, do: merge(id, was)),
      details: Enum.flat_map(kept, &detail/1),
      common_names: Enum.flat_map(kept, &common_names/1)
    }
  end

  defp move({id, %{parent_id: from}, %{parent_id: to} = now}) when from != to,
    do: [%{taxon_id: id, name: now.name, from: parent(from), to: parent(to)}]

  defp move(_row), do: []

  defp rename({id, %{name: from}, %{name: to}}) when from != to,
    do: [%{taxon_id: id, from: from, to: to}]

  defp rename(_row), do: []

  defp merge(id, was) do
    into = Taxa.taxon_redirect(id)
    %{taxon_id: id, name: was.name, into: into && Taxa.accepted_name(into)}
  end

  defp detail({id, was, now}) do
    case detail_text(was, now) do
      nil -> []
      text -> [%{taxon_id: id, name: now.name, text: text}]
    end
  end

  defp common_names({id, was, now}) do
    case {now.common_names -- was.common_names, was.common_names -- now.common_names} do
      {[], []} -> []
      {added, removed} -> [%{taxon_id: id, name: now.name, added: added, removed: removed}]
    end
  end

  defp parent(nil), do: "the root"
  defp parent(id), do: Taxa.accepted_name(id)

  defp detail_text(was, now) do
    [
      was.rank != now.rank && "rank #{was.rank} → #{now.rank}",
      was.authorship != now.authorship &&
        "authorship #{was.authorship || "none"} → #{now.authorship || "none"}"
    ]
    |> Enum.filter(& &1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, "; ")
    end
  end

  # The open rename proposals, by Gall.
  defp gall_renames do
    from(q in QueueItem, where: q.kind == :gall_rename and q.status == :open)
    |> Repo.all()
    |> Map.new(&{&1.proposal["gall_id"], &1.proposal})
  end

  defp gall_effects(before, after_) do
    for {gall_id, proposal} <- after_, Map.get(before, gall_id) != proposal do
      %{
        gall_id: gall_id,
        from: proposal["from"],
        to: proposal["to"],
        collision: proposal["collision"] == true
      }
    end
    |> Enum.sort_by(& &1.from)
  end

  # The splits coming into effect, and the Galls on the split taxon, each of
  # which then asks which taxon induces it (`f923` Task 7).
  defp split_effects(items) do
    for %QueueItem{subject: %{"kind" => "split", "stance" => "confirm"} = s} <- items,
        Repo.exists?(from(f in Fact, where: f.id == ^s["fact_id"] and f.standing == :current)) do
      id = s["taxon_id"]

      %{
        taxon_id: id,
        name: Taxa.accepted_name(id),
        into: Enum.map(List.wrap(s["into_taxon_ids"]), &Taxa.accepted_name/1),
        galls: length(Catalog.list_gall_summaries_by_inducer([id]))
      }
    end
  end
end
