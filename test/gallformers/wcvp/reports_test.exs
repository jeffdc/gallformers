defmodule Gallformers.Wcvp.ReportsTest do
  use ExUnit.Case, async: true

  alias Gallformers.Wcvp.Reports

  @fixture_dir "test/support/fixtures/reconciliation"

  setup do
    run_dir = Path.join(@fixture_dir, "2026-01-15")
    File.mkdir_p!(run_dir)

    File.write!(
      Path.join(run_dir, "taxonomy-mismatches.json"),
      Jason.encode!([
        %{
          gf_species_id: 1,
          gf_name: "Quercus alba",
          mismatch_type: "family",
          detail: "Family differs",
          gf_family: "Fagaceae",
          gf_genus: "Quercus",
          wcvp_accepted_name: "Quercus alba",
          wcvp_family: "Fagaceae2",
          wcvp_genus: "Quercus"
        }
      ])
    )

    File.write!(
      Path.join(run_dir, "in-gf-not-wcvp.json"),
      Jason.encode!([
        %{gf_species_id: 2, gf_name: "Xanthium sp", gf_family: "Asteraceae", gf_genus: "Xanthium"}
      ])
    )

    File.write!(
      Path.join(run_dir, "range-updates.json"),
      Jason.encode!([
        %{gf_species_id: 3, gf_name: "Zizia aurea", current_places: ["AL"], new_places: ["US-DC"]}
      ])
    )

    on_exit(fn -> File.rm_rf!(@fixture_dir) end)

    %{run_dir: run_dir}
  end

  describe "list_runs/1" do
    test "returns available run dates in reverse chronological order" do
      runs = Reports.list_runs(@fixture_dir)
      assert runs == ["2026-01-15"]
    end

    test "returns empty list when no runs exist" do
      assert Reports.list_runs("nonexistent/path") == []
    end
  end

  describe "summary/2" do
    test "returns counts for all report types" do
      summary = Reports.summary("2026-01-15", @fixture_dir)

      assert summary.run_date == "2026-01-15"
      assert summary.taxonomy_mismatches == 1
      assert summary.gf_not_in_wcvp == 1
      assert summary.range_updates == 1
    end

    test "returns nil for nonexistent run" do
      assert Reports.summary("1999-01-01", @fixture_dir) == nil
    end
  end

  describe "load_report/3" do
    test "loads and returns parsed report data" do
      {:ok, items} = Reports.load_report("2026-01-15", "taxonomy-mismatches", @fixture_dir)
      assert length(items) == 1
      assert hd(items)["gf_name"] == "Quercus alba"
    end

    test "returns error for missing report" do
      assert {:error, :not_found} = Reports.load_report("2026-01-15", "nonexistent", @fixture_dir)
    end
  end
end
