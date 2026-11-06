defmodule Gallformers.Import.Worker do
  @moduledoc """
  The import job (`9449` §5): takes one package a step on with
  `Gallformers.Import.advance_package/2` — a delivered package is validated
  and resolved, then waits for an admin; once approved
  (`Gallformers.Import.approve_package/2` enqueues it again) its batches
  are applied.

  Runs on the `import` queue, one job at a time, and unique per package
  while waiting: enqueueing again replaces the waiting job's actor. The
  actor (who delivered or approved the package) travels in the args, so
  the audit trail names them. After each step the package's listeners are
  told (`Gallformers.Import.Events`).
  """
  use Oban.Worker,
    queue: :import,
    max_attempts: 3,
    unique: [
      keys: [:package_id],
      period: :infinity,
      states: [:available, :scheduled, :retryable]
    ]

  alias Gallformers.Audit.Actor
  alias Gallformers.Import
  alias Gallformers.Import.Events

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"package_id" => package_id, "actor" => actor}}) do
    case Import.advance_package(actor(actor), package_id) do
      {:ok, package} -> Events.dispatch(package)
      {:error, reason} -> {:error, reason}
    end
  end

  defp actor(%{"type" => "user", "id" => id, "name" => name}), do: Actor.user(id, name)
  defp actor(%{"type" => "system", "name" => name}), do: Actor.system(name)
end
