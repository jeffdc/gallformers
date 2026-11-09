defmodule Gallformers.Guardrails.PrePushTest do
  @moduledoc """
  The push guard (matter `c800`): the git pre-push hook `dev/githooks/pre-push`,
  installed by `dev/githooks/install.sh`, blocks force pushes and pushes to
  main or master from anyone (any agent, any harness, a terminal) unless
  `GALLFORMERS_PUSH_MAIN=1` is set for that push. It holds on a branch
  without the versioned hook too, through the copy the install keeps.

  Each test pushes for real to a bare repository, with global and system git
  config shut out and `CLAUDECODE` unset, so nothing depends on the harness.
  """
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @hook Path.expand("dev/githooks/pre-push")
  @install Path.expand("dev/githooks/install.sh")

  @env [
    {"GIT_CONFIG_GLOBAL", "/dev/null"},
    {"GIT_CONFIG_NOSYSTEM", "1"},
    {"GIT_DIR", nil},
    {"GIT_INDEX_FILE", nil},
    {"GIT_WORK_TREE", nil},
    {"CLAUDECODE", nil},
    {"GALLFORMERS_PUSH_MAIN", nil},
    {"GIT_AUTHOR_NAME", "Test"},
    {"GIT_AUTHOR_EMAIL", "test@example.com"},
    {"GIT_COMMITTER_NAME", "Test"},
    {"GIT_COMMITTER_EMAIL", "test@example.com"}
  ]

  setup %{tmp_dir: tmp} do
    remote = Path.join(tmp, "remote.git")
    dir = Path.join(tmp, "work")
    File.mkdir_p!(dir)

    git!(tmp, ["init", "-q", "--bare", remote])
    git!(dir, ["init", "-q", "-b", "main"])
    git!(dir, ["remote", "add", "origin", remote])
    commit!(dir, "a.ex")

    File.mkdir_p!(Path.join(dir, "dev/githooks"))
    File.cp!(@hook, Path.join(dir, "dev/githooks/pre-push"))
    {_, 0} = cmd(dir, @install, [])

    %{dir: dir, remote: remote}
  end

  defp cmd(dir, command, args, env \\ []) do
    System.cmd(command, args, cd: dir, env: @env ++ env, stderr_to_stdout: true)
  end

  defp git(dir, args, env \\ []), do: cmd(dir, "git", args, env)

  defp git!(dir, args) do
    {out, 0} = git(dir, args)
    out
  end

  defp commit!(dir, file) do
    File.write!(
      Path.join(dir, file),
      "defmodule #{Macro.camelize(Path.rootname(file))} do\nend\n"
    )

    git!(dir, ["add", file])
    git!(dir, ["commit", "-q", "--no-verify", "-m", "Add #{file}"])
  end

  defp remote_has?(remote, branch),
    do: match?({_, 0}, git(remote, ["rev-parse", "--verify", "-q", "refs/heads/#{branch}"]))

  describe "a push to main" do
    test "is blocked for anyone, with no harness in sight", %{dir: dir, remote: remote} do
      {out, status} = git(dir, ["push", "-q", "origin", "main"])

      assert status != 0
      assert out =~ "pushes to main"
      refute remote_has?(remote, "main")
    end

    test "goes through with GALLFORMERS_PUSH_MAIN=1", %{dir: dir, remote: remote} do
      assert {_, 0} = git(dir, ["push", "-q", "origin", "main"], [{"GALLFORMERS_PUSH_MAIN", "1"}])
      assert remote_has?(remote, "main")
    end

    test "to master is blocked too", %{dir: dir, remote: remote} do
      {_, status} = git(dir, ["push", "-q", "origin", "main:master"])

      assert status != 0
      refute remote_has?(remote, "master")
    end

    test "is blocked on a branch without the versioned hook", %{dir: dir, remote: remote} do
      File.rm!(Path.join(dir, "dev/githooks/pre-push"))

      {_, status} = git(dir, ["push", "-q", "origin", "main"])

      assert status != 0
      refute remote_has?(remote, "main")
    end
  end

  describe "a push to another branch" do
    test "goes through", %{dir: dir, remote: remote} do
      git!(dir, ["checkout", "-q", "-b", "feature"])
      commit!(dir, "b.ex")

      assert {_, 0} = git(dir, ["push", "-q", "origin", "feature"])
      assert remote_has?(remote, "feature")
    end

    test "that rewrites its history is blocked", %{dir: dir} do
      git!(dir, ["checkout", "-q", "-b", "feature"])
      commit!(dir, "b.ex")
      git!(dir, ["push", "-q", "origin", "feature"])
      git!(dir, ["reset", "-q", "--hard", "HEAD~1"])
      commit!(dir, "c.ex")

      {out, status} = git(dir, ["push", "-q", "--force", "origin", "feature"])

      assert status != 0
      assert out =~ "force push"
    end

    test "that deletes it goes through", %{dir: dir, remote: remote} do
      git!(dir, ["checkout", "-q", "-b", "feature"])
      git!(dir, ["push", "-q", "origin", "feature"])

      assert {_, 0} = git(dir, ["push", "-q", "origin", "--delete", "feature"])
      refute remote_has?(remote, "feature")
    end
  end

  test "install.sh leaves someone else's pre-push hook alone", %{tmp_dir: tmp} do
    dir = Path.join(tmp, "other")
    File.mkdir_p!(dir)
    git!(dir, ["init", "-q"])
    installed = Path.join(dir, ".git/hooks/pre-push")
    File.write!(installed, "#!/bin/sh\necho mine\n")

    {out, status} = cmd(dir, @install, [])

    assert status != 0
    assert out =~ "already has a pre-push hook"
    assert File.read!(installed) == "#!/bin/sh\necho mine\n"
  end
end
