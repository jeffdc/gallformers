defmodule Gallformers.Storage.PrivateTest do
  @moduledoc """
  The private bucket's get/put. Tests run against the in-memory stub
  configured in `config/test.exs`, never real S3.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Storage.Private
  alias Gallformers.Storage.PrivateStub

  test "names the private bucket" do
    assert Private.bucket() == "gallformers-private"
  end

  test "tests use the in-memory stub" do
    assert Private.adapter() == PrivateStub
  end

  test "an object put can be got back" do
    assert :ok = Private.put("sources/1/abc.json", ~s({"a": 1}), content_type: "application/json")
    assert Private.get("sources/1/abc.json") == {:ok, ~s({"a": 1})}
  end

  test "a missing object is not found" do
    assert Private.get("sources/1/missing.json") == {:error, :not_found}
  end

  test "objects stored by one test process are not visible to another" do
    :ok = Private.put("sources/2/mine.json", "mine")

    other = Task.async(fn -> Private.get("sources/2/mine.json") end)
    assert Task.await(other) == {:ok, "mine"}

    unrelated = spawn_get("sources/2/mine.json")
    assert unrelated == {:error, :not_found}
  end

  defp spawn_get(key) do
    parent = self()
    spawn(fn -> send(parent, {:got, Private.get(key)}) end)
    assert_receive {:got, result}
    result
  end
end
