defmodule Gallformers.Import.CandidatesTest do
  @moduledoc """
  A name several species hold (`6611` Task 3): for a taxon item's
  candidates, each one's accepted name, the names it holds, its Galls and
  their Hosts, so a curator can compare them with what the Source says.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    chrysolepis = plant_fixture(name: "Quercus chrysolepis", parent: quercus)
    palmeri = plant_fixture(name: "Quercus palmeri", parent: quercus)
    legacy = source_fixture("Legacy", "1990")

    disholandricus = taxon_fixture(name: "Disholandricus", rank: :genus, kingdom: "Animalia")
    heteroecus = taxon_fixture(name: "Heteroecus", rank: :genus, kingdom: "Animalia")

    a =
      taxon_fixture(
        name: "Disholandricus chrysolepidis",
        parent: disholandricus,
        kingdom: "Animalia"
      )

    b = taxon_fixture(name: "Heteroecus chrysolepidis", parent: heteroecus, kingdom: "Animalia")

    {:ok, _} =
      Taxa.add_synonym(test_actor(), a, "Andricus chrysolepidis", authorship: "Ashmead, 1897")

    {:ok, _} = Taxa.add_synonym(test_actor(), b, "Andricus chrysolepidis", sensu: "Beutenmüller")

    galls =
      for {inducer, hosts, name} <- [
            {a, [chrysolepis, palmeri], "Disholandricus chrysolepidis (agamic)"},
            {b, [chrysolepis], "Heteroecus chrysolepidis (agamic)"}
          ] do
        gall = gall_fixture(name: name)
        relate!(legacy, "inducer_of", inducer, gall)
        for host <- hosts, do: relate!(legacy, "host_of", host, gall)
        gall
      end

    %{a: a, b: b, galls: galls, chrysolepis: chrysolepis, palmeri: palmeri}
  end

  defp relate!(source, type, taxon, gall) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: type, subject_taxon_id: taxon.id, object_gall_id: gall.id},
        confirm(source)
      )
  end

  test "each candidate with the names it holds, its Galls and their Hosts", ctx do
    item = %QueueItem{
      kind: :ambiguous_match,
      statement_ref: "t3",
      subject: %{"name_as_written" => "ANDRICUS CHRYSOLEPIDIS", "rank" => "species"},
      proposal: %{"candidate_ids" => [ctx.a.id, ctx.b.id]}
    }

    [gall_a, gall_b] = ctx.galls

    assert [a, b] = Import.candidate_comparison(item)

    assert %{taxon_id: a_id, name: "Disholandricus chrysolepidis", rank: :species} = a
    assert a_id == ctx.a.id

    assert a.names == [
             %{
               name: "Disholandricus chrysolepidis",
               status: :accepted,
               authorship: nil,
               sensu: nil
             },
             %{
               name: "Andricus chrysolepidis",
               status: :synonym,
               authorship: "Ashmead, 1897",
               sensu: nil
             }
           ]

    assert [%{gall_id: a_gall, name: "Disholandricus chrysolepidis (agamic)", hosts: a_hosts}] =
             a.galls

    assert a_gall == gall_a.id
    assert Enum.map(a_hosts, & &1.name) == ["Quercus chrysolepis", "Quercus palmeri"]

    assert [_, %{name: "Andricus chrysolepidis", sensu: "Beutenmüller"}] = b.names
    assert [%{gall_id: b_gall, hosts: [%{name: "Quercus chrysolepis"}]}] = b.galls
    assert b_gall == gall_b.id
  end

  test "an item about something other than a taxon has no candidates to compare" do
    assert Import.candidate_comparison(%QueueItem{
             kind: :ambiguous_match,
             statement_ref: "g1",
             proposal: %{"candidate_ids" => [1, 2]}
           }) == []

    assert Import.candidate_comparison(%QueueItem{
             kind: :dispute,
             statement_ref: "f3",
             proposal: %{}
           }) ==
             []
  end
end
