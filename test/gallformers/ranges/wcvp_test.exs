defmodule Gallformers.Ranges.WcvpTest do
  @moduledoc """
  A plant taxon's WCVP link and range review, by taxon (`a856` Task 8;
  `Gallformers.Ranges.Wcvp`). The WCVP lookup is
  `Gallformers.Wcvp.LookupStub` in tests: "Wcvptestus alpinus" is WCVP
  record 700, native in New York (NWY), introduced in Albania (ALB), regions
  the test seeds have no places for (a sync test maps them).

  Not async: loads the vocabularies (see `Gallformers.CatalogFixtures`).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Ranges
  alias Gallformers.Ranges.TaxonWcvp
  alias Gallformers.Ranges.Wcvp

  setup :audit_test_metadata

  defp audited?(table),
    do: Repo.exists?(from(c in test_audit_changes(), where: c.table_name == ^table))

  describe "match/2" do
    test "links a plant whose accepted name WCVP knows, audited" do
      plant = plant_fixture(name: "Wcvptestus alpinus")

      assert {:ok, :linked} = Wcvp.match(test_actor(), plant)

      assert %TaxonWcvp{
               wcvp_id: "700",
               powo_id: "urn:lsid:ipni.org:names:test700",
               wcvp_match_status: nil
             } = Wcvp.get_link(plant.id)

      assert audited?("taxon_wcvp")
      assert {:ok, :already_linked} = Wcvp.match(test_actor(), plant.id)
    end

    test "marks a plant WCVP does not know as no_match, keeping ignored" do
      plant = plant_fixture(name: "Nowhereus plantus")

      assert {:error, "No WCVP match found for Nowhereus plantus"} =
               Wcvp.match(test_actor(), plant)

      assert Wcvp.get_link(plant.id).wcvp_match_status == "no_match"

      {:ok, 1} = Wcvp.bulk_ignore(test_actor(), [plant.id])
      assert {:error, _} = Wcvp.match(test_actor(), plant)
      assert Wcvp.get_link(plant.id).wcvp_match_status == "ignored"
    end
  end

  describe "sync/3" do
    test "links, then replaces the plant's Host range by taxon and stamps the sync" do
      plant = plant_fixture(name: "Wcvptestus alpinus")
      host_range_fixture(plant, [{"MX-JAL", "exact"}])

      # The seeds have neither New York nor Albania: map the regions to seeded places.
      tdwg = %{
        "NWY" => [%{code: "US-CA", precision: "exact"}],
        "ALB" => [%{code: "RO", precision: "country"}]
      }

      assert {:ok, %{native_count: 1, introduced_count: 1, total_places: 2}} =
               Wcvp.sync(test_actor(), plant, %{tdwg_lookup: tdwg})

      assert [
               %{code: "RO", precision: "country", distribution_type: "introduced"},
               %{code: "US-CA", precision: "exact", distribution_type: "native"}
             ] = Ranges.get_places_for_taxon_with_precision(plant.id)

      assert %TaxonWcvp{wcvp_id: "700", wcvp_synced_at: %DateTime{}} = Wcvp.get_link(plant.id)
    end

    test "a plant WCVP does not know is not synced" do
      plant = plant_fixture(name: "Nowhereus syncus")
      host_range_fixture(plant, [{"US-CA", "exact"}])

      assert {:error, _} = Wcvp.sync(test_actor(), plant)
      assert [%{code: "US-CA"}] = Ranges.get_places_for_taxon_with_precision(plant.id)
    end
  end

  describe "put_link/3" do
    test "sets the link's fields; a new link on an ignored plant stays ignored" do
      plant = plant_fixture()
      {:ok, 1} = Wcvp.bulk_ignore(test_actor(), [plant.id])

      assert {:ok, %TaxonWcvp{wcvp_id: "123", wcvp_match_status: "ignored"}} =
               Wcvp.put_link(test_actor(), plant, %{wcvp_id: "123", powo_id: "p"})

      assert {:ok, %TaxonWcvp{wcvp_match_status: nil}} =
               Wcvp.put_link(test_actor(), plant, %{wcvp_match_status: nil})
    end

    test "rejects an unknown match status" do
      plant = plant_fixture()

      assert {:error, changeset} =
               Wcvp.put_link(test_actor(), plant, %{wcvp_match_status: "maybe"})

      assert %{wcvp_match_status: [_]} = errors_on(changeset)
    end
  end

  describe "linked_taxon_ids/1" do
    test "the plants linked to a WCVP record" do
      [a, b, c] = for _ <- 1..3, do: plant_fixture()
      id = "linked-#{System.unique_integer([:positive])}"
      {:ok, _} = Wcvp.put_link(test_actor(), b, %{wcvp_id: id})
      {:ok, _} = Wcvp.put_link(test_actor(), a, %{wcvp_id: id})
      {:ok, _} = Wcvp.put_link(test_actor(), c, %{wcvp_id: "other-#{id}"})

      assert Wcvp.linked_taxon_ids(id) == Enum.sort([a.id, b.id])
      assert Wcvp.linked_taxon_ids("none-#{id}") == []
    end
  end

  describe "bulk review" do
    setup do
      genus = plant_fixture(rank: :genus, name: "Reviewus")
      a = plant_fixture(name: "Reviewus alpha", parent: genus)
      b = plant_fixture(name: "Reviewus beta", parent: genus)
      c = plant_fixture(name: "Reviewus gamma", parent: genus)
      host_range_fixture(a, [{"US-CA", "exact"}, {"MX-JAL", "exact"}])
      %{a: a, b: b, c: c}
    end

    defp names(opts),
      do: Wcvp.list_for_range_review([search: "Reviewus"] ++ opts) |> Enum.map(& &1.name)

    test "lists plants with their genus, range size and link, by name", ctx do
      assert [
               %{
                 id: id,
                 name: "Reviewus alpha",
                 genus_name: "Reviewus",
                 range_count: 2,
                 wcvp_id: nil,
                 range_confirmed: false
               },
               %{name: "Reviewus beta", range_count: 0},
               %{name: "Reviewus gamma"}
             ] = Wcvp.list_for_range_review(search: "Reviewus")

      assert id == ctx.a.id
      assert Wcvp.count_for_range_review(search: "Reviewus") == 3
      assert names(has_range: :yes) == ["Reviewus alpha"]
      assert names(has_range: :no) == ["Reviewus beta", "Reviewus gamma"]
      assert names(limit: 1, offset: 1) == ["Reviewus beta"]
    end

    test "confirming, ignoring and clearing change what the filters show", ctx do
      assert {:ok, 2} = Wcvp.bulk_confirm_ranges(test_actor(), [ctx.a.id, ctx.b.id])
      assert names(filter: :confirmed) == ["Reviewus alpha", "Reviewus beta"]
      assert names(filter: :unconfirmed) == ["Reviewus gamma"]

      assert {:ok, 1} = Wcvp.bulk_ignore(test_actor(), [ctx.c.id])
      assert names(wcvp_match: :ignored, filter: :all) == ["Reviewus gamma"]
      assert names(wcvp_match: :active, filter: :all) == ["Reviewus alpha", "Reviewus beta"]

      assert {:ok, 1} = Wcvp.bulk_clear_match_status(test_actor(), [ctx.c.id])
      assert names(wcvp_match: :ignored, filter: :all) == []

      assert Enum.map(Wcvp.list_refs_for_range_review(search: "Reviewus", filter: :all), & &1.id) ==
               [ctx.a.id, ctx.b.id, ctx.c.id]
    end
  end
end
