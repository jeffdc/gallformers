defmodule Gallformers.Import.GallFactsTest do
  @moduledoc """
  A Gall's Facts as its page shows them with the Fact inspector (matter
  `87a1`, task 2): `Gallformers.Import.gall_facts/1`. Each current Fact in
  its group, with the change set's key for it (`Gallformers.Curation.Key`),
  its standing in words' terms (holds, stated by N Sources, or unconfirmed),
  and who says so: Gallformers' statement apart, the other Sources newest
  first.

  Not async: the vocabularies are loaded (`Gallformers.CatalogFixtures`)
  and tests make the one Gallformers Source.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Sources

  setup :audit_test_metadata

  setup do
    load_vocab!()
    %{gall: gall_fixture()}
  end

  defp host!(gall, plant, attribution) do
    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: plant.id, object_gall_id: gall.id},
        attribution
      )
  end

  defp trait!(gall, trait, value, attribution) do
    {:ok, _} =
      Catalog.assert_trait(
        test_actor(),
        %{gall_id: gall.id, trait: trait, value: value},
        attribution
      )
  end

  defp fact(groups, group, key), do: groups |> Map.fetch!(group) |> Enum.find(&(&1.key == key))

  test "each Fact carries its change-set key, a recorded occurrence's too", %{gall: gall} do
    paper = source_fixture("Keys", "1959")
    wasp = taxon_fixture(name: "Andricus keyed", kingdom: "Animalia")
    oak = plant_fixture(name: "Quercus keyed")
    california = place_id("US-CA")
    alberta = place_id("CA-AB")

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
        confirm(paper)
      )

    host!(gall, oak, confirm(paper))
    trait!(gall, "color", "red", confirm(paper))

    {:ok, _} =
      Catalog.assert_range(
        test_actor(),
        %{gall_id: gall.id, adjustment: :exclude, place_id: alberta},
        confirm(paper)
      )

    {:ok, _} =
      Catalog.assert_occurrence(
        test_actor(),
        %{gall_id: gall.id, place_id: california},
        confirm(paper)
      )

    {:ok, _} =
      Catalog.assert_alias(
        test_actor(),
        %{gall_id: gall.id, name: "keyed oak gall", kind: :common_name},
        confirm(paper)
      )

    groups = Import.gall_facts(gall.id)

    assert [%{key: {:inducer, wasp_id}, kind: :inducer}] = groups.inducer
    assert wasp_id == wasp.id

    assert [%{key: {:host, oak_id}, kind: :host, value: %{subject: %{name: "Quercus keyed"}}}] =
             groups.hosts

    assert oak_id == oak.id

    assert [%{trait: "color", facts: [%{key: {:trait, "color", "red"}, trait: "color"}]}] =
             groups.traits

    assert %{kind: :range} = fact(groups, :range, {:range, :exclude, alberta})
    assert %{kind: :occurrence} = fact(groups, :range, {:occurrence, california})
    assert [%{key: {:alias, "keyed oak gall"}, kind: :alias}] = groups.aliases
  end

  test "Gallformers' statement apart, the other Sources newest first", %{gall: gall} do
    older = source_fixture("Older", "1959")
    newer = source_fixture("Newer", "2001")
    legacy = Sources.get_legacy_data_source()
    trait!(gall, "color", "red", confirm(older))
    trait!(gall, "color", "red", confirm(legacy, %{stated: nil}))
    trait!(gall, "color", "red", confirm(newer))

    assert [%{facts: [red]}] = Import.gall_facts(gall.id).traits
    assert red.gallformers.source_id == legacy.id
    assert Enum.map(red.sources, & &1.source_id) == [newer.id, older.id]
  end

  test "the original data and a Gallformers change are one Gallformers statement, the change's",
       %{gall: gall} do
    gallformers = gallformers_source()
    legacy = Sources.get_legacy_data_source()
    trait!(gall, "color", "red", confirm(legacy, %{stated: nil}))

    trait!(
      gall,
      "color",
      "red",
      confirm(gallformers, %{statement_text: "Seen red in the field.", stated: "2025-07-14"})
    )

    assert [%{facts: [red]}] = Import.gall_facts(gall.id).traits
    assert red.gallformers.source_id == gallformers.id
    assert red.gallformers.statement == "Seen red in the field."
    assert red.sources == []
  end

  test "Gallformers says nothing: no Gallformers statement", %{gall: gall} do
    trait!(gall, "color", "red", confirm(source_fixture("Only", "1959")))

    assert [%{facts: [%{gallformers: nil, sources: [_]}]}] = Import.gall_facts(gall.id).traits
  end

  test "only the original data states it: unconfirmed", %{gall: gall} do
    trait!(gall, "color", "red", confirm(Sources.get_legacy_data_source(), %{stated: nil}))

    assert [%{facts: [red]}] = Import.gall_facts(gall.id).traits
    assert red.standing == :unconfirmed
  end

  test "holds: stated by the Sources whose statements count, Gallformers once", %{gall: gall} do
    gallformers = gallformers_source()
    legacy = Sources.get_legacy_data_source()
    trait!(gall, "color", "red", confirm(legacy, %{stated: nil}))
    trait!(gall, "color", "red", confirm(gallformers, %{statement_text: "Seen."}))
    trait!(gall, "color", "red", confirm(source_fixture("Paper", "1959")))

    assert [%{facts: [red]}] = Import.gall_facts(gall.id).traits
    assert red.standing == {:holds, 2}
  end

  test "a Source that says it isn't so doesn't count as stating it", %{gall: gall} do
    trait!(gall, "color", "red", deny(source_fixture("Says not", "1958")))
    trait!(gall, "color", "red", confirm(source_fixture("Says so", "1959")))

    groups = Import.gall_facts(gall.id)
    assert [%{facts: [red]}] = groups.traits
    assert red.standing == {:holds, 1}
    assert Enum.map(red.sources, & &1.stance) == [:confirm, :deny]
  end

  test "the Traits not recorded, in the page's order", %{gall: gall} do
    trait!(gall, "shape", "globular", confirm(source_fixture("Shape", "1959")))
    trait!(gall, "detachable", "integral", confirm(source_fixture("Detachable", "1959")))

    groups = Import.gall_facts(gall.id)
    assert Enum.map(groups.traits, & &1.trait) == ["detachable", "shape"]

    assert groups.traits_missing ==
             ~w(color texture season alignment walls plant_part form cells)
  end

  test "a withdrawn Fact isn't on the page", %{gall: gall} do
    trait!(gall, "shape", "globular", deny(source_fixture("Withdraws", "1959")))

    assert Import.gall_facts(gall.id).traits == []
  end

  test "the Facts no longer current are its past, each withdrawn or superseded (87a1)",
       %{gall: gall} do
    kinsey = source_fixture("Kinsey", "1959")
    weld = source_fixture("Weld", "2001")
    trait!(gall, "color", "red", confirm(kinsey))
    trait!(gall, "color", "red", deny(weld))
    trait!(gall, "detachable", "integral", confirm(kinsey))
    trait!(gall, "detachable", "detachable", confirm(weld))

    past = Import.gall_facts(gall.id).past

    assert %{standing: :withdrawn, sources: [%{stance: :deny} | _]} =
             Enum.find(past, &(&1.key == {:trait, "color", "red"}))

    assert %{standing: :superseded} =
             Enum.find(past, &(&1.key == {:trait, "detachable", "integral"}))

    refute Enum.find(past, &(&1.key == {:trait, "detachable", "detachable"}))
  end

  test "a Gall with no Facts has empty groups and every Trait not recorded", %{gall: gall} do
    groups = Import.gall_facts(gall.id)

    assert %{inducer: [], hosts: [], traits: [], range: [], aliases: []} = groups
    assert length(groups.traits_missing) == 10
  end
end
