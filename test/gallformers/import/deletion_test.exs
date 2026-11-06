defmodule Gallformers.Import.DeletionTest do
  @moduledoc """
  Deleting a Gall or a taxon (matter `ec2c`, "Deletes"): allowed only when
  nothing from a real Source rests on it (only the "Gallformers legacy
  data" Source and the Gallformers Source), shown first as an impact
  report, rechecked at delete time, audited, replay-logged and broadcast.
  Family and genus deletes cascade (all or nothing), intermediate ranks
  collapse into their parent, a plant section with species is blocked.

  Not async: the tests load the vocabularies and use the Gallformers Source.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures
  import Gallformers.ImportFixtures, only: [applied_package!: 3]

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Facts.Fact
  alias Gallformers.Images
  alias Gallformers.Import
  alias Gallformers.Import.Batch
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon

  setup :audit_test_metadata

  setup do
    load_vocab!()

    %{
      legacy: Sources.get_legacy_data_source(),
      gallformers: Sources.get_gallformers_source(),
      weld: source_fixture("Weld", "1959")
    }
  end

  defp uniq, do: System.unique_integer([:positive])

  defp trait!(gall, value, source, trait \\ "detachable") do
    {:ok, %{fact: fact}} =
      Catalog.assert_trait(
        test_actor(),
        %{gall_id: gall.id, trait: trait, value: value},
        statement(source)
      )

    fact
  end

  defp relationship!(type, taxon, gall, source) do
    {:ok, %{fact: fact}} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: type, subject_taxon_id: taxon.id, object_gall_id: gall.id},
        statement(source)
      )

    fact
  end

  # A Gallformers statement needs its words.
  defp statement(%{kind: :gallformers} = source),
    do: confirm(source, %{statement_text: "Gallformers says so.", stated: "2026-01-01"})

  defp statement(source), do: confirm(source)

  defp image!(owner) do
    {:ok, image} =
      Images.create_image(
        Map.merge(Images.Image.owner_attrs(owner), %{
          path: "gall/#{uniq()}/original.jpg",
          creator: "Tester",
          license: "CC0"
        })
      )

    image
  end

  defp open_item!(subject) do
    Repo.insert!(%QueueItem{kind: :gall_rename, subject: subject, proposal: %{}})
  end

  defp entries(kind), do: for(e <- Import.list_replay_entries(), e.kind == kind, do: e)

  describe "a Gall's impact" do
    test "a Gall with only legacy and Gallformers statements can be deleted", ctx do
      gall = gall_fixture()
      fact = trait!(gall, "integral", ctx.legacy)
      _gf = trait!(gall, "brown", ctx.gallformers, "color")
      image = image!({:gall, gall.id})

      assert {:ok, impact} = Import.deletion_impact({:gall, gall.id})

      assert impact.subject == %{type: :gall, id: gall.id, name: gall.name}
      assert impact.operation == :delete
      assert impact.deletable == true
      assert impact.blockers == []
      assert impact.galls == [%{id: gall.id, name: gall.name}]
      assert impact.taxa == []

      gall_id = gall.id

      assert %{kind: "gall_trait", about: {:gall, ^gall_id}, text: "detachable: integral"} =
               fact_row = Enum.find(impact.facts, &(&1.fact_id == fact.id))

      assert [%{id: legacy_id}] = fact_row.sources
      assert legacy_id == ctx.legacy.id
      assert [%{id: image_id, owner: {:gall, _}}] = impact.images
      assert image_id == image.id
    end

    test "a real Source's statement blocks it, saying why and what to do", ctx do
      gall = gall_fixture()
      trait!(gall, "integral", ctx.weld)
      trait!(gall, "brown", ctx.weld, "color")
      trait!(gall, "detachable", ctx.legacy)

      assert {:ok, impact} = Import.deletion_impact({:gall, gall.id})
      refute impact.deletable

      name = Sources.short_name(ctx.weld)

      assert [
               %{
                 kind: :source_facts,
                 record: {:gall, id},
                 source: %{id: source_id},
                 count: 2,
                 text: text,
                 action: action
               }
             ] = impact.blockers

      assert id == gall.id
      assert source_id == ctx.weld.id
      assert text == "2 Facts from #{name} rest on #{gall.name}"
      assert action =~ "merge it into the right Gall"
      assert action =~ "#{name}'s statements"
    end

    test "an open question naming it blocks it; a decided one is cleaned up", _ctx do
      gall = gall_fixture()
      other = gall_fixture()
      item = open_item!(%{"gall_id" => other.id, "note" => %{"gall_id" => gall.id}})

      assert {:ok, %{blockers: [%{kind: :open_question}]}} =
               Import.deletion_impact({:gall, gall.id})

      item
      |> QueueItem.decide_changeset(%{"accept" => true}, test_actor())
      |> Repo.update!()

      assert {:ok, %{blockers: [], cleanup: [%{kind: :queue_item}]}} =
               Import.deletion_impact({:gall, gall.id})
    end

    test "a package under review naming it blocks it; an applied one is cleaned up", ctx do
      gall = gall_fixture()
      package = applied_package!(ctx.weld, nil, batch_status: :ready)
      batch = Repo.get_by!(Batch, package_id: package.id)

      Repo.insert!(%BatchStatement{
        batch_id: batch.id,
        kind: :gall,
        ref: "g1",
        resolution: :resolved,
        gall_id: gall.id
      })

      assert {:ok, %{blockers: [%{kind: :package_under_review}]}} =
               Import.deletion_impact({:gall, gall.id})

      Repo.update_all(from(b in Batch, where: b.id == ^batch.id),
        set: [status: :applied, applied_at: DateTime.utc_now(:second)]
      )

      assert {:ok, %{blockers: [], cleanup: [%{kind: :batch_statement}]}} =
               Import.deletion_impact({:gall, gall.id})
    end

    test "no such Gall" do
      assert Import.deletion_impact({:gall, -1}) == {:error, :not_found}
    end
  end

  describe "deleting a Gall" do
    test "deletes it with its Facts and images, logs, audits and broadcasts", ctx do
      gall = gall_fixture(gallformers_code: "DEL#{uniq()}")
      fact = trait!(gall, "integral", ctx.legacy)
      image = image!({:gall, gall.id})
      Import.subscribe_records()

      assert {:ok, %{impact: impact, storage_errors: []}} =
               Import.record_deletion(test_actor(), {:gall, gall.id})

      assert impact.galls == [%{id: gall.id, name: gall.name}]
      assert Catalog.get_gall(gall.id) == nil
      assert Repo.get(Fact, fact.id) == nil
      assert Images.get_image(image.id) == nil

      assert_receive {:records_deleted, %{galls: [id], taxa: [], by: "test"}}
      assert id == gall.id

      assert [entry] = entries(:deletion)
      assert entry.key == %{"type" => "gall", "gall" => %{"id" => gall.id}}

      ops = Repo.all(from(c in test_audit_changes(), select: {c.table_name, c.op}))
      assert {"galls", :delete} in ops
      assert {"facts", :delete} in ops
    end

    test "a blocked delete changes nothing", ctx do
      gall = gall_fixture()
      trait!(gall, "integral", ctx.weld)

      assert {:error, {:blocked, [%{kind: :source_facts}]}} =
               Import.record_deletion(test_actor(), {:gall, gall.id})

      assert %Gall{} = Catalog.get_gall(gall.id)
      assert entries(:deletion) == []
    end

    test "already deleted" do
      gall = gall_fixture()
      assert {:ok, _} = Import.record_deletion(test_actor(), {:gall, gall.id})
      assert Import.record_deletion(test_actor(), {:gall, gall.id}) == {:error, :not_found}
    end

    test "a decided question naming it goes with it", _ctx do
      gall = gall_fixture()
      item = open_item!(%{"gall_id" => gall.id})

      item
      |> QueueItem.decide_changeset(%{"reject" => true}, test_actor())
      |> Repo.update!()

      assert {:ok, _} = Import.record_deletion(test_actor(), {:gall, gall.id})
      assert Repo.get(QueueItem, item.id) == nil
    end

    test "a decided question naming it among other things keeps its decision, without it", ctx do
      gall = gall_fixture()
      other = gall_fixture()
      package = applied_package!(ctx.weld, DateTime.utc_now(:second), [])
      batch = Repo.get_by!(Batch, package_id: package.id)

      item =
        Repo.insert!(%QueueItem{
          package_id: package.id,
          batch_id: batch.id,
          kind: :ambiguous_match,
          statement_ref: "g1",
          subject: %{"name" => "Some gall"},
          proposal: %{"candidate_ids" => [gall.id, other.id], "proposed" => other.id},
          status: :decided,
          decision: %{"gall_id" => other.id},
          decided_at: DateTime.utc_now(:second),
          decided_by_name: "t"
        })

      assert {:ok, _} = Import.record_deletion(test_actor(), {:gall, gall.id})

      kept = Repo.get!(QueueItem, item.id)
      assert kept.decision == %{"gall_id" => other.id}
      assert kept.proposal == %{"candidate_ids" => [other.id], "proposed" => other.id}
    end

    test "a decision in a package still under review blocks it", ctx do
      gall = gall_fixture()
      package = applied_package!(ctx.weld, nil, batch_status: :ready)
      batch = Repo.get_by!(Batch, package_id: package.id)

      Repo.insert!(%QueueItem{
        package_id: package.id,
        batch_id: batch.id,
        kind: :ambiguous_match,
        statement_ref: "g1",
        subject: %{},
        proposal: %{},
        status: :decided,
        decision: %{"gall_id" => gall.id},
        decided_at: DateTime.utc_now(:second),
        decided_by_name: "t"
      })

      assert {:error, {:blocked, [%{kind: :open_question}]}} =
               Import.record_deletion(test_actor(), {:gall, gall.id})
    end

    test "replays", ctx do
      gall = gall_fixture()
      trait!(gall, "integral", ctx.legacy)
      Repo.query!("DELETE FROM replay_log")
      assert {:ok, _} = Import.record_deletion(test_actor(), {:gall, gall.id})
      entries = Import.list_replay_entries()

      # Made again on a database that still has it.
      {:ok, _} = Catalog.create_gall(test_actor(), %{id: gall.id, name: gall.name})
      assert {:ok, 1} = Replay.run(entries, actor: test_actor())
      assert Catalog.get_gall(gall.id) == nil

      # Done already: skipped.
      assert {:ok, 1} = Replay.run(entries, actor: test_actor())
    end
  end

  describe "a taxon's impact and delete" do
    setup do
      family = taxon_fixture(rank: :family, name: "Delidae#{uniq()}")
      genus = taxon_fixture(rank: :genus, name: "Delus#{uniq()}", parent: family)
      species = taxon_fixture(name: "#{Taxa.accepted_name(genus)} alpha", parent: genus)
      gall = gall_fixture(name: "#{Taxa.accepted_name(species)} gall")
      %{family: family, genus: genus, species: species, gall: gall}
    end

    test "a genus cascades: its species, their Galls and images", ctx do
      relationship!("inducer_of", ctx.species, ctx.gall, ctx.legacy)
      trait!(ctx.gall, "integral", ctx.legacy)
      image!({:taxon, ctx.species.id})

      assert {:ok, impact} = Import.deletion_impact({:taxon, ctx.genus.id})
      assert impact.operation == :cascade
      assert impact.deletable == true

      assert Enum.map(impact.taxa, & &1.id) |> Enum.sort() ==
               Enum.sort([ctx.genus.id, ctx.species.id])

      assert impact.galls == [%{id: ctx.gall.id, name: ctx.gall.name}]
      assert [%{id: species_id}] = impact.children
      assert species_id == ctx.species.id
      assert [%{owner: {:taxon, _}}] = impact.images

      assert {:ok, _} = Import.record_deletion(test_actor(), {:taxon, ctx.genus.id})
      assert Taxa.get_taxon(ctx.genus.id) == nil
      assert Taxa.get_taxon(ctx.species.id) == nil
      assert Catalog.get_gall(ctx.gall.id) == nil
      assert %Taxon{} = Taxa.get_taxon(ctx.family.id)
    end

    test "any blocker below blocks the whole cascade, named with what to do", ctx do
      relationship!("inducer_of", ctx.species, ctx.gall, ctx.legacy)
      trait!(ctx.gall, "integral", ctx.weld)
      trait!(ctx.gall, "brown", ctx.weld, "color")
      trait!(ctx.gall, "green", ctx.weld, "color")
      trait!(ctx.gall, "red", ctx.weld, "color")

      assert {:ok, impact} = Import.deletion_impact({:taxon, ctx.family.id})
      assert impact.operation == :cascade
      refute impact.deletable

      assert [%{kind: :source_facts, record: {:gall, gall_id}, count: 4, action: action}] =
               impact.blockers

      assert gall_id == ctx.gall.id
      assert action =~ "merge it or move it first"

      assert {:error, {:blocked, _}} =
               Import.record_deletion(test_actor(), {:taxon, ctx.family.id})

      assert %Taxon{} = Taxa.get_taxon(ctx.species.id)
      assert %Gall{} = Catalog.get_gall(ctx.gall.id)
    end

    test "a real Source naming a Host blocks the plant's delete", ctx do
      plant = plant_fixture()
      relationship!("host_of", plant, ctx.gall, ctx.weld)

      assert {:ok, %{operation: :cascade, blockers: [%{record: {:taxon, id}}]}} =
               Import.deletion_impact({:taxon, plant.id})

      assert id == plant.id
    end

    test "deleting a plant takes its legacy Host Facts, not the Galls", ctx do
      plant = plant_fixture()
      host = relationship!("host_of", plant, ctx.gall, ctx.legacy)

      assert {:ok, impact} = Import.deletion_impact({:taxon, plant.id})
      assert impact.galls == []
      assert [%{fact_id: fact_id, rests_on: {:taxon, _}}] = impact.facts
      assert fact_id == host.id

      assert {:ok, _} = Import.record_deletion(test_actor(), {:taxon, plant.id})
      assert Taxa.get_taxon(plant.id) == nil
      assert Repo.get(Fact, host.id) == nil
      assert %Gall{} = Catalog.get_gall(ctx.gall.id)
    end

    test "an intermediate rank collapses: its children go to its parent", ctx do
      subgenus = taxon_fixture(rank: :subgenus, name: "Subdelus#{uniq()}", parent: ctx.genus)
      kid = taxon_fixture(name: "#{Taxa.accepted_name(ctx.genus)} kid#{uniq()}", parent: subgenus)

      assert {:ok, impact} = Import.deletion_impact({:taxon, subgenus.id})
      assert impact.operation == :collapse
      assert impact.deletable == true
      assert [%{id: kid_id}] = impact.children
      assert kid_id == kid.id
      assert impact.parent.id == ctx.genus.id
      assert Enum.map(impact.taxa, & &1.id) == [subgenus.id]

      assert {:ok, _} = Import.record_deletion(test_actor(), {:taxon, subgenus.id})
      assert Taxa.get_taxon(subgenus.id) == nil
      assert Taxa.get_taxon!(kid.id).parent_id == ctx.genus.id
    end

    test "a Gall named for a plant blocks the plant's delete" do
      plant = plant_fixture()
      named = gall_fixture(host_qualifier_taxon_id: plant.id)

      assert {:ok, %{blockers: [%{kind: :host_qualifier, text: text, action: action}]}} =
               Import.deletion_impact({:taxon, plant.id})

      assert text == "#{named.name} is named for #{Taxa.accepted_name(plant)}"
      assert action =~ "name parts"
    end

    test "a plant section with species is blocked until they are moved" do
      genus = plant_fixture(rank: :genus, name: "Sectus#{uniq()}")
      section = plant_fixture(rank: :section, name: "Sectio#{uniq()}", parent: genus)
      _oak = plant_fixture(name: "#{Taxa.accepted_name(genus)} alba", parent: section)

      assert {:ok, %{operation: :blocked, blockers: [%{kind: :section_has_species}]}} =
               Import.deletion_impact({:taxon, section.id})
    end

    test "an open question naming the taxon blocks the old taxonomy-admin delete too" do
      plant = plant_fixture()
      open_item!(%{"gall_id" => -1, "taxon_id" => plant.id})

      assert {:error, {:referenced, [%{table: "queue_items"}]}} =
               Import.record_taxonomy_edit(test_actor(), {:delete_taxon, plant})

      assert %Taxon{} = Taxa.get_taxon(plant.id)
    end
  end

  describe "redirect lookups" do
    test "nothing redirects by default" do
      assert Catalog.gall_redirect(-1) == nil
      assert Catalog.gall_redirect("NOPE") == nil
      assert Taxa.taxon_redirect(-1) == nil
    end
  end
end
