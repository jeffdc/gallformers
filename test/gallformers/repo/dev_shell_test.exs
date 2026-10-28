defmodule Gallformers.Repo.DevShellTest do
  @moduledoc """
  Development refuses to connect without the dev shell's Postgres settings,
  instead of silently falling back to whatever listens on localhost:5432
  (2026-10-28: Jeff's server read an empty Postgres.app copy while every
  write had gone to the dev-shell Postgres on 54317).
  """
  use ExUnit.Case, async: true

  alias Gallformers.Repo.DevShell

  test "a repo that requires the dev shell refuses to start without PGPORT" do
    for pgport <- [nil, ""] do
      error =
        assert_raise RuntimeError, fn ->
          DevShell.check!([database: "gallformers_dev", require_dev_shell: true], pgport)
        end

      assert error.message =~ "PGPORT is not set"
      assert error.message =~ "direnv allow"
    end
  end

  test "with PGPORT set it starts, and the option is not passed on" do
    config = DevShell.check!([database: "gallformers_dev", require_dev_shell: true], "54317")

    assert config == [database: "gallformers_dev"]
  end

  test "a repo that does not require it (test, prod) is left alone" do
    assert DevShell.check!([database: "gallformers_test"], nil) == [database: "gallformers_test"]
  end
end
