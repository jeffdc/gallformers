defmodule GallformersWeb.PhenologyComponents do
  @moduledoc """
  Phenology presentation shared by the compact gall panel and full explorer.
  Receives prediction results; contains no fitting or database access.
  """
  use Phoenix.Component

  import GallformersWeb.CoreComponents, only: [button: 1, input: 1]
  import GallformersWeb.Helpers, only: [valid_url?: 1]

  attr :species_id, :integer, required: true
  attr :open, :boolean, default: false
  attr :count, :integer, default: 0
  attr :predictions, :list, default: []
  attr :target_lat, :any, default: nil
  attr :notice, :string, default: nil
  attr :points_json, :string, default: "[]"
  attr :sources, :map, default: %{}

  @doc "Collapsible gall-page panel; the parent loads evidence on first expansion."
  def phenology_summary(assigns) do
    assigns = assign(assigns, :form, to_form(%{"target_lat" => assigns.target_lat}))

    ~H"""
    <section id="gall-phenology" class="border border-gray-200 rounded-lg p-3 bg-white">
      <.button
        id="toggle-phenology"
        variant="ghost"
        size="sm"
        phx-click="toggle_phenology"
        aria-expanded={to_string(@open)}
        aria-controls="gall-phenology-content"
      >
        Phenology {if @open, do: "−", else: "+"}
      </.button>
      <div :if={@open} id="gall-phenology-content" class="mt-2 text-sm">
        <p :if={@count == 0} class="text-gray-500">
          No phenology observations recorded yet for this species.
        </p>
        <div :if={@count > 0}>
          <div class="flex items-center justify-between">
            <span>{@count} observations</span>
            <.link
              href={explorer_path(@species_id, @target_lat)}
              class="text-gf-maroon hover:underline"
            >
              View full chart →
            </.link>
          </div>
          <p :if={@sources != %{}} class="text-xs text-gray-500 mt-1">
            {Enum.map_join(Enum.sort(@sources), " · ", fn {source, n} ->
              "#{n} #{source_label(source)}"
            end)}
          </p>
          <div id="gall-phenology-layout" class="space-y-4 mt-3">
            <div class="min-w-0">
              <.chart
                id="gall-phenology-chart"
                points_json={@points_json}
                predictions={@predictions}
                selection={false}
                class="h-[420px]"
              />
              <p :if={@predictions != []} class="mt-1 text-xs text-gray-500">
                Solid: fresh gall onset. Dashed: emergence. Dotted: viable collections.
              </p>
            </div>
            <div class="min-w-0">
              <.form
                for={@form}
                id="gall-phenology-latitude"
                phx-change="set_phenology_lat"
                phx-submit="set_phenology_lat"
              >
                <div class="mt-2 max-w-48">
                  <.input
                    field={@form[:target_lat]}
                    id="phenology_target_lat"
                    type="number"
                    label="Latitude (°N)"
                    min="25"
                    max="55"
                    step="0.1"
                    placeholder="e.g. 42"
                    phx-debounce="500"
                  />
                </div>
              </.form>
              <.prediction_results predictions={@predictions} />
              <p :if={@notice} class="mt-2 text-xs text-gray-500" role="status">{@notice}</p>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :points_json, :string, required: true
  attr :predictions, :list, default: []
  attr :lat_range, :any, default: nil
  attr :selection, :boolean, default: true
  attr :class, :string, default: "h-[540px]"

  @doc "One chart hook for the explorer and read-only gall panel."
  def chart(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="PhenologyChart"
      phx-update="ignore"
      data-points={@points_json}
      data-lat-range={if @lat_range, do: Jason.encode!(@lat_range)}
      data-predictions={Jason.encode!(@predictions)}
      data-selection-enabled={to_string(@selection)}
      class={["relative rounded-lg border border-gray-200 bg-white", @class]}
      role="figure"
      aria-label="Phenology observations by date and latitude"
    >
    </div>
    """
  end

  attr :predictions, :list, required: true

  @doc "Shared date outputs and evidence limitations for both displays."
  def prediction_results(assigns) do
    predictions = Enum.sort_by(assigns.predictions, &{&1.generation, event_order(&1.event)})

    assigns =
      assigns
      |> assign(:predictions, predictions)
      |> assign(:groups, Enum.group_by(predictions, & &1.generation) |> Enum.sort())

    ~H"""
    <div class="mt-2 space-y-4">
      <div :for={{generation, predictions} <- @groups}>
        <p class="text-xs font-medium text-gray-600">{generation_label(generation)}</p>
        <ul class="mt-1 space-y-2">
          <li
            :for={p <- predictions}
            data-event={p.event}
            data-generation={p.generation}
            data-low-doy={p.low_doy}
            data-high-doy={p.high_doy}
          >
            <p class="text-sm leading-6 text-gray-900">
              {event_sentence(p.event)} around <strong class="font-semibold">{date_range(p.low_doy, p.high_doy)}</strong>.
            </p>
            <p :if={p.sparse?} class="text-xs text-amber-800">
              Few records; season timing may be incomplete.
            </p>
            <p :if={p.extrapolated?} class="text-xs text-amber-800">
              Extrapolation: {latitude_label(p.target_lat)} is outside the recorded range
              ({latitude_range(p)}). Timing at this latitude is unverified.
            </p>
            <p
              :if={!p.extrapolated? && p.observed_max_lat - p.observed_min_lat < 2}
              class="text-xs text-amber-800"
            >
              Limited latitude coverage ({latitude_range(p)}); timing elsewhere is uncertain.
            </p>
          </li>
        </ul>
      </div>
      <details :if={@predictions != []} class="text-xs text-gray-600">
        <summary class="cursor-pointer hover:text-gf-maroon">Evidence &amp; methods</summary>
        <div class="mt-2 space-y-3">
          <p>Latitude-only estimates; elevation, host and year are not modeled.</p>
          <div :for={p <- @predictions}>
            <p class="font-medium">{event_label(p.event)} · {generation_label(p.generation)}</p>
            <.onset_anchor :if={p.event == :onset} anchor={p.anchor} />
            <p :if={Map.has_key?(p, :median_doy)}>
              The main window shows the middle 50% of latitude-adjusted records.
              Middle 80%: {date_range(p.outer_low_doy, p.outer_high_doy)};
              median: {doy_label(p.median_doy)}. These are not confidence intervals.
            </p>
            <p>
              {p.n} distinct date/location {if p.n == 1, do: "record", else: "records"}.
              <span :if={p.excluded_n > 0}>
                {p.excluded_n} records lack supported dates or coordinates.
              </span>
            </p>
          </div>
        </div>
      </details>
    </div>
    """
  end

  attr :anchor, :map, required: true

  defp onset_anchor(assigns) do
    assigns =
      assign(
        assigns,
        :url,
        Enum.find([assigns.anchor[:page_url], assigns.anchor[:source_url]], &valid_url?/1)
      )

    ~H"""
    <span class="block text-xs text-gray-600">
      Earliest recorded development, latitude-adjusted.
      <.link
        :if={@url}
        href={@url}
        target="_blank"
        rel="noopener"
        class="text-gf-maroon hover:underline"
      >
        Anchor record ↗
      </.link>
      {Calendar.strftime(@anchor.date, "%b %-d, %Y")} at {latitude_label(@anchor.latitude)}.
    </span>
    """
  end

  defp source_label("inat"), do: "iNaturalist"
  defp source_label("literature"), do: "literature"
  defp source_label(source), do: source || "unspecified source"

  defp latitude_label(lat), do: "#{Float.round(lat / 1, 1)}°N"

  defp latitude_range(p) do
    if Float.round(p.observed_min_lat / 1, 1) == Float.round(p.observed_max_lat / 1, 1),
      do: latitude_label(p.observed_min_lat),
      else: "#{latitude_label(p.observed_min_lat)}–#{latitude_label(p.observed_max_lat)}"
  end

  defp explorer_path(id, lat) do
    query = %{species_id: id, events: "onset,emergence,rearing"}
    query = if lat in [nil, ""], do: query, else: Map.put(query, :lat, lat)
    "/phenology?" <> URI.encode_query(query)
  end

  defp event_order(:onset), do: 0
  defp event_order(:rearing), do: 1
  defp event_order(:emergence), do: 2

  defp event_label(:onset), do: "Fresh gall onset"
  defp event_label(:emergence), do: "Adult emergence"
  defp event_label(:rearing), do: "Viable collections"

  defp event_sentence(:onset), do: "Fresh galls may start appearing"
  defp event_sentence(:emergence), do: "Look for emerging or active adults"
  defp event_sentence(:rearing), do: "Try collecting galls for rearing"

  defp generation_label(:sexgen), do: "Sexual generation"
  defp generation_label(:agamic), do: "Agamic generation"
  defp generation_label(:unknown), do: "Generation unspecified"

  defp date_range(day, day), do: doy_label(day)
  defp date_range(first, last), do: "#{doy_label(first)}–#{doy_label(last)}"

  defp doy_label(day) do
    ~D[2023-01-01] |> Date.add(day - 1) |> Calendar.strftime("%b %-d")
  end
end
