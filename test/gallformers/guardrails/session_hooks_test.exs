defmodule Gallformers.Guardrails.SessionHooksTest do
  @moduledoc """
  The session hooks (matter `c800`): `.claude/hooks/compaction_count.sh`
  warns from a session's second compaction on, and
  `.claude/hooks/new_lib_file.sh` asks once, before a new file under `lib/`,
  which existing modules were checked.
  """
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @compaction Path.expand(".claude/hooks/compaction_count.sh")
  @new_file Path.expand(".claude/hooks/new_lib_file.sh")

  setup %{tmp_dir: dir} do
    {_, 0} = System.cmd("git", ["init", "-q"], cd: dir)
    File.mkdir_p!(Path.join(dir, "lib/gallformers"))
    File.write!(Path.join(dir, "lib/gallformers/old.ex"), "defmodule Old do\nend\n")
    :ok
  end

  defp run(script, input) do
    System.cmd("sh", ["-c", ~s(printf '%s' "$INPUT" | "$SCRIPT")],
      env: [{"INPUT", Jason.encode!(input)}, {"SCRIPT", script}],
      stderr_to_stdout: true
    )
  end

  describe "compaction_count.sh" do
    defp compact(dir, session),
      do: run(@compaction, %{session_id: session, cwd: dir, source: "compact"})

    test "says nothing after a session's first compaction", %{tmp_dir: dir} do
      assert {"", 0} = compact(dir, "s1")
    end

    test "warns from the second compaction on, counting each session apart", %{tmp_dir: dir} do
      compact(dir, "s1")
      assert {out, 0} = compact(dir, "s1")
      assert out =~ "compacted 2 times"
      assert out =~ "start a fresh session"

      assert {out, 0} = compact(dir, "s1")
      assert out =~ "compacted 3 times"

      assert {"", 0} = compact(dir, "s2")
    end
  end

  describe "new_lib_file.sh" do
    defp write(dir, path),
      do:
        run(@new_file, %{
          tool_name: "Write",
          tool_input: %{file_path: Path.join(dir, path)},
          cwd: dir
        })

    test "blocks the first write of a new file under lib/, then lets it through", %{tmp_dir: dir} do
      assert {out, 2} = write(dir, "lib/gallformers/new_thing.ex")
      assert out =~ "Name the existing modules you checked"

      assert {_, 0} = write(dir, "lib/gallformers/new_thing.ex")
    end

    test "asks again for each new file", %{tmp_dir: dir} do
      write(dir, "lib/gallformers/new_thing.ex")

      assert {_, 2} = write(dir, "lib/gallformers_web/live/other_live.ex")
    end

    test "asks for a new file in a directory that doesn't exist yet", %{tmp_dir: dir} do
      assert {out, 2} = write(dir, "lib/gallformers/brand_new/deeper/thing.ex")
      assert out =~ "lib/gallformers/brand_new/deeper/thing.ex"
    end

    test "leaves a file that already exists alone", %{tmp_dir: dir} do
      assert {_, 0} = write(dir, "lib/gallformers/old.ex")
    end

    test "leaves files outside lib/ alone", %{tmp_dir: dir} do
      assert {_, 0} = write(dir, "test/gallformers/new_test.exs")
      assert {_, 0} = write(dir, "docs/notes.md")
    end
  end
end
