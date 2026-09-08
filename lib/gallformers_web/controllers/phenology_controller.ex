defmodule GallformersWeb.PhenologyController do
  @moduledoc """
  Controller actions for the public phenology explorer that aren't a
  natural fit for the LiveView — currently just the CSV export.

  Takes the same query-param shape as the LiveView (`search`, `gen`,
  `phen`, `display`) so the same filter URL maps to a corresponding
  download. Filter / brush parsing is shared with the LiveView via
  `GallformersWeb.PhenologyFilters` so they can't drift.
  """
  use GallformersWeb, :controller

  alias Gallformers.Phenology
  alias GallformersWeb.PhenologyFilters

  NimbleCSV.define(PhenologyCSV, separator: ",", escape: "\"")

  @obs_headers ~w(species phenophase lifestage viability host doy date latitude longitude source_type source_url page_url)
  @species_headers ~w(species n_obs latest)

  def export(conn, params) do
    case PhenologyFilters.parse_selection(params) do
      {:error, :invalid_landmark_selection} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(
          400,
          "Choose a reference day (1–366), latitude (25–55°N) and days before/after (0–183)."
        )

      selection ->
        export_selected(conn, params, selection)
    end
  end

  defp export_selected(conn, params, selection) do
    filters = PhenologyFilters.from_url_params(params)

    observations =
      filters
      |> Phenology.search_observations()
      |> apply_brush(PhenologyFilters.parse_brush(params))
      |> apply_selection(selection)

    {filename, body} =
      build_csv(filters[:display_mode], observations, filters[:sort], filters[:sort_dir])

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, body)
  end

  defp apply_brush(obs, nil), do: obs

  defp apply_brush(obs, %{doy_min: dmin, doy_max: dmax, lat_min: lmin, lat_max: lmax}) do
    Enum.filter(obs, fn o ->
      o.doy >= dmin and o.doy <= dmax and
        is_number(o.latitude) and o.latitude >= lmin and o.latitude <= lmax
    end)
  end

  # Display-only selection lens, mirroring the client-side applySelection so
  # the CSV matches the on-screen table. Modes are mutually exclusive.
  defp apply_selection(obs, nil), do: obs

  defp apply_selection(obs, {:date_range, doy, days}) do
    min = Integer.mod(doy - days, 365)
    max = Integer.mod(doy + days, 365)

    Enum.filter(obs, fn o ->
      if min <= max, do: o.doy >= min and o.doy <= max, else: o.doy >= min or o.doy <= max
    end)
  end

  defp apply_selection(obs, {:seasonal_landmark, window}) do
    Enum.filter(obs, &Phenology.in_seasonal_window?(&1.doy, &1.latitude, window))
  end

  # The two CSV shapes match what's on screen for the respective display
  # modes; predictions / any other mode gets the full obs table by default
  # so the download is never empty.
  defp build_csv(:species_list, observations, sort, sort_dir) do
    rows =
      observations
      |> Enum.group_by(&{&1.species_id, &1.species_name})
      |> Enum.map(fn {{_, name}, obs} ->
        latest =
          obs |> Enum.map(& &1.date) |> Enum.reject(&is_nil/1) |> Enum.max(Date, fn -> nil end)

        %{name: name, n_obs: length(obs), latest: latest}
      end)
      |> sort_species(sort, sort_dir)
      |> Enum.map(&[&1.name, &1.n_obs, format_date(&1.latest)])

    body = encode([@species_headers | rows])
    {"phenology_species.csv", body}
  end

  defp build_csv(_data_table_or_other, observations, _sort, _sort_dir) do
    rows = Enum.map(observations, &obs_to_row/1)
    body = encode([@obs_headers | rows])
    {"phenology_observations.csv", body}
  end

  # Mirrors PhenologyLive.sort_species_rows/3 (name-asc pre-pass = stable
  # tiebreaker) so the download order agrees with the on-screen species list.
  defp sort_species(rows, :name, dir), do: Enum.sort_by(rows, & &1.name, dir)

  defp sort_species(rows, :obs_count, dir),
    do: rows |> Enum.sort_by(& &1.name) |> Enum.sort_by(& &1.n_obs, dir)

  defp sort_species(rows, :recency, dir),
    do:
      rows |> Enum.sort_by(& &1.name) |> Enum.sort_by(&(&1.latest || ~D[0001-01-01]), {dir, Date})

  defp obs_to_row(o) do
    [
      o.species_name,
      o.phenophase || "",
      o.lifestage || "",
      o.viability || "",
      o.host_species_name || "",
      to_string(o.doy),
      format_date(o.date),
      format_number(o.latitude),
      format_number(o.longitude),
      o.source_type || "",
      o.source_url || "",
      o.page_url || ""
    ]
  end

  defp encode(rows), do: rows |> PhenologyCSV.dump_to_iodata() |> IO.iodata_to_binary()

  defp format_date(%Date{} = d), do: Date.to_iso8601(d)
  defp format_date(_), do: ""

  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, [:compact, decimals: 4])
  defp format_number(n) when is_number(n), do: to_string(n)
  defp format_number(_), do: ""
end
