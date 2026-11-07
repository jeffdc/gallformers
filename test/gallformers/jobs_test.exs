defmodule Gallformers.JobsTest do
  @moduledoc """
  Whether an Oban instance is running, safely where Oban isn't started at
  all (a release task such as the cutover replay).
  """
  use ExUnit.Case, async: true

  alias Gallformers.Jobs

  test "the app's Oban instance is running in tests" do
    assert Jobs.running?(Oban)
  end

  test "an instance that isn't running is not" do
    refute Jobs.running?(:no_such_oban)
  end

  test "with Oban not started at all, nothing is running (no raise)" do
    refute Jobs.running?(Oban, :no_such_registry)
  end
end
