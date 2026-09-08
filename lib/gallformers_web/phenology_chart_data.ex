defmodule GallformersWeb.PhenologyChartData do
  @moduledoc "Shared observation payload for phenology charts and explorer tables."

  def points(observations) do
    Enum.map(observations, fn o ->
      %{
        id: o.id,
        species_id: o.species_id,
        species_name: o.species_name,
        host_species_name: o.host_species_name,
        doy: o.doy,
        seasind: o.seasind,
        date: if(match?(%Date{}, o.date), do: Date.to_iso8601(o.date), else: ""),
        lat: o.latitude,
        lng: o.longitude,
        generation: generation_of(o.species_name),
        phenophase: o.phenophase || "(none)",
        lifestage: o.lifestage || "",
        viability: o.viability || "",
        source_type: o.source_type,
        source_url: o.source_url,
        page_url: o.page_url,
        site: o.site || "",
        state: o.state || "",
        country: o.country || ""
      }
    end)
  end

  def generation_of(name) when is_binary(name) do
    cond do
      String.contains?(name, "(sexgen)") -> "sexgen"
      String.contains?(name, "(agamic)") -> "agamic"
      true -> "unknown"
    end
  end

  def generation_of(_), do: "unknown"
end
