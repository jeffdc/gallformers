defmodule Gallformers.Import.GallRenameTest do
  @moduledoc """
  Rename proposals from taxonomy changes (`86e7` §3, Task 4): a rename or
  move that would change a Gall's derived name queues a `gall_rename` item
  in the admin queue instead of renaming the Gall; a curator accepts (the
  new name takes effect, the old one becomes a `former_label` alias of the
  Gallformers Source) or rejects (the old name is kept as an override).

  Not async: loads the vocabularies (see `Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Facts.AliasFact
  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.ReadModels.GallIndex
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.GallRenames
  alias Gallformers.Import.QueueItem
  alias Gallformers.Sources
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    load_vocab!()
    source = source_fixture("Weld", "1959")
    family = taxon_fixture(rank: :family, name: "Renamitidae", kingdom: "Animalia")
    other_family = taxon_fixture(rank: :family, name: "Othermitidae", kingdom: "Animalia")
    tribe = taxon_fixture(rank: :tribe, name: "Renamitini", parent: family, kingdom: "Animalia")
    genus = taxon_fixture(rank: :genus, name: "Renamita", parent: tribe, kingdom: "Animalia")
    species = taxon_fixture(name: "Renamita alba", parent: genus, kingdom: "Animalia")

    gall =
      gall!("Renamita alba (agamic)", species, source,
        generation: "agamic",
        gallformers_code: "renamita-alba-code"
      )

    %{
      source: source,
      family: family,
      other_family: other_family,
      tribe: tribe,
      genus: genus,
      species: species,
      gall: gall
    }
  end

  # A Gall induced by `inducer`, named as its parts derive.
  defp gall!(name, inducer, source, attrs) do
    gall = attrs |> Map.new() |> Map.put(:name, name) |> gall_fixture()

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: inducer.id, object_gall_id: gall.id},
        confirm(source)
      )

    assert Catalog.derived_name(gall.id) == {:ok, name}
    gall
  end

  defp proposals(gall),
    do: Enum.filter(Import.list_gall_renames(), &(&1.subject["gall_id"] == gall.id))

  defp rename!(taxon, name), do: {:ok, _} = Taxa.rename(test_actor(), taxon, name)

  defp decide(item, decision), do: Import.decide_queue_item(test_actor(), item, decision)

  describe "proposals" do
    test "renaming an Inducer proposes a rename per affected Gall and renames none", ctx do
      sexgen = gall!("Renamita alba (sexgen)", ctx.species, ctx.source, generation: "sexual")

      rename!(ctx.species, "Renamita nigra")

      assert [%QueueItem{kind: :gall_rename, status: :open, package_id: nil} = item] =
               proposals(ctx.gall)

      assert item.proposal == %{
               "gall_id" => ctx.gall.id,
               "from" => "Renamita alba (agamic)",
               "to" => "Renamita nigra (agamic)",
               "collision" => false
             }

      assert item.reason =~ "Renamita alba"
      assert [%{proposal: %{"to" => "Renamita nigra (sexgen)"}}] = proposals(sexgen)

      assert Catalog.get_gall!(ctx.gall.id).name == "Renamita alba (agamic)"
      assert Catalog.get_gall!(sexgen.id).name == "Renamita alba (sexgen)"
    end

    test "a Gall with a name override gets no proposal", ctx do
      {:ok, _} = Catalog.update_name_parts(test_actor(), ctx.gall, %{name_override: "Alba gall"})

      rename!(ctx.species, "Renamita nigra")

      assert proposals(ctx.gall) == []
      assert Gall.display_name(Catalog.get_gall!(ctx.gall.id)) == "Alba gall"
    end

    test "a Gall whose name can't be derived gets no proposal", ctx do
      # An undescribed Gall without a descriptor: no base.
      gall = gall_fixture(name: "Renamita provisional gall")

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: ctx.genus.id, object_gall_id: gall.id},
          confirm(ctx.source)
        )

      rename!(ctx.genus, "Renamitella")

      assert proposals(gall) == []
    end

    test "renaming a Host-qualifier taxon proposes a rename", ctx do
      plant = plant_fixture(name: "Renamquercus alba")

      {:ok, gall} =
        Catalog.update_name_parts(test_actor(), ctx.gall, %{host_qualifier_taxon_id: plant.id})

      assert gall.name == "Renamita alba (agamic) (on Renamquercus alba)"

      rename!(plant, "Renamquercus nova")

      assert [%{proposal: %{"to" => "Renamita alba (agamic) (on Renamquercus nova)"}}] =
               proposals(gall)
    end

    test "moving a tribe to another family proposes renames for its 'Unknown (Family)' Galls only",
         ctx do
      unknown =
        gall!("Unknown (Renamitidae) q-alba-cup-gall", ctx.tribe, ctx.source,
          descriptor: "q-alba-cup-gall"
        )

      genus_level =
        gall!("Renamita q-alba-bead-gall", ctx.genus, ctx.source, descriptor: "q-alba-bead-gall")

      {:ok, _} = Taxa.place(test_actor(), ctx.tribe, ctx.other_family)

      assert [%{proposal: %{"from" => "Unknown (Renamitidae) q-alba-cup-gall"} = proposal}] =
               proposals(unknown)

      assert proposal["to"] == "Unknown (Othermitidae) q-alba-cup-gall"
      assert proposals(genus_level) == []
      assert proposals(ctx.gall) == []
    end

    test "moving a genus to another family leaves genus-based names alone", ctx do
      genus_level =
        gall!("Renamita q-alba-bead-gall", ctx.genus, ctx.source, descriptor: "q-alba-bead-gall")

      {:ok, _} = Taxa.place(test_actor(), ctx.genus, ctx.other_family)

      assert Import.list_gall_renames() == []
      assert Catalog.get_gall!(genus_level.id).name == "Renamita q-alba-bead-gall"
    end

    test "renaming a family proposes renames for its 'Unknown (Family)' Galls", ctx do
      unknown =
        gall!("Unknown (Renamitidae) q-alba-cup-gall", ctx.tribe, ctx.source,
          descriptor: "q-alba-cup-gall"
        )

      rename!(ctx.family, "Novamitidae")

      assert [%{proposal: %{"to" => "Unknown (Novamitidae) q-alba-cup-gall"}}] =
               proposals(unknown)

      assert proposals(ctx.gall) == []
    end

    test "a second change updates the open proposal instead of adding another", ctx do
      rename!(ctx.species, "Renamita nigra")
      rename!(ctx.species, "Renamita rubra")

      assert [%{proposal: proposal}] = proposals(ctx.gall)

      assert {proposal["from"], proposal["to"]} ==
               {"Renamita alba (agamic)", "Renamita rubra (agamic)"}
    end

    test "a change back to the Gall's name withdraws the open proposal", ctx do
      rename!(ctx.species, "Renamita nigra")
      rename!(ctx.species, "Renamita alba")

      assert proposals(ctx.gall) == []
    end

    test "a colliding name is flagged and the taxonomy change still goes through", ctx do
      gall_fixture(name: "RENAMITA NIGRA (agamic)")

      assert {:ok, _} = Taxa.rename(test_actor(), ctx.species, "Renamita nigra")

      assert [%{proposal: %{"to" => "Renamita nigra (agamic)", "collision" => true}}] =
               proposals(ctx.gall)

      assert Taxa.accepted_name(ctx.species.id) == "Renamita nigra"
    end
  end

  describe "deciding" do
    setup ctx do
      rename!(ctx.species, "Renamita nigra")
      [item] = proposals(ctx.gall)
      %{item: item}
    end

    test "accept applies the new name, keeps the old one as a former label, leaves the code",
         ctx do
      :ok = Catalog.refresh_gall_index([ctx.gall.id])

      assert {:ok, %QueueItem{status: :decided, decision: %{"accept" => true}}} =
               decide(ctx.item, %{"accept" => true})

      gall = Catalog.get_gall!(ctx.gall.id)
      assert {gall.name, gall.name_override} == {"Renamita nigra (agamic)", nil}
      assert gall.gallformers_code == "renamita-alba-code"
      assert Repo.get!(GallIndex, gall.id).name == "Renamita nigra (agamic)"

      former = Repo.get_by!(AliasFact, gall_id: gall.id, name: "Renamita alba (agamic)")
      assert former.kind == :former_label

      gallformers = Sources.get_gallformers_source()
      assert [attribution] = Facts.list_attributions(former.fact_id)
      assert attribution.source_id == gallformers.id
      assert attribution.stance == :confirm
      assert attribution.stated_on == Date.utc_today()
      assert attribution.statement_text =~ "Renamita nigra (agamic)"
    end

    test "the decision is audited and recorded in the replay log", ctx do
      {:ok, _} = decide(ctx.item, %{"accept" => true})

      tables =
        Repo.all(from(c in test_audit_changes(), where: c.op == :update, select: c.table_name))

      assert "galls" in tables
      assert "queue_items" in tables

      assert %{kind: :queue_decision, key: key, payload: payload} =
               List.last(Import.list_replay_entries())

      assert key == %{
               "package" => nil,
               "batch_id" => nil,
               "kind" => "gall_rename",
               "statement_ref" => nil,
               "gall" => %{"id" => ctx.gall.id},
               "to" => "Renamita nigra (agamic)"
             }

      assert payload == %{"decision" => %{"accept" => true}, "from" => "Renamita alba (agamic)"}
    end

    test "reject keeps the displayed name as an override", ctx do
      assert {:ok, %QueueItem{status: :decided}} = decide(ctx.item, %{"reject" => true})

      gall = Catalog.get_gall!(ctx.gall.id)
      assert Gall.display_name(gall) == "Renamita alba (agamic)"
      assert gall.name_override == "Renamita alba (agamic)"
      assert gall.name == "Renamita nigra (agamic)"
      assert gall.gallformers_code == "renamita-alba-code"
      assert Repo.get_by(AliasFact, gall_id: gall.id) == nil

      # With an override, later taxonomy changes propose nothing.
      rename!(ctx.species, "Renamita rubra")
      assert proposals(gall) == []
    end

    test "a decision must be accept or reject", ctx do
      assert {:error, changeset} = decide(ctx.item, %{"gall_id" => ctx.gall.id})
      assert %{decision: [_]} = errors_on(changeset)
      assert {:error, _} = decide(ctx.item, %{"accept" => false})
    end

    test "a colliding name can't be accepted until the other Gall's name changes", ctx do
      other = gall_fixture(name: "Renamita nigra (agamic) other")

      {:ok, other} =
        Catalog.update_name_parts(test_actor(), other, %{name_override: "renamita NIGRA (agamic)"})

      assert {:error, changeset} = decide(ctx.item, %{"accept" => true})
      assert %{decision: [message]} = errors_on(changeset)
      assert message =~ "another Gall"
      assert [%{status: :open}] = proposals(ctx.gall)
      assert Catalog.get_gall!(ctx.gall.id).name == "Renamita alba (agamic)"

      {:ok, _} =
        Catalog.update_name_parts(test_actor(), other, %{name_override: "Renamita other"})

      assert {:ok, _} = decide(ctx.item, %{"accept" => true})
      assert Catalog.get_gall!(ctx.gall.id).name == "Renamita nigra (agamic)"
    end

    test "accept uses the name the parts give now", ctx do
      # The taxonomy changed again after the proposal was made, with the
      # listener not hearing of it (e.g. a proposal from an earlier run).
      Repo.query!(
        "UPDATE taxon_names SET name = 'Renamita rubra' WHERE taxon_id = $1 AND status = 'accepted'",
        [
          ctx.species.id
        ]
      )

      assert {:ok, item} = decide(ctx.item, %{"accept" => true})
      assert Catalog.get_gall!(ctx.gall.id).name == "Renamita rubra (agamic)"
      assert item.proposal["to"] == "Renamita rubra (agamic)"
      assert item.reason =~ "Renamita nigra (agamic)"
    end
  end

  test "is registered as a taxon-changed listener" do
    assert GallRenames in Taxa.Events.listeners()
  end
end
