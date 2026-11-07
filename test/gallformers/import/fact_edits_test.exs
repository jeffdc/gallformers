defmodule Gallformers.Import.FactEditsTest do
  @moduledoc """
  A curator's edits on a package's Facts before approval (matter `f14c`,
  item 4): drop a Fact, change a Host, change a Trait Fact's values, a
  note. Applying honours them, so the preview shows them; they replay; and
  removing one undoes it.

  Not async: packages create Sources (unique titles) and the Catalog
  vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.DoclingFixtures
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.Replay
  alias Gallformers.Import.StatementEdit
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    lobata = plant_fixture(name: "Quercus lobata", parent: quercus)
    douglasii = plant_fixture(name: "Quercus douglasii", parent: quercus)
    andricus = Taxa.get_by_legacy_id(:taxonomy, 33)
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    legacy = source_fixture("Legacy", "1990")
    gall = gall_fixture(name: "Andricus quercuscalifornicus (agamic)", generation: "agamic")

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
        confirm(legacy)
      )

    %{lobata: lobata, douglasii: douglasii, wasp: wasp, gall: gall}
  end

  @words "The galls are ovoid, a swelling on the leaf."

  # The fixture document with one more text item holding a Trait term.
  defp doc do
    words = %{
      "self_ref" => "#/texts/5",
      "label" => "text",
      "content_layer" => "body",
      "text" => @words,
      "prov" => [%{"page_no" => 2, "bbox" => %{}, "charspan" => [0, 0]}],
      "children" => []
    }

    DoclingFixtures.document()
    |> Map.update!("texts", &(&1 ++ [words]))
    |> update_in(["body", "children"], &(&1 ++ [%{"$ref" => "#/texts/5"}]))
  end

  # The fixture gall batch (format 4), its Host written in full, and an
  # "ovoid" shape the producer places under globular.
  defp gall_batch do
    batch()
    |> unique_batch_id()
    |> Map.put("format_version", 4)
    |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
    |> Map.update!("facts", fn facts ->
      facts ++
        [
          %{
            "id" => "f6",
            "stance" => "confirm",
            "kind" => "trait",
            "gall" => "g1",
            "trait" => "shape",
            "term" => "ovoid",
            "category" => %{"value" => "globular"},
            "evidence" => [%{"item" => "#/texts/5", "quote" => "ovoid"}]
          }
        ]
    end)
  end

  defp deliver do
    package(gall: gall_batch(), doc: doc()) |> with_review([], responded: true) |> deliver!()
  end

  defp gall_row(package), do: Enum.find(Import.list_batches(package), &(&1.file == "gall.json"))

  defp edit!(package, ref, edit) do
    {:ok, edit} = Import.edit_fact(test_actor(), package, gall_row(package), ref, edit)
    edit
  end

  defp preview!(package) do
    {:ok, preview} = Import.preview_package(Import.get_package!(package.id), test_actor())
    preview
  end

  defp entries(preview) do
    for g <- preview.galls,
        {category, list} <- g.facts,
        e <- if(category == :traits, do: list |> Map.values() |> List.flatten(), else: list),
        do: e
  end

  defp entries(preview, ref),
    do: Enum.filter(entries(preview), &(String.split(&1.ref, "+") |> hd() == ref))

  defp entry(preview, ref), do: Enum.find(entries(preview), &(&1.ref == ref))

  defp approve!(package) do
    {:ok, _} = Import.approve_package(test_actor(), Import.get_package!(package.id))
    Import.get_package!(package.id)
  end

  defp statement(package, ref),
    do:
      package
      |> gall_row()
      |> Import.list_statements()
      |> Enum.find(&(&1.kind == :fact and &1.ref == ref))

  defp relationship(fact_id),
    do: Repo.get!(Catalog.Facts.RelationshipFact, fact_id)

  describe "dropping a Fact" do
    test "the preview shows it dropped, and approval does not write it" do
      package = deliver()
      assert entry(preview!(package), "f3").status == :new

      edit = edit!(package, "f3", %{"drop" => true, "note" => "Torymus is the gall's inquiline"})
      assert %StatementEdit{kind: :drop, statement_ref: "f3", author_name: "test"} = edit

      dropped = entry(preview!(package), "f3")
      assert dropped.status == :dropped
      assert dropped.why == "an edit by test: Torymus is the gall's inquiline"
      assert [%{kind: :drop, note: "Torymus is the gall's inquiline"}] = dropped.edits
      # Its qualifier has no Relationship to qualify.
      assert entry(preview!(package), "f4").status == :dropped

      package = approve!(package)
      assert statement(package, "f3").fact_id == nil
      assert statement(package, "f3").detail["skipped"] =~ "an edit by test"
      assert is_integer(statement(package, "f2").fact_id)
    end
  end

  describe "changing a Host" do
    test "the Host Fact goes on the plant chosen, for that statement only", ctx do
      package = deliver()
      edit!(package, "f2", %{"host_taxon_id" => ctx.douglasii.id})

      host = entry(preview!(package), "f2")
      assert host.value.subject.taxon_id == ctx.douglasii.id
      assert host.value.subject.name == "Quercus douglasii"
      assert [%{name_as_written: "Quercus lobata"}] = host.words.names
      assert [%{kind: :host, value: %{"host_taxon_id" => id}}] = host.edits
      assert id == ctx.douglasii.id

      package = approve!(package)
      row = statement(package, "f2")
      assert relationship(row.fact_id).subject_taxon_id == ctx.douglasii.id
      assert row.detail["chosen_host_taxon_id"] == ctx.douglasii.id
    end

    test "only on a Host statement, and only a plant", ctx do
      package = deliver()
      batch = gall_row(package)

      assert {:error, "host_taxon_id goes only on a Host statement"} =
               Import.edit_fact(test_actor(), package, batch, "f1", %{
                 "host_taxon_id" => ctx.lobata.id
               })

      assert {:error, "host_taxon_id must be a plant"} =
               Import.edit_fact(test_actor(), package, batch, "f2", %{
                 "host_taxon_id" => ctx.wasp.id
               })

      assert {:error, :no_statement} =
               Import.edit_fact(test_actor(), package, batch, "f99", %{"drop" => true})
    end
  end

  describe "changing a Trait Fact's values" do
    test "the Fact goes on the values chosen, the Source's term kept", ctx do
      package = deliver()

      assert [%{value: %{trait: "shape", value: "globular"}, status: :new}] =
               entries(preview!(package), "f6")

      edit!(package, "f6", %{"values" => ["sphere", "hemispherical"]})
      traits = entries(preview!(package), "f6")
      assert Enum.map(traits, & &1.value.value) |> Enum.sort() == ["hemispherical", "sphere"]
      assert Enum.map(traits, & &1.words.term) == ["ovoid", "ovoid"]

      package = approve!(package)

      assert Enum.sort(Catalog.gall_summary(ctx.gall.id).traits["shape"]) == [
               "hemispherical",
               "sphere"
             ]

      {:ok, fact_id} =
        Catalog.find_fact(:trait, %{gall_id: ctx.gall.id, trait: "shape", value: "sphere"})

      assert Enum.find(Facts.list_attributions(fact_id), &(&1.source_id == package.source_id)).term ==
               "ovoid"
    end

    test "only values of its Trait" do
      package = deliver()

      assert {:error, "not values of shape: green"} =
               Import.edit_fact(test_actor(), package, gall_row(package), "f6", %{
                 "values" => ["green"]
               })

      assert {:error, "values go only on a Trait statement"} =
               Import.edit_fact(test_actor(), package, gall_row(package), "f2", %{
                 "values" => ["sphere"]
               })
    end
  end

  describe "a note" do
    test "is shown on the Fact and changes nothing" do
      package = deliver()
      edit!(package, "f2", %{"note" => "check the Host against the plate"})

      host = entry(preview!(package), "f2")
      assert host.status == :new
      assert [%{kind: :note, note: "check the Host against the plate"}] = host.edits

      assert {:error, %Ecto.Changeset{}} =
               Import.edit_fact(test_actor(), package, gall_row(package), "f2", %{"note" => "  "})
    end
  end

  describe "editing again, and removing" do
    test "a second edit of a kind replaces the first; removing one restores the preview", ctx do
      package = deliver()
      edit!(package, "f2", %{"host_taxon_id" => ctx.douglasii.id})

      edit =
        edit!(package, "f2", %{"host_taxon_id" => ctx.lobata.id, "note" => "lobata after all"})

      assert [%StatementEdit{value: %{"host_taxon_id" => id}, note: "lobata after all"}] =
               Import.list_fact_edits(package)

      assert id == ctx.lobata.id

      drop = edit!(package, "f2", %{"drop" => true})
      assert length(Import.list_fact_edits(package)) == 2
      assert entry(preview!(package), "f2").status == :dropped

      {:ok, _} = Import.remove_fact_edit(test_actor(), drop)
      assert %{status: :new} = entry(preview!(package), "f2")

      {:ok, _} = Import.remove_fact_edit(test_actor(), edit)
      assert Import.list_fact_edits(package) == []
      assert %{status: :new, edits: []} = entry(preview!(package), "f2")
    end

    test "an applied batch is not edited" do
      package = deliver()
      edit = edit!(package, "f2", %{"note" => "fine"})
      package = approve!(package)

      assert {:error, :not_editable} =
               Import.edit_fact(test_actor(), package, gall_row(package), "f2", %{"drop" => true})

      assert {:error, :not_editable} = Import.remove_fact_edit(test_actor(), edit)
    end
  end

  describe "the replay log" do
    test "each edit and removal is logged by stable keys, and replays", ctx do
      package = deliver()

      host =
        edit!(package, "f2", %{"host_taxon_id" => ctx.douglasii.id, "note" => "per the plate"})

      drop = edit!(package, "f3", %{"drop" => true})
      {:ok, _} = Import.remove_fact_edit(test_actor(), drop)

      batch_id = gall_row(package).producer_batch_id

      entries =
        for e <- Import.list_replay_entries(), e.kind in [:fact_edit, :fact_edit_removed], do: e

      key = fn ref, kind ->
        %{
          "package" => package.key,
          "batch_id" => batch_id,
          "statement_ref" => ref,
          "kind" => kind
        }
      end

      assert [
               {:fact_edit, key.("f2", "host"),
                %{
                  "value" => %{
                    "host_taxon" => %{
                      "name" => "Quercus douglasii",
                      "rank" => "species",
                      "kingdom" => "Plantae"
                    }
                  },
                  "note" => "per the plate"
                }},
               {:fact_edit, key.("f3", "drop"), %{"value" => %{}, "note" => nil}},
               {:fact_edit_removed, key.("f3", "drop"), %{}}
             ] == Enum.map(entries, &{&1.kind, &1.key, &1.payload})

      # Replayed on a database without the edit, it is made again.
      Repo.delete!(host)
      assert Import.list_fact_edits(package) == []
      assert {:ok, 3} = Replay.run(entries, actor: test_actor())
      assert_replays_again(entries, test_actor(), relogs: true)
      # The Host edit, not taken back, is skipped.
      assert_replays_again([hd(entries)])

      assert [%StatementEdit{statement_ref: "f2", kind: :host, note: "per the plate"} = replayed] =
               Import.list_fact_edits(package)

      assert replayed.value == %{"host_taxon_id" => ctx.douglasii.id}

      package = approve!(package)
      assert relationship(statement(package, "f2").fact_id).subject_taxon_id == ctx.douglasii.id

      # Its batch applied, an edit has done its part: replayed again, all
      # are skipped, the drop taken back too.
      assert_replays_again(entries)
    end
  end
end
