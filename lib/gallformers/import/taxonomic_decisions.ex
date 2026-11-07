defmodule Gallformers.Import.TaxonomicDecisions do
  @moduledoc """
  A curator's decision on a Source's taxonomic statement (matter `f923`
  Task 1): accept it (it counts, and the tree follows it when it wins),
  decline it with a reason, or reopen it. The decision itself is
  `Gallformers.Facts.accept/3`, `decline/4` and `reopen/2`; this records it
  in the replay log too, in the same audited transaction, so a decision
  made on preview is made again after the cutover data migration.

  ## The replay log

  A `:taxonomic_decision` entry's key is `%{"op", "source", "kind",
  "fact"}`: the operation (`"accept" | "decline" | "reopen"`), the Source by
  title, the act's kind as the import contract names it, and its natural
  key with taxa as stable references (`Gallformers.Import.StableRef`),
  taken before the decision (which may rename them). A decline's payload
  holds its `"reason"`. Replay finds the statement by the same references
  and makes the decision again, unless the statement is in that state
  already.

  ## The taxonomy queue

  Each decision settles the statement's questions in the taxonomy queue
  (`Gallformers.Import.TaxonomyQueue.settle/4`) before it is made, in the
  same transaction: its own question closes (so it doesn't block a lump
  its acceptance brings about), and an acceptance closes older papers'
  questions on the same slot as history. A reopened statement is asked
  again. Replaying a decision settles them the same way, so the questions
  an import raises again after the cutover close as they did.
  """
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Import.ReplayLog
  alias Gallformers.Import.StableRef
  alias Gallformers.Import.TaxonomyQueue
  alias Gallformers.Repo
  alias Gallformers.Taxa

  @type op :: :accept | :decline | :reopen

  @kinds %{
    "placement" => :placement,
    "name" => :name,
    "synonymy" => :synonymy,
    "split" => :split,
    "common_name" => :common_name
  }

  @doc """
  Makes decision `op` on attribution `attribution_id` (a decline with
  `reason`) and logs it for replay. Returns what `Gallformers.Facts` does;
  on an error nothing is written or logged.
  """
  @spec decide(Actor.t(), op(), integer(), String.t() | nil) ::
          {:ok, Facts.attribute_result()} | {:error, term()}
  def decide(%Actor{} = actor, op, attribution_id, reason \\ nil)
      when op in [:accept, :decline, :reopen] and is_integer(attribution_id) do
    Audit.transaction(actor, "import.taxonomic_decision", fn ->
      with %Attribution{} = attribution <- Facts.get_attribution(attribution_id),
           {:ok, key} <- replay_key(op, attribution),
           :ok <- TaxonomyQueue.settle(actor, op, attribution, reason),
           {:ok, result} <- apply_op(actor, op, attribution_id, reason) do
        payload = if op == :decline, do: %{"reason" => String.trim(reason)}, else: %{}
        ReplayLog.append!(:taxonomic_decision, key, payload)
        :ok = TaxonomyQueue.asked_again(op, attribution_id)
        result
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp apply_op(actor, :accept, id, _reason), do: Facts.accept(actor, id)
  defp apply_op(actor, :decline, id, reason), do: Facts.decline(actor, id, reason || "")
  defp apply_op(actor, :reopen, id, _reason), do: Facts.reopen(actor, id)

  defp replay_key(op, %Attribution{fact_id: fact_id, source_id: source_id}) do
    case Taxa.act_fact(fact_id) do
      {kind, key} ->
        {:ok,
         %{
           "op" => Atom.to_string(op),
           "source" => StableRef.source(source_id),
           "kind" => Atom.to_string(kind),
           "fact" => encode(kind, key)
         }}

      nil ->
        {:error, :not_taxonomic}
    end
  end

  # -- stable keys -----------------------------------------------------------------

  @doc """
  An act's natural key (as `Gallformers.Taxa.find_act_fact/2` takes it)
  with its taxa as stable references, for a replay log entry's `"fact"`.
  """
  @spec encode_key(Taxa.act_kind(), map()) :: map()
  def encode_key(kind, key), do: encode(kind, key)

  @doc "The natural key `encode_key/2` gave, its taxa found by their stable references."
  @spec decode_key(Taxa.act_kind(), map()) :: {:ok, map()} | {:error, term()}
  def decode_key(kind, fact), do: decode(kind, fact)

  @doc "The act kind a replay log entry names (`\"placement\"`), or `:error`."
  @spec kind(String.t()) :: {:ok, Taxa.act_kind()} | :error
  def kind(name), do: Map.fetch(@kinds, name)

  defp encode(:placement, key),
    do: %{"taxon" => ref(key.taxon_id), "parent" => ref(key.parent_id)}

  defp encode(:name, key) do
    %{"taxon" => ref(key.taxon_id), "name" => key.name, "rank" => to_string(key.rank)}
    |> Map.merge(for f <- [:sensu, :authorship], v = Map.get(key, f), into: %{}, do: {"#{f}", v})
  end

  defp encode(:synonymy, key),
    do: %{"name" => key.name, "accepted" => ref(key.accepted_taxon_id)}

  defp encode(:split, key),
    do: %{"taxon" => ref(key.taxon_id), "into" => Enum.map(key.into_taxon_ids, &ref/1)}

  defp encode(:common_name, key),
    do: %{"taxon" => ref(key.taxon_id), "common_name" => key.common_name}

  defp ref(nil), do: nil
  defp ref(taxon_id), do: StableRef.taxon(taxon_id)

  defp decode(:placement, fact) do
    with {:ok, taxon_id} <- resolve(fact["taxon"]),
         {:ok, parent_id} <- resolve(fact["parent"]),
         do: {:ok, %{taxon_id: taxon_id, parent_id: parent_id}}
  end

  defp decode(:name, fact) do
    with {:ok, taxon_id} <- resolve(fact["taxon"]) do
      {:ok,
       %{
         taxon_id: taxon_id,
         name: fact["name"],
         rank: fact["rank"],
         sensu: fact["sensu"],
         authorship: fact["authorship"]
       }}
    end
  end

  defp decode(:synonymy, fact) do
    with {:ok, accepted_id} <- resolve(fact["accepted"]),
         do: {:ok, %{name: fact["name"], accepted_taxon_id: accepted_id}}
  end

  defp decode(:split, fact) do
    with {:ok, taxon_id} <- resolve(fact["taxon"]),
         {:ok, into} <- resolve_all(fact["into"]),
         do: {:ok, %{taxon_id: taxon_id, into_taxon_ids: into}}
  end

  defp decode(:common_name, fact) do
    with {:ok, taxon_id} <- resolve(fact["taxon"]),
         do: {:ok, %{taxon_id: taxon_id, common_name: fact["common_name"]}}
  end

  defp resolve(nil), do: {:ok, nil}
  defp resolve(ref), do: StableRef.resolve_current_taxon(ref)

  defp resolve_all(refs) do
    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, ids} ->
      case resolve(ref) do
        {:ok, id} -> {:cont, {:ok, ids ++ [id]}}
        error -> {:halt, error}
      end
    end)
  end

  # -- replay ----------------------------------------------------------------------

  @ops %{"accept" => :accept, "decline" => :decline, "reopen" => :reopen}

  @doc """
  Replays a logged decision: finds the statement by its stable key and
  makes the decision again, unless it is in that state already.
  `{:error, {:statement_not_found, key}}` when there is no such statement.
  """
  @spec replay(Actor.t(), map(), map()) :: :ok | {:error, term()}
  def replay(%Actor{} = actor, %{"op" => op, "kind" => kind} = key, payload) do
    with {:ok, op} <- Map.fetch(@ops, op) |> or_error({:unknown_op, op}),
         {:ok, kind} <- Map.fetch(@kinds, kind) |> or_error({:unknown_kind, kind}),
         {:ok, attribution} <- find(kind, key) do
      if done?(op, attribution, payload["reason"]) do
        settle_only(actor, op, attribution, payload["reason"])
      else
        case decide(actor, op, attribution.id, payload["reason"]) do
          {:ok, _result} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  # A decision made already: its questions are settled all the same.
  defp settle_only(actor, op, attribution, reason) do
    case Audit.transaction(actor, "import.taxonomic_decision", fn ->
           TaxonomyQueue.settle(actor, op, attribution, reason)
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp or_error({:ok, value}, _error), do: {:ok, value}
  defp or_error(:error, error), do: {:error, error}

  defp find(kind, %{"source" => source, "fact" => fact} = key) do
    not_found = {:error, {:statement_not_found, key}}

    with {:ok, source_id} <- StableRef.resolve_source(source),
         {:ok, natural_key} <- decode(kind, fact),
         {:ok, fact_id} when is_integer(fact_id) <- Taxa.find_act_fact(kind, natural_key),
         %Attribution{} = attribution <- Facts.get_attribution(fact_id, source_id) do
      {:ok, attribution}
    else
      _ -> not_found
    end
  end

  defp done?(:accept, %Attribution{accepted_at: at}, _reason), do: at != nil

  defp done?(:decline, %Attribution{declined_at: at, decline_reason: was}, reason),
    do: at != nil and was == reason

  defp done?(:reopen, %Attribution{accepted_at: nil, declined_at: nil}, _reason), do: true
  defp done?(:reopen, _attribution, _reason), do: false
end
