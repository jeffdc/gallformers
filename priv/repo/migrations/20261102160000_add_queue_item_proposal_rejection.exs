defmodule Gallformers.Repo.Migrations.AddQueueItemProposalRejection do
  @moduledoc """
  A curator can reject an open queue item's proposal (`6611` Task 3): the
  item stays open, without its proposal, and accepting every proposal of a
  section leaves it out (`Gallformers.Import.reject_proposal/2`). Who
  rejected it and when; both cleared when it is restored or the proposal
  changes.

  Not in the replay log: a rejection changes no data, and the decision a
  curator makes afterwards is logged on its own.
  """
  use Ecto.Migration

  def change do
    alter table(:queue_items) do
      add :proposal_rejected_at, :utc_datetime
      add :proposal_rejected_by_name, :text
    end
  end
end
