defmodule Gallformers.Guardrails.CommitGateTest do
  @moduledoc """
  The commit gate (matter `c800`): the git pre-commit hook
  `dev/githooks/pre-commit`, installed by `dev/githooks/install.sh`, blocks
  any `git commit` (any agent, any harness, a terminal) until the tree being
  committed has a passing reuse review, recorded by
  `dev/guardrails/record_review.sh` from `dev/guardrails/review_packet.sh`'s
  packet.

  Each test runs real git commands in a fresh repository, with global and
  system git config shut out.
  """
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @hook Path.expand("dev/githooks/pre-commit")
  @install Path.expand("dev/githooks/install.sh")
  @packet Path.expand("dev/guardrails/review_packet.sh")
  @record Path.expand("dev/guardrails/record_review.sh")

  @env [
    {"GIT_CONFIG_GLOBAL", "/dev/null"},
    {"GIT_CONFIG_NOSYSTEM", "1"},
    {"GIT_DIR", nil},
    {"GIT_INDEX_FILE", nil},
    {"GIT_WORK_TREE", nil},
    {"GIT_AUTHOR_NAME", "Test"},
    {"GIT_AUTHOR_EMAIL", "test@example.com"},
    {"GIT_COMMITTER_NAME", "Test"},
    {"GIT_COMMITTER_EMAIL", "test@example.com"}
  ]

  setup %{tmp_dir: dir} do
    git!(dir, ["init", "-q"])
    File.write!(Path.join(dir, "a.ex"), "defmodule A do\nend\n")
    git!(dir, ["add", "a.ex"])
    git!(dir, ["commit", "-q", "-m", "start"])

    # The checkout's own versioned hook, as on a branch that has it.
    File.mkdir_p!(Path.join(dir, "dev/githooks"))
    File.cp!(@hook, Path.join(dir, "dev/githooks/pre-commit"))
    {_, 0} = cmd(dir, @install, [])

    File.write!(Path.join(dir, "a.ex"), "defmodule A do\n  def new_fun(x), do: x\nend\n")
    git!(dir, ["add", "a.ex"])
    :ok
  end

  defp cmd(dir, command, args) do
    {out, status} = System.cmd(command, args, cd: dir, env: @env, stderr_to_stdout: true)
    {out, status}
  end

  defp git(dir, args), do: cmd(dir, "git", args)

  defp git!(dir, args) do
    {out, 0} = git(dir, args)
    out
  end

  defp head(dir), do: dir |> git!(["rev-parse", "HEAD"]) |> String.trim()

  defp review(dir, verdict) do
    {packet, 0} = cmd(dir, @packet, [])
    report = Path.join(dir, "report.md")
    File.write!(report, "No findings.\n")
    {_, 0} = cmd(dir, @record, [verdict, report])
    String.trim(packet)
  end

  describe "a plain git commit" do
    test "with no review is blocked, and nothing is committed", %{tmp_dir: dir} do
      before = head(dir)

      {out, status} = git(dir, ["commit", "-m", "Add new_fun"])

      assert status != 0
      assert out =~ "hasn't had a reuse review"
      assert head(dir) == before
    end

    test "with a passing review goes through", %{tmp_dir: dir} do
      before = head(dir)
      review(dir, "pass")

      assert {_, 0} = git(dir, ["commit", "-q", "-m", "Add new_fun"])
      assert head(dir) != before
    end

    test "the review blocked is blocked", %{tmp_dir: dir} do
      review(dir, "block")

      {out, status} = git(dir, ["commit", "-m", "Add new_fun"])

      assert status != 0
      assert out =~ "the reuse review blocked this change"
    end

    test "after restaging needs a new review", %{tmp_dir: dir} do
      review(dir, "pass")
      File.write!(Path.join(dir, "b.ex"), "defmodule B do\nend\n")
      git!(dir, ["add", "b.ex"])

      assert {_, status} = git(dir, ["commit", "-m", "Add new_fun"])
      assert status != 0
    end

    test "with -a is checked against the tree it would commit", %{tmp_dir: dir} do
      review(dir, "pass")
      File.write!(Path.join(dir, "a.ex"), "defmodule A do\n  def other(x), do: x\nend\n")

      assert {_, status} = git(dir, ["commit", "-a", "-m", "Add new_fun"])
      assert status != 0
    end

    test "that concludes a merge goes through", %{tmp_dir: dir} do
      git!(dir, ["commit", "-q", "--no-verify", "-m", "Add new_fun"])
      git!(dir, ["checkout", "-q", "-b", "side", "HEAD~1"])
      File.write!(Path.join(dir, "c.ex"), "defmodule C do\nend\n")
      git!(dir, ["add", "c.ex"])
      git!(dir, ["commit", "-q", "--no-verify", "-m", "Add C"])
      git!(dir, ["checkout", "-q", "-"])
      git!(dir, ["merge", "-q", "--no-ff", "--no-commit", "side"])

      assert {_, 0} = git(dir, ["commit", "-q", "--no-edit"])
    end

    test "on a branch without the versioned hook goes through", %{tmp_dir: dir} do
      File.rm!(Path.join(dir, "dev/githooks/pre-commit"))

      assert {_, 0} = git(dir, ["commit", "-q", "-m", "Add new_fun"])
    end
  end

  describe "install.sh" do
    test "installs a wrapper that runs the checkout's own hook", %{tmp_dir: dir} do
      installed = Path.join(dir, ".git/hooks/pre-commit")

      assert File.read!(installed) =~ "dev/githooks/pre-commit"
      assert {_, 0} = cmd(dir, @install, [])
    end

    test "leaves someone else's pre-commit hook alone", %{tmp_dir: dir} do
      installed = Path.join(dir, ".git/hooks/pre-commit")
      File.write!(installed, "#!/bin/sh\necho mine\n")

      {out, status} = cmd(dir, @install, [])

      assert status != 0
      assert out =~ "already has a pre-commit hook"
      assert File.read!(installed) == "#!/bin/sh\necho mine\n"
    end
  end

  describe "the packet" do
    test "lists the new public definitions and the tree", %{tmp_dir: dir} do
      packet = dir |> review("pass") |> File.read!()

      assert packet =~ "a.ex: def new_fun(x), do: x"
      assert packet =~ "tree: "
    end

    test "lists each new file under lib/ for the reviewer to justify", %{tmp_dir: dir} do
      File.mkdir_p!(Path.join(dir, "lib/gallformers"))
      File.write!(Path.join(dir, "lib/gallformers/new_thing.ex"), "defmodule NewThing do\nend\n")
      File.write!(Path.join(dir, "notes.md"), "notes\n")
      git!(dir, ["add", "lib/gallformers/new_thing.ex", "notes.md"])

      packet = dir |> review("pass") |> File.read!()
      [_, section] = String.split(packet, "## New files under lib/", parts: 2)
      [section | _] = String.split(section, "\n## ", parts: 2)

      assert section =~ "lib/gallformers/new_thing.ex"
      refute section =~ "notes.md"
      refute section =~ "a.ex"
    end
  end

  test "a review isn't recorded once the staging changed", %{tmp_dir: dir} do
    {_, 0} = cmd(dir, @packet, [])
    File.write!(Path.join(dir, "b.ex"), "defmodule B do\nend\n")
    git!(dir, ["add", "b.ex"])
    File.write!(Path.join(dir, "report.md"), "No findings.\n")

    assert {out, 1} = cmd(dir, @record, ["pass", "report.md"])
    assert out =~ "staging changed"
  end
end
