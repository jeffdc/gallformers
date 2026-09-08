defmodule Gallformers.Phenology.SeasonalClock do
  @moduledoc """
  Species-independent, periodic thermal-landmark clock for 25–55°N.

  Forward and inverse coordinates use a fixed 365-day calendar. The bundled
  latitude grid is shared by every event; it is not a fitted species model.
  See `priv/phenology/README.md` for provenance and ecological limitations.
  """
  @path Path.expand("../../../priv/phenology/seasonal_landmarks.csv", __DIR__)
  @external_resource @path
  @anchors @path
           |> File.read!()
           |> String.split("\n", trim: true)
           |> tl()
           |> Enum.map(fn row ->
             [lat, spring, autumn, _] = row |> String.trim() |> String.split(",")

             {String.to_float(lat <> if(String.contains?(lat, "."), do: "", else: ".0")),
              String.to_float(spring), String.to_float(autumn)}
           end)

  @doc "Whether the shared reference supports a latitude."
  @spec supported_latitude?(term()) :: boolean()
  def supported_latitude?(lat), do: is_number(lat) and lat >= 25 and lat <= 55

  @doc "The exact bundled reference, as JSON-encodable rows for client-side selection."
  @spec reference() :: [[float()]]
  def reference, do: Enum.map(@anchors, &Tuple.to_list/1)

  @doc "Clock edges for a plotted DOY ± calendar days at a reference latitude."
  @spec window(term(), term(), term()) :: {:ok, {float(), float()}} | :error
  def window(doy, lat, days) do
    if is_number(doy) and doy == trunc(doy) and doy >= 1 and doy <= 366 and
         supported_latitude?(lat) and is_number(days) and days >= 0 and days <= 183 do
      {:ok, {coordinate(doy - days, lat), coordinate(doy + days, lat)}}
    else
      :error
    end
  end

  @doc "Whether a plotted day/latitude falls inside a circular landmark window."
  @spec in_window?(term(), term(), {float(), float()}) :: boolean()
  def in_window?(day, lat, {low, high}) do
    if is_number(day) and day >= 1 and day <= 366 and supported_latitude?(lat) do
      delta = coordinate(day, lat) - low
      offset = delta - floor(delta / 365) * 365
      high - low >= 365 or offset <= high - low + 1.0e-8 or offset >= 365 - 1.0e-8
    else
      false
    end
  end

  @doc "Interpolated spring and autumn thermal landmarks in calendar days."
  @spec anchors(number()) :: {float(), float()}
  def anchors(lat) when is_number(lat) and lat >= 25 and lat <= 55 do
    {l0, s0, a0} = Enum.find(Enum.reverse(@anchors), fn {l, _, _} -> l <= lat end)
    {l1, s1, a1} = Enum.find(@anchors, fn {l, _, _} -> l >= lat end)
    f = if l0 == l1, do: 0, else: (lat - l0) / (l1 - l0)
    {s0 + f * (s1 - s0), a0 + f * (a1 - a0)}
  end

  @doc "Maps calendar days to a continuous seasonal coordinate, including adjacent years."
  @spec coordinate(number(), number()) :: float()
  def coordinate(day, lat) do
    {s, a} = anchors(lat)
    year = floor((day - s) / 365)
    d = day - year * 365

    year * 365 +
      if(d <= a,
        do: (d - s) / (a - s) * 182.5,
        else: 182.5 + (d - a) / (s + 365 - a) * 182.5
      )
  end

  @doc "Maps a seasonal coordinate back to continuous calendar days at a supported latitude."
  @spec inverse(number(), number()) :: float()
  def inverse(phase, lat) do
    {s, a} = anchors(lat)
    year = floor(phase / 365)
    p = phase - year * 365

    year * 365 +
      if(p <= 182.5,
        do: s + p / 182.5 * (a - s),
        else: a + (p - 182.5) / 182.5 * (s + 365 - a)
      )
  end
end
