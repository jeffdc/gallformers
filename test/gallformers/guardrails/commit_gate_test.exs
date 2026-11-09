defmodule Gallformers.Guardrails.CommitGateTest do
  @moduledoc """
  The commit gate (matter `c800`): `.claude/hooks/require_review.sh` blocks a
  `git commit` until the staged tree has a passing reuse review, recorded by
  `dev/guardrails/record_review.sh` from `dev/guardrails/review_packet.sh`'s
  packet.
  """
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @hook Path.expand(".claude/hooks/require_review.sh")
  @packet Path.expand("dev/guardrails/review_packet.sh")
  @record Path.expand("dev/guardrails/record_review.sh")

  setup %{tmp_dir: dir} do
    git!(dir, ["init", "-q"])
    File.write!(Path.join(dir, "a.ex"), "defmodule A do\nend\n")
    git!(dir, ["add", "a.ex"])
    git!(dir, ["commit", "-q", "-m", "start"])

    File.write!(Path.join(dir, "a.ex"), "defmodule A do\n  def new_fun(x), do: x\nend\n")
    git!(dir, ["add", "a.ex"])
    :ok
  end

  defp git!(dir, args) do
    {out, 0} =
      System.cmd("git", ["-c", "user.name=Test", "-c", "user.email=test@example.com" | args],
        cd: dir,
        stderr_to_stdout: true
      )

    out
  end

  defp hook(dir, command) do
    input = Jason.encode!(%{tool_name: "Bash", tool_input: %{command: command}, cwd: dir})

    {out, status} =
      System.cmd("sh", ["-c", ~s(printf '%s' "$INPUT" | "$HOOK")],
        env: [{"INPUT", input}, {"HOOK", @hook}],
        stderr_to_stdout: true
      )

    {status, out}
  end

  defp review(dir, verdict) do
    {packet, 0} = System.cmd(@packet, [], cd: dir)
    report = Path.join(dir, "report.md")
    File.write!(report, "No findings.\n")
    {_, 0} = System.cmd(@record, [verdict, report], cd: dir)
    String.trim(packet)
  end

  test "a commit with no review is blocked", %{tmp_dir: dir} do
    assert {2, out} = hook(dir, ~s(git commit -m "Add new_fun"))
    assert out =~ "hasn't had a reuse review"
  end

  test "a commit with a passing review goes through", %{tmp_dir: dir} do
    review(dir, "pass")

    assert {0, _} = hook(dir, ~s(git commit -m "Add new_fun"))
  end

  test "a commit the review blocked is blocked", %{tmp_dir: dir} do
    review(dir, "block")

    assert {2, out} = hook(dir, ~s(git commit -m "Add new_fun"))
    assert out =~ "blocked this staged change"
  end

  test "restaging after a review needs a new review", %{tmp_dir: dir} do
    review(dir, "pass")
    File.write!(Path.join(dir, "b.ex"), "defmodule B do\nend\n")
    git!(dir, ["add", "b.ex"])

    assert {2, _} = hook(dir, ~s(git commit -m "Add new_fun"))
  end

  test "a merge goes through", %{tmp_dir: dir} do
    File.write!(
      Path.join([dir, ".git", "MERGE_HEAD"]),
      "0000000000000000000000000000000000000000\n"
    )

    assert {0, _} = hook(dir, "git commit --no-edit")
  end

  test "commit -a is blocked even after a review", %{tmp_dir: dir} do
    review(dir, "pass")

    assert {2, out} = hook(dir, ~s(git commit -am "Add new_fun"))
    assert out =~ "stage files by name"
  end

  test "other git commands are left alone", %{tmp_dir: dir} do
    assert {0, _} = hook(dir, "git log --oneline -3")
    assert {0, _} = hook(dir, "git status")
  end

  test "git -C path commit is checked in that path", %{tmp_dir: dir} do
    assert {2, _} = hook(Path.dirname(dir), ~s(git -C #{dir} commit -m "Add new_fun"))
  end

  test "the packet lists the new public definitions", %{tmp_dir: dir} do
    packet = dir |> review("pass") |> File.read!()

    assert packet =~ "a.ex: def new_fun(x), do: x"
    assert packet =~ "tree: "
  end

  test "a review isn't recorded once the staging changed", %{tmp_dir: dir} do
    {_, 0} = System.cmd(@packet, [], cd: dir)
    File.write!(Path.join(dir, "b.ex"), "defmodule B do\nend\n")
    git!(dir, ["add", "b.ex"])
    File.write!(Path.join(dir, "report.md"), "No findings.\n")

    assert {out, 1} = System.cmd(@record, ["pass", "report.md"], cd: dir, stderr_to_stdout: true)
    assert out =~ "staging changed"
  end
end
