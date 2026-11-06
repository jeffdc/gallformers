defmodule Gallformers.TestDbNamesTest do
  @moduledoc """
  The test databases' names (`config/test_db_names.exs`): one pair per
  checkout, so tests in a git worktree never share a database with the main
  checkout's (or another worktree's). The main checkout and CI keep the
  plain names.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Repo

  defp names(root) do
    {names, _binding} = Code.eval_file("config/test_db_names.exs")
    names.(root)
  end

  test "the main checkout, and CI: the plain names" do
    assert names("/Users/jeff/dev/gallformers") == %{
             app: "gallformers_test",
             wcvp: "wcvp_test"
           }

    assert names("/home/runner/work/gallformers/gallformers") == %{
             app: "gallformers_test",
             wcvp: "wcvp_test"
           }
  end

  test "a worktree: the plain names with the worktree's name" do
    assert names("/Users/jeff/dev/gallformers/.worktrees/design-system") == %{
             app: "gallformers_test_design_system",
             wcvp: "wcvp_test_design_system"
           }
  end

  test "a worktree name is made safe for a database name" do
    assert names("/x/.worktrees/Fix.Range-2").app == "gallformers_test_fix_range_2"
  end

  test "the running tests use this checkout's names" do
    %{app: app, wcvp: wcvp} = names(File.cwd!())

    assert Repo.config()[:database] == app
    assert Repo.WCVP.config()[:database] == wcvp
  end
end
