defmodule Gallformers.Import.Queue do
  @moduledoc """
  The admin queue's decisions (`9449` §5, Task 13): what an admin may
  decide for each kind of item, how decisions are honoured when a batch is
  resolved and applied, and which open items hold a package's approval.

  ## Decisions

  A decision is a map, by what the item is about:

  | Item | Decision |
  |---|---|
  | a taxon (`t1`): ambiguous, unresolved, unresolved Host, held-valid synonym | `%{"taxon_id" => id}` or `%{"skip" => true}` |
  | a name (`t1`, not a Host): ambiguous, unresolved | also `%{"new" => true}`, optionally with `"parent_id" => id`: the taxon it is created under, ranked above it |
  | a held-valid synonym (`Gallformers.Import.SynonymDecisions`) | also `%{"split" => true}` (a species of its own again) or `%{"synonym_of" => id}` (another species' synonym): tree edits for every Source |
  | a Host name (`Gallformers.Import.HostDecisions`) | also `%{"taxon_id" => id, "add_synonym" => true}` or `%{"wcvp_id" => id}` |
  | a Gall (`g1`): ambiguous, undescribed candidates, unresolved | `%{"gall_id" => id}`, `%{"new" => true}` or `%{"skip" => true}`; each may add `"drop" => [fact refs]` and `"host_reading" => %{"name", "taxon_id"}`, and new `"generation" => value` (`Gallformers.Import.GallDecisions`) |
  | the package's Source (`"source"`) | `%{"source_id" => id}` or `%{"new" => true}` |
  | the Source a notice retracts (`"retracts"`) | `%{"source_id" => id}` or `%{"skip" => true}` |
  | a phase 6 dispute (`f3`, `a2`, ...; `Gallformers.Import.Disputes`) | `%{"keep" => true}` (the statement stands) or `%{"skip" => true}` (it is dropped); a Host dispute also `%{"keep" => true, "host_reading" => %{"name", "taxon_id"}}` (it stands, the Host read as another plant throughout the Source; a species-level Host only) or `%{"keep" => true, "host_taxon_id" => id}` (it stands on the plant chosen, for its statements only); a Trait dispute also `%{"values" => [v, …]}` (it stands on those values of its Trait) |
  | a same-date conflict, a generation outside its group, a plant's disagreeing act | `%{}` (acknowledged) |
  | a taxonomic statement to accept (`Gallformers.Import.TaxonomyQueue`) | `%{"accept" => true}` or `%{"decline" => true, "reason" => text}` (a reason required) |
  | a rename proposal (`Gallformers.Import.GallRenames`) | `%{"accept" => true}` or `%{"reject" => true}` |
  | a statement set aside (`u:<slot>:<term>`, `Gallformers.Import.SetAside`) | `%{"keep" => true}` or `%{"state" => spec}` |
  | a name the producer missed (`n:<name>`, `Gallformers.Import.MissedNames`) | `%{"dismiss" => true}` or `%{"state" => spec}` |
  | a Trait term (`u:<trait>:<term>`, `Gallformers.Import.TraitTerms`) | `%{"place" => c}` or `%{"place" => [c1, c2]}` (for every Source: the values a term names), `%{"category" => c}` (these Galls), `%{"no_fit" => true}` or `%{"keep" => true}` |

  A decided item stays decided: resolving the package again keeps it and
  honours it (`overlay/2`), and the replay log records it
  (`Gallformers.Import.Replay`).

  A curator's note is not part of the decision: it is saved on its own,
  decided or not (`Gallformers.Import.add_note/3`), and is not replayed.
  A decision may still carry a `"note"` (text), as decisions made before
  notes were saved on their own do; it is shown as a note
  (`Gallformers.Import.notes_for/1`).

  ## One decision per name

  A package's taxonomy batch and gall batch often declare the same name
  under different refs. Within a package a name — its normalized name,
  rank and sensu (`name_keys/1`) — is queued once (`share_names/1`), and a
  decision on it, from either batch, holds for every batch that declares
  it.

  ## Honouring decisions

  A decided taxon or Gall becomes `:resolved` to the chosen entry (method
  `"decision"`), one decided new becomes `:new` (created when the batch
  is applied; the parent or generation it was decided with kept on its
  detail as `"chosen_parent_id"` or `"chosen_generation"`), and a skipped
  one stays unresolved, flagged `"skipped"`, so
  the statements that need it are not applied and it holds nothing.

  A dispute decided `skip` drops its statement from the batch (each of its
  statements, for one asking a question of several Galls):

    * an act or Fact (`a2`, `f3`) is not written (`drops/1`); a dropped
      Trait Fact's words stay as text on the Gall
      (`Gallformers.Import.Disputes.texts/2`);
    * a taxon (`t3`) or Gall (`g27`) becomes unresolved and `"skipped"`
      whatever it resolved to (`statement_decisions/1`): a new taxon or
      Gall is not created, and the acts and Facts that name it are not
      written. A dropped taxon is a decision on its name, so it is dropped
      in the package's other batch too. A Gall whose Inducer is dropped is
      no longer identified by it: it is matched again without it and
      queued on its own if it needs someone.

  ## The approval gate

  Open items about something a batch needs hold the package
  (`blocking?/2`): ambiguous and unresolved names and Galls, unresolved
  Hosts, undescribed-Gall candidates, disputes (but those about Trait
  terms, `Gallformers.Import.Disputes.trait?/1`), the Source, and a gall
  batch's held-valid synonyms. Same-date conflicts, generations outside
  their groups, a taxonomy batch's disagreeing acts and the taxonomic
  statements to accept or decline (`Gallformers.Import.TaxonomyQueue`) are
  for a curator after the fact: the Facts are recorded either way. Statements set aside
  and questions about Trait terms never hold approval: left alone, a
  statement stays out and a term stays as text on its Gall.
  """
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Catalog
  alias Gallformers.Import.Disputes
  alias Gallformers.Import.GallDecisions
  alias Gallformers.Import.HostDecisions
  alias Gallformers.Import.MissedNames
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.SetAside
  alias Gallformers.Import.SplitQuestions
  alias Gallformers.Import.SynonymDecisions
  alias Gallformers.Import.TaxonomyQueue
  alias Gallformers.Import.TraitTerms
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Rank

  @blocking [:ambiguous_match, :unresolved_name, :unresolved_host, :undescribed_gall, :dispute]

  @doc """
  Whether an open `item` (a queue item, or one about to be queued) of a
  batch of `batch_type` (nil for the package) holds approval.
  """
  @spec blocking?(QueueItem.t() | %{kind: QueueItem.kind()}, :taxonomy | :gall | nil) ::
          boolean()
  def blocking?(%{kind: :dispute} = item, _batch_type), do: not Disputes.trait?(item)
  def blocking?(%{kind: kind}, _batch_type) when kind in @blocking, do: true
  def blocking?(%{kind: :taxonomy_disagreement}, :gall), do: true
  def blocking?(%{kind: :taxonomy_acceptance}, _batch_type), do: false
  def blocking?(%{kind: :split_inducer}, _batch_type), do: false
  def blocking?(_item, _batch_type), do: false

  # -- validating decisions ----------------------------------------------------

  @doc "Checks `decision` fits `item`, adding errors on `:decision` to `changeset`."
  @spec validate_decision(Ecto.Changeset.t(), QueueItem.t(), map()) :: Ecto.Changeset.t()
  def validate_decision(changeset, item, decision) when is_map(decision) do
    {choice, rest} = Map.split(decision, Map.keys(decision) -- ["note"])

    with :ok <- check_note(rest),
         :ok <- check_host_or_choice(item, choice) do
      changeset
    else
      {:error, message} -> add_error(changeset, :decision, message)
    end
  end

  def validate_decision(changeset, _item, _decision),
    do: add_error(changeset, :decision, "must be a map")

  # A decision's note (older decisions; notes are saved on their own now).
  defp check_note(%{"note" => note}) when not is_binary(note), do: {:error, "note must be text"}
  defp check_note(_rest), do: :ok

  # The questions of no package take their own shapes.
  defp check_host_or_choice(%QueueItem{kind: :taxonomy_acceptance}, choice),
    do: TaxonomyQueue.check(choice)

  defp check_host_or_choice(%QueueItem{kind: :split_inducer} = item, choice),
    do: SplitQuestions.check(item, choice)

  defp check_host_or_choice(item, choice) do
    cond do
      new_taxon_parent?(item, choice) ->
        {parent_id, choice} = Map.pop(choice, "parent_id")

        with :ok <- check_choice(choices(item), choice),
             do: check_parent(item, choice, parent_id)

      GallDecisions.gall?(item) ->
        {extras, choice} = GallDecisions.split(choice)

        with :ok <- check_choice(choices(item), choice),
             do: GallDecisions.check(item, extras, choice)

      SynonymDecisions.synonym?(item) ->
        or_choice(SynonymDecisions.check(item, choice), item, choice)

      item.kind == :dispute and Disputes.host_extras?(choice) ->
        {extras, choice} = Disputes.split(choice)

        with :ok <- check_choice(choices(item), choice),
             do: Disputes.check_extras(item, extras, choice)

      true ->
        or_choice(HostDecisions.host?(item) && HostDecisions.check(item, choice), item, choice)
    end
  end

  # A name decided new may name the taxon to create it under.
  defp new_taxon_parent?(%QueueItem{kind: kind, statement_ref: "t" <> _}, choice)
       when kind != :dispute,
       do: Map.has_key?(choice, "parent_id")

  defp new_taxon_parent?(_item, _choice), do: false

  defp check_parent(_item, choice, _parent_id) when choice != %{"new" => true},
    do: {:error, "parent_id goes only with new"}

  defp check_parent(%QueueItem{subject: subject}, _choice, parent_id) do
    parent = is_integer(parent_id) && Taxa.get_taxon(parent_id)
    rank = Enum.find(Rank.all(), &(to_string(&1) == (subject || %{})["rank"]))

    cond do
      !parent -> {:error, "parent_id must be a taxon"}
      rank == nil -> {:error, "the name has no rank to place it by"}
      Rank.below?(rank, parent.rank) -> :ok
      true -> {:error, "parent_id must rank above the new #{rank}"}
    end
  end

  # A module's check, or (not its item, or none of its shapes) the item's choices.
  defp or_choice(result, item, choice) do
    if result in [false, :other], do: check_choice(choices(item), choice), else: result
  end

  # The choices an item allows, as {key, check}; :none means it is only
  # acknowledged.
  defp choices(%QueueItem{statement_ref: "source"}),
    do: [{"source_id", &source?/1}, {"new", &(&1 == true)}]

  defp choices(%QueueItem{statement_ref: "retracts"}),
    do: [{"source_id", &source?/1}, {"skip", &(&1 == true)}]

  defp choices(%QueueItem{kind: :dispute} = item), do: Disputes.choices(item)

  defp choices(%QueueItem{kind: :gall_rename}),
    do: [{"accept", &(&1 == true)}, {"reject", &(&1 == true)}]

  defp choices(%QueueItem{kind: :set_aside_statement} = item), do: SetAside.choices(item)
  defp choices(%QueueItem{kind: :trait_term} = item), do: TraitTerms.choices(item)
  defp choices(%QueueItem{kind: :missed_name} = item), do: MissedNames.choices(item)

  defp choices(%QueueItem{kind: kind})
       when kind in [:same_date_conflict, :generation_outside_group],
       do: :none

  defp choices(%QueueItem{kind: :taxonomy_disagreement, statement_ref: "a" <> _}), do: :none

  defp choices(%QueueItem{kind: :taxonomy_disagreement, statement_ref: "t" <> _}),
    do: {:optional, [{"taxon_id", &taxon?/1}, {"skip", &(&1 == true)}]}

  # A Host is never created by import (plants come from POWO), so only a
  # name can be decided new (e.g. against a proposed spelling variant).
  defp choices(%QueueItem{kind: :unresolved_host}),
    do: [{"taxon_id", &taxon?/1}, {"skip", &(&1 == true)}]

  defp choices(%QueueItem{statement_ref: "t" <> _}),
    do: [{"taxon_id", &taxon?/1}, {"new", &(&1 == true)}, {"skip", &(&1 == true)}]

  defp choices(%QueueItem{statement_ref: "g" <> _}),
    do: [{"gall_id", &gall?/1}, {"new", &(&1 == true)}, {"skip", &(&1 == true)}]

  defp choices(_item), do: :none

  defp check_choice(:none, choice) when map_size(choice) == 0, do: :ok

  defp check_choice(:none, _choice),
    do: {:error, "this item is only acknowledged (a note at most)"}

  defp check_choice({:optional, _allowed}, choice) when map_size(choice) == 0, do: :ok
  defp check_choice({:optional, allowed}, choice), do: check_choice(allowed, choice)

  defp check_choice(allowed, choice) do
    keys = Enum.map_join(allowed, ", ", &elem(&1, 0))

    with [{key, value}] <- Map.to_list(choice),
         {^key, check} <- List.keyfind(allowed, key, 0) do
      if check.(value), do: :ok, else: {:error, "#{key} is not valid here"}
    else
      _ -> {:error, "must be exactly one of #{keys}"}
    end
  end

  defp taxon?(id), do: is_integer(id) and Taxa.get_taxon(id) != nil
  defp gall?(id), do: is_integer(id) and Catalog.get_gall(id) != nil
  defp source?(id), do: is_integer(id) and Sources.get_source(id) != nil

  # -- honouring decisions -----------------------------------------------------

  @doc "The decided items of a batch."
  @spec decided(integer()) :: [QueueItem.t()]
  def decided(batch_id) do
    Repo.all(
      from(q in QueueItem,
        where: q.batch_id == ^batch_id and q.status == :decided,
        order_by: q.decided_at
      )
    )
  end

  @typedoc """
  What a decision does to a taxon or Gall statement: an item's decision
  map, or `{:dropped, reason}` for a statement whose dispute was decided
  `skip`.
  """
  @type statement_decision :: map() | {:dropped, String.t()}

  @doc """
  The decisions among `decided` (a batch's decided items) that bear on its
  taxon and Gall statements, by statement ref: each item's decision, and
  `{:dropped, reason}` for a taxon or Gall whose dispute was decided `skip`
  (a dropped statement stays dropped whatever else was decided for it).
  """
  @spec statement_decisions([QueueItem.t()]) :: %{String.t() => statement_decision()}
  def statement_decisions(decided) do
    {disputes, items} = Enum.split_with(decided, &(&1.kind == :dispute))

    by_ref =
      for %QueueItem{statement_ref: ref} = item <- items,
          statement_ref?(ref),
          into: %{},
          do: {ref, item.decision}

    dropped =
      for %QueueItem{decision: %{"skip" => true}} = item <- disputes,
          ref <- Disputes.refs(item),
          statement_ref?(ref),
          into: %{},
          do: {ref, {:dropped, drop_reason(item)}}

    Map.merge(by_ref, dropped)
  end

  @doc "The decision on `item` as it bears on its statement (`statement_decisions/1`), or nil."
  @spec statement_decision(QueueItem.t()) :: statement_decision() | nil
  def statement_decision(%QueueItem{statement_ref: ref} = item),
    do: Map.get(statement_decisions([item]), ref)

  defp statement_ref?("t" <> _), do: true
  defp statement_ref?("g" <> _), do: true
  defp statement_ref?(_ref), do: false

  defp drop_reason(item), do: "disputed finding upheld by #{item.decided_by_name}"

  @typedoc "A declared taxon's name key: its normalized name, rank and sensu."
  @type name_key :: {String.t(), String.t() | nil, String.t() | nil}

  @doc """
  The name key of each taxon `content` (a decoded batch) declares, by ref:
  its name (`name_reading`, else `name_as_written`) normalized
  (`Gallformers.Taxa.NameNormalizer`), its rank and its sensu. Within a
  package one name key is one name: it is queued once and decided once for
  every batch that declares it.
  """
  @spec name_keys(map() | nil) :: %{String.t() => name_key()}
  def name_keys(%{"taxa" => taxa}) when is_list(taxa) do
    for %{"ref" => ref} = t <- taxa,
        name = t["name_reading"] || t["name_as_written"],
        is_binary(name) and name != "",
        into: %{},
        do: {ref, {NameNormalizer.normalize(name), t["rank"], t["sensu"]}}
  end

  def name_keys(_content), do: %{}

  @doc """
  Queues each name once per package. `batches` are the package's batches
  being resolved, in order (the taxonomy batch first), each
  `%{file, batch_type, name_keys, queue}` (`name_keys/1`; the items the
  batch calls for). A taxon item whose name another item also has — the
  same name declared in both batches — is kept once: as an unresolved Host
  where it is one, else on the first batch whose approval it holds
  (`blocking?/2`), else on the first; its
  `subject["also"]` listing the others as `%{"batch" => file, "ref" => ref}`.
  The others are left out; their statements take its decision. Returns
  each batch's queue, in order.
  """
  @spec share_names([map()]) :: [[map()]]
  def share_names(batches) do
    indexed = Enum.with_index(batches)

    # Who queues each name: {batch, ref}, with whether the item holds its batch.
    claims =
      for {batch, i} <- indexed,
          item <- batch.queue,
          key = item_name_key(batch, item),
          do:
            {key,
             %{
               claim: {i, item.statement_ref},
               host?: item.kind == :unresolved_host,
               blocks?: blocking?(item, batch.batch_type)
             }}

    groups = Enum.group_by(claims, &elem(&1, 0), &elem(&1, 1))

    # A Host name goes to the Host-name step wherever it is one (`d585`).
    owners =
      Map.new(groups, fn {key, [first | _] = claimants} ->
        owner =
          Enum.find(claimants, &(&1.host? and &1.blocks?)) ||
            Enum.find(claimants, first, & &1.blocks?)

        {key, owner.claim}
      end)

    for {batch, i} <- indexed do
      Enum.flat_map(
        batch.queue,
        &kept_item(&1, i, item_name_key(batch, &1), owners, groups, batches)
      )
    end
  end

  # The item as the batch keeps it: unchanged when it is not about a name,
  # with the others listed when it owns its name, or left out.
  defp kept_item(item, _i, nil, _owners, _groups, _batches), do: [item]

  defp kept_item(item, i, key, owners, groups, batches) do
    if {i, item.statement_ref} == owners[key],
      do: [with_also(item, owners[key], groups[key], batches)],
      else: []
  end

  defp with_also(item, owner, claimants, batches) do
    case for(%{claim: {i, ref} = claim} <- claimants, claim != owner, do: {i, ref}) do
      [] ->
        item

      others ->
        also = for {i, ref} <- others, do: %{"batch" => Enum.at(batches, i).file, "ref" => ref}
        put_in(item, [:subject, "also"], also)
    end
  end

  defp item_name_key(batch, %{kind: kind, statement_ref: "t" <> _ = ref}) when kind != :dispute,
    do: Map.get(batch.name_keys, ref)

  defp item_name_key(_batch, _item), do: nil

  @doc """
  `statements` (taxon or Gall statements, as the resolver gives them or as
  stored) with `decisions` (`statement_decisions/1`, by ref) applied.
  """
  @spec overlay([map()], %{String.t() => statement_decision()}) :: [map()]
  def overlay(statements, decisions) when is_map(decisions) do
    Enum.map(statements, &apply_decision(&1, Map.get(decisions, &1.ref)))
  end

  # What a decision new chooses for what is created, kept on its statement's
  # detail for applying: a taxon's parent, a Gall's generation and the plant
  # chosen for its Host (`Gallformers.Import.GallDecisions`).
  @chosen [
    {"parent_id", "chosen_parent_id"},
    {"generation", "chosen_generation"},
    {"host_taxon_id", "chosen_host_taxon_id"}
  ]

  @doc """
  Applies a decision to one statement (nil: no decision). A dropped
  statement (`{:dropped, reason}`) becomes unresolved and `"skipped"`,
  whatever it resolved to, so nothing of it, or that needs it, is applied.
  """
  @spec apply_decision(map(), statement_decision() | nil) :: map()
  def apply_decision(statement, nil), do: statement

  def apply_decision(s, {:dropped, reason}) do
    s
    |> Map.merge(%{
      resolution: :unresolved,
      method: "decision",
      flags: Enum.uniq(s.flags ++ ["skipped"]),
      detail: Map.put(s.detail || %{}, "reason", "dropped: #{reason}")
    })
    |> clear(:taxon_id)
    |> clear(:gall_id)
  end

  def apply_decision(%{resolution: resolution} = s, %{"taxon_id" => id})
      when resolution in [:unresolved, :ambiguous],
      do: %{s | resolution: :resolved, taxon_id: id, method: "decision"}

  def apply_decision(%{resolution: resolution} = s, %{"gall_id" => id})
      when resolution in [:unresolved, :ambiguous],
      do: %{s | resolution: :resolved, gall_id: id, method: "decision"}

  def apply_decision(%{resolution: resolution} = s, %{"new" => true} = decision)
      when resolution in [:unresolved, :ambiguous] do
    chosen =
      for {key, detail_key} <- @chosen,
          Map.has_key?(decision, key),
          into: %{},
          do: {detail_key, decision[key]}

    %{s | resolution: :new, method: "decision", detail: Map.merge(s.detail || %{}, chosen)}
  end

  def apply_decision(%{resolution: resolution} = s, %{"skip" => true})
      when resolution in [:unresolved, :ambiguous],
      do: %{s | flags: Enum.uniq(s.flags ++ ["skipped"])}

  def apply_decision(statement, _decision), do: statement

  defp clear(statement, key),
    do: if(Map.has_key?(statement, key), do: Map.put(statement, key, nil), else: statement)

  @doc """
  The acts and Facts curators dropped (disputes decided `skip`, and the
  statements a Gall decision leaves out, `Gallformers.Import.GallDecisions`),
  ref to the reason. A dropped taxon or Gall is honoured on its statement
  instead (`statement_decisions/1`).
  """
  @spec drops([QueueItem.t()]) :: %{String.t() => String.t()}
  def drops(decided) do
    disputed =
      for %QueueItem{kind: :dispute, decision: %{"skip" => true}} = item <- decided,
          ref <- Disputes.refs(item),
          not statement_ref?(ref),
          into: %{},
          do: {ref, drop_reason(item)}

    Map.merge(GallDecisions.drops(decided), disputed)
  end

  @doc """
  Whether `statements` hold a gall batch: a Host name neither resolved nor
  skipped (`d585`).
  """
  @spec holds_gall_batch?([map()]) :: boolean()
  def holds_gall_batch?(statements) do
    Enum.any?(statements, fn s ->
      s.kind == :taxon and s.detail["host"] == true and s.resolution in [:unresolved, :ambiguous] and
        "skipped" not in s.flags
    end)
  end
end
