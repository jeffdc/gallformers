defmodule Gallformers.Import.ReplayLog do
  @moduledoc """
  Appends to the replay log (`Gallformers.Import.ReplayEntry`, `9449` §5,
  Task 14). Called inside the audited transaction of the step it records,
  so an entry exists exactly when its change does. Keys and payloads hold
  stable references only (`Gallformers.Import.StableRef`), never database
  IDs.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Import.ReplayEntry
  alias Gallformers.Repo

  @doc "Appends an entry; raises (rolling the step back) if it cannot be written."
  @spec append!(ReplayEntry.kind(), map(), map()) :: ReplayEntry.t()
  def append!(kind, key, payload \\ %{}) do
    %ReplayEntry{}
    |> ReplayEntry.changeset(%{kind: kind, key: key, payload: payload})
    |> Repo.insert!()
  end

  @doc "Every entry, in order."
  @spec list() :: [ReplayEntry.t()]
  def list, do: Repo.all(from(e in ReplayEntry, order_by: e.id))
end
