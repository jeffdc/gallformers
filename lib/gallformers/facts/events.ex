defmodule Gallformers.Facts.Events do
  @moduledoc """
  "Facts changed" events, synchronous, with the dependency inverted (as
  `Gallformers.Taxa.Events`): `Gallformers.Facts` never references the
  contexts whose read models are built from Facts (e.g. `Catalog`).

  After an attribution write stores the standings it recomputed, Facts calls
  every registered listener with the IDs of the Facts whose standing
  changed — a Fact that became current, or stopped being current (withdrawn,
  superseded, retracted, unsupported) — inside the write's transaction. The
  read models depend only on which Facts are current, so a write that
  changes no standing (a restated or added attribution of a Fact already
  current) is no event; a Fact's typed details never change once made.

  A listener returns `:ok`, or `{:error, reason}` when its side can't
  accept the change (the tree refusing a placement that would form a
  cycle, `Gallformers.Taxa.Sync`): the write then rolls back, returning
  `{:error, {:rejected, listener, reason}}`, and later listeners are not
  called. Anything else (or a raise) also rolls the write back. Only
  cheap reactions belong here;
  expensive derived work (read-model refresh) is enqueued to run
  asynchronously — an Oban job enqueued inside the transaction runs after it
  commits, and never if it rolls back.

  ## Registration

      config :gallformers, Gallformers.Facts.Events,
        listeners: [Gallformers.Catalog.FactListener]
  """

  alias Gallformers.Repo

  @doc "Reacts to Facts whose standing changed, inside the change's transaction."
  @callback facts_changed([integer()]) :: :ok | {:error, term()}

  @type rejection :: {:rejected, module(), term()}

  @doc "The registered listeners, in call order."
  @spec listeners() :: [module()]
  def listeners do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:listeners, [])
  end

  @doc """
  Calls each listener with `fact_ids`. Must be called inside the
  transaction making the change: on a listener's error it rolls that
  transaction back with `{:rejected, listener, reason}`.
  """
  @spec dispatch([integer()]) :: :ok
  def dispatch(fact_ids) when is_list(fact_ids) do
    unless Repo.in_transaction?() do
      raise ArgumentError, "facts changed events are dispatched inside the change's transaction"
    end

    Enum.each(listeners(), fn listener ->
      case listener.facts_changed(fact_ids) do
        :ok ->
          :ok

        {:error, reason} ->
          Repo.rollback({:rejected, listener, reason})

        other ->
          raise ArgumentError,
                "#{inspect(listener)}.facts_changed/1 must return :ok or {:error, reason}, " <>
                  "got: #{inspect(other)}"
      end
    end)
  end
end
