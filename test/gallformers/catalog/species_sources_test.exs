defmodule Gallformers.Catalog.SpeciesSourcesTest do
  @moduledoc """
  The Sources of a species page (`Gallformers.Catalog.species_sources/2`):
  every Source citing the organism (its taxonomic statements) or one of its
  Galls (citations, notes and Facts), each once with what it covers;
  Gallformers' own Sources are left out.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Sources
  alias Gallformers.Taxa

  setup do
    n = System.unique_integer([:positive])
    genus = taxon_fixture(rank: :genus, name: "Sourcea#{n}", kingdom: "Animalia")
    species = taxon_fixture(name: "Sourcea#{n} alba", parent: genus, kingdom: "Animalia")
    %{genus: genus, species: species, agamic: gall_fixture(), sexgen: gall_fixture()}
  end

  defp inducer!(taxon, gall, source) do
    key = %{type: "inducer_of", subject_taxon_id: taxon.id, object_gall_id: gall.id}
    {:ok, _} = Catalog.assert_relationship(test_actor(), key, confirm(source))
    :ok
  end

  test "Sources of its Galls and of its taxonomy, each once, by year", ctx do
    early = source_fixture("Early", "1881")
    late = source_fixture("Late", "1990")
    revision = source_fixture("Revision", "1959")

    inducer!(ctx.species, ctx.agamic, early)
    inducer!(ctx.species, ctx.sexgen, early)
    inducer!(ctx.species, ctx.sexgen, late)

    {:ok, _} =
      Taxa.assert_placement(
        test_actor(),
        %{taxon_id: ctx.species.id, parent_id: ctx.genus.id},
        confirm(revision)
      )

    sources = Catalog.species_sources(ctx.species.id, [ctx.agamic.id, ctx.sexgen.id])

    assert Enum.map(sources, & &1.id) == [early.id, revision.id, late.id]

    assert %{gall_ids: galls, taxonomy: false} = Enum.find(sources, &(&1.id == early.id))
    assert Enum.sort(galls) == Enum.sort([ctx.agamic.id, ctx.sexgen.id])

    assert %{gall_ids: [], taxonomy: true, pubyear: "1959"} =
             Enum.find(sources, &(&1.id == revision.id))

    assert %{gall_ids: [sexgen_id]} = Enum.find(sources, &(&1.id == late.id))
    assert sexgen_id == ctx.sexgen.id
  end

  test "Gallformers' own Sources are left out", ctx do
    legacy = Sources.get_legacy_data_source()
    inducer!(ctx.species, ctx.agamic, legacy)

    {:ok, _} =
      Taxa.assert_name(
        test_actor(),
        %{taxon_id: ctx.species.id, name: Taxa.accepted_name(ctx.species), rank: :species},
        %{source_id: legacy.id, stance: :confirm, stated: nil}
      )

    assert Catalog.species_sources(ctx.species.id, [ctx.agamic.id]) == []
  end
end
