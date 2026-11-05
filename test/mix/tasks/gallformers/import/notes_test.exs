defmodule Mix.Tasks.Gallformers.Import.NotesTest do
  @moduledoc """
  `mix gallformers.import.notes` (`20e5`): writes one producer package
  directory per Gall note.

  Not async: the tests use the one Gallformers Source.
  """
  use Gallformers.DataCase, async: false

  import ExUnit.CaptureIO
  import Gallformers.CatalogFixtures

  alias Gallformers.Sources
  alias Mix.Tasks.Gallformers.Import.Notes

  setup :audit_test_metadata

  setup do
    gallformers = gallformers_source()
    galls = for n <- 1..3, do: gall_fixture(name: "Notes task gall #{n}")

    for gall <- galls,
        do: {:ok, _} = Sources.store_note(test_actor(), gallformers, gall.id, "Note #{gall.id}.")

    dir = Path.join(System.tmp_dir!(), "notes_task_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir, ids: Enum.map(galls, & &1.id)}
  end

  test "writes a directory per note, dated as asked", %{dir: dir, ids: [id | _] = ids} do
    output = capture_io(fn -> Notes.run(["--dir", dir, "--stated-on", "2026-10-30"]) end)

    assert output =~ "3 note packages"
    assert dir |> File.ls!() |> Enum.sort() == Enum.map(ids, &"note-#{&1}")

    note = dir |> Path.join("note-#{id}/note.json") |> File.read!() |> Jason.decode!()
    assert note["stated_on"] == "2026-10-30"

    assert %{"texts" => [%{"text" => "Note " <> _}]} =
             dir |> Path.join("note-#{id}/document.json") |> File.read!() |> Jason.decode!()
  end

  test "takes Gall IDs, in order, and a limit", %{dir: dir, ids: [a, _b, c]} do
    capture_io(fn -> Notes.run(["--dir", dir, "--limit", "1", "#{c}", "#{a}"]) end)
    assert File.ls!(dir) == ["note-#{a}"]
  end

  test "needs a directory" do
    assert_raise Mix.Error, ~r/--dir/, fn -> Notes.run([]) end
  end
end
