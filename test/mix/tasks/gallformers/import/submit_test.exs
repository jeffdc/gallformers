defmodule Mix.Tasks.Gallformers.Import.SubmitTest do
  @moduledoc """
  `mix gallformers.import.submit` (matter e381 *Delivery*): delivers a
  producer's package directory and reports where it stands.

  Not async: packages create Sources and the Catalog vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import ExUnit.CaptureIO
  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures

  alias Gallformers.Audit.Actor
  alias Gallformers.Import
  alias Mix.Tasks.Gallformers.Import.Submit

  setup do
    # The task writes as its own system actor; so must the fixtures.
    put_test_actor(Actor.system("import_submit"))
    load_vocab!()
    dir = Path.join(System.tmp_dir!(), "submit_task_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    files = package(gall: unique_batch_id(batch())) |> with_review()
    for {name, bytes} <- files, do: File.write!(Path.join(dir, name), bytes)
    # A producer's directory holds more than the package.
    File.write!(Path.join(dir, "notes-phase3.md"), "notes")

    %{dir: dir}
  end

  test "delivers the package files from the directory and reports the review", %{dir: dir} do
    key = "task-#{System.unique_integer([:positive])}"
    output = capture_io(fn -> Submit.run([dir, "--key", key]) end)

    assert output =~ key
    assert output =~ "awaiting_review"
    assert %{status: :awaiting_review} = Import.get_package_by_key(key)
  end

  test "names the package after the directory by default", %{dir: dir} do
    capture_io(fn -> Submit.run([dir]) end)

    assert [package] =
             Import.list_packages().entries
             |> Enum.filter(&String.starts_with?(&1.key, Path.basename(dir) <> "-"))

    assert package.status == :awaiting_review
  end

  test "refuses a directory with no batch" do
    empty = Path.join(System.tmp_dir!(), "submit_empty_#{System.unique_integer([:positive])}")
    File.mkdir_p!(empty)
    on_exit(fn -> File.rm_rf(empty) end)

    assert_raise Mix.Error, ~r/no taxonomy.json or gall.json/, fn -> Submit.run([empty]) end
  end
end
