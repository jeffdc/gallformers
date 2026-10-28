defmodule Mix.Tasks.Gallformers.Import.VocabTest do
  @moduledoc """
  `mix gallformers.import.vocab` (`294c` step 3): writes the import
  contract's vocabulary files from the database and code, or with `--check`
  lists the files that differ and fails.

  Not async: loading the vocabularies waits on concurrent loads.
  """
  use Gallformers.DataCase, async: false

  import ExUnit.CaptureIO

  alias Gallformers.Catalog
  alias Mix.Tasks.Gallformers.Import.Vocab, as: VocabTask

  setup do
    {:ok, _counts} = Catalog.load_vocab(test_actor())
    dir = Path.join(System.tmp_dir!(), "vocab_task_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "writes the files, then --check passes", %{dir: dir} do
    output = capture_io(fn -> VocabTask.run(["--dir", dir, "--version", "2026-01-02"]) end)

    assert output =~ "vocabulary_version 2026-01-02"
    assert output =~ "Wrote #{Path.join(dir, "traits.json")}"
    assert {:ok, "{\n" <> _} = File.read(Path.join(dir, "places.json"))

    output = capture_io(fn -> VocabTask.run(["--dir", dir]) end)
    assert output =~ "up to date"

    output = capture_io(fn -> VocabTask.run(["--check", "--dir", dir]) end)
    assert output =~ "up to date"
  end

  test "--check fails listing the files that differ, writing nothing", %{dir: dir} do
    capture_io(fn -> VocabTask.run(["--dir", dir, "--version", "2026-01-02"]) end)
    path = Path.join(dir, "ranks.schema.json")
    File.write!(path, "{}\n")

    assert_raise Mix.Error, ~r/ranks\.schema\.json/, fn ->
      capture_io(fn -> VocabTask.run(["--check", "--dir", dir]) end)
    end

    assert File.read!(path) == "{}\n"
  end

  test "refuses a --version that is not a date", %{dir: dir} do
    assert_raise Mix.Error, ~r/YYYY-MM-DD/, fn ->
      VocabTask.run(["--dir", dir, "--version", "soon"])
    end
  end
end
