defmodule Gallformers.Catalog.ReadModels.GallIndexWorker do
  @moduledoc """
  Refreshes one Gall's row of the ID tool's lookup table
  (`Gallformers.Catalog.ReadModels.GallIndex.refresh/1`), on the `catalog`
  queue. Unique per Gall while waiting: changes to a Gall's Facts or taxa
  queue one refresh, which reads the Gall as it is when it runs. A refresh
  already running is no reason to skip another (it may have read the Gall
  before the newest change), so executing jobs are not part of uniqueness.
  """
  use Oban.Worker,
    queue: :catalog,
    max_attempts: 5,
    unique: [
      keys: [:gall_id],
      period: :infinity,
      states: [:available, :scheduled, :retryable]
    ]

  alias Gallformers.Catalog.ReadModels.GallIndex

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"gall_id" => gall_id}}) when is_integer(gall_id),
    do: GallIndex.refresh([gall_id])
end
