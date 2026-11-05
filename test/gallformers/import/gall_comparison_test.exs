defmodule Gallformers.Import.GallComparisonTest do
  @moduledoc """
  Comparing what a batch Gall says with a Gallformers Gall (`d213` Task 4):
  field by field (Host, where on the plant, detachable, generation and
  season, form), each agreeing, differing, conflicting or not stated. A
  different coarse plant part (the leaf's values are one) or a different
  form is a conflict.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures

  alias Gallformers.Catalog.ReadModels.GallSummary
  alias Gallformers.Import.GallComparison

  defp summary(attrs) do
    struct!(
      %GallSummary{gall_id: System.unique_integer([:positive]), name: "a Gall"},
      attrs
    )
  end

  defp host(taxon), do: %{taxon_id: taxon.id, name: "a plant", rank: taxon.rank}

  defp trait(ref, trait, value, stance \\ "confirm") do
    %{
      "id" => "f#{System.unique_integer([:positive])}",
      "kind" => "trait",
      "gall" => ref,
      "trait" => trait,
      "stance" => stance,
      "term" => value,
      "category" => %{"value" => value}
    }
  end

  defp batch_gall(identified_by),
    do: %{"ref" => "g1", "name_as_written" => "the gall", "identified_by" => identified_by}

  defp source(identified_by \\ %{}, facts \\ [], hosts \\ []),
    do: GallComparison.source_side(batch_gall(identified_by), facts, hosts)

  describe "source_side/3" do
    test "reads identified_by and the Gall's confirmed trait Facts" do
      ident = %{
        "generation" => %{"value" => "agamic", "as_written" => "agamic"},
        "plant_part" => %{"value" => "stem", "as_written" => "branch"}
      }

      facts = [
        trait("g1", "plant_part", "bud"),
        trait("g1", "form", "oak apple"),
        trait("g1", "season", "Spring"),
        trait("g1", "detachable", "integral"),
        trait("g2", "form", "bullet"),
        trait("g1", "form", "plum", "dispute"),
        # Format 3.
        %{
          "kind" => "trait",
          "gall" => "g1",
          "trait" => "season",
          "stance" => "confirm",
          "value" => %{"value" => "Summer", "as_written" => "summer"}
        }
      ]

      s = GallComparison.source_side(batch_gall(ident), facts, [7])

      assert s.hosts == [7]
      assert Enum.sort(s.where) == ["bud", "stem"]
      assert s.form == ["oak apple"]
      assert Enum.sort(s.season) == ["Spring", "Summer"]
      assert s.detachable == ["integral"]
      assert s.generation == "agamic"
    end
  end

  describe "where on the plant" do
    test "roots vs stem conflicts (Callirhytis rhizoxenus)" do
      s = source(%{"plant_part" => %{"value" => "underground (roots+)"}})
      c = GallComparison.compare(s, summary(traits: %{"plant_part" => ["stem"]}))

      assert c.fields.where == :conflict
      assert c.conflicts == [:where]
    end

    test "stem vs fruit conflicts (C. q. juglans)" do
      s = source(%{}, [trait("g1", "plant_part", "stem")])
      c = GallComparison.compare(s, summary(traits: %{"plant_part" => ["fruit"]}))

      assert c.fields.where == :conflict
    end

    test "leaf values are one: lower leaf vs leaf midrib agrees" do
      s = source(%{"plant_part" => %{"value" => "lower leaf"}})
      c = GallComparison.compare(s, summary(traits: %{"plant_part" => ["leaf midrib"]}))

      assert c.fields.where == :agree
      assert c.conflicts == []
      assert c.agrees == 1
    end

    test "the petiole is not the leaf" do
      assert GallComparison.coarse_part("leaf edge") == "leaf"
      assert GallComparison.coarse_part("leaf") == "leaf"
      assert GallComparison.coarse_part("petiole") == "petiole"
      assert GallComparison.coarse_part("stem") == "stem"
    end

    test "not stated on a side is none" do
      s = source(%{"plant_part" => %{"value" => "stem"}})
      assert GallComparison.compare(s, summary([])).fields.where == :none

      assert GallComparison.compare(source(), summary(traits: %{"plant_part" => ["stem"]})).fields.where ==
               :none
    end
  end

  describe "form, detachable, generation and season" do
    test "a different form conflicts; the same agrees" do
      s = source(%{}, [trait("g1", "form", "bullet")])

      assert GallComparison.compare(s, summary(traits: %{"form" => ["oak apple"]})).fields.form ==
               :conflict

      assert GallComparison.compare(s, summary(traits: %{"form" => ["bullet"]})).fields.form ==
               :agree
    end

    test "detachable agrees or differs; unknown is not stated" do
      s = source(%{}, [trait("g1", "detachable", "integral")])

      assert GallComparison.compare(s, summary(traits: %{"detachable" => ["integral"]})).fields.detachable ==
               :agree

      assert GallComparison.compare(s, summary(traits: %{"detachable" => ["detachable"]})).fields.detachable ==
               :differ

      assert GallComparison.compare(s, summary(traits: %{"detachable" => ["unknown"]})).fields.detachable ==
               :none
    end

    test "generation and season: agree when the Source's are the Gall's, else differ" do
      agamic = %{"generation" => %{"value" => "agamic"}}

      assert GallComparison.compare(source(agamic), summary(generation: "agamic")).fields.generation ==
               :agree

      assert GallComparison.compare(source(agamic), summary(generation: "sexual")).fields.generation ==
               :differ

      spring = source(%{}, [trait("g1", "season", "Spring")])

      assert GallComparison.compare(spring, summary(traits: %{"season" => ["Spring", "Summer"]})).fields.generation ==
               :agree

      assert GallComparison.compare(spring, summary(traits: %{"season" => ["Fall"]})).fields.generation ==
               :differ

      assert GallComparison.compare(source(), summary(generation: "agamic")).fields.generation ==
               :none
    end
  end

  describe "Host" do
    setup do
      quercus = plant_fixture(name: "Quercus", rank: :genus)
      alba = plant_fixture(name: "Quercus alba", parent: quercus)
      rubra = plant_fixture(name: "Quercus rubra", parent: quercus)
      %{quercus: quercus, alba: alba, rubra: rubra}
    end

    test "agrees when a Source Host is among the Gall's, else differs (never conflicts)", ctx do
      s = source(%{}, [], [ctx.alba.id])

      assert GallComparison.compare(s, summary(hosts: [host(ctx.alba), host(ctx.rubra)])).fields.host ==
               :agree

      c = GallComparison.compare(s, summary(hosts: [host(ctx.rubra)]))
      assert c.fields.host == :differ
      assert c.conflicts == []
    end

    test "a genus on either side agrees with its species", ctx do
      assert GallComparison.compare(
               source(%{}, [], [ctx.alba.id]),
               summary(hosts: [host(ctx.quercus)])
             ).fields.host == :agree

      assert GallComparison.compare(
               source(%{}, [], [ctx.quercus.id]),
               summary(hosts: [host(ctx.rubra)])
             ).fields.host == :agree
    end
  end

  describe "rank/2" do
    test "most agreeing fields first, ties in their order" do
      s =
        source(%{"plant_part" => %{"value" => "stem"}}, [
          trait("g1", "form", "bullet"),
          trait("g1", "detachable", "integral")
        ])

      none = summary(gall_id: 1)
      one = summary(gall_id: 2, traits: %{"plant_part" => ["stem"]})
      also_none = summary(gall_id: 3, traits: %{"plant_part" => ["fruit"]})

      two =
        summary(gall_id: 4, traits: %{"plant_part" => ["stem"], "detachable" => ["integral"]})

      assert [none, one, also_none, two]
             |> GallComparison.rank(s)
             |> Enum.map(fn {summary, c} -> {summary.gall_id, c.agrees} end) ==
               [{4, 2}, {2, 1}, {1, 0}, {3, 0}]
    end
  end

  test "to_proposal/1 is the comparison with string keys" do
    s = source(%{"plant_part" => %{"value" => "stem"}})
    c = GallComparison.compare(s, summary(gall_id: 9, traits: %{"plant_part" => ["fruit"]}))

    assert GallComparison.to_proposal(c) == %{
             "gall_id" => 9,
             "agrees" => 0,
             "conflicts" => ["where"],
             "fields" => %{
               "host" => "none",
               "where" => "conflict",
               "detachable" => "none",
               "generation" => "none",
               "form" => "none"
             }
           }
  end
end
