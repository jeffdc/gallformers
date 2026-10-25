defmodule Gallformers.Catalog.AcceptanceTest do
  @moduledoc """
  Acceptance tests for the gall Fact kinds (`9449` §6, Task 9): the
  Sources–Facts rules (`8567` *Sources–Facts design*) as they play out on a
  Gall's Hosts, qualifiers and occurrences.

  Not async: some tests make the one Gallformers Source.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Facts.Standing.Conflict
  alias Gallformers.Sources

  defp standing(fact_id), do: Facts.get_fact!(fact_id).standing

  defp host_of(plant, gall),
    do: %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id}

  setup do
    %{gall: gall_fixture(), oak: plant_fixture(name: "Quercus alba")}
  end

  test "two Sources confirm one Host", %{gall: gall, oak: oak} do
    {:ok, first} =
      Catalog.assert_relationship(
        test_actor(),
        host_of(oak, gall),
        confirm(source_fixture("Weld", "1959"))
      )

    {:ok, second} =
      Catalog.assert_relationship(
        test_actor(),
        host_of(oak, gall),
        confirm(source_fixture("Kinsey", "1923"))
      )

    assert second.fact.id == first.fact.id
    assert second.fact.kind == "gall_relationship"
    assert standing(first.fact.id) == :current
    assert length(Facts.list_attributions(first.fact.id)) == 2
  end

  test "a denial before and after a confirmation gives the same result", %{gall: gall, oak: oak} do
    other_gall = gall_fixture()
    older = source_fixture("Beutenmuller", "1904")
    newer = source_fixture("Revision", "1990")

    # The newer Source denies; whether its denial arrives first or last, the
    # Host is withdrawn.
    {:ok, denied_last} =
      Catalog.assert_relationship(test_actor(), host_of(oak, gall), confirm(older))

    {:ok, _} = Catalog.assert_relationship(test_actor(), host_of(oak, gall), deny(newer))

    {:ok, denied_first} =
      Catalog.assert_relationship(test_actor(), host_of(oak, other_gall), deny(newer))

    {:ok, _} = Catalog.assert_relationship(test_actor(), host_of(oak, other_gall), confirm(older))

    assert standing(denied_last.fact.id) == :withdrawn
    assert standing(denied_first.fact.id) == :withdrawn
  end

  test "a retraction cancels a Source's stances", %{gall: gall, oak: oak} do
    red_oak = plant_fixture(name: "Quercus rubra")
    older = source_fixture("Felt", "1940")
    retracted = source_fixture("Fabricated", "2019")

    {:ok, denied} = Catalog.assert_relationship(test_actor(), host_of(oak, gall), confirm(older))
    {:ok, _} = Catalog.assert_relationship(test_actor(), host_of(oak, gall), deny(retracted))

    {:ok, only_retracted} =
      Catalog.assert_relationship(test_actor(), host_of(red_oak, gall), confirm(retracted))

    assert standing(denied.fact.id) == :withdrawn
    assert standing(only_retracted.fact.id) == :current

    notice = source_fixture("Retraction notice", "2021")
    {:ok, _} = Sources.retract_source(retracted, notice, ~D[2021-06-01])
    {:ok, []} = Facts.recompute_for_source(test_actor(), retracted.id)

    assert standing(denied.fact.id) == :current
    assert standing(only_retracted.fact.id) == :retracted
  end

  test "a qualifier is denied while its Relationship stands", %{gall: gall} do
    inquiline = taxon_fixture(name: "Synergus magnus")
    older = source_fixture("Evans", "1967")
    newer = source_fixture("Ronquist", "1999")

    {:ok, rel} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inquiline_of", subject_taxon_id: inquiline.id, object_gall_id: gall.id},
        confirm(older)
      )

    qualifier = %{of_fact_id: rel.fact.id, qualifier: "lethality", value: "lethal"}

    {:ok, q} = Catalog.assert_qualifier(test_actor(), qualifier, confirm(older))
    {:ok, _} = Catalog.assert_qualifier(test_actor(), qualifier, deny(newer))

    assert q.fact.kind == "gall_qualifier"
    assert standing(q.fact.id) == :withdrawn
    assert standing(rel.fact.id) == :current
  end

  test "a Gallformers override cites Observations", %{gall: gall, oak: oak} do
    gallformers = gallformers_source()

    {:ok, rel} =
      Catalog.assert_relationship(
        test_actor(),
        host_of(oak, gall),
        confirm(source_fixture("Weld", "1959"))
      )

    {:ok, override} =
      Catalog.assert_relationship(
        test_actor(),
        host_of(oak, gall),
        deny(gallformers, %{
          stated: "2026-10-24",
          statement_text:
            "Not on Q. alba; the 1959 record is Q. stellata, per these Observations.",
          observations: [
            %{provider: :inaturalist, external_id: "12345"},
            %{provider: :inaturalist, external_id: "67890"}
          ]
        })
      )

    assert override.fact.id == rel.fact.id
    assert standing(rel.fact.id) == :withdrawn

    assert %Attribution{observations: observations} =
             Enum.find(Facts.list_attributions(rel.fact.id), &(&1.source_id == gallformers.id))

    assert observations |> Enum.map(& &1.external_id) |> Enum.sort() == ["12345", "67890"]
  end

  test "a same-date conflict is reported", %{gall: gall, oak: oak} do
    {:ok, rel} =
      Catalog.assert_relationship(
        test_actor(),
        host_of(oak, gall),
        confirm(source_fixture("A", "1950"))
      )

    {:ok, %{conflicts: conflicts}} =
      Catalog.assert_relationship(
        test_actor(),
        host_of(oak, gall),
        deny(source_fixture("B", "1950"))
      )

    assert [%Conflict{type: :same_date, fact_ids: [fact_id]}] = conflicts
    assert fact_id == rel.fact.id

    # Until a curator decides, the Fact keeps its standing.
    assert standing(rel.fact.id) == :current
  end

  test "a Host that isn't a plant is rejected", %{gall: gall} do
    wasp = taxon_fixture(name: "Andricus foo", kingdom: "Animalia")
    unknown_kingdom = taxon_fixture(name: "Mystery organism")

    for taxon <- [wasp, unknown_kingdom] do
      assert {:error, changeset} =
               Catalog.assert_relationship(
                 test_actor(),
                 host_of(taxon, gall),
                 confirm(source_fixture("A", "1950"))
               )

      assert %{subject_taxon_id: ["must be a plant"]} = errors_on(changeset)
    end
  end

  test "two Sources recording one place make one occurrence Fact with two dated attributions",
       %{gall: gall} do
    place = %{gall_id: gall.id, place_id: place_id("US-CA")}

    {:ok, first} =
      Catalog.assert_occurrence(
        test_actor(),
        place,
        confirm(source_fixture("Felt", "1940"), %{
          value_as_written: "Mt. Diablo",
          when_as_written: "July 1938"
        })
      )

    {:ok, second} =
      Catalog.assert_occurrence(
        test_actor(),
        place,
        confirm(source_fixture("Russo", "2006"), %{
          value_as_written: "California",
          when_as_written: "late summer",
          stage_as_written: "mature, adults emerging"
        })
      )

    assert second.fact.id == first.fact.id
    assert first.fact.kind == "gall_occurrence"

    assert [
             %{stated_on: ~D[1940-01-01], when_as_written: "July 1938", stage_as_written: nil},
             %{
               stated_on: ~D[2006-01-01],
               when_as_written: "late summer",
               stage_as_written: "mature, adults emerging"
             }
           ] = Facts.list_attributions(first.fact.id)
  end
end
