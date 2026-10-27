defmodule Gallformers.CatalogMigration.TestSeedsTest do
  @moduledoc """
  The test database's new tables as the catalog migration made them from
  the old-table seeds (`priv/repo/test_seeds.sql`), with the test's own
  curated decisions (`test/support/fixtures/catalog_migration/`):
  `make test-db` and CI run `mix gallformers.catalog.migrate --curated`
  after loading the seeds. Page tests read this converted data, so this
  checks the cases they rely on. Nothing here runs the migration.
  """
  use Gallformers.DataCase, async: true

  # Reading the seeds, converted, is what this module tests.
  # credo:disable-for-this-file Gallformers.Credo.Checks.TestQuality.TestsOwnTheirData

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Facts.AliasFact
  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.Vocab.GenerationValue
  alias Gallformers.Sources
  alias Gallformers.Taxa

  # Each seed gall's Inducer link: {accepted name, rank}, or nil.
  @inducers %{
    100 => nil,
    101 => nil,
    102 => nil,
    103 => nil,
    200 => {"Andricus crystallinus", :species},
    201 => {"Cynips quercus", :species},
    300 => {"Andricus seedii", :species},
    301 => {"Andricus seedii", :species},
    302 => {"Neuroterus seedatorius", :species},
    303 => {"Neuroterus seedatorius", :species},
    304 => {"Andricus", :genus},
    305 => {"Cynips seedhostus", :species}
  }

  @gallformers_source 58
  @citing_source 59

  defp inducer(gall_id), do: Taxa.get_by_legacy_id(:gall_inducer, gall_id)

  defp generation(%Gall{generation_value_id: nil}), do: nil

  defp generation(%Gall{generation_value_id: id}),
    do: Repo.get!(GenerationValue, id).value

  test "every seed gall is a Gall keeping its ID and name, linked to its Inducer" do
    old =
      Repo.all(from(s in "species", where: s.taxoncode == "gall", select: {s.id, s.name}))

    assert Enum.sort(Enum.map(old, &elem(&1, 0))) == Enum.sort(Map.keys(@inducers))

    for {id, name} <- old do
      assert %Gall{} = gall = Catalog.get_gall(id), "seed gall #{id} is not a Gall"
      assert Gall.display_name(gall) == name

      link =
        case inducer(id) do
          nil -> nil
          taxon -> {Taxa.accepted_name(taxon), taxon.rank}
        end

      assert link == @inducers[id], "seed gall #{id} #{name}"
    end
  end

  test "the agamic/sexgen pair shares one Inducer" do
    assert inducer(300).id == inducer(301).id
    assert generation(Catalog.get_gall!(300)) == "agamic"
    assert generation(Catalog.get_gall!(301)) == "sexual"
  end

  test "the gall forms share one Inducer, the form kept in the name" do
    assert inducer(302).id == inducer(303).id
    assert generation(Catalog.get_gall!(302)) == "agamic"
    assert generation(Catalog.get_gall!(303)) == "sexual"

    assert Gall.display_name(Catalog.get_gall!(302)) ==
             "Neuroterus seedatorius (australis) (agamic)"
  end

  describe "Gall names (86e7)" do
    test "each Gall with an Inducer has today's name as its derived name, with no override" do
      for id <- [200, 201, 300, 301, 302, 303, 304, 305] do
        gall = Catalog.get_gall!(id)
        old = Repo.one!(from(s in "species", where: s.id == ^id, select: s.name))

        assert {gall.name, gall.name_override} == {old, nil}, "seed gall #{id}"
        assert Catalog.derived_name(id) == {:ok, old}, "seed gall #{id}"
      end
    end

    test "the parts are read from the names" do
      assert Catalog.get_gall!(302).form_label == "australis"
      assert Catalog.get_gall!(304).descriptor == "n-densiflorus-seed-gall"
      assert Catalog.get_gall!(305).host_qualifier_taxon_id == 10

      for id <- [300, 301, 303, 305] do
        assert %Gall{form_label: nil, descriptor: nil} = Catalog.get_gall!(id)
      end
    end

    test "a Gall with no Inducer keeps today's name as its stored name" do
      for id <- [100, 101, 102, 103] do
        gall = Catalog.get_gall!(id)
        old = Repo.one!(from(s in "species", where: s.id == ^id, select: s.name))

        assert {gall.name, gall.name_override} == {old, nil}
        assert Catalog.derived_name(id) == {:error, :no_base}
      end
    end
  end

  test "the undescribed gall's Inducer is its genus, the species' genus" do
    genus = inducer(304)

    assert {Taxa.accepted_name(genus), genus.rank} == {"Andricus", :genus}
    assert inducer(300).parent_id == genus.id
  end

  test "the Gallformers note is a note document holding its text" do
    assert [note] = Sources.list_gall_notes(300)
    assert {note.kind, note.source_id} == {:note, @gallformers_source}

    assert [item] = Sources.list_document_items(note)
    assert item.text =~ "seed note"
  end

  test "another Source's citation is a legacy citation" do
    assert [citation] = Catalog.list_legacy_citations(300)
    assert citation.source_id == @citing_source
    assert citation.description =~ "seed citation"
  end

  test "each Gall's default Source is its useasdefault row: a citation or its note" do
    assert Catalog.get_gall!(300).default_source_id == @citing_source
    assert Catalog.get_gall!(301).default_source_id == @gallformers_source
    assert Catalog.get_gall!(302).default_source_id == nil
  end

  test "the undescribed gall's former label and code are gall alias Facts of those kinds" do
    aliases =
      Repo.all(
        from(a in AliasFact, where: a.gall_id == 304, order_by: a.name, select: {a.name, a.kind})
      )

    assert aliases == [{"Andricus q-seed-old-label", :former_label}, {"q-seed-code", :code}]
    assert Taxa.resolve_name("Andricus q-seed-old-label") == :none
  end

  test "images carry their Gall or taxon" do
    images =
      Repo.all(
        from(i in "image",
          where: i.species_id in [300, 10],
          select: {i.species_id, i.gall_id, i.taxon_id}
        )
      )

    assert Enum.sort(images) == [{10, nil, 10}, {300, 300, nil}]
  end

  test "a common alias is a gall alias Fact, a scientific one a synonym of the Inducer" do
    assert [%AliasFact{name: "seed oak apple", kind: :common_name}] =
             Repo.all(from(a in AliasFact, where: a.gall_id == 300))

    synonyms =
      for %{status: :synonym, name: name} <- Taxa.get_taxon!(inducer(300).id).names, do: name

    assert synonyms == ["Callirhytis seedii"]
  end

  test "the host's common alias is a common name of its taxon, its scientific one a synonym" do
    assert Enum.map(Taxa.list_common_names(10), & &1.name) == ["tanoak"]
    assert Enum.map(Taxa.list_synonyms(10), & &1.name) == ["Lithocarpus densiflorus"]
  end

  test "the host genus's old description is its common name; the family's type is dropped" do
    genus = Taxa.get_by_legacy_id(:taxonomy, 41)
    family = Taxa.get_by_legacy_id(:taxonomy, 40)

    assert Enum.map(Taxa.list_common_names(genus), & &1.name) == ["Tanoaks"]
    assert Taxa.list_common_names(family) == []
  end

  test "the host is a plant in its genus and family, its native and introduced range by taxon" do
    host = Taxa.get_taxon!(10)

    assert {Taxa.accepted_name(host), host.kingdom} == {"Notholithocarpus densiflorus", "Plantae"}
    assert {host.datacomplete, host.abundance_id} == {true, 1}

    assert Enum.map(Taxa.ancestors(host), &{Taxa.accepted_name(&1), &1.rank}) == [
             {"Notholithocarpus", :genus},
             {"Fagaceae", :family}
           ]

    rows =
      Repo.all(
        from(hr in "host_range",
          join: p in "place",
          on: p.id == hr.place_id,
          where: hr.species_id == 10,
          select: {p.code, hr.distribution_type, hr.taxon_id}
        )
      )

    assert Enum.sort(rows) == [{"RO-B", "introduced", 10}, {"US-CA", "native", 10}]
  end

  test "the genus placeholder plant is a genus-level Host carrying its range rows" do
    genus = Taxa.get_by_legacy_id(:taxonomy, 41)

    assert %{hosts: hosts} = Catalog.gall_summary(304)
    assert %{taxon_id: genus.id, name: "Notholithocarpus", rank: :genus} in hosts

    rows =
      Repo.all(
        from(hr in "host_range",
          join: p in "place",
          on: p.id == hr.place_id,
          where: hr.species_id == 11,
          select: {p.code, hr.precision, hr.taxon_id}
        )
      )

    assert rows == [{"MX", "country", genus.id}]
  end
end
