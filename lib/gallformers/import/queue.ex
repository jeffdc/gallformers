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
  | a Gall (`g1`): ambiguous, undescribed candidates, unresolved | `%{"gall_id" => id}`, `%{"new" => true}` or `%{"skip" => true}` |
  | the package's Source (`"source"`) | `%{"source_id" => id}` or `%{"new" => true}` |
  | the Source a notice retracts (`"retracts"`) | `%{"source_id" => id}` or `%{"skip" => true}` |
  | a phase 6 dispute (`f3`, `a2`, ...) | `%{"keep" => true}` (the statement stands) or `%{"skip" => true}` (it is dropped) |
  | a same-date conflict, a generation outside its group, a disagreeing act | `%{"note" => text}` or `%{}` (acknowledged) |
  | a rename proposal (`Gallformers.Import.GallRenames`) | `%{"accept" => true}` or `%{"reject" => true}` |

  Any decision may add a `"note"`. A decided item stays decided: resolving
  the package again keeps it and honours it (`overlay/2`), and the replay
  log records it (`Gallformers.Import.Replay`).

  ## Honouring decisions

  A decided taxon or Gall becomes `:resolved` to the chosen entry (method
  `"decision"`), a Gall decided new becomes `:new` (created when the batch
  is applied), and a skipped one stays unresolved, flagged `"skipped"`, so
  the statements that need it are not applied and it holds nothing. A
  dispute decided `skip` drops its statement from the batch.

  ## The approval gate

  Open items about something a batch needs hold the package
  (`blocking?/2`): ambiguous and unresolved names and Galls, unresolved
  Hosts, undescribed-Gall candidates, disputes, the Source, and a gall
  batch's held-valid synonyms. Same-date conflicts, generations outside
  their groups and a taxonomy batch's disagreeing acts are for a curator
  after the fact: the Facts are recorded either way.
  """
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Catalog
  alias Gallformers.Import.QueueItem
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa

  @blocking [:ambiguous_match, :unresolved_name, :unresolved_host, :undescribed_gall, :dispute]

  @doc "Whether an open `item` of a batch of `batch_type` (nil for the package) holds approval."
  @spec blocking?(QueueItem.t(), :taxonomy | :gall | nil) :: boolean()
  def blocking?(%QueueItem{kind: kind}, _batch_type) when kind in @blocking, do: true
  def blocking?(%QueueItem{kind: :taxonomy_disagreement}, :gall), do: true
  def blocking?(_item, _batch_type), do: false

  # -- validating decisions ----------------------------------------------------

  @doc "Checks `decision` fits `item`, adding errors on `:decision` to `changeset`."
  @spec validate_decision(Ecto.Changeset.t(), QueueItem.t(), map()) :: Ecto.Changeset.t()
  def validate_decision(changeset, item, decision) when is_map(decision) do
    {choice, rest} = Map.split(decision, Map.keys(decision) -- ["note"])

    with :ok <- check_note(rest),
         :ok <- check_choice(choices(item), choice) do
      changeset
    else
      {:error, message} -> add_error(changeset, :decision, message)
    end
  end

  def validate_decision(changeset, _item, _decision),
    do: add_error(changeset, :decision, "must be a map")

  defp check_note(%{"note" => note}) when not is_binary(note), do: {:error, "note must be text"}
  defp check_note(_rest), do: :ok

  # The choices an item allows, as {key, check}; :none means it is only
  # acknowledged.
  defp choices(%QueueItem{statement_ref: "source"}),
    do: [{"source_id", &source?/1}, {"new", &(&1 == true)}]

  defp choices(%QueueItem{statement_ref: "retracts"}),
    do: [{"source_id", &source?/1}, {"skip", &(&1 == true)}]

  defp choices(%QueueItem{kind: :dispute}),
    do: [{"keep", &(&1 == true)}, {"skip", &(&1 == true)}]

  defp choices(%QueueItem{kind: :gall_rename}),
    do: [{"accept", &(&1 == true)}, {"reject", &(&1 == true)}]

  defp choices(%QueueItem{kind: kind})
       when kind in [:same_date_conflict, :generation_outside_group],
       do: :none

  defp choices(%QueueItem{kind: :taxonomy_disagreement, statement_ref: "a" <> _}), do: :none

  defp choices(%QueueItem{kind: :taxonomy_disagreement, statement_ref: "t" <> _}),
    do: {:optional, [{"taxon_id", &taxon?/1}, {"skip", &(&1 == true)}]}

  defp choices(%QueueItem{statement_ref: "t" <> _}),
    do: [{"taxon_id", &taxon?/1}, {"skip", &(&1 == true)}]

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

  @doc """
  `statements` (taxon or Gall statements, as the resolver gives them or as
  stored) with the decisions among `decided` applied.
  """
  @spec overlay([map()], [QueueItem.t()]) :: [map()]
  def overlay(statements, decided) do
    by_ref =
      for %QueueItem{kind: kind} = item <- decided,
          kind != :dispute,
          into: %{},
          do: {item.statement_ref, item.decision}

    Enum.map(statements, &apply_decision(&1, Map.get(by_ref, &1.ref)))
  end

  @doc "Applies a decision to one statement (nil: no decision)."
  @spec apply_decision(map(), map() | nil) :: map()
  def apply_decision(statement, nil), do: statement

  def apply_decision(%{resolution: resolution} = s, %{"taxon_id" => id})
      when resolution in [:unresolved, :ambiguous],
      do: %{s | resolution: :resolved, taxon_id: id, method: "decision"}

  def apply_decision(%{resolution: resolution} = s, %{"gall_id" => id})
      when resolution in [:unresolved, :ambiguous],
      do: %{s | resolution: :resolved, gall_id: id, method: "decision"}

  def apply_decision(%{resolution: resolution} = s, %{"new" => true})
      when resolution in [:unresolved, :ambiguous],
      do: %{s | resolution: :new, method: "decision"}

  def apply_decision(%{resolution: resolution} = s, %{"skip" => true})
      when resolution in [:unresolved, :ambiguous],
      do: %{s | flags: Enum.uniq(s.flags ++ ["skipped"])}

  def apply_decision(statement, _decision), do: statement

  @doc "The statements curators dropped (disputes decided `skip`), ref to the reason."
  @spec drops([QueueItem.t()]) :: %{String.t() => String.t()}
  def drops(decided) do
    for %QueueItem{kind: :dispute, decision: %{"skip" => true}} = item <- decided,
        into: %{},
        do: {item.statement_ref, "disputed finding upheld by #{item.decided_by_name}"}
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

  @doc """
  The queue items for a batch's phase 6 disputes: findings in `review` (the
  decoded `review.json`) about batch `file` that the producer disagreed
  with, one item per statement (several reviewers' findings together).
  """
  @spec dispute_items(map() | nil, String.t()) :: [map()]
  def dispute_items(nil, _file), do: []

  def dispute_items(review, file) do
    review
    |> Map.get("findings", [])
    |> List.wrap()
    |> Enum.filter(&(&1["batch"] == file and get_in(&1, ["response", "decision"]) == "disagree"))
    |> Enum.group_by(& &1["id"])
    |> Enum.sort_by(fn {id, _} -> id end)
    |> Enum.map(fn {id, findings} ->
      %{
        kind: :dispute,
        statement_ref: id,
        subject: %{
          "findings" =>
            Enum.map(
              findings,
              &Map.take(&1, ["problem", "reason", "suggestion", "reviewer", "response"])
            )
        },
        proposal: %{},
        reason:
          Enum.map_join(findings, " | ", fn f ->
            "reviewer: #{f["reason"]}; producer: #{f["response"]["reason"]}"
          end)
      }
    end)
  end
end
