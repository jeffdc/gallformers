defmodule Gallformers.Phenology.PredictionVisibilityTest do
  use ExUnit.Case, async: true
  alias Gallformers.Phenology.Prediction
  alias GallformersWeb.PhenologyFilters, as: Filters

  test "stage visibility leaves evidence scope and every event prediction unchanged" do
    filters =
      Filters.from_url_params(%{"search" => "cinerosa", "gen" => "agamic", "min_lat" => "28"})

    evidence =
      for {stage, day, viable} <- [
            {"developing", 200, "viable"},
            {"dormant", 270, "viable"},
            {"maturing", 350, nil},
            {"Free-living", 10, nil}
          ] do
        %{
          species_id: 1,
          species_name: "Test (agamic)",
          source_type: "inat",
          latitude: 30.0,
          longitude: -98.0,
          date: Date.add(~D[2023-01-01], day - 1),
          phenophase: stage,
          viability: viable
        }
      end

    for phases <- [[], ["dormant"], ["developing"], ["maturing", "Free-living"]] do
      changed = Map.put(filters, :phenophases, phases)
      assert Filters.prediction_scope(changed) == Filters.prediction_scope(filters)
      assert length(Filters.visible_observations(evidence, changed)) == length(phases)

      for event <- [:onset, :emergence, :rearing] do
        assert {:ok, [_]} = Prediction.predict(evidence, 30.0, [event])
      end
    end

    assert Filters.prediction_scope(filters).generation == :agamic
    assert Filters.prediction_scope(filters).min_lat == 28.0

    refute Filters.prediction_scope(Map.put(filters, :search, ["Eurosta"])) ==
             Filters.prediction_scope(filters)
  end
end
