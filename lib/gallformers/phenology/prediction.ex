defmodule Gallformers.Phenology.Prediction do
  @moduledoc """
  Shared seasonal-landmark predictions for the explorer and compact gall view.

  Selected species pool within generation. Developing observations estimate only
  the leading edge, anchored to the earliest seasonally normalized record.
  Free-living and maturing observations jointly
  describe emergence; perimature and enclosed Adult annotations do not. Viable
  collections require explicit viability, independently of phenophase.

  Date/locality replicates collapse within species and one-degree geographic
  cells receive equal weight. Quantiles describe the available evidence, not
  confidence intervals or validated physiological limits.
  """
  alias Gallformers.Phenology.SeasonalClock, as: Clock

  @events [:onset, :emergence, :rearing]
  @type event :: :onset | :emergence | :rearing
  @type generation :: :sexgen | :agamic | :unknown
  @type prediction :: map()

  @doc "Supported ecological questions, in display order."
  @spec events() :: [event()]
  def events, do: @events

  @doc """
  Fits the requested events at a supported latitude.

  No usable evidence returns an empty list, not an operational error. Set
  `contours: false` for date-only results; dates and evidence counts are identical.
  """
  @spec predict([map()], number(), [event()], keyword()) ::
          {:ok, [prediction()]} | {:error, :unsupported_latitude | :unsupported_event}
  def predict(observations, latitude, events \\ @events, opts \\ []) do
    cond do
      not Clock.supported_latitude?(latitude) ->
        {:error, :unsupported_latitude}

      not Enum.all?(events, &(&1 in @events)) ->
        {:error, :unsupported_event}

      true ->
        predictions =
          events
          |> Enum.uniq()
          |> Enum.flat_map(
            &fit_event(observations, latitude, &1, Keyword.get(opts, :contours, true))
          )

        {:ok, predictions}
    end
  end

  @doc "Generation encoded by the current GF species-name convention."
  @spec generation_of(map()) :: generation()
  def generation_of(observation) do
    name = Map.get(observation, :species_name) || ""

    cond do
      String.ends_with?(name, "(sexgen)") -> :sexgen
      String.ends_with?(name, "(agamic)") -> :agamic
      true -> :unknown
    end
  end

  defp matches_event?(%{phenophase: "developing"}, :onset), do: true

  defp matches_event?(%{phenophase: phase}, :emergence) when phase in ["maturing", "Free-living"],
    do: true

  defp matches_event?(%{viability: "viable"}, :rearing), do: true
  defp matches_event?(_, _), do: false

  defp fit_event(observations, latitude, event, contours?) do
    observations
    |> Enum.filter(&matches_event?(&1, event))
    |> Enum.group_by(&generation_of/1)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {_, group} -> fit_group(group, latitude, event, contours?) end)
  end

  defp usable?(o) do
    match?(%Date{}, o.date) and Clock.supported_latitude?(o.latitude) and
      is_number(o.longitude) and o.longitude >= -180 and o.longitude <= 180
  end

  defp weighted_coordinate(o, counts) do
    day =
      Date.new!(
        2023,
        o.date.month,
        min(o.date.day, Calendar.ISO.days_in_month(2023, o.date.month))
      )
      |> Date.day_of_year()

    {Clock.coordinate(day, o.latitude), 1 / counts[{floor(o.latitude), floor(o.longitude)}]}
  end

  defp circular_center(values) do
    sin_sum = Enum.sum(Enum.map(values, fn {v, w} -> w * :math.sin(v * 2 * :math.pi() / 365) end))
    cos_sum = Enum.sum(Enum.map(values, fn {v, w} -> w * :math.cos(v * 2 * :math.pi() / 365) end))
    :math.atan2(sin_sum, cos_sum) * 365 / (2 * :math.pi())
  end

  defp center_values(values) do
    center = circular_center(values)

    values
    |> Enum.map(fn {v, w} -> {unwrap(v, center), w} end)
    |> Enum.sort()
  end

  defp unwrap(value, center), do: center + mod(value - center + 182.5, 365) - 182.5

  # A stable representative keeps the anchor link independent of query order,
  # including when several observations collapse to the same date/locality.
  defp anchor_key(o) do
    {o.date, o.latitude, o.longitude, Map.get(o, :page_url), Map.get(o, :source_url),
     Map.get(o, :id)}
  end

  defp thresholds(obs, counts, true) do
    values = Enum.map(obs, &weighted_coordinate(&1, counts))
    center = circular_center(values)

    {anchor, {phase, _}} =
      obs
      |> Enum.zip(values)
      |> Enum.min_by(fn {o, {v, _}} -> {unwrap(v, center), anchor_key(o)} end)

    provenance =
      Map.take(anchor, [:id, :species_id, :species_name, :date, :latitude, :page_url, :source_url])

    {[unwrap(phase, center)], provenance}
  end

  defp thresholds(obs, counts, false) do
    sorted = obs |> Enum.map(&weighted_coordinate(&1, counts)) |> center_values()
    {Enum.map([0.1, 0.25, 0.5, 0.75, 0.9], &quantile(sorted, &1)), nil}
  end

  defp fit_group(group, lat, event, contours?) do
    onset? = event == :onset

    valid = Enum.filter(group, &usable?/1)
    candidates = if onset?, do: Enum.sort_by(valid, &anchor_key/1), else: valid

    obs =
      Enum.uniq_by(
        candidates,
        &{&1.species_id, &1.date, round(&1.latitude * 10), round(&1.longitude * 10)}
      )

    if obs == [] do
      []
    else
      cell = fn o -> {floor(o.latitude), floor(o.longitude)} end
      counts = Enum.frequencies_by(obs, cell)

      {qs, anchor} = thresholds(obs, counts, onset?)
      rows = contour_rows(qs, onset?, contours?)
      p = row(qs, lat, onset?) |> Map.delete(:lat)
      p = Map.new(p, fn {k, d} -> {k, Integer.mod(round(d) - 1, 365) + 1} end)

      p = if onset?, do: Map.put(p, :anchor, anchor), else: p

      names =
        valid
        |> Enum.map(&(Map.get(&1, :species_name) || "Species #{&1.species_id}"))
        |> Enum.uniq()
        |> Enum.sort()

      name = Enum.join(names, ", ")

      generation = generation_of(hd(valid))

      [
        Map.merge(p, %{
          generation: generation,
          event: event,
          sparse?: length(obs) < 5,
          extrapolated?:
            lat < Enum.min(Enum.map(obs, & &1.latitude)) or
              lat > Enum.max(Enum.map(obs, & &1.latitude)),
          n: length(obs),
          raw_n: length(group),
          cells: map_size(counts),
          target_lat: lat,
          contours: rows,
          wrap_year: true,
          cohort_name: name,
          source:
            valid |> Enum.map(& &1.source_type) |> Enum.uniq() |> Enum.sort() |> Enum.join(" + "),
          phase:
            valid |> Enum.map(& &1.phenophase) |> Enum.uniq() |> Enum.sort() |> Enum.join(" + "),
          excluded_n: length(group) - length(valid),
          observed_min_lat: Enum.min(Enum.map(obs, & &1.latitude)),
          observed_max_lat: Enum.max(Enum.map(obs, & &1.latitude))
        })
      ]
    end
  end

  defp row(qs, lat, true) do
    [onset] = Enum.map(qs, &Clock.inverse(&1, lat))
    %{lat: lat, low_doy: onset, high_doy: onset}
  end

  defp row(qs, lat, false) do
    [a, b, c, d, e] = Enum.map(qs, &Clock.inverse(&1, lat))
    %{lat: lat, low_doy: b, high_doy: d, median_doy: c, outer_low_doy: a, outer_high_doy: e}
  end

  defp contour_rows(_qs, _onset?, false), do: []
  defp contour_rows(qs, onset?, true), do: Enum.map(250..550, &row(qs, &1 / 10, onset?))

  defp quantile(values, p) do
    total = Enum.sum(Enum.map(values, &elem(&1, 1)))

    Enum.reduce_while(values, 0.0, fn {v, w}, acc ->
      if acc + w >= p * total - 1.0e-10, do: {:halt, v}, else: {:cont, acc + w}
    end)
  end

  defp mod(x, period), do: x - floor(x / period) * period
end
