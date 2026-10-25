defmodule Gallformers.Import.ApplyTest do
  @moduledoc """
  Applying approved batches (`9449` §5, Task 13): the Source step, taxonomy
  batches (phase 1 rule, §3) and gall batches, the diff of a Source's
  attributions, and the queue items applying produces.

  Not async: packages create Sources (unique titles), some tests use the one
  Gallformers Source, and the Catalog vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.Package
  alias Gallformers.Import.QueueItem
  alias Gallformers.Sources
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    lobata = plant_fixture(name: "Quercus lobata", parent: quercus)
    douglasii = plant_fixture(name: "Quercus douglasii", parent: quercus)
    andricus = taxon_fixture(name: "Andricus", rank: :genus, kingdom: "Animalia")
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
    torymus = taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")

    legacy = source_fixture("Legacy", "1990")
    gall = gall_fixture(name: "Andricus quercuscalifornicus (agamic)", generation: "agamic")

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
        confirm(legacy)
      )

    %{
      quercus: quercus,
      lobata: lobata,
      douglasii: douglasii,
      andricus: andricus,
      wasp: wasp,
      torymus: torymus,
      legacy: legacy,
      gall: gall
    }
  end

  # The fixture gall batch, its Host written in full (the fixture document
  # names no genus Quercus to expand "Q. lobata" from).
  defp gall_batch do
    batch()
    |> unique_batch_id()
    |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
  end

  defp drop_facts(batch, ids),
    do: Map.update!(batch, "facts", fn facts -> Enum.reject(facts, &(&1["id"] in ids)) end)

  defp approve!(package) do
    {:ok, _} = Import.approve_package(test_actor(), package)
    Import.get_package!(package.id)
  end

  defp statements(batch),
    do: batch |> Import.list_statements() |> Map.new(&{{&1.kind, &1.ref}, &1})

  defp fact_statement(package, file, ref) do
    batch = Enum.find(Import.list_batches(package), &(&1.file == file))
    statements(batch)[{:fact, ref}] || statements(batch)[{:act, ref}]
  end

  defp attribution(fact_id, source_id),
    do: Enum.find(Facts.list_attributions(fact_id), &(&1.source_id == source_id))

  defp changes_for(table, id) do
    Repo.all(
      from c in Carbonite.Change, where: c.table_name == ^table and c.table_pk == ^["#{id}"]
    )
  end

  defp change_count, do: Repo.aggregate(Carbonite.Change, :count)

  defp put_place!(code, name) do
    Repo.insert_all("place", [%{name: name, code: code, type: "state"}], on_conflict: :nothing)
  end

  describe "the Source step" do
    test "a new Source is created with today's columns filled, and the document stored" do
      package = package(gall: gall_batch()) |> with_review() |> deliver!() |> approve!()

      assert %Package{status: :approved, source_id: source_id} = package
      source = Sources.get_source!(source_id)

      assert source.title == "T"
      assert source.citation == "A. 2024. T."
      assert source.author == "A"
      assert source.pubyear == "2024"
      assert source.license == "CC-BY"
      assert source.licenselink == "https://creativecommons.org/licenses/by/4.0/"
      assert source.kind == :publication
      assert source.authors == ["A"]
      assert source.authored_precision == :year
      assert source.license_as_written == "CC BY 4.0"
    end

    test "a second package of the same Source is matched by its citation" do
      first = package(gall: gall_batch()) |> with_review() |> deliver!() |> approve!()
      second = package(gall: gall_batch()) |> with_review() |> deliver!()

      assert second.source_id == first.source_id
    end

    test "a title held by another Source with a different citation is queued" do
      {:ok, _} =
        Sources.create_source(%{
          title: "T",
          author: "Someone",
          pubyear: "1950",
          link: "https://example.com/t",
          citation: "Someone. 1950. T.",
          license: "All Rights Reserved"
        })

      package = package(gall: gall_batch()) |> with_review() |> deliver!()

      assert package.source_id == nil

      assert [%QueueItem{kind: :ambiguous_match, statement_ref: "source", batch_id: nil}] =
               Import.list_queue_items(package, kind: :ambiguous_match)

      assert {:error, {:open_items, [_]}} = Import.approve_package(test_actor(), package)
    end
  end

  describe "gall batches" do
    test "a re-import drops one Fact and leaves unchanged ones untouched", ctx do
      first = package(gall: gall_batch()) |> with_review() |> deliver!() |> approve!()
      source_id = first.source_id

      host = fact_statement(first, "gall.json", "f2")
      parasitoid = fact_statement(first, "gall.json", "f3")
      qualifier = fact_statement(first, "gall.json", "f4")
      inducer = fact_statement(first, "gall.json", "f1")

      assert %BatchStatement{delta: :new} = host
      assert %BatchStatement{delta: :confirms_existing} = inducer
      assert Facts.get_fact!(parasitoid.fact_id).standing == :current

      host_attribution = attribution(host.fact_id, source_id)
      inducer_attribution = attribution(inducer.fact_id, source_id)

      # The Source re-runs and no longer states the parasitoid (or its qualifier).
      second =
        package(gall: gall_batch() |> drop_facts(["f3", "f4"]))
        |> with_review()
        |> deliver!()
        |> approve!()

      assert second.source_id == source_id
      assert Facts.get_fact!(parasitoid.fact_id).standing == :unsupported
      assert Facts.get_fact!(qualifier.fact_id).standing == :unsupported
      assert attribution(parasitoid.fact_id, source_id) == nil

      # Unchanged attributions are not rewritten: no audit rows beyond their insert.
      assert [%Carbonite.Change{op: :insert}] = changes_for("attributions", host_attribution.id)

      assert [%Carbonite.Change{op: :insert}] =
               changes_for("attributions", inducer_attribution.id)

      assert attribution(host.fact_id, source_id).batch_id == host_attribution.batch_id

      assert %BatchStatement{delta: :confirms_existing, fact_id: fact_id} =
               fact_statement(second, "gall.json", "f2")

      assert fact_id == host.fact_id
      assert Facts.get_fact!(inducer.fact_id).standing == :current
      assert Catalog.gall_summary(ctx.gall.id).hosts |> Enum.map(& &1.taxon_id) == [ctx.lobata.id]
    end

    test "a re-import that changes a statement updates its attribution" do
      first = package(gall: gall_batch()) |> with_review() |> deliver!() |> approve!()
      host = fact_statement(first, "gall.json", "f2")
      before = attribution(host.fact_id, first.source_id)

      changed =
        gall_batch()
        |> put_in(["facts", Access.at(1), "evidence"], [
          %{"item" => "#/texts/2", "quote" => "throughout the hills", "page" => "58"}
        ])

      second = package(gall: changed) |> with_review() |> deliver!() |> approve!()
      [gall_row] = Import.list_batches(second)

      after_update = attribution(host.fact_id, first.source_id)
      assert after_update.id == before.id
      assert after_update.batch_id == gall_row.id
      assert [%{quote: "throughout the hills", page: "58"}] = after_update.evidence
      assert [_insert, %Carbonite.Change{op: :update}] = changes_for("attributions", before.id)
    end

    test "mode add never removes the Source's other attributions" do
      first = package(gall: gall_batch()) |> with_review() |> deliver!() |> approve!()
      parasitoid = fact_statement(first, "gall.json", "f3")

      package(gall: gall_batch() |> Map.put("mode", "add") |> drop_facts(["f3", "f4"]))
      |> with_review()
      |> deliver!()
      |> approve!()

      assert Facts.get_fact!(parasitoid.fact_id).standing == :current
    end

    test "re-applying a batch changes nothing" do
      package = package(gall: gall_batch()) |> with_review() |> deliver!() |> approve!()
      before = change_count()

      assert {:ok, %Package{status: :approved}} = Import.apply_package(test_actor(), package)
      assert change_count() == before
      assert Enum.map(Import.list_batches(package), & &1.status) == [:applied]
    end

    test "a same-date conflict lands in the queue", ctx do
      other = source_fixture("Other", "2024")

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "host_of", subject_taxon_id: ctx.lobata.id, object_gall_id: ctx.gall.id},
          confirm(other)
        )

      denial =
        gall_batch()
        |> drop_facts(["f3", "f4"])
        |> put_in(["facts", Access.at(1), "stance"], "deny")

      package = package(gall: denial) |> with_review() |> deliver!() |> approve!()

      assert [%QueueItem{statement_ref: "f2", status: :open} = item] =
               Import.list_queue_items(package, kind: :same_date_conflict)

      assert item.subject["fact_id"] == fact_statement(package, "gall.json", "f2").fact_id

      assert %BatchStatement{delta: :denies_or_replaces} =
               fact_statement(package, "gall.json", "f2")
    end

    test "an older Gallformers statement does not replace a newer one", ctx do
      gallformers = gallformers_source()

      statement = fn text, date ->
        %{
          "format" => "gallformers-import",
          "format_version" => 3,
          "vocabulary_version" => "2026-10-11",
          "batch_type" => "gall",
          "mode" => "add",
          "batch_id" => "gf-#{System.unique_integer([:positive])}-0000",
          "produced_at" => "2026-10-07T14:00:00Z",
          "producer" => %{"name" => "curator", "version" => "0"},
          "source" => %{"gallformers" => true},
          "taxa" => [
            %{
              "ref" => "t1",
              "name_as_written" => "Andricus quercuscalifornicus",
              "rank" => "species"
            },
            %{"ref" => "t2", "name_as_written" => "Quercus douglasii", "rank" => "species"}
          ],
          "galls" => [
            %{
              "ref" => "g1",
              "name_as_written" => "agamic gall",
              "identified_by" => %{
                "inducer" => "t1",
                "generation" => %{"value" => "agamic", "as_written" => "agamic"}
              }
            }
          ],
          "facts" => [
            %{
              "id" => "f1",
              "stance" => "confirm",
              "kind" => "relationship",
              "type" => "host_of",
              "subject" => "t2",
              "object" => "g1",
              "evidence" => [
                %{
                  "statement" => %{"text" => text, "stated_on" => date},
                  "observations" => [%{"provider" => "inaturalist", "id" => "123"}]
                }
              ]
            }
          ]
        }
      end

      newer =
        batch_files([{"gall.json", statement.("Verified from Observations.", "2026-10-07")}])

      first = newer |> deliver!(review: false) |> approve!()
      assert first.source_id == gallformers.id

      older = batch_files([{"gall.json", statement.("An earlier note.", "2025-01-01")}])
      older |> deliver!(review: false) |> approve!()

      fact_id = fact_statement(first, "gall.json", "f1").fact_id
      kept = attribution(fact_id, gallformers.id)

      assert kept.statement_text == "Verified from Observations."
      assert kept.stated_on == ~D[2026-10-07]
      assert [%{provider: :inaturalist, external_id: "123"}] = kept.observations

      assert Catalog.gall_summary(ctx.gall.id).hosts |> Enum.map(& &1.taxon_id) == [
               ctx.douglasii.id
             ]
    end
  end

  describe "taxonomy batches" do
    test "a taxonomy batch adding a new species makes its gall batch resolve", ctx do
      taxonomy =
        taxonomy_batch()
        |> unique_batch_id()
        |> Map.put("taxa", [
          %{
            "ref" => "t1",
            "name_as_written" => "Andricus novus",
            "rank" => "species",
            "new" => %{"status" => "sp. nov."}
          },
          %{"ref" => "t2", "name_as_written" => "Andricus", "rank" => "genus"}
        ])
        |> Map.put("acts", [
          %{
            "id" => "a1",
            "stance" => "confirm",
            "kind" => "name",
            "taxon" => "t1",
            "authorship" => %{"as_written" => "Example, 2024"},
            "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
          },
          %{
            "id" => "a2",
            "stance" => "confirm",
            "kind" => "placement",
            "taxon" => "t1",
            "parent" => "t2",
            "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
          }
        ])

      gall =
        gall_batch()
        |> drop_facts(["f3", "f4"])
        |> put_in(["taxa", Access.at(0), "name_as_written"], "Andricus novus")
        |> put_in(["galls", Access.at(0), "new"], true)

      package = package(gall: gall, taxonomy: taxonomy) |> with_review() |> deliver!()
      [_taxonomy_batch, gall_batch_row] = Import.list_batches(package)

      assert %BatchStatement{resolution: :new, taxon_id: nil} =
               statements(gall_batch_row)[{:taxon, "t1"}]

      package = approve!(package)
      assert package.status == :approved

      assert {:ok, novus} = Taxa.resolve_name("Andricus novus", rank: :species)
      assert novus.parent_id == ctx.andricus.id

      [taxonomy_row, gall_row] = Import.list_batches(package)
      assert taxonomy_row.status == :applied
      assert gall_row.status == :applied

      assert %BatchStatement{resolution: :resolved, taxon_id: taxon_id} =
               statements(gall_row)[{:taxon, "t1"}]

      assert taxon_id == novus.id

      %BatchStatement{gall_id: gall_id} = statements(gall_row)[{:gall, "g1"}]
      assert [%{taxon_id: ^taxon_id}] = Catalog.gall_summary(gall_id).inducers
      assert Catalog.get_gall!(gall_id).name == "Andricus novus (agamic)"

      # Every act is recorded as a Fact attributed to the Source.
      name_act = fact_statement(package, "taxonomy.json", "a1")
      assert %BatchStatement{delta: :new} = name_act

      assert [%{authorship_as_written: "Example, 2024"}] =
               Facts.list_attributions(name_act.fact_id)

      assert Import.list_queue_items(package, kind: :taxonomy_disagreement) == []
    end

    test "a disagreeing synonymy is flagged and the tree is unchanged" do
      callirhytis = taxon_fixture(name: "Callirhytis quercusexempla", kingdom: "Animalia")
      andricus_ex = taxon_fixture(name: "Andricus quercusexempla", kingdom: "Animalia")

      taxonomy =
        taxonomy_batch()
        |> unique_batch_id()
        |> Map.put("taxa", [
          %{
            "ref" => "t1",
            "name_as_written" => "Callirhytis quercusexempla",
            "rank" => "species"
          },
          %{"ref" => "t2", "name_as_written" => "Andricus quercusexempla", "rank" => "species"}
        ])
        |> Map.put("acts", [
          %{
            "id" => "a1",
            "stance" => "confirm",
            "kind" => "synonymy",
            "name" => "t1",
            "accepted" => "t2",
            "status_as_written" => "comb. nov.",
            "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
          }
        ])

      package =
        package(gall: nil, taxonomy: taxonomy) |> with_review() |> deliver!() |> approve!()

      act = fact_statement(package, "taxonomy.json", "a1")
      assert Facts.get_fact!(act.fact_id).standing == :current

      assert [%QueueItem{statement_ref: "a1", status: :open}] =
               Import.list_queue_items(package, kind: :taxonomy_disagreement)

      # The editorial tree still holds both as accepted, separate taxa.
      assert Taxa.accepted_name(callirhytis) == "Callirhytis quercusexempla"
      assert [%{status: :accepted}] = Taxa.get_taxon!(callirhytis.id).names
      assert [%{status: :accepted}] = Taxa.get_taxon!(andricus_ex.id).names
    end
  end

  describe "retraction" do
    test "a retraction package flips the retracted Source's Facts" do
      paper = package(gall: gall_batch()) |> with_review() |> deliver!() |> approve!()
      host = fact_statement(paper, "gall.json", "f2")
      assert Facts.get_fact!(host.fact_id).standing == :current

      notice =
        gall_batch()
        |> Map.merge(%{"mode" => "add", "taxa" => [], "galls" => [], "facts" => []})
        |> Map.update!("source", fn source ->
          Map.merge(source, %{
            "title" => "Retraction notice: T",
            "citation" => "Editors. 2026. Retraction of A. 2024. T.",
            "authored" => %{"date" => "2026-05-01", "as_written" => "1 May 2026"},
            "retracts" => %{"citation_as_written" => "A. 2024. T."}
          })
        end)

      retraction = package(gall: notice) |> with_review() |> deliver!() |> approve!()

      retracted = Sources.get_source!(paper.source_id)
      assert retracted.retracted_by_id == retraction.source_id
      assert retracted.retracted_on == ~D[2026-05-01]
      assert Facts.get_fact!(host.fact_id).standing == :retracted
    end
  end

  describe "the simple-paper example" do
    test "applies end to end", ctx do
      put_place!("US-OR", "Oregon")
      package = deliver!(with_review(example_package("simple-paper")))

      # The document names no genus Quercus to expand "Q." from: the admin
      # resolves the two Host names (d585), then resolves again.
      for item <- Import.list_queue_items(package, kind: :unresolved_host) do
        plant = if item.statement_ref == "t2", do: ctx.lobata, else: ctx.douglasii
        {:ok, _} = Import.decide_queue_item(test_actor(), item, %{"taxon_id" => plant.id})
      end

      {:ok, package} = Import.resolve_package(test_actor(), package)
      package = approve!(package)

      assert package.status == :approved
      [taxonomy_row, gall_row] = Import.list_batches(package)
      assert {taxonomy_row.status, gall_row.status} == {:applied, :applied}

      facts = for {{:fact, _}, s} <- statements(gall_row), do: s
      assert length(facts) == 15
      assert Enum.reject(facts, &is_integer(&1.fact_id)) == []

      # g1 is the seeded Gall; g2 a new undescribed Gall.
      s = statements(gall_row)
      assert s[{:gall, "g1"}].gall_id == ctx.gall.id
      new_gall = s[{:gall, "g2"}].gall_id
      assert new_gall != ctx.gall.id
      assert [%{taxon_id: andricus}] = Catalog.gall_summary(new_gall).inducers
      assert andricus == ctx.andricus.id

      summary = Catalog.gall_summary(ctx.gall.id)
      assert Enum.map(summary.hosts, & &1.taxon_id) == [ctx.lobata.id]
      assert summary.traits["color"] == ["tan"]
      assert summary.traits["detachable"] == ["integral"]

      # The denied Host is withdrawn.
      assert Facts.get_fact!(s[{:fact, "f3"}].fact_id).standing == :withdrawn
      assert s[{:fact, "f3"}].delta == :new
    end
  end
end
