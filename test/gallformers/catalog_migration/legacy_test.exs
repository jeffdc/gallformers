defmodule Gallformers.CatalogMigration.LegacyTest do
  @moduledoc """
  The data migration's legacy data (`9449` Task 16): Inducer, Host and
  Trait Facts attributed to one undated "Gallformers legacy data" Source;
  record-level citations; Gallformers notes kept verbatim; images with a
  typed reference.

  Not async: the migration rebuilds every new table inside the sandbox, and
  the Gallformers Source is unique.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures, only: [source_fixture: 2, gallformers_source: 0, deny: 1]
  import Gallformers.OldModelFixtures

  alias Gallformers.Catalog
  alias Gallformers.CatalogMigration
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Facts
  alias Gallformers.Facts.Fact
  alias Gallformers.Sources
  alias Gallformers.Sources.Source
  alias Gallformers.Storage.Private
  alias Gallformers.Taxa

  setup do
    old = old_catalog_fixture()

    trait!(old.agamic, "color", "red")
    trait!(old.agamic, "plant_part", "stem")
    # Not in the contract's vocabulary: reported, not migrated.
    trait!(old.agamic, "color", "chartreuse")

    Repo.query!("UPDATE gall_traits SET detachable = 'detachable' WHERE species_id = $1", [
      old.agamic
    ])

    Repo.query!("UPDATE gall_traits SET detachable = 'unknown' WHERE species_id = $1", [
      old.sexgen
    ])

    %{old: old}
  end

  # Lenient: the seeds' stored ranges await curated decisions, which
  # `Gallformers.CatalogMigration.CuratedTest` covers (strict mode too).
  defp run! do
    assert {:ok, %Report{} = report} = CatalogMigration.run(actor: test_actor(), pending: :skip)
    report
  end

  defp legacy_source, do: Sources.get_source_by_title("Gallformers legacy data")

  defp summary_names(taxa), do: Enum.map(taxa, & &1.name)

  defp gall_facts(gall_id) do
    Repo.all(
      from(f in Fact,
        where:
          f.id in subquery(
            from(r in "relationship_facts",
              where: r.object_gall_id == ^gall_id,
              select: r.fact_id
            )
          ) or
            f.id in subquery(
              from(t in "trait_facts", where: t.gall_id == ^gall_id, select: t.fact_id)
            )
      )
    )
  end

  test "a migrated Gall has its Inducer, Hosts and Traits current, attributed to the undated legacy Source",
       ctx do
    report = run!()

    summary = Catalog.gall_summary(ctx.old.agamic)
    assert summary_names(summary.inducers) == ["Andricus fixtura"]
    # The placeholder "Fixturquercus spp" became a genus-level Host.
    assert summary_names(summary.hosts) == ["Fixturquercus", "Fixturquercus alba"]

    assert summary.traits == %{
             "color" => ["red"],
             "detachable" => ["detachable"],
             "plant_part" => ["stem"]
           }

    legacy = legacy_source()
    assert %Source{kind: :database, authored_date: nil} = legacy

    facts = gall_facts(ctx.old.agamic)
    assert length(facts) == 6

    for fact <- facts do
      assert fact.standing == :current
      assert [attribution] = Facts.list_attributions(fact)

      assert {attribution.source_id, attribution.stance, attribution.stated_on} ==
               {legacy.id, :confirm, nil}
    end

    # Undescribed and placeholder Galls get their genus- or family-level Inducer.
    assert summary_names(Catalog.gall_summary(ctx.old.in_family).inducers) == ["Cynipidae"]

    # "unknown" detachability states nothing; an unmapped value is reported.
    assert Catalog.gall_summary(ctx.old.sexgen).traits == %{}

    assert for(
             %{category: "Trait value not in the vocabulary", detail: d} <- report.problems,
             do: d
           ) == [~s[color: "chartreuse" on 1 gall(s)]]

    assert Enum.reject(report.reconciliation, &Report.balanced?/1) == []
  end

  test "the ID tool's lookup table is rebuilt at the end, one row per Gall, no job enqueued",
       ctx do
    Oban.Testing.with_testing_mode(:manual, fn ->
      report = run!()

      refute Repo.exists?(
               from(j in Oban.Job,
                 where: j.worker == "Gallformers.Catalog.ReadModels.GallIndexWorker"
               )
             )

      gall_ids = Repo.all(from(g in Catalog.Gall, select: g.id))
      rows = Repo.all(from(r in "gall_index", select: {r.gall_id, r.host_taxon_ids}))

      assert Enum.sort(Enum.map(rows, &elem(&1, 0))) == Enum.sort(gall_ids)

      hosts = Map.new(rows)[ctx.old.agamic]
      assert ctx.old.alba in hosts
      assert length(hosts) == 2

      assert %{old: n, new: n} =
               Enum.find(report.reconciliation, &(&1.label =~ "lookup table"))
    end)
  end

  test "a real Source's later denial withdraws a legacy Host", ctx do
    run!()

    revision = source_fixture("Revision", "1990")

    {:ok, %{fact: fact}} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: ctx.old.alba, object_gall_id: ctx.old.agamic},
        deny(revision)
      )

    assert fact.standing == :withdrawn
    assert summary_names(Catalog.gall_summary(ctx.old.agamic).hosts) == ["Fixturquercus"]
  end

  test "Gallformers notes keep their text exactly, as undated note documents", ctx do
    gallformers = gallformers_source()

    note =
      "Closely resembles <i>A. foo</i>.\n\n  Observed in Illinois — July; see https://inaturalist.org/x  "

    species_source!(ctx.old.agamic, gallformers.id, note, useasdefault: true)

    report = run!()

    assert [document] = Sources.list_gall_notes(ctx.old.agamic)

    assert {document.kind, document.source_id, document.version_date} ==
             {:note, gallformers.id, nil}

    assert [%{ref: "#/texts/0", text: ^note}] = Sources.list_document_items(document)
    assert Private.get(document.s3_key) == {:ok, note}

    # A note is not a citation.
    assert Catalog.list_legacy_citations(ctx.old.agamic) == []
    assert Enum.reject(report.reconciliation, &Report.balanced?/1) == []
  end

  test "other Sources' record-level citations become legacy citations, not Facts", ctx do
    weld = source_fixture("Weld", "1959")

    species_source!(ctx.old.agamic, weld.id, "Galls on the stems.",
      useasdefault: true,
      externallink: "https://example.com/weld#p12"
    )

    run!()

    assert [citation] = Catalog.list_legacy_citations(ctx.old.agamic)

    assert {citation.source_id, citation.description, citation.useasdefault,
            citation.externallink} ==
             {weld.id, "Galls on the stems.", true, "https://example.com/weld#p12"}

    refute Repo.exists?(from(a in "attributions", where: a.source_id == ^weld.id))
  end

  test "each Gall's default Source is today's useasdefault row, its note or a citation", ctx do
    gallformers = gallformers_source()
    weld = source_fixture("Weld", "1959")
    felt = source_fixture("Felt", "1940")

    species_source!(ctx.old.agamic, gallformers.id, "The note.", useasdefault: true)
    species_source!(ctx.old.agamic, weld.id, "Weld on the agamic gall.")
    # Two defaults: the lowest species_source ID is kept.
    species_source!(ctx.old.sexgen, felt.id, "Felt on the sexual gall.", useasdefault: true)
    species_source!(ctx.old.sexgen, weld.id, "Weld on the sexual gall.", useasdefault: true)
    # A plant's has no Gall to go to.
    species_source!(ctx.old.alba, weld.id, "Weld on the oak.", useasdefault: true)

    report = run!()

    assert Catalog.get_gall!(ctx.old.agamic).default_source_id == gallformers.id
    assert Catalog.get_gall!(ctx.old.sexgen).default_source_id == felt.id
    assert Catalog.get_gall!(ctx.old.in_family).default_source_id == nil

    defaults = Enum.find(report.reconciliation, &(&1.label =~ "Default Sources"))
    assert Report.balanced?(defaults) == true
    assert {"on species that are not Galls", 1} in defaults.accounted

    assert {"further defaults of a Gall (the lowest species_source ID kept)", 1} in defaults.accounted

    # With the seeds' Galls 300 and 301, whose Source 58 is no longer the
    # Gallformers Source here (`gallformers_source/0` takes its place).
    assert defaults.new == 4
    assert {"Galls whose default Source is their Gallformers note", 1} in report.counts

    assert [detail] =
             for(
               %{category: "Gall with several default Sources", detail: d} <- report.problems,
               do: d
             )

    assert detail =~ "#{ctx.old.sexgen}"
  end

  test "image paths are unchanged and each image gets its typed reference", ctx do
    gall_image = image!(ctx.old.agamic, "gall/880201/original_a.jpg")
    plant_image = image!(ctx.old.alba, "gall/880101/original_b.jpg")
    placeholder_image = image!(ctx.old.spp, "gall/880103/original_c.jpg")

    run!()

    genus = Taxa.get_by_legacy_id(:taxonomy, ctx.old.quercus)

    rows =
      Repo.all(
        from(i in "image",
          where: i.id in ^[gall_image, plant_image, placeholder_image],
          select: {i.id, i.path, i.species_id, i.gall_id, i.taxon_id}
        )
      )

    assert Enum.sort(rows) ==
             Enum.sort([
               {gall_image, "gall/880201/original_a.jpg", ctx.old.agamic, ctx.old.agamic, nil},
               {plant_image, "gall/880101/original_b.jpg", ctx.old.alba, nil, ctx.old.alba},
               {placeholder_image, "gall/880103/original_c.jpg", ctx.old.spp, nil, genus.id}
             ])
  end

  test "running twice keeps one legacy Source and the same Facts", ctx do
    run!()
    first = for f <- gall_facts(ctx.old.agamic), do: f.kind

    run!()

    assert Repo.aggregate(from(s in Source, where: s.title == "Gallformers legacy data"), :count) ==
             1

    assert Enum.sort(for f <- gall_facts(ctx.old.agamic), do: f.kind) == Enum.sort(first)
  end
end
