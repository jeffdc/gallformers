defmodule Gallformers.Wcvp.ReporterTest do
  use ExUnit.Case, async: true

  alias Gallformers.Wcvp.Reporter

  describe "write_report/3" do
    test "writes JSON array to file in dated directory" do
      dir = Path.join(System.tmp_dir!(), "reconciliation_test")
      File.rm_rf!(dir)

      items = [
        %{gf_species_id: 1, gf_name: "Quercus alba", detail: "test"},
        %{gf_species_id: 2, gf_name: "Quercus rubra", detail: "test2"}
      ]

      path = Reporter.write_report(items, "test-report", dir)

      assert File.exists?(path)
      assert String.ends_with?(path, "test-report.json")

      decoded = path |> File.read!() |> Jason.decode!()
      assert length(decoded) == 2
      assert hd(decoded)["gf_name"] == "Quercus alba"

      File.rm_rf!(dir)
    end

    test "creates directory if it does not exist" do
      dir = Path.join(System.tmp_dir!(), "reconciliation_new_#{:rand.uniform(10000)}")

      Reporter.write_report([], "empty-report", dir)
      assert File.dir?(dir)

      File.rm_rf!(dir)
    end
  end

  describe "report_dir/0" do
    test "returns dated directory path under priv/repo/data/reconciliation" do
      dir = Reporter.report_dir()
      today = Date.utc_today() |> Date.to_iso8601()
      assert String.contains?(dir, "reconciliation/#{today}")
    end
  end
end
