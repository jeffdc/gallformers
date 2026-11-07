defmodule Mix.Tasks.Gallformers.Facts.RecomputeContestsTest do
  @moduledoc """
  `mix gallformers.facts.recompute_contests` (matter `f923`): recomputes
  the standings of the Facts contesting a name and prints how many changed.
  What it recomputes is `Gallformers.Facts.recompute_contests/1`'s
  (`Gallformers.Facts.ContestTest`, `Gallformers.Taxa.SyncTest`).
  """
  use Gallformers.DataCase, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Gallformers.Facts.RecomputeContests

  # The task's own actor is "recompute_contests"; a test's sandbox is audited as one actor.
  test "prints the summary, and nothing changes on the seeded catalog" do
    output = capture_io(fn -> RecomputeContests.recompute(test_actor()) end)

    assert output =~ "Contests recomputed: "
    assert output =~ "Facts whose standing changed: 0"
  end
end
