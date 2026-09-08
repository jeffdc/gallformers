defmodule Gallformers.Phenology.SeasonalClockTest do
  use ExUnit.Case, async: true
  alias Gallformers.Phenology.SeasonalClock, as: Clock

  test "client reference contains the exact anchors used by predictions" do
    assert length(Clock.reference()) == 121

    for [lat, spring, autumn] <- Clock.reference() do
      assert Clock.anchors(lat) == {spring, autumn}
    end
  end

  test "selection transfers calendar-day edges, wraps winter and ignores unsupported points" do
    for day <- [1, 90, 180, 270, 355, 366], lat <- [25, 37.5, 55] do
      {:ok, {low, high} = window} = Clock.window(day, lat, 10)
      assert_in_delta Clock.inverse(low, lat), day - 10, 1.0e-8
      assert_in_delta Clock.inverse(high, lat), day + 10, 1.0e-8

      for other <- [25, 40, 55] do
        projected = Clock.coordinate(day, lat) |> Clock.inverse(other)
        wrapped = projected - floor((projected - 1) / 365) * 365
        assert Clock.in_window?(wrapped, other, window) == true
      end

      refute Clock.in_window?(day, nil, window)
      refute Clock.in_window?(day, 24.9, window)
    end

    {:ok, winter} = Clock.window(355, 40, 15)
    assert Clock.in_window?(5, 40, winter) == true
    refute Clock.in_window?(6, 40, winter)
    {:ok, exact} = Clock.window(120, 40, 0)
    assert Clock.in_window?(120, 40, exact) == true
    refute Clock.in_window?(121, 40, exact)
    {:ok, whole_year} = Clock.window(180, 40, 183)
    for day <- 1..366, do: assert(Clock.in_window?(day, 40, whole_year) == true)
    assert Clock.window(100, 60, 10) == :error
    assert Clock.window(100, 40, -1) == :error
    assert Clock.window(100, 40, 184) == :error
    assert Clock.window(nil, 40, 10) == :error
  end

  test "finite latitude support and all interpolated landmarks are ordered" do
    refute Clock.supported_latitude?(nil)
    refute Clock.supported_latitude?(-30)
    refute Clock.supported_latitude?(55.01)

    for i <- 250..550 do
      lat = i / 10
      assert Clock.supported_latitude?(lat) == true
      {spring, autumn} = Clock.anchors(lat)
      assert spring < autumn and autumn < spring + 365

      for day <- [0, 60, 180, 300, 370] do
        assert_in_delta Clock.inverse(Clock.coordinate(day, lat), lat), day, 1.0e-8
      end
    end
  end
end
