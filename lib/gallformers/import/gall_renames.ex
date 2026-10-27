defmodule Gallformers.Import.GallRenames do
  @moduledoc """
  Rename proposals (`86e7` §3): a taxonomy change that would change a
  Gall's derived name — its Inducer renamed or moved, an "Unknown (Family)"
  Gall's family changing, its Host qualifier renamed — queues a
  `:gall_rename` item in the admin queue (`Gallformers.Import.QueueItem`)
  instead of renaming the Gall. The Gall keeps its name until a curator
  decides.

  ## Proposals

  This module is a "taxon changed" listener (`Gallformers.Taxa.Events`,
  registered after `Gallformers.Catalog.TaxonListener`), so it runs inside
  the taxonomy change's transaction. The Catalog says which Galls the
  change touches and the name their parts give now
  (`Gallformers.Catalog.gall_name_changes/1`: never a Gall with a name
  override or whose parts give no name). For each whose name would change,
  the Gall's one open proposal is created or updated with `%{"gall_id",
  "from", "to", "collision"}`; for each whose name would not (a change
  undone), its open proposal is withdrawn. A name that is already another
  Gall's (`collision`) is only flagged: a name never fails the taxonomy
  change.

  ## Decisions

  Through `Gallformers.Import.decide_queue_item/3`, `%{"accept" => true}`
  or `%{"reject" => true}`:

    * **accept** — the Gall takes the name its parts give at the decision
      (if that is not the proposed one, the item's proposal and reason say
      so), and the name it showed becomes a `former_label` alias of the
      Gallformers Source (`Gallformers.Catalog.accept_gall_rename/2`).
      Refused while the name is another Gall's, ignoring case.
    * **reject** — the name shown is kept as the Gall's name override
      (`Gallformers.Catalog.update_name_parts/3`), so later taxonomy
      changes propose nothing for it.

  Neither touches the Gallformers code. A decision is recorded in the
  replay log as a `:queue_decision` with the Gall's stable reference and
  the name it was decided for (`replay_key/1`); replaying the taxonomy
  change makes the proposal again, and replay decides it (`find/2`).
  """
  @behaviour Gallformers.Taxa.Events

  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.StableRef
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Event

  # -- proposals ---------------------------------------------------------------

  @impl true
  def taxon_changed(%Event{type: type} = event) when type in [:move, :rename] do
    {unchanged, changed} =
      event |> Catalog.gall_name_changes() |> Enum.split_with(&(&1.from == &1.to))

    withdraw(Enum.map(unchanged, & &1.gall_id))
    reason = reason(event)
    Enum.each(changed, &propose(&1, reason))
  end

  def taxon_changed(%Event{}), do: :ok

  defp withdraw([]), do: :ok

  defp withdraw(gall_ids) do
    ids = Enum.map(gall_ids, &Integer.to_string/1)

    Repo.delete_all(from(q in open(), where: fragment("(?->>'gall_id')", q.subject) in ^ids))

    :ok
  end

  defp propose(%{gall_id: gall_id} = change, reason) do
    proposal = %{
      "gall_id" => gall_id,
      "from" => change.from,
      "to" => change.to,
      "collision" => change.collision
    }

    case Repo.one(from(q in open(gall_id), lock: "FOR UPDATE")) do
      nil ->
        %QueueItem{}
        |> QueueItem.create_changeset(%{
          kind: :gall_rename,
          subject: %{"gall_id" => gall_id},
          proposal: proposal,
          reason: reason
        })
        |> Repo.insert!()

      item ->
        item |> Changeset.change(proposal: proposal, reason: reason) |> Repo.update!()
    end
  end

  defp reason(%Event{type: :rename, old_name: old, new_name: new}),
    do: "#{old} was renamed #{new}."

  defp reason(%Event{type: :move, taxon_id: taxon_id, to_parent_id: nil}),
    do: "#{Taxa.accepted_name(taxon_id)} was made a root of the tree."

  defp reason(%Event{type: :move, taxon_id: taxon_id, to_parent_id: parent_id}),
    do: "#{Taxa.accepted_name(taxon_id)} was moved under #{Taxa.accepted_name(parent_id)}."

  defp open, do: from(q in QueueItem, where: q.kind == :gall_rename and q.status == :open)

  defp open(gall_id),
    do: from(q in open(), where: fragment("(?->>'gall_id')", q.subject) == ^"#{gall_id}")

  @doc "Rename proposals, oldest first. Options: `:status` (default `:open`; `:all` for every one)."
  @spec list(keyword()) :: [QueueItem.t()]
  def list(opts \\ []) do
    query = from(q in QueueItem, where: q.kind == :gall_rename, order_by: q.id)

    case Keyword.get(opts, :status, :open) do
      :all -> Repo.all(query)
      status -> Repo.all(from(q in query, where: q.status == ^status))
    end
  end

  # -- decisions ---------------------------------------------------------------

  @doc """
  Honours a decided proposal, inside `Gallformers.Import.decide_queue_item/3`'s
  transaction: renames the Gall (accept) or keeps its name as an override
  (reject). Returns the item, its proposal updated if the name applied is
  not the one proposed; a refusal rolls the decision back with a changeset
  (errors on `:decision`).
  """
  @spec honour(Actor.t(), QueueItem.t()) :: QueueItem.t()
  def honour(%Actor{} = actor, %QueueItem{kind: :gall_rename, decision: decision} = item) do
    gall_id = item.proposal["gall_id"]

    case decision do
      %{"accept" => true} ->
        case Catalog.accept_gall_rename(actor, gall_id) do
          {:ok, %{to: to}} -> applied(item, to)
          {:error, reason} -> Repo.rollback(refusal(item, reason))
        end

      %{"reject" => true} ->
        gall = Catalog.get_gall!(gall_id)

        case Catalog.update_name_parts(actor, gall, %{name_override: Gall.display_name(gall)}) do
          {:ok, _gall} -> item
          {:error, changeset} -> Repo.rollback(refusal(item, changeset))
        end
    end
  end

  defp applied(%QueueItem{proposal: %{"to" => to}} = item, to), do: item

  defp applied(%QueueItem{proposal: proposal} = item, to) do
    item
    |> Changeset.change(
      proposal: Map.put(proposal, "to", to),
      reason:
        "#{item.reason} Renamed #{to}: the name its parts gave at the decision, " <>
          "not #{proposal["to"]} as proposed."
    )
    |> Repo.update!()
  end

  defp refusal(item, reason) do
    item |> Changeset.change() |> Changeset.add_error(:decision, refusal_message(item, reason))
  end

  defp refusal_message(item, :collision) do
    "can't be accepted: #{item.proposal["to"]} is already the name of another Gall " <>
      "(names are unique, ignoring case); rename that Gall first, or reject"
  end

  defp refusal_message(_item, :overridden),
    do: "can't be accepted: the Gall has a name override (reject keeps it)"

  defp refusal_message(_item, {:not_derivable, reason}),
    do: "can't be accepted: the Gall's name parts give no name (#{reason})"

  defp refusal_message(_item, :no_gallformers_source),
    do: "can't be accepted: there is no Gallformers Source to state the former name"

  defp refusal_message(_item, %Changeset{} = changeset) do
    changeset
    |> Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> then(&"can't be applied: #{&1}")
  end

  # -- the replay log ----------------------------------------------------------

  @doc """
  A decided proposal's replay-log key: the `:queue_decision` key fields
  (no package, batch or statement) with the Gall's stable reference and the
  name it was decided for.
  """
  @spec replay_key(QueueItem.t()) :: map()
  def replay_key(%QueueItem{kind: :gall_rename, proposal: proposal}) do
    %{
      "package" => nil,
      "batch_id" => nil,
      "kind" => "gall_rename",
      "statement_ref" => nil,
      "gall" => StableRef.gall(proposal["gall_id"]),
      "to" => proposal["to"]
    }
  end

  @doc """
  The proposal for Gall `gall_id` to name `to` that replay decides: the
  open one, else the latest decided one (already replayed), else nil.
  """
  @spec find(integer(), String.t()) :: QueueItem.t() | nil
  def find(gall_id, to) when is_integer(gall_id) and is_binary(to) do
    items =
      Repo.all(
        from(q in QueueItem,
          where:
            q.kind == :gall_rename and fragment("(?->>'gall_id')", q.subject) == ^"#{gall_id}" and
              fragment("(?->>'to')", q.proposal) == ^to,
          order_by: [desc: q.id]
        )
      )

    Enum.find(items, &(&1.status == :open)) || List.first(items)
  end
end
