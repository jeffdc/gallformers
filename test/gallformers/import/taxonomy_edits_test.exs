defmodule Gallformers.Import.TaxonomyEditsTest do
  @moduledoc """
  The taxonomy admin's new edits in the replay log (`a856` Task 8): a
  plant's editorial flags, removing a synonym or common name, deleting a
  taxon, a Host range, and the WCVP link and review — each made, audited,
  logged by stable keys, and replayed on a fresh copy to the same result.

  Not async: loads the vocabularies (see `Gallformers.CatalogFixtures`) and
  wipes the replay log inside its sandbox.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures

  alias Gallformers.Import
  alias Gallformers.Import.Replay
  alias Gallformers.Ranges
  alias Gallformers.Ranges.Wcvp
  alias Gallformers.Taxa

  setup :audit_test_metadata

  # The seeds have neither New York nor Albania: the stub's regions map to seeded places.
  @ref_data %{
    tdwg_lookup: %{
      "NWY" => [%{code: "US-CA", precision: "exact"}],
      "ALB" => [%{code: "RO", precision: "country"}]
    }
  }

  # What the data migration fills: the same names on every run.
  defp seed! do
    genus = plant_fixture(rank: :genus, name: "Replayus")
    alpha = plant_fixture(name: "Replayus alpha", parent: genus)
    {:ok, _} = Taxa.add_synonym(test_actor(), alpha, "Replayus olda")
    {:ok, _} = Taxa.add_common_name(test_actor(), alpha, "Alpha plant")
    {:ok, _} = Taxa.add_common_name(test_actor(), alpha, "Kept name")
    doomed = plant_fixture(name: "Replayus doomed", parent: genus)
    wcvp = plant_fixture(name: "Wcvptestus alpinus")
    ignored = plant_fixture(name: "Replayus ignorus", parent: genus)
    %{genus: genus, alpha: alpha, doomed: doomed, wcvp: wcvp, ignored: ignored}
  end

  @names [
    "Replayus",
    "Replayus alpha",
    "Replayus doomed",
    "Wcvptestus alpinus",
    "Replayus ignorus"
  ]

  defp find(name) do
    case Taxa.resolve_name(name, kingdom: "Plantae") do
      {:ok, taxon} -> taxon
      :none -> nil
    end
  end

  defp wipe! do
    ids = for name <- @names, taxon = find(name), do: taxon.id
    Repo.query!("DELETE FROM host_range WHERE taxon_id = ANY($1)", [ids])
    Repo.query!("DELETE FROM taxon_wcvp WHERE taxon_id = ANY($1)", [ids])
    Repo.query!("DELETE FROM taxon_ancestry WHERE descendant_id = ANY($1)", [ids])
    Repo.query!("UPDATE taxa SET parent_id = NULL WHERE id = ANY($1)", [ids])
    Repo.query!("DELETE FROM taxa WHERE id = ANY($1)", [ids])
    Repo.query!("DELETE FROM replay_log")
  end

  defp snapshot do
    taxa =
      for name <- @names do
        case find(name) do
          nil ->
            {name, :none}

          taxon ->
            taxon = Taxa.get_taxon!(taxon.id)
            link = Wcvp.get_link(taxon.id)

            {name, taxon.datacomplete, taxon.abundance_id,
             Enum.map(Taxa.list_synonyms(taxon), & &1.name),
             Enum.map(Taxa.list_common_names(taxon), & &1.name),
             for(
               p <- Ranges.get_places_for_taxon_with_precision(taxon.id),
               do: {p.code, p.precision, p.distribution_type}
             ),
             link &&
               {link.wcvp_id, link.powo_id, link.wcvp_match_status, link.range_confirmed,
                link.wcvp_synced_at}}
        end
      end

    %{taxa: taxa, log: for(e <- Import.list_replay_entries(), do: {e.kind, e.key, e.payload})}
  end

  defp edit!(edit), do: {:ok, _} = Import.record_taxonomy_edit(test_actor(), edit)

  test "each edit is made, logged by stable keys, and replays to the same result" do
    load_vocab!()
    Repo.query!("DELETE FROM replay_log")
    t = seed!()
    [synonym] = Taxa.list_synonyms(t.alpha)
    [common, _kept] = Taxa.list_common_names(t.alpha)

    edit!({:update_editorial, t.alpha, %{datacomplete: true, abundance_id: 2}})
    edit!({:remove_synonym, synonym})
    edit!({:remove_common_name, common.id})
    edit!({:delete_taxon, t.doomed})

    edit!(
      {:set_host_range, t.alpha,
       [{place_id("US-CA"), "exact", "native"}, {place_id("RO"), "country", "introduced"}]}
    )

    assert {:ok, %{total_places: 2}} =
             Import.record_wcvp_edit(test_actor(), {:sync, t.wcvp, @ref_data})

    assert {:ok, 1} = Import.record_wcvp_edit(test_actor(), {:confirm_ranges, [t.alpha.id]})
    assert {:ok, 1} = Import.record_wcvp_edit(test_actor(), {:ignore, [t.ignored.id]})

    assert {:error, "No WCVP match found for Replayus alpha"} =
             Import.record_wcvp_edit(test_actor(), {:match, t.alpha})

    before = snapshot()

    assert {"Replayus doomed", :none} in before.taxa

    assert Enum.find(before.taxa, &(elem(&1, 0) == "Replayus alpha")) |> elem(5) == [
             {"RO", "country", "introduced"},
             {"US-CA", "exact", "native"}
           ]

    ops = for {:taxonomy_edit, key, _payload} <- before.log, do: key["op"]

    assert ops == ~w(update_editorial remove_synonym remove_common_name delete_taxon
                     set_host_range set_host_range set_wcvp set_wcvp set_wcvp set_wcvp)

    # Logged by name: no database IDs.
    {:taxonomy_edit, key, payload} = Enum.at(before.log, 4)

    assert key["taxon"] == %{
             "name" => "Replayus alpha",
             "rank" => "species",
             "kingdom" => "Plantae"
           }

    assert payload["places"] == [
             %{"code" => "US-CA", "precision" => "exact", "distribution_type" => "native"},
             %{"code" => "RO", "precision" => "country", "distribution_type" => "introduced"}
           ]

    # Audited: the log's rows, and the taxa and link rows the edits changed.
    changes = Repo.all(from(c in test_audit_changes(), select: {c.table_name, c.op}))
    assert Enum.count(changes, &(&1 == {"replay_log", :insert})) == 10
    assert {"taxa", :delete} in changes
    assert {"taxon_wcvp", :insert} in changes

    entries = Import.list_replay_entries()
    wipe!()
    seed!()

    assert {:ok, 10} = Replay.run(entries, actor: test_actor())
    assert snapshot() == before
  end

  test "a sync without preloaded region data logs the range it wrote too" do
    plant = plant_fixture(name: "Wcvptestus alpinus")
    Repo.query!("DELETE FROM replay_log")

    assert {:ok, _summary} = Import.record_wcvp_edit(test_actor(), {:sync, plant})

    ops = for e <- Import.list_replay_entries(), do: e.key["op"]
    assert ops == ~w(set_host_range set_wcvp)
  end

  test "an edit that fails is not logged" do
    genus = plant_fixture(rank: :genus)
    _child = plant_fixture(parent: genus)
    Repo.query!("DELETE FROM replay_log")

    assert {:error, {:referenced, [%{table: "taxa"}]}} =
             Import.record_taxonomy_edit(test_actor(), {:delete_taxon, genus})

    assert Import.list_replay_entries() == []
  end
end
