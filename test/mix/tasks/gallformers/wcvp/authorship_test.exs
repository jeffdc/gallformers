defmodule Mix.Tasks.Gallformers.Wcvp.AuthorshipTest do
  @moduledoc """
  `mix gallformers.wcvp.authorship` (matter `f14c`): fills plants' names'
  authorship from WCVP (the stub in tests) and prints what it found.
  """
  use Gallformers.DataCase, async: true

  import ExUnit.CaptureIO
  import Gallformers.CatalogFixtures

  alias Gallformers.Taxa
  alias Mix.Tasks.Gallformers.Wcvp.Authorship

  # The task's own actor is "wcvp_authorship"; a test's sandbox is audited as one actor.
  test "fills plants' blank names and prints the summary, ambiguous names listed" do
    plant = plant_fixture(name: "Wcvptestus alpinus")
    homonym = plant_fixture(name: "Wcvphomonymus dubius")

    output = capture_io(fn -> Authorship.backfill(test_actor()) end)

    assert [%{authorship: "Test"}] = Taxa.get_taxon!(plant.id).names
    assert output =~ "Plant names: "
    assert output =~ "Wcvphomonymus dubius (taxon #{homonym.id})"

    assert capture_io(fn -> Authorship.backfill(test_actor()) end) =~
             "given WCVP's authorship now: 0"
  end
end
