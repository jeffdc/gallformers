defmodule Gallformers.Taxa.TreeTest do
  @moduledoc """
  The editorial taxonomy tree (`9449` §3): creating taxa, and the tree
  validator every parent change goes through (no cycles; a child ranks below
  its parent).
  """
  use Gallformers.DataCase, async: true

  import Gallformers.TaxaFixtures

  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.TaxonName

  defp changes_for(table) do
    Repo.all(from c in Carbonite.Change, where: c.table_name == ^table, order_by: c.id)
  end

  defp parent_id(taxon), do: Taxa.get_taxon!(taxon.id).parent_id

  describe "create_taxon/2" do
    test "creates a taxon with its accepted name" do
      family = taxon_fixture(rank: :family, name: "Cynipidae", kingdom: "Animalia")

      assert {:ok, %Taxon{} = genus} =
               Taxa.create_taxon(test_actor(), %{
                 rank: :genus,
                 origin: :curated,
                 parent_id: family.id,
                 kingdom: "Animalia",
                 name: "Andricus",
                 authorship: "Hartig, 1840"
               })

      assert %Taxon{rank: :genus, origin: :curated, kingdom: "Animalia"} = genus
      assert genus.parent_id == family.id

      assert [%TaxonName{name: "Andricus", status: :accepted, authorship: "Hartig, 1840"}] =
               Taxa.get_taxon!(genus.id).names

      assert Taxa.accepted_name(genus) == "Andricus"
    end

    test "taxon IDs come from the sequence shared with Galls" do
      %{rows: [[default]]} =
        Repo.query!("""
        SELECT column_default FROM information_schema.columns
        WHERE table_name = 'taxa' AND column_name = 'id'
        """)

      assert default =~ "entity_id_seq"
    end

    test "a child takes its parent's kingdom when none is given" do
      genus = taxon_fixture(rank: :genus, kingdom: "Plantae", origin: :powo)
      species = taxon_fixture(rank: :species, parent: genus, origin: :powo)

      assert species.kingdom == "Plantae"
    end

    test "needs a rank, an origin and a name" do
      assert {:error, changeset} = Taxa.create_taxon(test_actor(), %{})
      errors = errors_on(changeset)

      assert errors.rank == ["can't be blank"]
      assert errors.origin == ["can't be blank"]
      assert errors.name == ["can't be blank"]
    end

    test "an unknown rank is rejected" do
      assert {:error, changeset} =
               Taxa.create_taxon(test_actor(), %{rank: "clade", origin: :curated, name: "X"})

      assert %{rank: ["is invalid"]} = errors_on(changeset)
    end

    test "a parent must rank above its child" do
      species = taxon_fixture(rank: :species)

      assert {:error, changeset} =
               Taxa.create_taxon(test_actor(), %{
                 rank: :genus,
                 origin: :curated,
                 name: "Upside",
                 parent_id: species.id
               })

      assert {_, [validation: :rank_inversion]} = changeset.errors[:parent_id]
    end

    test "a parent that does not exist is rejected" do
      assert {:error, changeset} =
               Taxa.create_taxon(test_actor(), %{
                 rank: :species,
                 origin: :curated,
                 name: "Orphan",
                 parent_id: -1
               })

      assert %{parent_id: ["does not exist"]} = errors_on(changeset)
    end

    test "is audited" do
      taxon = taxon_fixture()

      assert [%{op: :insert, table_pk: [pk]}] = changes_for("taxa")
      assert pk == to_string(taxon.id)
      assert [%{op: :insert}] = changes_for("taxon_names")
    end
  end

  describe "acceptance: placements forming a cycle or rank inversion are rejected" do
    setup do
      family = taxon_fixture(rank: :family, name: "Cynipidae")
      genus = taxon_fixture(rank: :genus, name: "Andricus", parent: family)
      subgenus = taxon_fixture(rank: :subgenus, name: "Callirhytis", parent: genus)
      species = taxon_fixture(rank: :species, name: "Andricus foo", parent: subgenus)

      %{family: family, genus: genus, subgenus: subgenus, species: species}
    end

    # While every edge respects rank order a cycle is also a rank inversion;
    # the cycle is reported, since it is the deeper fault.
    test "placing a taxon under its own descendant is rejected", ctx do
      assert {:error, changeset} = Taxa.place(test_actor(), ctx.genus, ctx.species)
      assert {_, [validation: :cycle]} = changeset.errors[:parent_id]

      assert {:error, changeset} = Taxa.place(test_actor(), ctx.family, ctx.subgenus)
      assert {_, [validation: :cycle]} = changeset.errors[:parent_id]

      assert parent_id(ctx.genus) == ctx.family.id
      assert parent_id(ctx.family) == nil
    end

    test "placing a taxon under itself is rejected", ctx do
      assert {:error, changeset} = Taxa.place(test_actor(), ctx.genus, ctx.genus)
      assert {_, [validation: :cycle]} = changeset.errors[:parent_id]
      assert parent_id(ctx.genus) == ctx.family.id
    end

    test "placing a taxon under one of the same or lower rank is rejected", ctx do
      other_genus = taxon_fixture(rank: :genus, name: "Cynips", parent: ctx.family)

      assert {:error, changeset} = Taxa.place(test_actor(), ctx.genus, other_genus)
      assert {_, [validation: :rank_inversion]} = changeset.errors[:parent_id]

      elsewhere = taxon_fixture(rank: :species, name: "Cynips bar")
      assert {:error, changeset} = Taxa.place(test_actor(), ctx.subgenus, elsewhere)
      assert {_, [validation: :rank_inversion]} = changeset.errors[:parent_id]

      assert parent_id(ctx.genus) == ctx.family.id
      assert parent_id(ctx.subgenus) == ctx.genus.id
    end

    test "a valid move changes the parent and is audited", ctx do
      other_family = taxon_fixture(rank: :family, name: "Cecidomyiidae")

      assert {:ok, %Taxon{} = moved} = Taxa.place(test_actor(), ctx.genus, other_family)
      assert moved.parent_id == other_family.id
      assert parent_id(ctx.genus) == other_family.id

      assert %{op: :update, changed_from: %{"parent_id" => from}} =
               List.last(changes_for("taxa"))

      assert from == ctx.family.id
    end

    test "a taxon can be made a root", ctx do
      assert {:ok, %Taxon{parent_id: nil}} = Taxa.place(test_actor(), ctx.genus, nil)
      assert parent_id(ctx.genus) == nil
    end

    test "taxa can be given by ID", ctx do
      other_family = taxon_fixture(rank: :family)
      assert {:ok, _} = Taxa.place(test_actor(), ctx.genus.id, other_family.id)
      assert parent_id(ctx.genus) == other_family.id
    end
  end
end
