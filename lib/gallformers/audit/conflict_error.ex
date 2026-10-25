defmodule Gallformers.Audit.ConflictError do
  @moduledoc """
  Raised when an audited operation would join a database transaction that
  already records a different actor.

  The audit trail records one actor per database transaction, so a second
  actor's changes would be silently attributed to the first. Run each actor's
  work in its own transaction instead.
  """
  defexception [:recorded, :requested]

  @impl true
  def message(%{recorded: recorded, requested: requested}) do
    "this database transaction is already audited as #{inspect(recorded)}; " <>
      "it cannot also be attributed to #{inspect(requested)}"
  end
end
