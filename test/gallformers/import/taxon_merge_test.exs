defmodule Gallformers.Import.TaxonMergeTest do
  @moduledoc """
  A lump across contexts (`f923` Task 4): merging taxon B into A re-points
  B's Inducer Facts (and its other gall Facts) to A with their attributions
  and `name_as_written`, combines them with A's where A holds the same
  Fact, and proposes the Gall renames that follow; a name collision is
  flagged on the proposal (the existing flow), and what still blocks
  (an open question naming B) fails the merge with the reason.

  Not async: loads the vocabularies.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon

  setup :audit_test_metadata

  setup do
    load_vocab!()
    weld = source_fixture("Weld", "1959")
    family = taxon_fixture(rank: :family, name: "Lumpidae", kingdom: "Animalia")
    genus = taxon_fixture(rank: :genus, name: "Lumpa", parent: family)
    survivor = taxon_fixture(name: "Lumpa alba", parent: genus)
    absorbed = taxon_fixture(name: "Lumpa nigra", parent: genus)

    %{weld: weld, genus: genus, survivor: survivor, absorbed: absorbed}
  end

  defp gall!(name, inducer, source, attrs) do
    gall = attrs |> Map.new() |> Map.put(:name, name) |> gall_fixture()

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: inducer.id, object_gall_id: gall.id},
        confirm(source, %{
          names: [
            %{taxon_id: inducer.id, name_as_written: Taxa.accepted_name(inducer), role: "subject"}
          ]
        })
      )

    gall
  end

  defp inducer_ids(gall) do
    from(r in Current.relationships("inducer_of"),
      where: r.object_gall_id == ^gall.id,
      select: r.subject_taxon_id
    )
    |> Repo.all()
  end

  defp proposals(gall),
    do: Enum.filter(Import.list_gall_renames(), &(&1.subject["gall_id"] == gall.id))

  test "re-points the absorbed taxon's Inducer Facts, keeping their Sources, and proposes renames",
       ctx do
    gall = gall!("Lumpa nigra (agamic)", ctx.absorbed, ctx.weld, generation: "agamic")
    [%{fact_id: fact_id}] = Catalog.facts_naming_taxa([ctx.absorbed.id])
    [attribution] = Facts.list_attributions(fact_id)

    assert {:ok, _} = Taxa.merge(test_actor(), ctx.absorbed, ctx.survivor)

    assert inducer_ids(gall) == [ctx.survivor.id]
    [%{fact_id: now}] = Catalog.facts_naming_taxa([ctx.survivor.id])
    assert [moved] = Facts.list_attributions(now)
    assert moved.id == attribution.id
    assert [%{name_as_written: "Lumpa nigra", taxon_id: s}] = moved.names
    assert s == ctx.survivor.id

    assert [
             %QueueItem{
               proposal: %{"from" => "Lumpa nigra (agamic)", "to" => "Lumpa alba (agamic)"}
             }
           ] =
             proposals(gall)

    assert Catalog.get_gall!(gall.id).name == "Lumpa nigra (agamic)"
  end

  test "an Inducer Fact the survivor holds already gains the absorbed one's Sources", ctx do
    kinsey = source_fixture("Kinsey", "1930")
    gall = gall!("Lumpa alba (sexgen)", ctx.survivor, kinsey, generation: "sexual")

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: ctx.absorbed.id, object_gall_id: gall.id},
        confirm(ctx.weld)
      )

    assert {:ok, _} = Taxa.merge(test_actor(), ctx.absorbed, ctx.survivor)

    assert inducer_ids(gall) == [ctx.survivor.id]
    [%{fact_id: fact_id}] = Catalog.facts_naming_taxa([ctx.survivor.id])

    assert Enum.sort(Enum.map(Facts.list_attributions(fact_id), & &1.source_id)) ==
             Enum.sort([kinsey.id, ctx.weld.id])
  end

  test "a Gall name collision is flagged on the proposal, not a failure", ctx do
    _taken = gall!("Lumpa alba (agamic)", ctx.survivor, ctx.weld, generation: "agamic")
    gall = gall!("Lumpa nigra (agamic)", ctx.absorbed, ctx.weld, generation: "agamic")

    assert {:ok, _} = Taxa.merge(test_actor(), ctx.absorbed, ctx.survivor)
    assert [%QueueItem{proposal: %{"collision" => true}}] = proposals(gall)
  end

  test "an open question naming the absorbed taxon fails the merge with the reason", ctx do
    # A rename proposal about another Gall, naming the absorbed taxon.
    other = gall_fixture()

    Repo.insert!(%QueueItem{
      kind: :gall_rename,
      subject: %{"gall_id" => other.id, "taxon_id" => ctx.absorbed.id},
      proposal: %{}
    })

    assert {:error, {:rejected, Gallformers.Import.TaxonMerges, {:blocked, [_ | _]}}} =
             Taxa.merge(test_actor(), ctx.absorbed, ctx.survivor)

    assert %Taxon{} = Taxa.get_taxon(ctx.absorbed.id)
  end
end
