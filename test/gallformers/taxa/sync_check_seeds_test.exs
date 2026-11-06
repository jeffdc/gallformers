defmodule Gallformers.Taxa.SyncCheckSeedsTest do
  @moduledoc """
  The test database as `make test-db` builds it (the seeds converted by the
  catalog migration, which writes today's non-plant tree as legacy
  statements, `f923` Task 3): the tree and the Facts agree, so
  `Gallformers.Taxa.Sync.check/0` finds nothing (Task 5).
  """
  use Gallformers.DataCase, async: true

  # Reading the converted seeds is what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  alias Gallformers.Taxa.Sync

  test "the built test database's tree follows its Facts" do
    assert Sync.check() == []
  end
end
