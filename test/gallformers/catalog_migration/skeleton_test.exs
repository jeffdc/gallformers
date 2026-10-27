defmodule Gallformers.CatalogMigration.SkeletonTest do
  @moduledoc """
  The data migration's skeleton (`9449` Task 15): taxa, plants, Inducers and
  Galls rebuilt from today's tables, on a small fixture of old-model rows
  (`Gallformers.OldModelFixtures`) beside the seeds.

  Not async: the migration rebuilds every new table inside the sandbox and
  loads the vocabularies.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.OldModelFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.CatalogMigration
  alias Gallformers.CatalogMigration.NameSuffixes
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon

  setup do
    %{old: old_catalog_fixture()}
  end

  # Lenient: the seeds' stored ranges await curated decisions, which
  # `Gallformers.CatalogMigration.CuratedTest` covers (strict mode too).
  defp run!(opts \\ []) do
    opts = opts |> Keyword.put_new(:actor, test_actor()) |> Keyword.put_new(:pending, :skip)
    assert {:ok, %Report{} = report} = CatalogMigration.run(opts)

    report
  end

  defp taxon_named(name, rank) do
    assert {:ok, %Taxon{} = taxon} = Taxa.resolve_name(name, rank: rank)
    taxon
  end

  defp parent_name(%Taxon{parent_id: nil}), do: nil
  defp parent_name(%Taxon{parent_id: id}), do: Taxa.accepted_name(id)

  defp generation(%Gall{generation_value_id: nil}), do: nil

  defp generation(%Gall{generation_value_id: id}),
    do: Repo.get!(Catalog.Vocab.GenerationValue, id).value

  defp inducer(gall_id) do
    case Taxa.get_by_legacy_id(:gall_inducer, gall_id) do
      nil -> nil
      taxon -> {Taxa.accepted_name(taxon), taxon.rank}
    end
  end

  test "counts reconcile", ctx do
    report = run!()

    unbalanced = for entry <- report.reconciliation, not Report.balanced?(entry), do: entry
    assert unbalanced == []

    galls = Enum.find(report.reconciliation, &(&1.label == "Galls"))
    old_galls = Repo.one!(from(s in "species", where: s.taxoncode == "gall", select: count()))
    assert {galls.old, galls.new} == {old_galls, old_galls}
    assert Repo.aggregate(Gall, :count) == old_galls
    assert %Gall{id: id} = Catalog.get_gall(ctx.old.agamic)
    assert id == ctx.old.agamic
  end

  test "an agamic/sexgen pair yields one Inducer and two Galls", ctx do
    run!()

    andricus = taxon_named("Andricus", :genus)
    fixtura = taxon_named("Andricus fixtura", :species)
    assert fixtura.parent_id == andricus.id
    assert fixtura.kingdom == "Animalia"
    assert fixtura.origin == :curated

    assert Taxa.get_by_legacy_id(:gall_inducer, ctx.old.agamic).id == fixtura.id
    assert Taxa.get_by_legacy_id(:gall_inducer, ctx.old.sexgen).id == fixtura.id

    agamic = Catalog.get_gall!(ctx.old.agamic)
    sexgen = Catalog.get_gall!(ctx.old.sexgen)

    assert {agamic.name, agamic.name_override, generation(agamic)} ==
             {"Andricus fixtura (agamic)", nil, "agamic"}

    assert {sexgen.name, sexgen.name_override, generation(sexgen)} ==
             {"Andricus fixtura (sexgen)", nil, "sexual"}

    assert {agamic.gallformers_code, agamic.datacomplete} == {"fixtura-agamic", false}
    assert {sexgen.gallformers_code, sexgen.datacomplete} == {nil, true}
  end

  test "undescribed Galls link at the genus or the family; Unknown (Unknown) gets none", ctx do
    report = run!()

    assert inducer(ctx.old.undescribed) == {"Andricus", :genus}
    assert inducer(ctx.old.in_family) == {"Cynipidae", :family}
    assert inducer(ctx.old.no_inducer) == nil

    assert Gall.display_name(Catalog.get_gall!(ctx.old.in_family)) ==
             "Unknown (Cynipidae) q-alba-fixture-bead"

    assert Gall.display_name(Catalog.get_gall!(ctx.old.no_inducer)) ==
             "Unknown (Unknown) fixture-mystery"

    # No taxon for the placeholders themselves.
    assert Taxa.resolve_name("Unknown") == :none
    refute Enum.any?(report.unparsed, &(&1.gall_id == ctx.old.no_inducer))
  end

  test "an unknown suffix is reported, not guessed", ctx do
    report = run!()

    assert [%{gall_id: id, reason: "unknown suffix (pacificus)"}] =
             Enum.filter(report.unparsed, &(&1.gall_id == ctx.old.unknown_suffix))

    assert id == ctx.old.unknown_suffix
    assert inducer(ctx.old.unknown_suffix) == nil
    assert Taxa.resolve_name("Andricus fixturaria") == :none

    gall = Catalog.get_gall!(ctx.old.unknown_suffix)
    assert Gall.display_name(gall) == "Andricus fixturaria (pacificus)"
  end

  test "curated rows apply, and those needing review are reported", ctx do
    {:ok, shipped} = File.read(NameSuffixes.default_path())
    path = Path.join(System.tmp_dir!(), "name_suffixes_skeleton_test.csv")

    File.write!(
      path,
      shipped <>
        "gall,#{ctx.old.unknown_suffix},Andricus fixturaria (pacificus),Andricus fixturaria,," <>
        "true,Historical / infraspecific name,curator checks for a cryptic species\n"
    )

    on_exit(fn -> File.rm(path) end)

    report = run!(name_suffixes: path)

    assert inducer(ctx.old.unknown_suffix) == {"Andricus fixturaria", :species}

    assert [%{reason: "curator checks for a cryptic species"}] =
             Enum.filter(report.needs_review, &(&1.gall_id == ctx.old.unknown_suffix))

    assert Catalog.get_gall!(ctx.old.unknown_suffix).name_override ==
             "Andricus fixturaria (pacificus)"
  end

  defp names(gall_id) do
    g = Catalog.get_gall!(gall_id)
    {g.name, g.name_override}
  end

  defp name_parts(gall_id) do
    g = Catalog.get_gall!(gall_id)
    {g.form_label, g.host_qualifier_taxon_id, g.descriptor}
  end

  defp worksheet_row(report, gall_id),
    do: Enum.find(report.curation["gall_names"].rows, &(&1["gall_id"] == gall_id))

  # The shipped mapping plus curated `rows` ({id, name, inducer, generation, category}).
  defp with_curated_rows(rows) do
    {:ok, shipped} = File.read(NameSuffixes.default_path())

    path =
      Path.join(
        System.tmp_dir!(),
        "name_suffixes_names_#{System.unique_integer([:positive])}.csv"
      )

    extra =
      for {id, name, inducer, generation, category} <- rows,
          do: "gall,#{id},\"#{name}\",#{inducer},#{generation},false,#{category},test row\n"

    File.write!(path, [shipped | extra])
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "Gall names (86e7 §4)" do
    test "names are derived from their parts; today's names need no override", ctx do
      run!()

      assert names(ctx.old.agamic) == {"Andricus fixtura (agamic)", nil}
      assert names(ctx.old.undescribed) == {"Andricus q-alba-fixture-gall", nil}
      assert name_parts(ctx.old.undescribed) == {nil, nil, "q-alba-fixture-gall"}
      assert names(ctx.old.in_family) == {"Unknown (Cynipidae) q-alba-fixture-bead", nil}
      assert name_parts(ctx.old.in_family) == {nil, nil, "q-alba-fixture-bead"}
      assert names(ctx.old.no_inducer) == {"Unknown (Unknown) fixture-mystery", nil}
      assert name_parts(ctx.old.no_inducer) == {nil, nil, "fixture-mystery"}
    end

    test "a name with no derivation is stored as it is and listed", ctx do
      report = run!()

      assert names(ctx.old.unknown_suffix) == {"Andricus fixturaria (pacificus)", nil}

      assert %{"category" => "not derivable", "derived" => nil} =
               worksheet_row(report, ctx.old.unknown_suffix)
    end

    test "a seasonal generation reads \"(spring generation)\", as today's names do" do
      gall!(880_299, "Andricus fixturspring (spring generation)", 33)

      run!()

      assert names(880_299) == {"Andricus fixturspring (spring generation)", nil}
    end

    test "a name its parts do not reproduce keeps today's name as its override" do
      gall!(880_207, "Andricus fixturvern (summer and autumn generations)", 33)

      report = run!()

      assert names(880_207) ==
               {"Andricus fixturvern (summer generation)",
                "Andricus fixturvern (summer and autumn generations)"}

      assert %{
               "category" => "generation written otherwise",
               "derived" => "Andricus fixturvern (summer generation)",
               "name" => "Andricus fixturvern (summer and autumn generations)"
             } = worksheet_row(report, 880_207)
    end

    test "curated form labels and Host qualifiers become name parts", ctx do
      gall!(880_208, "Andricus fixturform (australis) (agamic)", 33)
      gall!(880_209, "Andricus fixturhost (on Fixturquercus alba)", 33)
      gall!(880_210, "Andricus fixturlost (on Fixturquercus nowhere)", 33)
      gall!(880_211, "Andricus fixturtwo (one) (two)", 33)
      gall!(880_212, "Andricus fixturauthor (Fixture, 1906)", 33)

      path =
        with_curated_rows([
          {880_208, "Andricus fixturform (australis) (agamic)", "Andricus fixturform", "agamic",
           "Gall form"},
          {880_209, "Andricus fixturhost (on Fixturquercus alba)", "Andricus fixturhost", "",
           "Host-scoped"},
          {880_210, "Andricus fixturlost (on Fixturquercus nowhere)", "Andricus fixturlost", "",
           "Host-scoped"},
          {880_211, "Andricus fixturtwo (one) (two)", "Andricus fixturtwo", "", "Gall form"},
          {880_212, "Andricus fixturauthor (Fixture, 1906)", "Andricus fixturauthor", "",
           "Name text"}
        ])

      report = run!(name_suffixes: path)

      assert names(880_208) == {"Andricus fixturform (australis) (agamic)", nil}
      assert name_parts(880_208) == {"australis", nil, nil}

      assert names(880_209) == {"Andricus fixturhost (on Fixturquercus alba)", nil}
      assert name_parts(880_209) == {nil, ctx.old.alba, nil}

      assert names(880_210) ==
               {"Andricus fixturlost", "Andricus fixturlost (on Fixturquercus nowhere)"}

      assert %{"category" => "Host qualifier not resolved"} = worksheet_row(report, 880_210)

      assert names(880_211) == {"Andricus fixturtwo (one)", "Andricus fixturtwo (one) (two)"}
      assert name_parts(880_211) == {"one", nil, nil}

      assert %{"category" => "several form labels or Host qualifiers"} =
               worksheet_row(report, 880_211)

      assert names(880_212) == {"Andricus fixturauthor", "Andricus fixturauthor (Fixture, 1906)"}

      assert %{"category" => "parenthetical not read as a name part", "reason" => reason} =
               worksheet_row(report, 880_212)

      assert reason =~ "(Fixture, 1906)"
    end

    test "the report reconciles the names and lists every override", ctx do
      gall!(880_207, "Andricus fixturvern (summer and autumn generations)", 33)

      report = run!()

      entry = Enum.find(report.reconciliation, &(&1.label == "Gall names (today's names shown)"))
      assert Report.balanced?(entry) == true
      assert entry.old == Repo.aggregate(Gall, :count)

      overridden = Repo.all(from(g in Gall, where: not is_nil(g.name_override), select: g.id))
      listed = Enum.map(report.curation["gall_names"].rows, & &1["gall_id"])

      assert Enum.sort(overridden) -- listed == []
      assert ctx.old.unknown_suffix in listed
      refute ctx.old.agamic in listed

      assert {"kept as an override (the derived name differs)", length(overridden)} in entry.accounted

      for gall <- Repo.all(Gall) do
        old = Repo.one!(from(s in "species", where: s.id == ^gall.id, select: s.name))
        assert Gall.display_name(gall) == String.trim(old)
      end
    end
  end

  test "plants keep their IDs as POWO taxa in Plantae, under their genus or section", ctx do
    run!()

    alba = Taxa.get_taxon!(ctx.old.alba)
    rubra = Taxa.get_taxon!(ctx.old.rubra)

    assert {Taxa.accepted_name(alba), alba.rank, alba.origin, alba.kingdom} ==
             {"Fixturquercus alba", :species, :powo, "Plantae"}

    assert parent_name(alba) == "Fixturquercus"
    assert parent_name(rubra) == "Fixturlobatae"

    assert Enum.map(Taxa.ancestors(rubra), &{Taxa.accepted_name(&1), &1.rank}) == [
             {"Fixturlobatae", :section},
             {"Fixturquercus", :genus},
             {"Fixturaceae", :family}
           ]

    refute Taxa.get_taxon(ctx.old.spp)
  end

  test "plants keep their data-complete flag and abundance, reconciled in the report", ctx do
    report = run!()

    alba = Taxa.get_taxon!(ctx.old.alba)
    rubra = Taxa.get_taxon!(ctx.old.rubra)

    assert {alba.datacomplete, alba.abundance_id} == {true, 2}
    assert {rubra.datacomplete, rubra.abundance_id} == {false, nil}

    for label <- ["Data-complete plants", "Plants with an abundance"] do
      assert %{} = entry = Enum.find(report.reconciliation, &(&1.label == label)), label
      assert Report.balanced?(entry), label
      assert entry.new >= 1, label
    end
  end

  test "a placeholder's range rows land on its genus", ctx do
    run!()

    genus = taxon_named("Fixturquercus", :genus)

    rows =
      Repo.all(
        from(hr in "host_range",
          where: hr.species_id in ^[ctx.old.alba, ctx.old.spp],
          select: {hr.species_id, hr.taxon_id}
        )
      )

    assert Enum.sort(rows) ==
             Enum.sort([
               {ctx.old.alba, ctx.old.alba},
               {ctx.old.spp, genus.id},
               {ctx.old.spp, genus.id}
             ])
  end

  test "a genus placeholder's species ID maps to its genus, for its old /host/:id URL", ctx do
    report = run!()

    genus = taxon_named("Fixturquercus", :genus)
    assert Taxa.get_by_legacy_id(:genus_placeholder, ctx.old.spp).id == genus.id
    assert Taxa.get_by_legacy_id(:genus_placeholder, ctx.old.alba) == nil

    entry =
      Enum.find(
        report.reconciliation,
        &(&1.label == "Genus placeholder URLs (→ their genus page)")
      )

    # Every placeholder here has a genus: all of them are mapped.
    assert entry.new == entry.old
    assert entry.new >= 1
  end

  test "the crosswalk maps old taxonomy IDs", ctx do
    run!()

    assert %Taxon{rank: :family, kingdom: "Plantae"} =
             family = Taxa.get_by_legacy_id(:taxonomy, ctx.old.fagaceae)

    assert Taxa.accepted_name(family) == "Fixturaceae"

    cynipidae = Taxa.get_by_legacy_id(:taxonomy, 30)
    assert {Taxa.accepted_name(cynipidae), cynipidae.kingdom} == {"Cynipidae", "Animalia"}
    assert Taxa.get_by_legacy_id(:taxonomy, 32).rank == :tribe

    # A placeholder genus maps to its family; the Unknown family to nothing.
    assert Taxa.get_by_legacy_id(:taxonomy, 35).id == cynipidae.id
    assert Taxa.get_by_legacy_id(:taxonomy, ctx.old.unknown_family) == nil
    assert Taxa.get_by_legacy_id(:taxonomy, ctx.old.unknown_genus) == nil
  end

  test "descriptions below family become common names; family types and placeholders' do not" do
    family = taxonomy!(880_060, "Fixturulmaceae", "family", description: "Plant")

    genus =
      taxonomy!(880_061, "Fixturulmus", "genus", parent: family, description: " Fixture elms ")

    section =
      taxonomy!(880_062, "Fixturulmus sect. Fixturae", "section",
        parent: genus,
        description: "Fixture field elms"
      )

    blank = taxonomy!(880_063, "Fixturceltis", "genus", parent: family, description: "  ")

    tribe =
      taxonomy!(880_064, "Fixturini", "intermediate",
        rank: "Tribe",
        parent: 31,
        description: "Fixture gall wasps"
      )

    taxonomy!(880_065, "Unknown (Fixturini)", "genus",
      parent: 30,
      placeholder: true,
      description: "Placeholder genus for undescribed species"
    )

    report = run!()

    names = fn old_id ->
      :taxonomy
      |> Taxa.get_by_legacy_id(old_id)
      |> Taxa.list_common_names()
      |> Enum.map(& &1.name)
    end

    assert names.(genus) == ["Fixture elms"]
    assert names.(section) == ["Fixture field elms"]
    assert names.(tribe) == ["Fixture gall wasps"]
    assert names.(blank) == []
    assert names.(family) == []
    # The placeholder's crosswalk entry is its family, which gets no name from it.
    assert names.(30) == []

    entry =
      Enum.find(
        report.reconciliation,
        &(&1.label == "Taxonomy descriptions below family (→ common names)")
      )

    assert entry.old == entry.new + Enum.sum(Enum.map(entry.accounted, &elem(&1, 1)))
    assert entry.new >= 3

    assert {"placeholder genera (no taxon)", placeholders} =
             List.keyfind(entry.accounted, "placeholder genera (no taxon)", 0)

    assert placeholders >= 1
  end

  test "species rows that are neither galls nor plants are reported, not migrated" do
    Repo.insert_all("species", [
      %{
        id: 880_301,
        name: "Fixtura incerta",
        taxoncode: "undetermined",
        inserted_at: ~U[2026-01-01 00:00:00Z],
        updated_at: ~U[2026-01-01 00:00:00Z]
      }
    ])

    report = run!()

    assert ["880301 Fixtura incerta (undetermined)"] =
             for(
               %{category: "species row neither gall nor plant (not migrated)", detail: d} <-
                 report.problems,
               do: d
             )

    assert Taxa.get_taxon(880_301) == nil
    assert Catalog.get_gall(880_301) == nil
  end

  test "taxa sharing an accepted name, rank and kingdom are reported" do
    taxonomy!(880_030, "Fixturidae", "family", description: "Midge")
    taxonomy!(880_031, "Fixturidae", "family", description: "Midge")

    report = run!()

    assert [%{name: "Fixturidae", rank: :family, kingdom: "Animalia", taxon_ids: [_, _]}] =
             Enum.filter(report.duplicates, &(&1.name == "Fixturidae"))
  end

  test "the shared ID sequence ends above every ID used" do
    run!()

    %{rows: [[next]]} = Repo.query!("SELECT nextval('entity_id_seq')")

    for table <- ["species", "galls", "taxa"] do
      %{rows: [[max]]} = Repo.query!("SELECT COALESCE(MAX(id), 0) FROM #{table}")
      assert next > max, "entity_id_seq is not above #{table}"
    end
  end

  test "running twice gives the same result" do
    run!()
    first = snapshot()

    run!()
    assert snapshot() == first
  end

  test "the report prints", ctx do
    text = run!() |> Report.format()

    assert text =~ "Galls"
    assert text =~ "#{ctx.old.unknown_suffix}"
    assert text =~ "unknown suffix (pacificus)"
  end

  # Everything by stable keys (names, legacy and kept IDs), not new IDs.
  defp snapshot do
    %{
      taxa:
        Taxon
        |> Repo.all()
        |> Enum.map(fn t ->
          {Taxa.accepted_name(t), t.rank, t.kingdom, t.origin, parent_name(t),
           if(Repo.exists?(from(s in "species", where: s.id == ^t.id)), do: t.id)}
        end)
        |> Enum.sort(),
      galls:
        Gall
        |> Repo.all()
        |> Enum.map(&{&1.id, &1.name, &1.name_override, generation(&1), &1.gallformers_code})
        |> Enum.sort(),
      legacy:
        from(l in Taxa.LegacyId, select: {l.kind, l.legacy_id, l.taxon_id})
        |> Repo.all()
        |> Enum.map(fn {kind, id, taxon_id} -> {kind, id, Taxa.accepted_name(taxon_id)} end)
        |> Enum.sort(),
      host_range:
        from(hr in "host_range", select: {hr.species_id, hr.place_id, hr.taxon_id})
        |> Repo.all()
        |> Enum.map(fn {s, p, t} -> {s, p, t && Taxa.accepted_name(t)} end)
        |> Enum.sort()
    }
  end
end
