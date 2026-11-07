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

  @collecting :gallformers_replay_log_collecting

  @doc "Appends an entry; raises (rolling the step back) if it cannot be written."
  @spec append!(ReplayEntry.kind(), map(), map()) :: ReplayEntry.t()
  def append!(kind, key, payload \\ %{}) do
    entry =
      %ReplayEntry{}
      |> ReplayEntry.changeset(%{kind: kind, key: key, payload: payload})
      |> Repo.insert!()

    case Process.get(@collecting) do
      nil -> :ok
      collected -> Process.put(@collecting, [entry | collected])
    end

    entry
  end

  @doc """
  Runs `fun` and returns its result with the entries it appended, in order
  (written as ever). A decision keeps them, so that Undo knows what it
  changed (`Gallformers.Import.Undo`). A nested call sees its own, and
  passes them on to the enclosing one.
  """
  @spec collect((-> result)) :: {result, [ReplayEntry.t()]} when result: var
  def collect(fun) when is_function(fun, 0) do
    outer = Process.get(@collecting)
    Process.put(@collecting, [])

    try do
      result = fun.()
      {result, Enum.reverse(Process.get(@collecting))}
    after
      collected = Process.get(@collecting)

      case outer do
        nil -> Process.delete(@collecting)
        outer -> Process.put(@collecting, collected ++ outer)
      end
    end
  end

  @doc "Every entry, in order."
  @spec list() :: [ReplayEntry.t()]
  def list, do: Repo.all(from(e in ReplayEntry, order_by: e.id))
end
