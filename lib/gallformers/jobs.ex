defmodule Gallformers.Jobs do
  @moduledoc """
  Whether background jobs can be queued. A release task (the cutover's
  catalog migration and replay, `Gallformers.Release`) runs without Oban;
  callers that queue a job then do its work at once instead.
  """
  use Boundary, deps: [], exports: :all

  @doc """
  Whether the Oban instance `name` is running. False, without raising,
  where Oban isn't started at all (its `registry` doesn't exist), which
  is where `Oban.whereis/1` would raise.
  """
  @spec running?(Oban.name(), atom()) :: boolean()
  def running?(name, registry \\ Oban.Registry) do
    Process.whereis(registry) != nil and Oban.whereis(name) != nil
  end
end
