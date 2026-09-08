defmodule Gallformers.Phenology.PredictionTest do
  use ExUnit.Case, async: true
  alias Gallformers.Phenology.Prediction
  alias Gallformers.Phenology.SeasonalClock, as: Clock

  defp obs(id, day, phase \\ "developing", source \\ "inat") do
    %{
      species_id: id,
      species_name: "Unprepared species (agamic)",
      date: Date.add(~D[2023-01-01], day - 1),
      latitude: 30.0,
      longitude: -98.0,
      phenophase: phase,
      source_type: source
    }
  end

  test "clock is invertible and continuous across January at all supported latitudes" do
    for lat <- [25.0, 30.13, 40.0, 50.9, 55.0], d <- [-5, 0, 1, 100, 250, 365, 380] do
      p = Clock.coordinate(d, lat)
      assert_in_delta Clock.inverse(p, lat), d, 1.0e-8
      assert_in_delta Clock.coordinate(d + 365, lat), p + 365, 1.0e-8
      assert Clock.coordinate(d + 1, lat) > p
    end
  end

  test "new species and one-site records need no prepared artifact" do
    assert {:ok, [p]} = Prediction.predict([obs(999_999, 150)], 40, [:onset])
    assert p.n == 1 and p.cells == 1
    assert p.event == :onset
    assert p.low_doy == p.high_doy
    refute Map.has_key?(p, :median_doy)
    assert p.low_doy > 150
  end

  test "selected species and sources pool emergence, excluding perimature" do
    records = [
      obs(1, 360, "Free-living"),
      obs(1, 10, "Free-living"),
      obs(1, 80, "maturing", "literature"),
      obs(1, 80, "perimature", "literature"),
      obs(2, 80, "Free-living")
    ]

    assert {:ok, ps} = Prediction.predict(records, 30, [:emergence])
    assert [p] = ps
    assert p.n == 4
    assert p.event == :emergence
    assert p.source == "inat + literature"
    assert Enum.all?(p.contours, &(&1.low_doy <= &1.high_doy)) == true
  end

  test "onset stays at the earliest developing record when late records dominate" do
    early = Map.put(obs(1, 196), :page_url, "https://www.inaturalist.org/observations/126373795")
    later = Enum.map(220..310, &obs(1, &1))

    assert {:ok, [p]} = Prediction.predict([early | later], 30, [:onset])
    assert p.low_doy == 196 and p.high_doy == 196
    assert p.anchor.date == early.date
    assert p.anchor.page_url == early.page_url
    assert Enum.all?(p.contours, &(&1.low_doy == &1.high_doy)) == true
    assert {:ok, [alone]} = Prediction.predict([early], 30, [:onset])
    assert alone.contours == p.contours
  end

  test "repeated later local records do not bend the shared onset curve" do
    anchor = obs(1, 196)

    local_records =
      for lat <- [25.0, 40.0, 50.0], year <- 2020..2025 do
        %{obs(1, 270) | latitude: lat, date: Date.new!(year, 9, 27)}
      end

    for lat <- [25, 30, 35, 40, 45, 50, 55] do
      assert {:ok, [alone]} = Prediction.predict([anchor], lat, [:onset])
      assert {:ok, [p]} = Prediction.predict([anchor | local_records], lat, [:onset])
      assert p.low_doy == alone.low_doy
      assert p.high_doy == alone.high_doy
      assert p.contours == alone.contours
      assert p.anchor == alone.anchor
      refute Map.has_key?(p, :local_onset_weight)
      refute Map.has_key?(p, :fallback_doy)
    end
  end

  test "onset ranks seasonally normalized dates, not raw calendar dates" do
    southern = obs(1, 100)
    northern = %{obs(1, 110) | latitude: 50.0}
    assert Clock.coordinate(110, 50) < Clock.coordinate(100, 30)
    assert {:ok, [p]} = Prediction.predict([southern, northern], 50, [:onset])
    assert p.low_doy == 110
    assert p.anchor.latitude == 50.0
    assert p.anchor.date == northern.date
  end

  test "winter onset crosses January and exposes the same anchor in compact results" do
    records = [obs(1, 355), obs(1, 5)]
    assert {:ok, [p]} = Prediction.predict(records, 30, [:onset])
    assert p.low_doy == 355 and p.high_doy == 355
    assert p.anchor.date == ~D[2023-12-21]
    assert {:ok, [compact]} = Prediction.predict(records, 30, [:onset], contours: false)
    assert Map.delete(compact, :contours) == Map.delete(p, :contours)
  end

  test "onset anchor and date-locality deduplication are deterministic" do
    a = Map.put(obs(1, 150), :page_url, "https://example.org/a")
    b = %{a | page_url: "https://example.org/b"}
    records = [a, b, obs(1, 200), %{a | latitude: nil}]
    assert {:ok, [p]} = Prediction.predict(records, 30, [:onset])
    assert {:ok, [q]} = Prediction.predict(Enum.reverse(records), 30, [:onset])
    assert p == q
    assert p.n == 2 and p.excluded_n == 1
    assert p.anchor.page_url == a.page_url
  end

  test "viable collections ignore stage but require explicit viability and keep generations separate" do
    a = Map.put(obs(1, 270, "dormant"), :viability, "viable")
    b = Map.put(obs(2, 280, "developing", "literature"), :viability, "viable")
    c = %{a | species_name: "Another species (sexgen)"}

    assert {:ok, ps} =
             Prediction.predict([a, b, c, obs(1, 350, "maturing")], 30, [:rearing])

    assert length(ps) == 2
    assert Enum.sum(Enum.map(ps, & &1.n)) == 3
    assert Enum.map(ps, & &1.event) == [:rearing, :rearing]
    assert {:ok, []} = Prediction.predict([obs(1, 350, "maturing")], 30, [:rearing])
  end

  test "duplicates collapse, edits recalibrate, invalid records are counted" do
    a = obs(1, 150)
    assert {:ok, [p]} = Prediction.predict([a, a, %{a | latitude: nil}], 30, [:onset])
    assert p.n == 1 and p.excluded_n == 1
    assert p.low_doy == 150
    assert {:ok, [q]} = Prediction.predict([obs(1, 170)], 30, [:onset])
    assert q.low_doy == 170
    assert {:error, _} = Prediction.predict([a], 60, [:onset])
    assert {:ok, []} = Prediction.predict([a], 30, [:emergence])
  end

  test "occupied geographic cells have equal weight regardless of sampling density" do
    busy_cell = Enum.map(100..119, &obs(1, &1, "maturing"))
    other_cell = %{obs(1, 200, "maturing") | longitude: -100.0}
    records = busy_cell ++ [other_cell]
    assert {:ok, [p]} = Prediction.predict(records, 30, [:emergence])
    assert p.n == 21 and p.raw_n == 21 and p.cells == 2
    assert p.high_doy == 200
    assert {:ok, [repeated]} = Prediction.predict(records ++ busy_cell, 30, [:emergence])
    assert Map.drop(repeated, [:raw_n]) == Map.drop(p, [:raw_n])
  end

  test "winter dates wrap without changing compact outputs or evidence metadata" do
    records = [obs(1, 355, "maturing"), obs(1, 5, "Free-living")]
    assert {:ok, [full]} = Prediction.predict(records, 30, [:emergence])
    assert {:ok, [compact]} = Prediction.predict(records, 30, [:emergence], contours: false)
    assert compact.contours == []
    assert Map.delete(full, :contours) == Map.delete(compact, :contours)
    assert compact.low_doy == 355 and compact.high_doy == 5
    assert compact.sparse? and not compact.extrapolated?
    assert compact.excluded_n == 0 and compact.cells == 1
    assert {:ok, [projected]} = Prediction.predict(records, 40, [:emergence])
    assert projected.extrapolated? == true
  end

  test "leap-day evidence uses the documented fixed non-leap calendar" do
    record = %{obs(1, 59) | date: ~D[2024-02-29]}
    assert {:ok, [p]} = Prediction.predict([record], 30, [:onset])
    assert p.low_doy == 59 and p.high_doy == 59
  end

  test "enclosed Adult annotations do not become emergence and unsupported requests are explicit" do
    enclosed = Map.put(obs(1, 250, "dormant"), :lifestage, "Adult")
    assert {:ok, []} = Prediction.predict([enclosed], 30, [:emergence])
    assert {:ok, []} = Prediction.predict([], 30, [:onset, :emergence, :rearing])
    assert {:error, :unsupported_event} = Prediction.predict([], 30, [:dormant])
    assert {:error, :unsupported_latitude} = Prediction.predict([], -30, [:emergence])
  end
end
