defmodule Gallformers.Taxa.Events do
  @moduledoc """
  "Taxon changed" events, synchronous, with the dependency inverted (`8567`
  rule 6).

  Taxa calls every registered listener inside the transaction that changes
  a taxon, after the change is written, in registration order. A listener
  returns `:ok`, or `{:error, reason}` when its side can't accept the change
  (e.g. a derived Gall name would collide): the taxonomy change then fails
  and rolls back, returning `{:error, {:rejected, listener, reason}}`, and
  later listeners are not called. A listener that raises, or returns
  anything else, also rolls the change back.

  ## Registration

  Listeners are application wiring, so Taxa never references the contexts
  that listen (e.g. `Catalog`):

      config :gallformers, Gallformers.Taxa.Events,
        listeners: [Gallformers.Catalog.TaxonListener]

  Only cheap, consistency-keeping reactions belong in a listener; expensive
  derived work (search indexing, read-model refresh) is enqueued to run
  asynchronously.
  """

  alias Gallformers.Repo
  alias Gallformers.Taxa.Event

  @doc "Reacts to a taxon change, inside the change's transaction."
  @callback taxon_changed(Event.t()) :: :ok | {:error, term()}

  @type rejection :: {:rejected, module(), term()}

  @doc "The registered listeners, in call order."
  @spec listeners() :: [module()]
  def listeners do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:listeners, [])
  end

  @doc """
  Calls each listener with `event`. Must be called inside the transaction
  making the change: on a listener's error it rolls that transaction back
  with `{:rejected, listener, reason}`.
  """
  @spec dispatch(Event.t()) :: :ok
  def dispatch(%Event{} = event) do
    unless Repo.in_transaction?() do
      raise ArgumentError, "taxon change events are dispatched inside the change's transaction"
    end

    Enum.each(listeners(), fn listener ->
      case listener.taxon_changed(event) do
        :ok ->
          :ok

        {:error, reason} ->
          Repo.rollback({:rejected, listener, reason})

        other ->
          raise ArgumentError,
                "#{inspect(listener)}.taxon_changed/1 must return :ok or {:error, reason}, " <>
                  "got: #{inspect(other)}"
      end
    end)
  end
end
