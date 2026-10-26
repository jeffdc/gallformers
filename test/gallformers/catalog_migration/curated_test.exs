defmodule Gallformers.CatalogMigration.CuratedTest do
  @moduledoc """
  The data migration's curated inputs (`9449` Task 17): non-galls, stored
  gall ranges, aliases sorted by meaning and key couplets, each reported
  for curation and applied from a decision file in
  `priv/catalog_migration/`. A strict run (the default, and production's)
  stops on any row that needs a decision and has none; a lenient run
  (`pending: :skip`) skips and reports them.

  Not async: the migration rebuilds every new table inside the sandbox, and
  the Gallformers Source is unique.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures, only: [gallformers_source: 0]
  import Gallformers.OldModelFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.CatalogMigration
  alias Gallformers.CatalogMigration.Curated
  alias Gallformers.CatalogMigration.Kingdoms
  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.CatalogMigration.TaxonMerges
  alias Gallformers.Import
  alias Gallformers.Taxa

  @files %{
    non_galls: {"non_galls.csv", "gall_id,name,decision,note"},
    range_decisions: {"range_decisions.csv", "gall_id,cause,decision,note"},
    aliases: {"aliases.csv", "owner,owner_id,alias_id,name,type,decision,target,note"},
    keys: {"keys.csv", "key,couplet,lead,species_id,decision,target_gall_id,note"},
    taxon_merges: {"taxon_merges.csv", "old_taxonomy_id,into_old_taxonomy_id,note"},
    kingdoms: {"kingdoms.csv", "old_taxonomy_id,kingdom,note"}
  }

  # The seeds' Gall 101 has an introduced-only host region outside its
  # stored range; every run here decides it.
  @seed_ranges ["101,introduced,ignore,"]

  setup do
    dir = Path.join(System.tmp_dir!(), "curated_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    ctx = %{old: old_catalog_fixture(), dir: dir}
    curated!(ctx, :range_decisions, @seed_ranges)

    for input <- [:non_galls, :aliases, :keys, :taxon_merges, :kingdoms],
        do: curated!(ctx, input, [])

    ctx
  end

  defp curated!(ctx, input, rows) do
    {file, header} = Map.fetch!(@files, input)
    File.write!(Path.join(ctx.dir, file), Enum.join([header | rows], "\n") <> "\n")
  end

  defp run(ctx, opts \\ []) do
    paths = for {input, {file, _header}} <- @files, do: {input, Path.join(ctx.dir, file)}
    CatalogMigration.run([actor: test_actor()] ++ paths ++ opts)
  end

  defp run!(ctx, opts \\ []) do
    assert {:ok, %Report{} = report} = run(ctx, opts)
    report
  end

  defp pending(report, input), do: for(%{input: ^input, key: key} <- report.pending, do: key)

  defp curation(report, name), do: Map.fetch!(report.curation, name).rows

  # -- non-galls ------------------------------------------------------------------

  describe "non-galls" do
    setup ctx do
      lookalike = gall!(880_250, "Fixturella lookalike", 33)
      trait!(lookalike, "form", "non-gall")
      gallhost!(lookalike, ctx.old.alba)
      %{lookalike: lookalike}
    end

    test "a non-gall without a decision stops a strict run, naming it, and writes nothing",
         ctx do
      assert {:error, {:pending_decisions, %Report{} = report}} = run(ctx)

      assert pending(report, "non_galls.csv") == [ctx.lookalike]
      assert [%{detail: detail}] = report.pending
      assert detail =~ "Fixturella lookalike"
      assert Catalog.get_gall(ctx.old.agamic) == nil
    end

    test "a lenient run migrates it and reports it pending", ctx do
      report = run!(ctx, pending: :skip)

      assert pending(report, "non_galls.csv") == [ctx.lookalike]
      assert %Gall{} = Catalog.get_gall(ctx.lookalike)
    end

    test "an excluded non-gall is not migrated; its ID is listed for redirects", ctx do
      curated!(ctx, :non_galls, ["#{ctx.lookalike},Fixturella lookalike,exclude,lookalike"])

      report = run!(ctx)

      assert report.pending == []
      assert Catalog.get_gall(ctx.lookalike) == nil
      assert %Gall{} = Catalog.get_gall(ctx.old.agamic)

      assert [%{"gall_id" => id, "decision" => "exclude"}] = curation(report, "non_galls")
      assert id == ctx.lookalike

      galls = Enum.find(report.reconciliation, &(&1.label == "Galls"))
      assert galls.old == galls.new + 1
      assert {"non-galls excluded (non_galls.csv)", 1} in galls.accounted
      assert Enum.reject(report.reconciliation, &Report.balanced?/1) == []
    end

    test "a non-gall marked migrate is migrated", ctx do
      curated!(ctx, :non_galls, ["#{ctx.lookalike},Fixturella lookalike,migrate,"])

      assert run!(ctx).pending == []
      assert %Gall{} = Catalog.get_gall(ctx.lookalike)
    end

    test "an unknown decision is an error naming the row", ctx do
      curated!(ctx, :non_galls, ["#{ctx.lookalike},Fixturella lookalike,maybe,"])

      assert {:error, message} = run(ctx)
      assert message =~ "non_galls.csv row 2"
    end
  end

  # -- stored gall ranges --------------------------------------------------------------

  describe "stored gall ranges" do
    setup ctx do
      place!(880_901, "US-TX", "Texas", "US")
      place!(880_902, "US-NY", "New York", "US")
      place!(880_903, "CA-ON", "Ontario", "CA")

      quercus = ctx.old.quercus
      host_a = plant!(880_150, "Fixturquercus texana", quercus)
      host_b = plant!(880_151, "Fixturquercus ontariensis", quercus)
      host_c = plant!(880_152, "Fixturquercus mexicana", quercus)
      host_d = plant!(880_153, "Fixturquercus recens", quercus)
      host_e = plant!(880_154, "Fixturquercus incognita", quercus)

      for code <- ["US-CA", "US-TX", "US-NY"], do: host_range!(host_a, code)
      host_range!(host_b, "CA-ON")
      host_range!(host_c, "MX-JAL")
      host_range!(host_c, "RO-B", distribution_type: "introduced")
      for code <- ["US-CA", "US-NY"], do: host_range!(host_d, code)
      # Re-imported from WCVP after the Gall's range was last confirmed.
      host_traits!(host_d, wcvp_synced_at: ~U[2026-05-01 00:00:00Z])

      gall = fn id, label, opts ->
        gall!(id, "Andricus q-fixture-#{label}", 33, [undescribed: true] ++ opts)
      end

      # A curator removed US-NY from a copy of the host union.
      removed = gall.(880_260, "removed", [])
      gallhost!(removed, host_a)
      for code <- ["US-CA", "US-TX"], do: gall_range!(removed, code)

      # A copy of host_a's range; host_b was linked later.
      later = gall.(880_261, "later", [])
      gallhost!(later, host_a)
      gallhost!(later, host_b, inserted_at: ~U[2026-03-01 00:00:00Z])
      for code <- ["US-CA", "US-TX", "US-NY"], do: gall_range!(later, code)

      # Confirmed in February; host_d's range widened in May.
      widened = gall.(880_262, "widened", range_computed_at: ~U[2026-02-01 00:00:00Z])
      gallhost!(widened, host_d)
      gall_range!(widened, "US-CA")

      # The copy took native ranges only.
      introduced = gall.(880_263, "introduced", [])
      gallhost!(introduced, host_c)
      gall_range!(introduced, "MX-JAL")

      # Stored at country precision, plus a place no Host has.
      outside = gall.(880_264, "outside", [])
      gallhost!(outside, host_a)
      gall_range!(outside, "US", "country")
      gall_range!(outside, "BS")

      # Its Host has no range data.
      none = gall.(880_265, "none", [])
      gallhost!(none, host_e)
      gall_range!(none, "US-CA")

      # The same as the union: nothing to keep.
      same = gall.(880_266, "same", [])
      gallhost!(same, host_a)
      gall_range!(same, "US", "country")

      %{
        g: %{
          removed: removed,
          later: later,
          widened: widened,
          introduced: introduced,
          outside: outside,
          none: none,
          same: same
        }
      }
    end

    defp range_rows(report, galls) do
      ids = Map.values(galls)

      for %{"gall_id" => id} = row <- curation(report, "ranges"), id in ids, into: %{} do
        {{id, row["cause"]}, {row["places"], row["suggested"]}}
      end
    end

    defp range_facts(gall_id) do
      Old.rows(
        """
        SELECT r.adjustment, p.code, a.source_id, a.statement_text, a.stated_on
        FROM range_facts r
        JOIN place p ON p.id = r.place_id
        JOIN attributions a ON a.fact_id = r.fact_id
        WHERE r.gall_id = $1 ORDER BY r.adjustment, p.code
        """,
        [gall_id]
      )
    end

    defp codes(:everywhere), do: :everywhere
    defp codes(places), do: Enum.map(places, & &1.code)

    test "each difference is classified, telling drift apart from curator removals", ctx do
      report = run!(ctx, pending: :skip)
      g = ctx.g

      assert range_rows(report, g) == %{
               {g.removed, "removed"} => {["US-NY"], "exclude"},
               # A copy whose union a later Host widened is drift, not an exclusion.
               {g.later, "host_added_later"} => {["CA-ON"], "ignore"},
               {g.widened, "host_range_widened"} => {["US-NY"], "ignore"},
               {g.introduced, "introduced"} => {["RO-B"], "ignore"},
               {g.outside, "outside"} => {["BS"], "include"},
               {g.none, "no_host_range"} => {["US-CA"], "only"}
             }

      assert Enum.sort(pending(report, "range_decisions.csv")) ==
               Enum.sort([
                 {g.removed, "removed"},
                 {g.later, "host_added_later"},
                 {g.widened, "host_range_widened"},
                 {g.introduced, "introduced"},
                 {g.outside, "outside"},
                 {g.none, "no_host_range"}
               ])

      # Pending rows make no Facts.
      assert range_facts(g.removed) == []

      # The seven above and the seeds' three.
      assert {"Galls with a stored range", 10} in report.counts
    end

    test "missing range decisions stop a strict run, naming the rows", ctx do
      assert {:error, {:pending_decisions, report}} = run(ctx)

      assert {ctx.g.removed, "removed"} in pending(report, "range_decisions.csv")
      assert [_ | _] = Enum.filter(report.pending, &(&1.detail =~ "Andricus q-fixture-removed"))
      assert Catalog.get_gall(ctx.g.removed) == nil
    end

    test "decisions become range Facts: exclusions by Gallformers, the rest by the legacy Source",
         ctx do
      gallformers = gallformers_source()
      g = ctx.g

      curated!(
        ctx,
        :range_decisions,
        @seed_ranges ++
          [
            "#{g.removed},removed,exclude,removed by a curator",
            "*,host_added_later,ignore,",
            "#{g.widened},host_range_widened,ignore,",
            "#{g.introduced},introduced,exclude,",
            "#{g.outside},outside,include,",
            "#{g.none},no_host_range,only,"
          ]
      )

      report = run!(ctx)
      assert report.pending == []
      legacy = Gallformers.Sources.get_source_by_title("Gallformers legacy data")

      assert [%{adjustment: "exclude", code: "US-NY", source_id: source_id, stated_on: nil} = f] =
               range_facts(g.removed)

      assert source_id == gallformers.id
      assert f.statement_text =~ "removed by a curator"
      assert codes(Catalog.potential_range(g.removed)) == ["US-CA", "US-TX"]

      assert codes(Catalog.potential_range(g.later)) == ["CA-ON", "US-CA", "US-NY", "US-TX"]
      assert range_facts(g.later) == []
      assert codes(Catalog.potential_range(g.introduced)) == ["MX-JAL"]

      assert [%{adjustment: "include", code: "BS", source_id: legacy_id}] = range_facts(g.outside)
      assert legacy_id == legacy.id
      assert "BS" in codes(Catalog.potential_range(g.outside))

      assert [%{adjustment: "only", code: "US-CA"}] = range_facts(g.none)
      assert codes(Catalog.potential_range(g.none)) == ["US-CA"]

      assert range_facts(g.same) == []

      # exclude US-NY, RO-B; include BS; only US-CA.
      assert %{old: 4, new: 4} = Enum.find(report.reconciliation, &(&1.label =~ "Range Facts"))
    end

    test "a written worksheet, its decisions filled in, is a decision file", ctx do
      gallformers_source()
      report = run!(ctx, pending: :skip)

      paths = Report.write_curation(report, Path.join(ctx.dir, "reports"))
      worksheet = Enum.find(paths, &String.ends_with?(&1, "ranges_report.csv"))

      [header | rows] =
        worksheet |> File.read!() |> NimbleCSV.RFC4180.parse_string(skip_headers: false)

      decision = Enum.find_index(header, &(&1 == "decision"))
      suggested = Enum.find_index(header, &(&1 == "suggested"))
      filled = for row <- rows, do: List.replace_at(row, decision, Enum.at(row, suggested))

      File.write!(
        Path.join(ctx.dir, "range_decisions.csv"),
        NimbleCSV.RFC4180.dump_to_iodata([header | filled])
      )

      assert run!(ctx).pending == []
      assert [%{adjustment: "exclude", code: "US-NY"}] = range_facts(ctx.g.removed)
    end

    test "a decision the cause cannot take is an error naming the row", ctx do
      curated!(ctx, :range_decisions, @seed_ranges ++ ["#{ctx.g.removed},removed,include,"])

      assert {:error, message} = run(ctx)
      assert message =~ "range_decisions.csv row 3"
    end
  end

  # -- aliases -------------------------------------------------------------------------

  describe "aliases" do
    setup ctx do
      o = ctx.old
      alias!(880_501, "Cynips fixturoides", "scientific", species: o.agamic, species: o.sexgen)
      alias!(880_502, "q-alba-old-label", "scientific", species: o.undescribed)
      alias!(880_503, "Fixture oak", "common", species: o.alba)
      alias!(880_504, "Quercus fixturalba", "scientific", species: o.alba)
      alias!(880_505, "Fixturquercoides", "scientific", taxonomy: o.quercus)
      alias!(880_506, "Fixture apple gall", "common", species: o.agamic)
      alias!(880_507, "FXQ-12", "scientific", species: o.sexgen)
      :ok
    end

    defp alias_facts do
      Old.rows("""
      SELECT af.gall_id, af.name, a.source_id
      FROM alias_facts af JOIN attributions a ON a.fact_id = af.fact_id
      ORDER BY af.gall_id, af.name
      """)
    end

    defp names_in_taxa(name),
      do: Repo.all(from(n in "taxon_names", where: n.name == ^name, select: n.status))

    defp resolves_to(name) do
      assert {:ok, taxon} = Taxa.resolve_name(name)
      {taxon.id, taxon.matched_name.status}
    end

    test "scientific aliases await a decision; common names follow the design", ctx do
      o = ctx.old
      assert {:error, {:pending_decisions, report}} = run(ctx)

      assert Enum.sort(pending(report, "aliases.csv")) ==
               Enum.sort([
                 {"gall", o.agamic, 880_501},
                 {"gall", o.sexgen, 880_501},
                 {"gall", o.undescribed, 880_502},
                 {"plant", o.alba, 880_504},
                 {"taxonomy", o.quercus, 880_505},
                 {"gall", o.sexgen, 880_507}
               ])

      worksheet = curation(report, "aliases")

      assert %{"decision" => "common_name", "decided_by" => "mechanical"} =
               Enum.find(worksheet, &(&1["alias_id"] == 880_503))
    end

    test "decisions sort aliases by meaning; a former label never enters taxon_names", ctx do
      o = ctx.old

      curated!(ctx, :aliases, [
        "gall,#{o.agamic},880501,Cynips fixturoides,scientific,synonym,,",
        "gall,#{o.sexgen},880501,Cynips fixturoides,scientific,synonym,,",
        "gall,#{o.undescribed},880502,q-alba-old-label,scientific,former_label,,",
        "plant,*,*,,scientific,synonym,,all plant scientific aliases",
        "taxonomy,#{o.quercus},880505,Fixturquercoides,scientific,synonym,,",
        "gall,#{o.sexgen},880507,FXQ-12,scientific,code,,"
      ])

      report = run!(ctx)
      assert report.pending == []

      fixtura = Taxa.get_by_legacy_id(:gall_inducer, o.agamic)
      genus = Taxa.get_by_legacy_id(:taxonomy, o.quercus)

      assert resolves_to("Cynips fixturoides") == {fixtura.id, :synonym}
      assert resolves_to("Quercus fixturalba") == {o.alba, :synonym}
      assert resolves_to("Fixturquercoides") == {genus.id, :synonym}

      # Former labels and codes are the Gall's, never taxon names.
      assert names_in_taxa("q-alba-old-label") == []
      assert names_in_taxa("FXQ-12") == []
      assert Taxa.resolve_name("q-alba-old-label") == :none

      legacy = Gallformers.Sources.get_source_by_title("Gallformers legacy data").id

      assert [
               %{gall_id: 100, name: "Oak Apple Gall Wasp", source_id: ^legacy},
               %{gall_id: agamic, name: "Fixture apple gall", source_id: ^legacy},
               %{gall_id: sexgen, name: "FXQ-12", source_id: ^legacy},
               %{gall_id: undescribed, name: "q-alba-old-label", source_id: ^legacy}
             ] = alias_facts()

      assert {agamic, sexgen, undescribed} == {o.agamic, o.sexgen, o.undescribed}

      assert "Fixture oak" in Enum.map(Taxa.list_common_names(o.alba), & &1.name)
      assert "White Oak" in Enum.map(Taxa.list_common_names(1), & &1.name)

      assert %{old: 4, new: 4} =
               Enum.find(report.reconciliation, &(&1.label =~ "Gall alias Facts"))
    end

    test "a decision that cannot apply stays pending", ctx do
      o = ctx.old
      alias!(880_508, "Not a label", "scientific", species: o.alba)

      curated!(ctx, :aliases, [
        "gall,*,*,,scientific,drop,,",
        "taxonomy,*,*,,scientific,drop,,",
        "plant,#{o.alba},880504,Quercus fixturalba,scientific,drop,,",
        "plant,#{o.alba},880508,Not a label,scientific,former_label,,"
      ])

      assert {:error, {:pending_decisions, report}} = run(ctx)
      assert [{"plant", alba, 880_508}] = pending(report, "aliases.csv")
      assert alba == o.alba
      assert [%{detail: detail}] = report.pending
      assert detail =~ "as former_label: former_label applies to Galls only"

      run!(ctx, pending: :skip)
      assert names_in_taxa("Not a label") == []
      refute Enum.any?(alias_facts(), &(&1.name == "Not a label"))
    end
  end

  # -- keys ----------------------------------------------------------------------------

  describe "keys" do
    setup ctx do
      o = ctx.old
      lookalike = gall!(880_250, "Fixturella lookalike", 33)
      trait!(lookalike, "form", "non-gall")
      curated!(ctx, :non_galls, ["#{lookalike},Fixturella lookalike,exclude,"])

      taxon = fn name, ids -> %{"type" => "taxon", "name" => name, "species_id" => ids} end

      key!(880_001, "fixture-key", %{
        "1" => %{
          "leads" => [
            %{
              "text" => "Galls in clusters.",
              "destination" => %{"type" => "couplet", "number" => "2"}
            },
            %{
              "text" => "Galls single.",
              "destination" => taxon.("Andricus fixtura", [o.agamic, o.sexgen])
            }
          ]
        },
        "2" => %{
          "leads" => [
            %{"text" => "On oak.", "destination" => taxon.("Fixturquercus alba", o.alba)},
            %{
              "text" => "Not a gall.",
              "destination" => taxon.("Lookalikes", [lookalike, 999_999])
            }
          ]
        }
      })

      %{lookalike: lookalike}
    end

    defp destination(couplet, lead),
      do:
        key_couplets(880_001)[couplet]["leads"] |> Enum.at(lead - 1) |> Map.fetch!("destination")

    test "links to Galls stay as they are; the rest await a decision", ctx do
      assert {:error, {:pending_decisions, report}} = run(ctx)

      assert Enum.sort(pending(report, "keys.csv")) ==
               Enum.sort([
                 {"fixture-key", "2", 1, ctx.old.alba},
                 {"fixture-key", "2", 2, ctx.lookalike},
                 {"fixture-key", "2", 2, 999_999}
               ])

      whys = Map.new(curation(report, "keys"), &{&1["species_id"], &1["why"]})
      assert whys[ctx.old.alba] == "plant"
      assert whys[ctx.lookalike] == "non-gall (excluded)"
      assert whys[999_999] == "no such species"
    end

    test "decisions drop or re-target a couplet's links", ctx do
      o = ctx.old

      curated!(ctx, :keys, [
        "fixture-key,2,1,#{o.alba},drop,,the host page is not a gall page",
        "fixture-key,2,2,#{ctx.lookalike},retarget,#{o.sexgen},",
        "fixture-key,2,2,999999,drop,,"
      ])

      assert run!(ctx).pending == []

      assert destination("1", 2)["species_id"] == [o.agamic, o.sexgen]
      assert %{"name" => "Fixturquercus alba"} = dest = destination("2", 1)
      refute dest["species_id"]
      assert destination("2", 2)["species_id"] == o.sexgen

      # Applied decisions are not pending on a second run.
      assert run!(ctx).pending == []
      assert destination("2", 2)["species_id"] == o.sexgen
    end

    test "re-targeting to something that is not a Gall stays pending", ctx do
      o = ctx.old

      curated!(ctx, :keys, [
        "fixture-key,2,1,#{o.alba},drop,,",
        "fixture-key,2,2,#{ctx.lookalike},retarget,#{o.alba},",
        "fixture-key,2,2,999999,drop,,"
      ])

      assert {:error, {:pending_decisions, report}} = run(ctx)
      assert pending(report, "keys.csv") == [{"fixture-key", "2", 2, ctx.lookalike}]
      assert destination("2", 2)["species_id"] == [ctx.lookalike, 999_999]
    end
  end

  # -- the replay log and duplicate taxon keys -----------------------------------------

  test "the migration never empties the replay log", ctx do
    entry = %{"taxon" => %{"name" => "X", "rank" => "species"}, "name" => "Y"}

    {:ok, _} =
      Gallformers.Audit.transaction(test_actor(), "test.replay_log", fn ->
        Repo.insert_all("replay_log", [
          %{
            kind: "synonym_added",
            key: entry,
            payload: %{},
            inserted_at: ~U[2026-01-01 00:00:00Z]
          }
        ])
      end)

    run!(ctx)

    assert [%{kind: :synonym_added, key: ^entry}] = Import.list_replay_entries()
  end

  test "duplicate taxon keys stop a strict run; a lenient run reports them", ctx do
    taxonomy!(880_030, "Fixturidae", "family", description: "Midge")
    taxonomy!(880_031, "Fixturidae", "family", description: "Midge")

    assert {:error, {:pending_decisions, report}} = run(ctx)
    assert [%{name: "Fixturidae"}] = report.duplicates
    assert Taxa.resolve_name("Fixturidae") == :none

    assert [%{name: "Fixturidae"}] = run!(ctx, pending: :skip).duplicates
  end

  # -- taxon merges --------------------------------------------------------------------

  defp problems(report, category),
    do: for(%{category: ^category, detail: detail} <- report.problems, do: detail)

  defp higher_taxa(report),
    do: Enum.find(report.reconciliation, &(&1.label == "Higher taxa (taxonomy rows)"))

  describe "taxon merges" do
    setup do
      %{s: gall_family_fixture()}
    end

    defp merge_rows(s) do
      [
        "#{s.gall_family},#{s.family},one family (gall-forming mistletoe)",
        "#{s.gall_genus},#{s.genus},one genus"
      ]
    end

    test "without a merge, the twice-kept genus is a duplicate taxon key", ctx do
      assert {:error, {:pending_decisions, report}} = run(ctx)

      assert [%{name: "Fixturphoradendron", rank: :genus, kingdom: "Plantae"}] =
               report.duplicates
    end

    test "a merged family and genus are no taxa of their own: they map onto their targets",
         ctx do
      s = ctx.s
      curated!(ctx, :taxon_merges, merge_rows(s))

      report = run!(ctx)
      assert report.duplicates == []
      assert report.pending == []

      family = Taxa.get_by_legacy_id(:taxonomy, s.family)
      genus = Taxa.get_by_legacy_id(:taxonomy, s.genus)
      assert {Taxa.accepted_name(family), family.rank} == {"Fixtursantalaceae", :family}
      assert {Taxa.accepted_name(genus), genus.parent_id} == {"Fixturphoradendron", family.id}

      # Old IDs and bookmarks of the merged rows resolve to the targets.
      assert Taxa.get_by_legacy_id(:taxonomy, s.gall_family).id == family.id
      assert Taxa.get_by_legacy_id(:taxonomy, s.gall_genus).id == genus.id
      assert Taxa.get_by_legacy_id(:taxonomy, s.placeholder).id == family.id
      assert Taxa.resolve_name("Fixtursantalaceae (gall)") == :none

      # Both keep kingdom Plantae.
      assert {family.kingdom, genus.kingdom} == {"Plantae", "Plantae"}

      # Children attach to the targets: the section, the Galls' Inducer links.
      section = Taxa.get_by_legacy_id(:taxonomy, s.section)
      assert {Taxa.accepted_name(section), section.parent_id} == {"Fixturvillosae", genus.id}

      inducer = Taxa.get_by_legacy_id(:gall_inducer, s.gall)

      assert {Taxa.accepted_name(inducer), inducer.parent_id, inducer.kingdom} ==
               {"Fixturphoradendron serotinum", genus.id, "Plantae"}

      assert Taxa.get_by_legacy_id(:gall_inducer, s.undescribed).id == family.id
      assert Taxa.get_taxon!(s.plant).parent_id == genus.id

      assert {"merged into another taxon (taxon_merges.csv)", 2} in higher_taxa(report).accounted
      assert Enum.reject(report.reconciliation, &Report.balanced?/1) == []
      assert problems(report, "taxon_merges.csv") == []
    end

    test "a merge across ranks is an error naming the row; nothing is written", ctx do
      s = ctx.s
      curated!(ctx, :taxon_merges, ["#{s.gall_family},#{s.genus},"])

      assert {:error, message} = run(ctx)
      assert message =~ "taxon_merges.csv row 2"
      assert message =~ "rank"
      assert Catalog.get_gall(ctx.old.agamic) == nil
    end

    test "a merge into itself or into a merged row is an error naming the row", ctx do
      s = ctx.s
      curated!(ctx, :taxon_merges, ["#{s.gall_genus},#{s.gall_genus},"])
      assert {:error, message} = run(ctx)
      assert message =~ "taxon_merges.csv row 2"

      curated!(ctx, :taxon_merges, merge_rows(s) ++ ["#{s.section},#{s.gall_genus},"])
      assert {:error, message} = run(ctx)
      assert message =~ "taxon_merges.csv row 4"
    end

    test "rows naming unknown taxonomy rows are reported, not used", ctx do
      s = ctx.s

      curated!(
        ctx,
        :taxon_merges,
        merge_rows(s) ++ ["999990,#{s.family},", "#{s.section},999991,"]
      )

      report = run!(ctx)

      assert problems(report, "taxon_merges.csv") == [
               "999990 into #{s.family}: 999990 is not a taxonomy row; the merge is not used",
               "#{s.section} into 999991: 999991 is not a taxonomy row; the merge is not used"
             ]

      assert Taxa.get_by_legacy_id(:taxonomy, s.section).rank == :section
    end

    test "a merged family's kingdom decision is reported, not used", ctx do
      s = ctx.s
      curated!(ctx, :taxon_merges, merge_rows(s))
      curated!(ctx, :kingdoms, ["#{s.gall_family},Fungi,"])

      report = run!(ctx)

      assert [detail] = problems(report, "kingdoms.csv")
      assert detail =~ "#{s.gall_family}"
      assert Taxa.get_by_legacy_id(:taxonomy, s.gall_family).kingdom == "Plantae"
    end
  end

  # -- kingdoms ------------------------------------------------------------------------

  describe "kingdoms" do
    setup do
      %{k: kingdomless_family_fixture()}
    end

    defp no_kingdom(report, family_id) do
      for detail <- problems(report, "taxonomy"),
          detail =~ "#{family_id}" and detail =~ "has no kingdom",
          do: detail
    end

    test "a family whose type gives none has no kingdom, reported", ctx do
      report = run!(ctx)

      assert [_] = no_kingdom(report, ctx.k.family)
      assert Taxa.get_by_legacy_id(:taxonomy, ctx.k.family).kingdom == nil
    end

    test "a kingdom decision applies to the family and everything below it", ctx do
      k = ctx.k
      curated!(ctx, :kingdoms, ["#{k.family},Chromista,phylum Cercozoa"])

      report = run!(ctx)

      assert no_kingdom(report, k.family) == []
      family = Taxa.get_by_legacy_id(:taxonomy, k.family)
      genus = Taxa.get_by_legacy_id(:taxonomy, k.genus)
      inducer = Taxa.get_by_legacy_id(:gall_inducer, k.gall)

      assert {family.kingdom, family.origin} == {"Chromista", :curated}
      assert genus.kingdom == "Chromista"

      assert {Taxa.accepted_name(inducer), inducer.kingdom} ==
               {"Fixturphora brassicae", "Chromista"}

      assert problems(report, "kingdoms.csv") == []
    end

    test "an unknown kingdom is an error naming the row", ctx do
      curated!(ctx, :kingdoms, ["#{ctx.k.family},Protista,"])

      assert {:error, message} = run(ctx)
      assert message =~ "kingdoms.csv row 2"
    end

    test "a kingdom on a row that is not a family is an error naming the row", ctx do
      curated!(ctx, :kingdoms, ["#{ctx.k.family},Chromista,", "#{ctx.k.genus},Chromista,"])

      assert {:error, message} = run(ctx)
      assert message =~ "kingdoms.csv row 3"
    end

    test "rows naming unknown taxonomy rows are reported, not used", ctx do
      curated!(ctx, :kingdoms, ["999992,Fungi,"])

      report = run!(ctx)

      assert [detail] = problems(report, "kingdoms.csv")
      assert detail =~ "999992"
    end
  end

  test "the shipped merge and kingdom decisions load" do
    assert {:ok, merges} = TaxonMerges.load(Curated.default_path(:taxon_merges))

    assert merges |> Map.values() |> Enum.map(&{&1.old_id, &1.into_id}) |> Enum.sort() ==
             [{984, 23}, {985, 202}]

    assert {:ok, %{1140 => %{kingdom: "Chromista"}}} =
             Kingdoms.load(Curated.default_path(:kingdoms))
  end
end
