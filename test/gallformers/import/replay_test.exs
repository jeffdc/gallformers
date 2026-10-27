defmodule Gallformers.Import.ReplayTest do
  @moduledoc """
  The replay log (`9449` §5, Task 14): every data-changing step of the
  backscan is logged by stable keys, and replaying the log against a
  database freshly filled by the data migration gives the same result.

  Not async: packages create Sources (unique titles), the Gallformers Source
  is unique, and the test wipes the new tables inside its sandbox (first the
  converted seeds' rows, so its own seed stands for the data migration).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Facts
  alias Gallformers.Facts.Fact
  alias Gallformers.Import
  alias Gallformers.Import.Batch
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Import.StableRef
  alias Gallformers.Sources
  alias Gallformers.Sources.DocumentItem
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon

  setup :audit_test_metadata

  # Migrated Galls keep their species IDs, so the seed gives them fixed IDs.
  @stem_gall_id 990_001
  @bud_gall_id 990_002

  # -- the seed: what the data migration fills ---------------------------------

  defp seed! do
    quercus = plant_fixture(name: "Quercus", rank: :genus)
    lobata = plant_fixture(name: "Quercus lobata", parent: quercus)
    plant_fixture(name: "Quercus douglasii", parent: quercus)
    andricus = taxon_fixture(name: "Andricus", rank: :genus, kingdom: "Animalia")
    wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")
    taxon_fixture(name: "Callirhytis quercusexempla", kingdom: "Animalia")

    legacy =
      Sources.get_source_by_title("Gallformers legacy data") ||
        then(source_fixture("Legacy", "1990"), fn s ->
          {:ok, s} = Sources.update_source(s, %{title: "Gallformers legacy data"})
          s
        end)

    for {id, name} <- [
          {@stem_gall_id, "Andricus quercuscalifornicus stem gall"},
          {@bud_gall_id, "Andricus quercuscalifornicus bud gall"}
        ] do
      {:ok, gall} = Catalog.create_gall(test_actor(), %{id: id, name: name})

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
          confirm(legacy)
        )
    end

    %{lobata: lobata, wasp: wasp}
  end

  # -- the backscan: batches applied, decisions, Host names, taxonomy edits ---

  defp backscan!(seeded) do
    # A revision: a new species, a disagreeing synonymy, its Galls; the Host
    # is written the old way and resolved in the Host-name step.
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
        %{"ref" => "t2", "name_as_written" => "Andricus", "rank" => "genus"},
        %{"ref" => "t3", "name_as_written" => "Callirhytis quercusexempla", "rank" => "species"}
      ])
      |> Map.put("acts", [
        act("a1", "name", %{"taxon" => "t1"}),
        act("a2", "placement", %{"taxon" => "t1", "parent" => "t2"}),
        act("a3", "synonymy", %{"name" => "t3", "accepted" => "t1"})
      ])

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["taxa", Access.at(0), "name_as_written"], "Andricus novus")
      |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus tinctoria")
      |> put_in(["galls", Access.at(0), "new"], true)

    revision = package(gall: gall, taxonomy: taxonomy) |> with_review() |> deliver!()
    assert [_] = Import.list_queue_items(revision, kind: :unresolved_host)

    {:ok, _} = Import.record_synonym_added(test_actor(), seeded.lobata, "Quercus tinctoria")
    {:ok, revision} = Import.resolve_package(test_actor(), revision)
    {:ok, revision} = Import.approve_package(test_actor(), revision)
    assert revision.status == :approved

    [disagreement] = Import.list_queue_items(revision, kind: :taxonomy_disagreement)

    {:ok, _} =
      Import.decide_queue_item(test_actor(), disagreement, %{"note" => "left for phase 2"})

    # A curator applies part of the revision editorially.
    {:ok, _} =
      Import.record_taxonomy_edit(
        test_actor(),
        {:add_common_name, seeded.wasp, "California gall wasp"}
      )

    # A second paper, its Gall ambiguous between two migrated entries.
    second =
      batch()
      |> unique_batch_id()
      |> put_in(["source", "title"], "U")
      |> put_in(["source", "citation"], "B. 2025. U.")
      |> put_in(["source", "authored"], %{"date" => "2025", "as_written" => "2025"})
      |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
      |> update_in(["galls", Access.at(0), "identified_by"], &Map.delete(&1, "generation"))

    second = package(gall: second) |> with_review() |> deliver!()
    [ambiguous] = Import.list_queue_items(second, kind: :ambiguous_match)
    {:ok, _} = Import.decide_queue_item(test_actor(), ambiguous, %{"gall_id" => @stem_gall_id})
    {:ok, _} = Import.approve_package(test_actor(), second)

    # A Gallformers statement on the Gall the revision created.
    statement =
      example("gallformers-statement")
      |> unique_batch_id()
      |> put_in(["taxa", Access.at(0), "name_as_written"], "Andricus novus")

    statement = batch_files([{"gall.json", statement}]) |> deliver!(review: false)
    {:ok, _} = Import.approve_package(test_actor(), statement)
    :ok
  end

  defp act(id, kind, fields) do
    Map.merge(
      %{
        "id" => id,
        "stance" => "confirm",
        "kind" => kind,
        "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
      },
      fields
    )
  end

  # -- wiping the new tables (inside the sandbox) -------------------------------

  @new_tables ~w(replay_log queue_items batch_unmapped batch_statements
                 attribution_evidence attribution_names attribution_observations attributions
                 qualifier_facts relationship_facts trait_facts range_facts occurrence_facts
                 alias_facts description_facts placement_facts name_facts synonymy_facts
                 split_facts common_name_facts facts import_batches import_packages
                 document_items source_documents legacy_citations galls generation_group_taxa
                 taxon_ancestry taxon_common_names legacy_taxon_ids taxon_names taxa)

  defp wipe!(source_ids_before) do
    for table <- @new_tables, do: Repo.query!("DELETE FROM #{table}")
    Repo.query!("UPDATE source SET retracted_by_id = NULL, retracted_on = NULL")
    Repo.query!("DELETE FROM source WHERE NOT (id = ANY($1))", [source_ids_before])
  end

  # -- snapshots by stable keys -------------------------------------------------

  @detail_tables %{
    "gall_relationship" => "relationship_facts",
    "gall_qualifier" => "qualifier_facts",
    "gall_trait" => "trait_facts",
    "gall_range" => "range_facts",
    "gall_occurrence" => "occurrence_facts",
    "gall_alias" => "alias_facts",
    "gall_description" => "description_facts",
    "taxon_placement" => "placement_facts",
    "taxon_name" => "name_facts",
    "taxon_synonymy" => "synonymy_facts",
    "taxon_split" => "split_facts",
    "taxon_common_name" => "common_name_facts"
  }

  defp snapshot do
    %{
      taxa: Enum.sort(for taxon <- Repo.all(Taxon), do: taxon_entry(taxon)),
      galls: Enum.sort(for gall <- Repo.all(Gall), do: gall_entry(gall)),
      facts: Enum.sort(for fact <- Repo.all(Fact), do: fact_entry(fact)),
      queue: Enum.sort(for item <- Repo.all(QueueItem), do: queue_entry(item)),
      log: for(e <- Import.list_replay_entries(), do: {e.kind, e.key, e.payload})
    }
  end

  defp taxon_entry(taxon) do
    taxon = Taxa.get_taxon!(taxon.id)

    {Taxa.accepted_name(taxon), taxon.rank, taxon.kingdom, taxon.origin,
     taxon.parent_id && Taxa.accepted_name(taxon.parent_id),
     taxon.names |> Enum.filter(&(&1.status == :synonym)) |> Enum.map(& &1.name) |> Enum.sort(),
     taxon |> Taxa.list_common_names() |> Enum.map(& &1.name) |> Enum.sort()}
  end

  defp gall_entry(gall), do: {Gall.display_name(gall), gall_generation(gall)}

  defp gall_generation(%Gall{generation_value_id: nil}), do: nil

  defp gall_generation(%Gall{generation_value_id: id}),
    do: Repo.get!(Catalog.Vocab.GenerationValue, id).value

  defp fact_entry(fact) do
    {fact.kind, detail(fact), fact.standing,
     fact.id |> Facts.list_attributions() |> Enum.map(&attribution_entry/1) |> Enum.sort()}
  end

  defp detail(%Fact{id: id, kind: kind}) do
    %{columns: columns, rows: [row]} =
      Repo.query!("SELECT * FROM #{Map.fetch!(@detail_tables, kind)} WHERE fact_id = $1", [id])

    columns
    |> Enum.zip(row)
    |> Enum.reject(fn {column, _} -> column in ["fact_id", "normalized_name"] end)
    |> Enum.map(fn {column, value} -> {column, stable(column, value)} end)
    |> Enum.sort()
  end

  defp stable(_column, nil), do: nil
  defp stable("into_taxon_ids", ids), do: ids |> Enum.map(&Taxa.accepted_name/1) |> Enum.sort()

  defp stable("place_id", id),
    do: Repo.one!(from p in "place", where: p.id == ^id, select: p.code)

  defp stable("of_fact_id", id), do: detail(Facts.get_fact!(id))

  defp stable("trait_value_id", id) do
    value = Repo.get!(Catalog.Vocab.TraitValue, id)
    "#{value.trait}=#{value.value}"
  end

  defp stable(column, id) when column in ["parent_id"], do: Taxa.accepted_name(id)

  defp stable(column, id) do
    cond do
      String.ends_with?(column, "taxon_id") -> Taxa.accepted_name(id)
      String.ends_with?(column, "gall_id") or column == "gall_context_id" -> gall_name(id)
      true -> id
    end
  end

  defp gall_name(id), do: id |> Catalog.get_gall!() |> Gall.display_name()

  defp attribution_entry(a) do
    {Sources.get_source!(a.source_id).title, a.stance, a.stated_on, a.stated_precision,
     a.value_as_written, a.statement_text, a.when_as_written, a.stage_as_written,
     a.status_as_written, a.authorship_as_written,
     a.batch_id && Repo.get!(Batch, a.batch_id).producer_batch_id,
     Enum.sort(
       for e <- a.evidence do
         {e.document_item_id && Repo.get!(DocumentItem, e.document_item_id).ref, e.quote,
          e.span_start, e.span_length, e.page, e.url, e.whole_item, e.cites_as_written}
       end
     ),
     Enum.sort(for n <- a.names, do: {Taxa.accepted_name(n.taxon_id), n.name_as_written, n.role}),
     Enum.sort(for o <- a.observations, do: {o.provider, o.external_id, o.url})}
  end

  # A rename proposal comes from no package.
  defp queue_entry(%QueueItem{kind: :gall_rename} = item) do
    {nil, nil, item.kind, item.proposal["from"], item.proposal["to"], item.status, item.decision}
  end

  defp queue_entry(item) do
    package = Import.get_package!(item.package_id)
    batch = item.batch_id && Import.get_batch!(item.batch_id)

    {package.key, batch && batch.producer_batch_id, item.kind, item.statement_ref, item.status,
     item.decision && StableRef.encode_decision(item.decision)}
  end

  # -- the acceptance test ------------------------------------------------------

  test "replaying the log on a fresh copy gives the same result" do
    load_vocab!()
    gallformers_source()
    source_ids_before = Repo.all(from s in "source", select: s.id)

    # The seed below stands for the data migration: start without the
    # converted seeds' rows.
    wipe!(source_ids_before)
    backscan!(seed!())
    before = snapshot()
    entries = Import.list_replay_entries()

    # The snapshot holds what the backscan did: the new species and its Gall,
    # the synonym and common name, the papers' and Gallformers' Facts.
    assert [_] =
             Enum.filter(
               before.taxa,
               &match?({"Andricus novus", :species, "Animalia", _, "Andricus", _, _}, &1)
             )

    assert [{"Quercus lobata", _, _, _, _, ["Quercus tinctoria"], _}] =
             Enum.filter(before.taxa, &(elem(&1, 5) != []))

    assert [{"Andricus quercuscalifornicus", _, _, _, _, _, ["California gall wasp"]}] =
             Enum.filter(before.taxa, &(elem(&1, 6) != []))

    assert {"Andricus novus (agamic)", "agamic"} in before.galls
    assert length(before.facts) > 10

    statement_texts =
      for {_kind, _detail, _standing, attributions} <- before.facts,
          attribution <- attributions,
          text = elem(attribution, 5),
          text != nil,
          do: text

    assert statement_texts != []

    assert Enum.map(entries, & &1.kind) == [
             :synonym_added,
             :batch_applied,
             :batch_applied,
             :queue_decision,
             :taxonomy_edit,
             :queue_decision,
             :batch_applied,
             :batch_applied
           ]

    # No database IDs in the log: a Gall chosen by an admin is its kept ID.
    assert Enum.find(entries, &(&1.key["statement_ref"] == "g1")).payload ==
             %{"decision" => %{"gall" => %{"id" => @stem_gall_id}}}

    wipe!(source_ids_before)
    assert Repo.aggregate(Taxon, :count) == 0
    seed!()

    assert {:ok, 8} = Replay.run(entries, actor: test_actor())
    assert snapshot() == before
  end

  test "the Host-name step's plants and the taxonomy admin's edits replay by name" do
    seed_tree = fn ->
      quercus = plant_fixture(name: "Quercus", rank: :genus)
      cynipini = taxon_fixture(name: "Cynipini", rank: :tribe, kingdom: "Animalia")
      andricus = taxon_fixture(name: "Andricus", rank: :genus, kingdom: "Animalia")
      %{quercus: quercus, cynipini: cynipini, andricus: andricus}
    end

    wipe!(Repo.all(from s in "source", select: s.id))
    t = seed_tree.()

    {:ok, _} =
      Import.record_plant_added(test_actor(), %{
        name: "Quercus tinctoria",
        rank: :species,
        parent_id: t.quercus.id
      })

    {:ok, sp} =
      Import.record_taxonomy_edit(
        test_actor(),
        {:create_taxon, %{name: "Andricus exemplaris", rank: :species, kingdom: "Animalia"}}
      )

    {:ok, _} = Import.record_taxonomy_edit(test_actor(), {:place, sp, t.andricus})
    {:ok, _} = Import.record_taxonomy_edit(test_actor(), {:place, t.andricus, t.cynipini})
    {:ok, _} = Import.record_taxonomy_edit(test_actor(), {:rename, sp, "Andricus exemplarius"})

    before = snapshot()
    entries = Import.list_replay_entries()
    assert length(entries) == 5

    wipe!(Repo.all(from s in "source", select: s.id))
    seed_tree.()

    assert {:ok, 5} = Replay.run(entries, actor: test_actor())
    assert snapshot() == before

    assert {:ok, renamed} = Taxa.resolve_name("Andricus exemplarius", rank: :species)
    assert Taxa.accepted_name(renamed.parent_id) == "Andricus"
  end

  test "a rename proposal's decision replays after the taxonomy edit that made it" do
    load_vocab!()
    # Sources outlive the wipe, so the seed's own is made once.
    legacy = source_fixture("Legacy", "1990")
    source_ids = Repo.all(from s in "source", select: s.id)
    wipe!(source_ids)

    seed_gall = fn ->
      andricus = taxon_fixture(name: "Andricus", rank: :genus, kingdom: "Animalia")
      wasp = taxon_fixture(name: "Andricus exemplaris", parent: andricus, kingdom: "Animalia")

      {:ok, gall} =
        Catalog.create_gall(test_actor(), %{
          id: @stem_gall_id,
          name: "Andricus exemplaris (agamic)",
          generation_value_id: Catalog.get_generation_value("agamic").id
        })

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
          confirm(legacy)
        )

      wasp
    end

    wasp = seed_gall.()
    {:ok, _} = Import.record_taxonomy_edit(test_actor(), {:rename, wasp, "Andricus exemplarius"})
    [proposal] = Import.list_gall_renames()
    {:ok, _} = Import.decide_queue_item(test_actor(), proposal, %{"accept" => true})

    before = snapshot()
    entries = Import.list_replay_entries()
    assert Enum.map(entries, & &1.kind) == [:taxonomy_edit, :queue_decision]
    assert {"Andricus exemplarius (agamic)", "agamic"} in before.galls

    wipe!(source_ids)
    seed_gall.()

    assert {:ok, 2} = Replay.run(entries, actor: test_actor())
    assert snapshot() == before

    # A decision replayed again is skipped: its proposal is decided.
    assert {:ok, 1} = Replay.run([List.last(entries)], actor: test_actor())
    assert snapshot().galls == before.galls
  end

  test "a log entry that cannot be replayed stops the replay and says which" do
    load_vocab!()

    entries = [
      %{
        kind: :synonym_added,
        key: %{
          "taxon" => %{"name" => "Nothing here", "rank" => "species", "kingdom" => "Plantae"},
          "name" => "Q. nowhere"
        },
        payload: %{}
      }
    ]

    assert {:error, %{index: 0, reason: {:taxon_not_found, _}}} =
             Replay.run(entries, actor: test_actor())
  end
end
