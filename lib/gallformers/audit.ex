defmodule Gallformers.Audit do
  @moduledoc """
  Who changed what, and when, for the audited tables (matter `ede2`).

  Capture is done by Carbonite's PostgreSQL triggers, installed in the
  `carbonite_default` schema. A tracked table's trigger records every inserted,
  updated and deleted row (with the replaced values on updates) against the
  audit transaction of the current database transaction. A write to a tracked
  table with no audit transaction is rejected by the database, and the
  transaction's metadata must name an actor and an operation; there is no
  default actor.

  Every write to a tracked table therefore goes through `transaction/3` or
  `run_multi/3`, which record the actor and operation inside the database
  transaction before the first write. Tables are tracked by calling
  `Gallformers.Audit.Migration.track_table/2` in the migration that creates
  them.

  ## One actor per database transaction

  The audit trail holds one record per database transaction. A nested or
  later audited call inside the same database transaction joins it: with the
  same actor the first operation name stands; with a different actor it
  raises `Gallformers.Audit.ConflictError` rather than misattributing the
  changes. In tests the whole test runs in one sandbox transaction, so a test
  uses one actor throughout (see `Gallformers.DataCase.test_actor/0`).
  """
  use Boundary,
    deps: [Gallformers.Repo],
    exports: [Actor, ChangeLog, ConflictError, Migration]

  alias Ecto.Multi
  alias Gallformers.Audit.Actor
  alias Gallformers.Audit.ConflictError
  alias Gallformers.Repo

  @doc """
  Runs `fun` in a database transaction attributed to `actor` and `operation`.

  The audit metadata is written first, inside the transaction. Returns what
  `Repo.transaction/2` returns: `{:ok, result}`, or `{:error, value}` when
  `fun` calls `Repo.rollback(value)`. A rolled-back transaction leaves no
  audit record.

  `operation` names what is being done, e.g. `"taxa.place"`.
  """
  @spec transaction(Actor.t(), String.t(), (-> result)) :: {:ok, result} | {:error, any()}
        when result: var
  def transaction(%Actor{} = actor, operation, fun) when is_function(fun, 0) do
    meta = meta!(actor, operation)

    Repo.transaction(fn ->
      record!(Repo, meta)
      fun.()
    end)
  end

  @doc """
  Runs `multi` in a database transaction attributed to `actor` and `operation`.

  The audit metadata is written before the multi's first step. Returns what
  `Repo.transaction/1` returns for a multi: `{:ok, changes}`, or
  `{:error, failed_step, value, changes_so_far}` with nothing kept.
  """
  @spec run_multi(Multi.t(), Actor.t(), String.t()) ::
          {:ok, map()} | {:error, Multi.name(), any(), map()}
  def run_multi(%Multi{} = multi, %Actor{} = actor, operation) do
    meta = meta!(actor, operation)

    result =
      Repo.transaction(fn ->
        record!(Repo, meta)

        case Repo.transaction(multi) do
          {:ok, changes} -> changes
          {:error, step, value, changes} -> Repo.rollback({step, value, changes})
        end
      end)

    case result do
      {:ok, changes} -> {:ok, changes}
      {:error, {step, value, changes}} -> {:error, step, value, changes}
    end
  end

  @doc """
  The actor the current database transaction is audited as, or `:error`
  outside an audited transaction. For code called back inside another
  context's audited write (an event listener) that writes in turn, as the
  same actor.
  """
  @spec current_actor() :: {:ok, Actor.t()} | :error
  def current_actor do
    import Ecto.Query, only: [from: 2]

    if Repo.in_transaction?() do
      from(t in Carbonite.Transaction,
        where: t.xact_id == fragment("pg_current_xact_id()"),
        select: t.meta
      )
      |> Ecto.Query.put_query_prefix(Carbonite.default_prefix())
      |> Repo.one()
      |> case do
        %{"actor" => actor} -> {:ok, Actor.from_meta(actor)}
        _ -> :error
      end
    else
      :error
    end
  end

  defp meta!(actor, operation) when is_binary(operation) do
    case String.trim(operation) do
      "" -> raise ArgumentError, "an audited operation needs a name"
      trimmed -> %{"actor" => Actor.to_meta(actor), "operation" => trimmed}
    end
  end

  defp meta!(_actor, operation) do
    raise ArgumentError, "an audited operation needs a name, got: #{inspect(operation)}"
  end

  # Carbonite keeps the first metadata written in a database transaction and
  # ignores later inserts, so compare what is recorded with what was asked.
  defp record!(repo, meta) do
    {:ok, transaction} = Carbonite.insert_transaction(repo, %{meta: meta})
    recorded = transaction.meta["actor"]

    if recorded != meta["actor"] do
      raise ConflictError, recorded: recorded, requested: meta["actor"]
    end

    transaction.id
  end
end
