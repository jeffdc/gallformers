defmodule Gallformers.Ranges.WcvpAuthorshipTest do
  @moduledoc """
  Plants' authorship from WCVP (matter `f14c`, "Other decisions";
  `Gallformers.Ranges.WcvpAuthorship`): each plant name WCVP holds
  unambiguously takes WCVP's authors where it has none. The WCVP lookup is
  `Gallformers.Wcvp.LookupStub`: "Wcvptestus alpinus" (700) by "Test";
  "Wcvphomonymus dubius" twice (910 "Smith", 911 "Jones"); and
  "Wcvphomonymus dubius var. minor" twice, a synonym of 910 ("Brown") and
  of 700 ("Green").

  Each test scopes the backfill to its own plants (`:taxon_ids`): the
  converted seeds hold plants too.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Ranges.TaxonWcvp
  alias Gallformers.Ranges.WcvpAuthorship
  alias Gallformers.Taxa

  setup :audit_test_metadata

  defmodule UnavailableLookup do
    @moduledoc false
    def available?, do: false
  end

  # A plant's names and their authorship, accepted first.
  defp authorships(taxon) do
    for n <- Taxa.get_taxon!(taxon.id).names, do: {n.name, n.authorship}
  end

  # A WCVP link made directly, as the data migration carries it.
  defp link!(taxon, wcvp_id), do: Repo.insert!(%TaxonWcvp{taxon_id: taxon.id, wcvp_id: wcvp_id})

  defp backfill!(taxa, opts \\ []) do
    assert {:ok, summary} =
             WcvpAuthorship.backfill(
               test_actor(),
               Keyword.put(opts, :taxon_ids, Enum.map(taxa, & &1.id))
             )

    summary
  end

  test "a plant's blank names take WCVP's authors, found by exact name, audited" do
    plant = plant_fixture(name: "Wcvptestus alpinus")
    {:ok, _} = Taxa.add_synonym(test_actor(), plant, "Wcvphybridus parentus var. crossus")

    summary = backfill!([plant])

    assert authorships(plant) == [
             {"Wcvptestus alpinus", "Test"},
             {"Wcvphybridus parentus var. crossus", "Test"}
           ]

    assert %{names: 2, matched: 2, filled: 2, ambiguous: [], not_in_wcvp: 0} = summary

    assert Repo.exists?(
             from(c in test_audit_changes(),
               where: c.table_name == "taxon_names" and c.op == :update
             )
           ) == true
  end

  test "the accepted name takes its linked WCVP record's authors, though WCVP holds the name twice" do
    plant = plant_fixture(name: "Wcvphomonymus dubius")
    {:ok, _} = Taxa.add_synonym(test_actor(), plant, "Wcvphomonymus dubius var. minor")
    link!(plant, "911")

    backfill!([plant])

    assert [{"Wcvphomonymus dubius", "Jones"}, {_synonym, nil}] = authorships(plant)
  end

  test "a name WCVP holds twice takes the authors of the record in the plant's synonymy" do
    plant = plant_fixture(name: "Wcvphomonymus dubius")
    {:ok, _} = Taxa.add_synonym(test_actor(), plant, "Wcvphomonymus dubius var. minor")
    link!(plant, "910")

    backfill!([plant])

    assert authorships(plant) == [
             {"Wcvphomonymus dubius", "Smith"},
             {"Wcvphomonymus dubius var. minor", "Brown"}
           ]
  end

  test "a link to another name's record gives the accepted name nothing" do
    # Linked by synonym resolution to a record of another name.
    plant = plant_fixture(name: "Nowhereus linkedus")
    link!(plant, "700")

    summary = backfill!([plant])

    assert authorships(plant) == [{"Nowhereus linkedus", nil}]
    assert %{matched: 0, not_in_wcvp: 1} = summary
  end

  test "ambiguous names stay blank and are counted" do
    plant = plant_fixture(name: "Wcvphomonymus dubius")
    {:ok, _} = Taxa.add_synonym(test_actor(), plant, "Wcvphomonymus dubius var. minor")

    summary = backfill!([plant])

    assert authorships(plant) == [
             {"Wcvphomonymus dubius", nil},
             {"Wcvphomonymus dubius var. minor", nil}
           ]

    assert %{matched: 0, filled: 0} = summary

    assert Enum.sort(summary.ambiguous) == [
             %{taxon_id: plant.id, name: "Wcvphomonymus dubius"},
             %{taxon_id: plant.id, name: "Wcvphomonymus dubius var. minor"}
           ]
  end

  test "names WCVP does not hold, or holds at another rank, are counted as not in WCVP" do
    missing = plant_fixture(name: "Nowhereus plantus")
    # WCVP's "Wcvptestus alpinus" is a species.
    other_rank = plant_fixture(name: "Wcvptestus alpinus", rank: :subspecies)

    summary = backfill!([missing, other_rank])

    assert authorships(missing) == [{"Nowhereus plantus", nil}]
    assert authorships(other_rank) == [{"Wcvptestus alpinus", nil}]
    assert %{names: 2, matched: 0, not_in_wcvp: 2} = summary
  end

  test "an authorship a name holds is kept; running again fills nothing" do
    curated = plant_fixture(name: "Wcvptestus alpinus")
    {:ok, _} = Taxa.set_authorship(test_actor(), curated, "Curator, 2026")
    {:ok, _} = Taxa.add_synonym(test_actor(), curated, "Wcvphybridus parentus var. crossus")

    first = backfill!([curated])

    assert authorships(curated) == [
             {"Wcvptestus alpinus", "Curator, 2026"},
             {"Wcvphybridus parentus var. crossus", "Test"}
           ]

    assert %{matched: 2, filled: 1, kept: 1, unchanged: 0} = first

    assert %{matched: 2, filled: 0, kept: 1, unchanged: 1} = backfill!([curated])
  end

  test "only plants: other taxa are left alone" do
    wasp = taxon_fixture(name: "Wcvptestus alpinus", kingdom: "Animalia", origin: :curated)

    assert %{names: 0} = backfill!([wasp])
    assert authorships(wasp) == [{"Wcvptestus alpinus", nil}]
  end

  test "every plant by default, and an error when WCVP is unavailable" do
    plant = plant_fixture(name: "Wcvptestus alpinus")

    assert {:ok, %{names: names}} = WcvpAuthorship.backfill(test_actor())
    assert names > 1
    assert [{_, "Test"}] = authorships(plant)

    assert {:error, :wcvp_unavailable} =
             WcvpAuthorship.backfill(test_actor(), lookup: UnavailableLookup)
  end

  test "the summary prints" do
    plant = plant_fixture(name: "Wcvphomonymus dubius")
    text = [plant] |> backfill!() |> WcvpAuthorship.format()

    assert text =~ "Plant names: 1"
    assert text =~ "ambiguous in WCVP: 1"
    assert text =~ "Wcvphomonymus dubius (taxon #{plant.id})"
  end
end
