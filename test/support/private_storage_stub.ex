defmodule Gallformers.Storage.PrivateStub do
  @moduledoc """
  In-memory stand-in for the private bucket in tests (`config/test.exs`).

  Objects are kept per test: each belongs to the process that stored it, or
  to the test process that started it (through `$callers`, as for Tasks), so
  async tests never see each other's objects. `start/0` is called once from
  `test/test_helper.exs`.
  """
  @behaviour Gallformers.Storage.Private

  @table __MODULE__

  @doc "Starts the process owning the object table for the whole test run."
  def start do
    {:ok, _pid} =
      Agent.start(fn -> :ets.new(@table, [:named_table, :public, :set]) end, name: __MODULE__)

    :ok
  end

  @impl true
  def put_object(bucket, key, data, _opts) do
    true = :ets.insert(@table, {{owner(), bucket, key}, data})
    :ok
  end

  @impl true
  def get_object(bucket, key) do
    case :ets.lookup(@table, {owner(), bucket, key}) do
      [{_key, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  defp owner, do: List.last(Process.get(:"$callers", [])) || self()
end
