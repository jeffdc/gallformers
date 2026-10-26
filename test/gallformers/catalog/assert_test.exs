defmodule Gallformers.Catalog.AssertTest do
  @moduledoc """
  Galls and the gall Fact kinds (`9449` §4, Task 9): each kind's natural key,
  endpoint and vocabulary checks, and slots.

  Not async: Trait tests load the vocabularies (see
  `Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Audit
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Facts.AliasFact
  alias Gallformers.Catalog.Facts.DescriptionFact
  alias Gallformers.Catalog.Facts.QualifierFact
  alias Gallformers.Catalog.Facts.RangeFact
  alias Gallformers.Catalog.Facts.RelationshipFact
  alias Gallformers.Catalog.Facts.TraitFact
  alias Gallformers.Catalog.Gall
  alias Gallformers.Facts
  alias Gallformers.Facts.Fact
  alias Gallformers.Sources.SourceDocument

  defp standing(fact_id), do: Facts.get_fact!(fact_id).standing

  defp changes_for(table) do
    Repo.all(from c in Carbonite.Change, where: c.table_name == ^table, order_by: c.id)
  end

  defp next_entity_id do
    %{rows: [[id]]} = Repo.query!("SELECT nextval('entity_id_seq')")
    id
  end

  setup do
    %{source: source_fixture("Weld", "1959")}
  end

  # -- Galls -------------------------------------------------------------------

  describe "create_gall/2" do
    test "takes its ID from the sequence Galls share with taxa" do
      before = next_entity_id()
      gall = gall_fixture()
      taxon = taxon_fixture()

      assert before < gall.id
      assert gall.id < taxon.id
    end

    test "keeps an explicit ID, as migrated Galls keep their species IDs" do
      id = next_entity_id() + 1_000
      assert %Gall{id: ^id} = gall_fixture(id: id)
      assert Catalog.get_gall!(id).id == id
    end

    test "its display name is the override when there is one, and is unique" do
      gall = gall_fixture(name: "Andricus foo (agamic)")
      assert Gall.display_name(gall) == "Andricus foo (agamic)"

      overridden = gall_fixture(name: "Andricus bar", name_override: "Andricus bar (on Q. alba)")
      assert Gall.display_name(overridden) == "Andricus bar (on Q. alba)"

      assert {:error, changeset} =
               Catalog.create_gall(test_actor(), %{
                 name: "x",
                 name_override: "Andricus foo (agamic)"
               })

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "its Code is unique when given" do
      gall_fixture(gallformers_code: "GF-1")

      assert {:error, changeset} =
               Catalog.create_gall(test_actor(), %{name: "other", gallformers_code: "GF-1"})

      assert %{gallformers_code: ["has already been taken"]} = errors_on(changeset)
    end

    test "carries a generation value and an abundance" do
      load_vocab!()
      agamic = Catalog.get_generation_value("agamic")

      gall = gall_fixture(generation_value_id: agamic.id, abundance_id: 1, datacomplete: true)
      assert %Gall{generation_value_id: id, abundance_id: 1, datacomplete: true} = gall
      assert id == agamic.id

      assert {:error, changeset} =
               Catalog.create_gall(test_actor(), %{name: "y", abundance_id: -1})

      assert %{abundance_id: ["does not exist"]} = errors_on(changeset)
    end

    test "is audited" do
      gall = gall_fixture()
      assert [%{op: :insert, table_pk: [pk]}] = changes_for("galls")
      assert pk == to_string(gall.id)
    end

    test "a Gall's note document must belong to a Gall", %{source: source} do
      changeset =
        SourceDocument.changeset(%SourceDocument{}, %{
          source_id: source.id,
          kind: :note,
          s3_key: "notes/x.md",
          sha256: String.duplicate("a", 64),
          gall_id: -1,
          version_date: ~D[2026-10-24]
        })

      assert {:error, %Ecto.Changeset{} = changeset} =
               Audit.transaction(test_actor(), "test.note", fn ->
                 case Repo.insert(changeset) do
                   {:ok, document} -> document
                   {:error, changeset} -> Repo.rollback(changeset)
                 end
               end)

      assert %{gall_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  # -- Relationships -----------------------------------------------------------

  describe "assert_relationship/3" do
    setup do
      %{gall: gall_fixture(), other: gall_fixture(), wasp: taxon_fixture(kingdom: "Animalia")}
    end

    test "an organism-to-Gall Relationship is keyed by type, subject and object", ctx do
      key = %{type: "inducer_of", subject_taxon_id: ctx.wasp.id, object_gall_id: ctx.gall.id}

      {:ok, first} = Catalog.assert_relationship(test_actor(), key, confirm(ctx.source))

      {:ok, same} =
        Catalog.assert_relationship(test_actor(), key, confirm(source_fixture("B", "1960")))

      {:ok, other} =
        Catalog.assert_relationship(
          test_actor(),
          %{key | type: "emerged_from"},
          confirm(ctx.source)
        )

      assert same.fact.id == first.fact.id
      assert other.fact.id != first.fact.id
      assert %Fact{kind: "gall_relationship", slot: nil, standing: :current} = first.fact
      assert %RelationshipFact{type: "inducer_of", subject_taxon_id: s} = first.detail
      assert s == ctx.wasp.id
    end

    test "a genus is a Host when it is a plant", ctx do
      quercus = plant_fixture(rank: :genus, name: "Quercus")

      assert {:ok, %{detail: %RelationshipFact{type: "host_of"}}} =
               Catalog.assert_relationship(
                 test_actor(),
                 %{type: "host_of", subject_taxon_id: quercus.id, object_gall_id: ctx.gall.id},
                 confirm(ctx.source)
               )
    end

    test "a Gall-to-Gall Relationship joins two different Galls", ctx do
      {:ok, rel} =
        Catalog.assert_relationship(
          test_actor(),
          %{
            type: "alternate_generation_of",
            subject_gall_id: ctx.gall.id,
            object_gall_id: ctx.other.id
          },
          confirm(ctx.source)
        )

      assert %RelationshipFact{subject_gall_id: s, object_gall_id: o} = rel.detail
      assert {s, o} == {ctx.gall.id, ctx.other.id}

      assert {:error, changeset} =
               Catalog.assert_relationship(
                 test_actor(),
                 %{
                   type: "modified_form_of",
                   subject_gall_id: ctx.gall.id,
                   object_gall_id: ctx.gall.id
                 },
                 confirm(ctx.source)
               )

      assert %{object_gall_id: ["can't be the subject Gall"]} = errors_on(changeset)
    end

    test "an organism-to-organism Relationship happens in a Gall", ctx do
      parasitoid = taxon_fixture(kingdom: "Animalia")

      key = %{
        type: "parasitoid_of",
        subject_taxon_id: parasitoid.id,
        object_taxon_id: ctx.wasp.id,
        gall_context_id: ctx.gall.id
      }

      {:ok, in_gall} = Catalog.assert_relationship(test_actor(), key, confirm(ctx.source))

      {:ok, in_other} =
        Catalog.assert_relationship(
          test_actor(),
          %{key | gall_context_id: ctx.other.id},
          confirm(ctx.source)
        )

      assert in_other.fact.id != in_gall.fact.id

      assert {:error, changeset} =
               Catalog.assert_relationship(
                 test_actor(),
                 Map.delete(key, :gall_context_id),
                 confirm(ctx.source)
               )

      assert %{gall_context_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "endpoints must be the kinds the type takes", ctx do
      for key <- [
            # a Gall as an organism-to-Gall subject
            %{type: "inducer_of", subject_gall_id: ctx.other.id, object_gall_id: ctx.gall.id},
            # a taxon as a Gall-to-Gall object
            %{
              type: "modified_form_of",
              subject_gall_id: ctx.gall.id,
              object_taxon_id: ctx.wasp.id
            },
            # a Gall context on a Relationship that is not between organisms
            %{
              type: "inducer_of",
              subject_taxon_id: ctx.wasp.id,
              object_gall_id: ctx.gall.id,
              gall_context_id: ctx.other.id
            }
          ] do
        assert {:error, changeset} =
                 Catalog.assert_relationship(test_actor(), key, confirm(ctx.source))

        refute changeset.valid?
      end
    end

    test "the database enforces each type's endpoint kinds", ctx do
      {:ok, fact} = Facts.create_fact(test_actor(), %{kind: "gall_relationship"})

      assert_raise Postgrex.Error, ~r/relationship_facts_endpoint_kinds/, fn ->
        Repo.insert_all("relationship_facts", [
          %{
            fact_id: fact.id,
            type: "host_of",
            subject_gall_id: ctx.other.id,
            object_gall_id: ctx.gall.id
          }
        ])
      end
    end

    test "an unknown type is rejected", ctx do
      assert {:error, changeset} =
               Catalog.assert_relationship(
                 test_actor(),
                 %{type: "eats", subject_taxon_id: ctx.wasp.id, object_gall_id: ctx.gall.id},
                 confirm(ctx.source)
               )

      assert %{type: ["is invalid"]} = errors_on(changeset)
    end
  end

  # -- Qualifiers --------------------------------------------------------------

  describe "assert_qualifier/3" do
    setup ctx do
      gall = gall_fixture()

      relationship = fn type ->
        {:ok, %{fact: fact}} =
          Catalog.assert_relationship(
            test_actor(),
            %{type: type, subject_taxon_id: taxon_fixture().id, object_gall_id: gall.id},
            confirm(ctx.source)
          )

        fact
      end

      %{relationship: relationship}
    end

    test "is keyed by its Relationship, qualifier and value; one Fact per value", ctx do
      rel = ctx.relationship.("parasitoid_in")
      key = %{of_fact_id: rel.id, qualifier: "parasitism_mode", value: "koinobiont"}

      {:ok, first} = Catalog.assert_qualifier(test_actor(), key, confirm(ctx.source))

      {:ok, same} =
        Catalog.assert_qualifier(test_actor(), key, confirm(source_fixture("B", "1970")))

      {:ok, other} =
        Catalog.assert_qualifier(test_actor(), %{key | value: "solitary"}, confirm(ctx.source))

      assert same.fact.id == first.fact.id
      assert other.fact.id != first.fact.id
      assert %QualifierFact{qualifier: "parasitism_mode", value: "koinobiont"} = first.detail
    end

    test "required for formation takes the contract's true", ctx do
      rel = ctx.relationship.("symbiont_of")

      assert {:ok, %{detail: %QualifierFact{value: "true"}}} =
               Catalog.assert_qualifier(
                 test_actor(),
                 %{of_fact_id: rel.id, qualifier: "required_for_formation", value: true},
                 confirm(ctx.source)
               )
    end

    test "lethality has one value per Relationship: the newest Source's value supersedes",
         ctx do
      rel = ctx.relationship.("inquiline_of")

      {:ok, older} =
        Catalog.assert_qualifier(
          test_actor(),
          %{of_fact_id: rel.id, qualifier: "lethality", value: "non-lethal"},
          confirm(ctx.source)
        )

      {:ok, newer} =
        Catalog.assert_qualifier(
          test_actor(),
          %{of_fact_id: rel.id, qualifier: "lethality", value: "lethal"},
          confirm(source_fixture("Revision", "1990"))
        )

      assert newer.fact.slot == "relationship:#{rel.id}:lethality"
      assert older.fact.slot == newer.fact.slot
      assert standing(newer.fact.id) == :current
      assert standing(older.fact.id) == :superseded
    end

    test "must fit its Relationship's type", ctx do
      rel = ctx.relationship.("emerged_from")

      assert {:error, changeset} =
               Catalog.assert_qualifier(
                 test_actor(),
                 %{of_fact_id: rel.id, qualifier: "lethality", value: "lethal"},
                 confirm(ctx.source)
               )

      assert %{qualifier: ["does not fit a emerged_from Relationship"]} = errors_on(changeset)
    end

    test "takes only the qualifier's values", ctx do
      rel = ctx.relationship.("inquiline_of")

      assert {:error, changeset} =
               Catalog.assert_qualifier(
                 test_actor(),
                 %{of_fact_id: rel.id, qualifier: "lethality", value: "koinobiont"},
                 confirm(ctx.source)
               )

      assert %{value: ["is invalid"]} = errors_on(changeset)
    end

    test "qualifies a Relationship Fact only", ctx do
      {:ok, not_a_relationship} = Facts.create_fact(test_actor(), %{kind: "gall_trait"})

      assert {:error, changeset} =
               Catalog.assert_qualifier(
                 test_actor(),
                 %{of_fact_id: not_a_relationship.id, qualifier: "lethality", value: "lethal"},
                 confirm(ctx.source)
               )

      assert %{of_fact_id: ["is not a Relationship Fact"]} = errors_on(changeset)
    end
  end

  # -- Traits ------------------------------------------------------------------

  describe "assert_trait/3" do
    setup do
      load_vocab!()
      %{gall: gall_fixture()}
    end

    test "is keyed by Gall and Trait value; multi-valued Traits have no slot", ctx do
      key = %{gall_id: ctx.gall.id, trait: "color", value: "red"}

      {:ok, first} =
        Catalog.assert_trait(
          test_actor(),
          key,
          confirm(ctx.source, %{value_as_written: "crimson"})
        )

      {:ok, same} =
        Catalog.assert_trait(test_actor(), key, confirm(source_fixture("B", "1970")))

      {:ok, other} =
        Catalog.assert_trait(test_actor(), %{key | value: "green"}, confirm(ctx.source))

      assert same.fact.id == first.fact.id
      assert other.fact.id != first.fact.id
      assert %Fact{kind: "gall_trait", slot: nil} = first.fact
      assert %TraitFact{trait_value_id: id} = first.detail
      assert id == Catalog.get_trait_value("color", "red").id
      assert standing(other.fact.id) == :current
    end

    test "detachable has one value: the newest Source's value supersedes", ctx do
      {:ok, older} =
        Catalog.assert_trait(
          test_actor(),
          %{gall_id: ctx.gall.id, trait: "detachable", value: "integral"},
          confirm(ctx.source)
        )

      {:ok, newer} =
        Catalog.assert_trait(
          test_actor(),
          %{gall_id: ctx.gall.id, trait: "detachable", value: "detachable"},
          confirm(source_fixture("Revision", "1990"))
        )

      assert newer.fact.slot == "gall:#{ctx.gall.id}:detachable"
      assert older.fact.slot == newer.fact.slot
      assert standing(newer.fact.id) == :current
      assert standing(older.fact.id) == :superseded
    end

    test "takes only the Trait's values", ctx do
      assert {:error, changeset} =
               Catalog.assert_trait(
                 test_actor(),
                 %{gall_id: ctx.gall.id, trait: "color", value: "plaid"},
                 confirm(ctx.source)
               )

      assert %{value: ["is not a color value"]} = errors_on(changeset)

      assert {:error, changeset} =
               Catalog.assert_trait(
                 test_actor(),
                 %{gall_id: ctx.gall.id, trait: "generation", value: "agamic"},
                 confirm(ctx.source)
               )

      assert %{trait: ["is invalid"]} = errors_on(changeset)
    end
  end

  # -- Ranges, aliases, descriptions -------------------------------------------

  describe "assert_range/3" do
    test "is keyed by Gall, adjustment and place", ctx do
      gall = gall_fixture()
      key = %{gall_id: gall.id, adjustment: :exclude, place_id: place_id("US-CA")}

      {:ok, first} = Catalog.assert_range(test_actor(), key, confirm(ctx.source))

      {:ok, same} =
        Catalog.assert_range(test_actor(), %{key | adjustment: "exclude"}, confirm(ctx.source))

      {:ok, other} =
        Catalog.assert_range(
          test_actor(),
          %{key | place_id: place_id("CA-AB")},
          confirm(ctx.source)
        )

      assert same.fact.id == first.fact.id
      assert other.fact.id != first.fact.id
      assert %Fact{kind: "gall_range"} = first.fact
      assert %RangeFact{adjustment: :exclude} = first.detail

      assert {:error, changeset} =
               Catalog.assert_range(
                 test_actor(),
                 %{key | adjustment: "widen"},
                 confirm(ctx.source)
               )

      assert %{adjustment: ["is invalid"]} = errors_on(changeset)

      assert {:error, changeset} =
               Catalog.assert_range(test_actor(), %{key | place_id: -1}, confirm(ctx.source))

      assert %{place_id: ["does not exist"]} = errors_on(changeset)
    end

    test "has no include: a Gall's range never leaves its Hosts' ranges", ctx do
      gall = gall_fixture()

      for adjustment <- [:include, "include"] do
        assert {:error, changeset} =
                 Catalog.assert_range(
                   test_actor(),
                   %{gall_id: gall.id, adjustment: adjustment, place_id: place_id("RO-B")},
                   confirm(ctx.source)
                 )

        assert %{adjustment: ["is invalid"]} = errors_on(changeset)
      end
    end

    test "the database refuses an include row" do
      assert_raise Postgrex.Error, ~r/range_facts_adjustment_check/, fn ->
        Repo.query!(
          "INSERT INTO range_facts (fact_id, gall_id, adjustment, place_id) VALUES ($1, $2, $3, $4)",
          [-1, -1, "include", -1]
        )
      end
    end

    test "adjustments for one Gall and place share a slot: the newest statement wins", ctx do
      gall = gall_fixture()
      us_ca = place_id("US-CA")

      {:ok, excluded} =
        Catalog.assert_range(
          test_actor(),
          %{gall_id: gall.id, adjustment: :exclude, place_id: us_ca},
          confirm(ctx.source)
        )

      {:ok, only} =
        Catalog.assert_range(
          test_actor(),
          %{gall_id: gall.id, adjustment: :only, place_id: us_ca},
          confirm(source_fixture("Revision", "1990"))
        )

      {:ok, elsewhere} =
        Catalog.assert_range(
          test_actor(),
          %{gall_id: gall.id, adjustment: :exclude, place_id: place_id("CA-AB")},
          confirm(ctx.source)
        )

      assert excluded.fact.slot == "gall:#{gall.id}:place:#{us_ca}"
      assert only.fact.slot == excluded.fact.slot
      assert elsewhere.fact.slot != excluded.fact.slot
      assert standing(only.fact.id) == :current
      assert standing(excluded.fact.id) == :superseded
      assert standing(elsewhere.fact.id) == :current
    end
  end

  describe "assert_alias/3" do
    test "is keyed by Gall and name, ignoring case", ctx do
      gall = gall_fixture()

      {:ok, first} =
        Catalog.assert_alias(
          test_actor(),
          %{gall_id: gall.id, name: "Oak apple"},
          confirm(ctx.source)
        )

      {:ok, same} =
        Catalog.assert_alias(
          test_actor(),
          %{gall_id: gall.id, name: " oak APPLE "},
          confirm(ctx.source)
        )

      assert same.fact.id == first.fact.id
      assert %Fact{kind: "gall_alias"} = first.fact
      assert %AliasFact{name: "Oak apple"} = same.detail
    end
  end

  describe "assert_description/3" do
    test "is one Fact per Gall, each Source's quotes on its attribution", ctx do
      gall = gall_fixture()

      {:ok, first} =
        Catalog.assert_description(test_actor(), %{gall_id: gall.id}, confirm(ctx.source))

      {:ok, same} =
        Catalog.assert_description(
          test_actor(),
          %{gall_id: gall.id},
          confirm(source_fixture("B", "1970"))
        )

      assert same.fact.id == first.fact.id
      assert %Fact{kind: "gall_description"} = first.fact
      assert %DescriptionFact{} = first.detail
      assert length(Facts.list_attributions(first.fact.id)) == 2
    end
  end

  test "a failed attribution leaves no Fact behind" do
    gall = gall_fixture()
    facts_before = Repo.aggregate(Fact, :count)

    assert {:error, changeset} =
             Catalog.assert_alias(
               test_actor(),
               %{gall_id: gall.id, name: "Oak apple"},
               %{source_id: -1, stance: :confirm}
             )

    assert %{source_id: ["does not exist"]} = errors_on(changeset)
    assert Repo.aggregate(Fact, :count) == facts_before
  end

  test "Fact details are audited", ctx do
    gall = gall_fixture()

    {:ok, %{fact: fact}} =
      Catalog.assert_alias(
        test_actor(),
        %{gall_id: gall.id, name: "Oak apple"},
        confirm(ctx.source)
      )

    assert [%{op: :insert, table_pk: [pk]}] = changes_for("alias_facts")
    assert pk == to_string(fact.id)
  end
end
