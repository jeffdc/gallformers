defmodule Mix.Tasks.Gallformers.Import.TermCandidatesTest do
  @moduledoc """
  `mix gallformers.import.term_candidates` (`d213`, Task F): gathers the
  Trait terms of the producer packages under the directories given into
  seed candidates, and prints a summary.

  Not async: the Catalog vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import ExUnit.CaptureIO
  import Gallformers.CatalogFixtures

  alias Gallformers.Audit.Actor
  alias Gallformers.Import
  alias Mix.Tasks.Gallformers.Import.TermCandidates

  setup do
    # The task writes as its own system actor; so must the fixtures.
    put_test_actor(Actor.system("term_candidates"))
    :ok
  end

  setup :audit_test_metadata

  setup do
    load_vocab!()

    root =
      Path.join(System.tmp_dir!(), "term_candidates_task_#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(root) end)

    dir = Path.join(root, "pkg-a")
    File.mkdir_p!(dir)

    fact = fn id, value, as_written ->
      %{
        "id" => id,
        "stance" => "confirm",
        "kind" => "trait",
        "gall" => "g1",
        "trait" => "shape",
        "value" => %{"value" => value, "as_written" => as_written},
        "evidence" => [%{"item" => "#/texts/1", "quote" => as_written}]
      }
    end

    File.write!(
      Path.join(dir, "gall.json"),
      Jason.encode!(%{
        "format_version" => 3,
        "galls" => [%{"ref" => "g1", "name_as_written" => "A gall"}],
        "facts" => [fact.("f1", "globular", "rounded"), fact.("f2", "globular", "ovoid")]
      })
    )

    %{root: root}
  end

  test "gathers the candidates and prints a summary", %{root: root} do
    output = capture_io(fn -> TermCandidates.run([root]) end)

    assert output =~ "1 package"
    assert output =~ "1 new"
    assert output =~ "ovoid"
    assert [%{normalized_term: "rounded", total: 1}] = Import.list_term_candidates()
  end

  test "needs a directory" do
    assert_raise Mix.Error, ~r/Usage/, fn -> TermCandidates.run([]) end
  end

  test "refuses a directory that does not exist", %{root: root} do
    assert_raise Mix.Error, ~r/no such directory/, fn ->
      TermCandidates.run([Path.join(root, "missing")])
    end
  end
end
