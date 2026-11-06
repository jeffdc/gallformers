defmodule GallformersWeb.DataDisplayComponents do
  @moduledoc """
  Data display components for the Gallformers application.

  Provides components for displaying species data, images, taxonomy,
  sources, and other domain-specific information.
  """
  use Phoenix.Component
  use Gettext, backend: GallformersWeb.Gettext

  import GallformersWeb.CoreComponents, only: [icon: 1]

  alias Gallformers.TaxonName

  @doc """
  Renders a taxonomic name with correct italicization based on rank.

  Species, genus, and section names are wrapped in `<em>` (italic).
  Family and higher ranks render as plain `<span>`.

  When rank is `"auto"`, italicization is inferred from the name itself
  (e.g., names ending in -idae, -oidea are not italicized). Use this when
  the rank is unknown, such as in identification key destinations.

  When `genus_placeholder` is `true`, a subtle non-italic `(genus-level)`
  annotation is appended after the taxon name to indicate that the record
  represents an unidentified member of a genus (e.g. "Quercus spp").

  ## Examples

      <.taxon_name name="Andricus quercuslanigera" />
      <.taxon_name name="Cynipidae" rank="family" />
      <.taxon_name name="Quercus" rank="genus" class="text-subsection" />
      <.taxon_name name="Ichneumonoidea" rank="auto" />
      <.taxon_name name="Quercus spp" genus_placeholder={true} />
  """
  attr :name, :string, required: true
  attr :rank, :any, default: "species"
  attr :class, :any, default: nil

  attr :genus_placeholder, :boolean,
    default: false,
    doc: "when true, append a non-italic '(genus-level)' annotation after the name"

  def taxon_name(assigns) do
    assigns = assign(assigns, :italicize, should_italicize?(assigns.rank, assigns.name))

    ~H"""
    <%= if @italicize do %>
      <span class={["taxon-name", @class]}>{name_segments(@name)}</span>
    <% else %>
      <span class={@class}>{@name}</span>
    <% end %>
    <span
      :if={@genus_placeholder}
      class="ml-1 align-baseline text-caption not-italic text-muted"
      title="This host record represents an unidentified member of the genus, not a specific species."
    >
      (genus-level)
    </span>
    """
  end

  # The name's italic and upright parts as one string, so no template
  # whitespace falls between them.
  defp name_segments(name) do
    name
    |> TaxonName.segments()
    |> Enum.map(fn
      {text, :italic} -> ["<em>", escape(text), "</em>"]
      {text, :upright} -> escape(text)
    end)
    |> Phoenix.HTML.raw()
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp should_italicize?("auto", name), do: TaxonName.italicize_name?(name)
  defp should_italicize?(rank, _name), do: TaxonName.italicize_rank?(rank)

  @doc """
  Renders a legend for the range map.

  ## Modes

  - `:public` — Documented, Country-level (for gall and host detail pages)
  - `:host_admin` — Documented, Country-level, Out of Range
  - `:gall_admin` — In Gall Range, Country-level, Host Only (not in gall range), Not in Range
  """
  attr :mode, :atom, required: true, values: [:public, :host_admin, :gall_admin]

  def range_map_legend(assigns) do
    ~H"""
    <div class="space-y-1">
      <.legend_swatch fill="bg-map-documented">
        {if @mode == :gall_admin, do: "In Gall Range", else: "Documented"}
      </.legend_swatch>
      <.legend_swatch fill="bg-map-country">Country-level record only</.legend_swatch>
      <.legend_swatch :if={@mode == :gall_admin} fill="bg-map-excluded">
        Host Only (not in gall range)
      </.legend_swatch>
      <.legend_swatch :if={@mode in [:host_admin, :gall_admin]} fill="bg-map-none">
        {if @mode == :gall_admin, do: "Not in Range", else: "Out of Range"}
      </.legend_swatch>
      <%!-- Hatched entries for introduced range --%>
      <.legend_swatch :if={@mode == :gall_admin} fill="bg-map-documented" hatched>
        Introduced (in gall range)
      </.legend_swatch>
      <.legend_swatch :if={@mode == :gall_admin} fill="bg-map-excluded" hatched>
        Introduced (not in gall range)
      </.legend_swatch>
      <.legend_swatch :if={@mode in [:public, :host_admin]} fill="bg-map-documented" hatched>
        Introduced range
      </.legend_swatch>
    </div>
    """
  end

  # One legend entry: a swatch in the map's fill (hatched for introduced
  # ranges, `.gf-hatch` in components.css) and its label.
  attr :fill, :string, required: true, doc: "the map fill's utility"
  attr :hatched, :boolean, default: false
  slot :inner_block, required: true

  defp legend_swatch(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <div class={["size-4 rounded-ctl border border-line-strong", @fill, @hatched && "gf-hatch"]}>
      </div>
      <span class="text-caption text-ink-2">{render_slot(@inner_block)}</span>
    </div>
    """
  end

  @doc """
  Renders a geographic range map showing US and Canadian states/provinces.

  Uses MapLibre GL JS with PMTiles for WebGL-based choropleth rendering.
  Shows countries at wide zoom, subdivisions when zoomed in.
  Displays regions in green if in range, coral if excluded, and white otherwise.

  ## Examples

      <.range_map in_range={["US-CA", "US-TX", "US-NY"]} />

      <.range_map in_range={["US-CA", "US-TX"]} excluded_range={["US-AZ"]} />

      <.range_map in_range={@places} editable />
  """
  attr :in_range, :list,
    required: true,
    doc: "list of postal codes in range (e.g., [\"CA\", \"TX\"])"

  attr :excluded_range, :list,
    default: [],
    doc: "list of postal codes explicitly excluded"

  attr :inherited_range, :list,
    default: [],
    doc: "list of postal codes with country/continent-level range (shown lighter green)"

  attr :introduced_range, :list,
    default: [],
    doc: "list of codes with introduced host range (shown with hatching pattern)"

  attr :editable, :boolean,
    default: false,
    doc: "whether regions are clickable for editing"

  attr :navigable, :boolean,
    default: false,
    doc: "whether clicking a region navigates to its place page"

  attr :place_mode, :boolean,
    default: false,
    doc: "when true, uses blue highlights and skips host-range labels (for place detail pages)"

  attr :id, :string,
    default: "range-map",
    doc: "unique id for the map element"

  attr :class, :any,
    default: nil,
    doc: "additional CSS classes"

  attr :tiles_url, :string,
    default: nil,
    doc: "URL to PMTiles boundary file. Defaults to :tiles_url app config."

  attr :empty_text, :string,
    default: "No range data available",
    doc: "text shown when no range data exists"

  attr :max_bounds, :any,
    default: nil,
    doc: "JSON-encodable [[west, south], [east, north]] max bounds for the map"

  attr :bounds, :any,
    default: nil,
    doc: "JSON-encodable [[west, south], [east, north]] initial bounds to fit"

  def range_map(assigns) do
    tiles_url =
      assigns.tiles_url ||
        Application.get_env(:gallformers, :tiles_url, "/tiles/boundaries.pmtiles")

    in_range_json = Jason.encode!(assigns.in_range)
    excluded_range_json = Jason.encode!(assigns.excluded_range)
    inherited_range_json = Jason.encode!(assigns.inherited_range)
    introduced_range_json = Jason.encode!(assigns.introduced_range)

    assigns =
      assigns
      |> assign(:tiles_url, tiles_url)
      |> assign(:in_range_json, in_range_json)
      |> assign(:excluded_range_json, excluded_range_json)
      |> assign(:inherited_range_json, inherited_range_json)
      |> assign(:introduced_range_json, introduced_range_json)
      |> assign(:max_bounds_json, if(assigns.max_bounds, do: Jason.encode!(assigns.max_bounds)))
      |> assign(:bounds_json, if(assigns.bounds, do: Jason.encode!(assigns.bounds)))

    ~H"""
    <div
      id={@id}
      class={["relative min-h-100", @class]}
      phx-hook="RangeMap"
      phx-update="ignore"
      data-in-range={@in_range_json}
      data-excluded-range={@excluded_range_json}
      data-inherited-range={@inherited_range_json}
      data-introduced-range={@introduced_range_json}
      data-editable={to_string(@editable)}
      data-navigable={to_string(@navigable)}
      data-place-mode={to_string(@place_mode)}
      data-tiles-url={@tiles_url}
      data-empty-text={@empty_text}
      data-max-bounds={@max_bounds_json}
      data-bounds={@bounds_json}
    >
      <div class="flex items-center justify-center p-8 text-muted">
        <.icon name="ph-map-trifold" class="size-8 animate-pulse" />
        <span class="ml-2">{gettext("Loading map...")}</span>
      </div>
    </div>
    """
  end
end
