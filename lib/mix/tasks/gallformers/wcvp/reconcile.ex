defmodule Mix.Tasks.Gallformers.Wcvp.Reconcile do
  @moduledoc """
  Reconciles gallformers plant data against WCVP.

  ## Usage

      mix gallformers.wcvp.reconcile

  Requires WCVP data to be downloaded first (mix gallformers.wcvp.download).

  Produces reports in priv/repo/data/reconciliation/YYYY-MM-DD/:
    - taxonomy-mismatches.json
    - in-gf-not-wcvp.json
    - in-wcvp-not-gf-usca.json
    - in-wcvp-not-gf-hemisphere.json
    - range-updates.json
  """

  use Mix.Task

  import Ecto.Query

  @shortdoc "Reconcile gallformers plants against WCVP taxonomy"

  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy.Taxonomy
  alias Gallformers.Wcvp.{Matcher, Reader, Reporter, Tdwg}

  @data_dir "priv/repo/data/wcvp"
  @names_file "wcvp_names.csv"
  @dist_file "wcvp_distribution.csv"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    names_path = Path.join(@data_dir, @names_file)
    dist_path = Path.join(@data_dir, @dist_file)

    unless File.exists?(names_path) and File.exists?(dist_path) do
      Mix.raise("""
      WCVP data not found at #{@data_dir}/.
      Run `mix gallformers.wcvp.download` first.
      """)
    end

    IO.puts("Loading WCVP data...")

    IO.puts("  Building accepted names index...")
    accepted_by_id = Reader.build_accepted_name_lookup(names_path)

    accepted_by_name =
      Map.new(accepted_by_id, fn {_id, name} -> {name.taxon_name, name} end)

    IO.puts("  Building synonym index...")
    synonym_index = Reader.build_synonym_index(names_path)

    IO.puts("  Building distribution index...")
    dist_index = Reader.build_distribution_index(dist_path)

    IO.puts("  Loading TDWG mapping...")
    tdwg_lookup = Tdwg.load()

    IO.puts("  Loading gallformers plants...")
    gf_plants = load_gf_plants()

    IO.puts("\nLoaded:")
    IO.puts("  #{map_size(accepted_by_name)} accepted WCVP names")
    IO.puts("  #{map_size(synonym_index)} WCVP synonyms")
    IO.puts("  #{map_size(dist_index)} WCVP distribution entries")
    IO.puts("  #{length(gf_plants)} gallformers plants")

    IO.puts("\nMatching gallformers plants against WCVP...")

    {matches, taxonomy_mismatches, gf_not_in_wcvp} =
      match_gf_plants(gf_plants, accepted_by_name, synonym_index, accepted_by_id)

    IO.puts("  #{length(matches)} matched")
    IO.puts("  #{length(taxonomy_mismatches)} taxonomy mismatches")
    IO.puts("  #{length(gf_not_in_wcvp)} not found in WCVP")

    IO.puts("\nFinding range updates for matched species...")
    range_updates = find_range_updates(matches, dist_index, tdwg_lookup)
    IO.puts("  #{length(range_updates)} species with new range data")

    IO.puts("\nWriting reports...")
    report_dir = Reporter.report_dir()

    reports = [
      {"taxonomy-mismatches", taxonomy_mismatches},
      {"in-gf-not-wcvp", gf_not_in_wcvp},
      {"range-updates", range_updates}
    ]

    Enum.each(reports, fn {name, items} ->
      path = Reporter.write_report(items, name, report_dir)
      IO.puts("  #{path} (#{length(items)} items)")
    end)

    IO.puts("\nDone. Reports written to #{report_dir}/")
  end

  # -- Loading gallformers data --

  defp load_gf_plants do
    from(s in Species,
      where: s.taxoncode == "plant",
      join: st in "species_taxonomy",
      on: st.species_id == s.id,
      join: t in Taxonomy,
      on: t.id == st.taxonomy_id,
      left_join: parent in Taxonomy,
      on: parent.id == t.parent_id,
      select: %{
        id: s.id,
        name: s.name,
        genus: t.name,
        family: coalesce(parent.name, ""),
        taxonomy_type: t.type
      },
      order_by: s.name
    )
    |> Repo.all()
    # If a species is linked to a section, walk up to get genus and family
    |> Enum.map(&resolve_taxonomy/1)
  end

  # Species linked to a section need an extra hop to get genus and family
  defp resolve_taxonomy(%{taxonomy_type: "section"} = plant) do
    case Repo.one(
           from(t in Taxonomy,
             where: t.name == ^plant.genus and t.type == "section",
             join: genus in Taxonomy,
             on: genus.id == t.parent_id,
             left_join: family in Taxonomy,
             on: family.id == genus.parent_id,
             select: %{genus: genus.name, family: coalesce(family.name, "")},
             limit: 1
           )
         ) do
      nil -> plant
      resolved -> %{plant | genus: resolved.genus, family: resolved.family}
    end
  end

  defp resolve_taxonomy(plant), do: plant

  # -- Matching --

  defp match_gf_plants(gf_plants, accepted_by_name, synonym_index, accepted_by_id) do
    gf_plants
    |> Enum.reduce({[], [], []}, fn plant, acc ->
      result = Matcher.match_name(plant.name, accepted_by_name, synonym_index, accepted_by_id)
      classify_match(plant, result, acc)
    end)
  end

  defp classify_match(plant, {:exact, wcvp}, {matches, tax_mismatches, not_found}) do
    match = %{gf_id: plant.id, gf_name: plant.name, wcvp_id: wcvp.plant_name_id}

    case check_taxonomy(plant, wcvp) do
      nil -> {[match | matches], tax_mismatches, not_found}
      mismatch -> {[match | matches], [mismatch | tax_mismatches], not_found}
    end
  end

  defp classify_match(plant, {:fuzzy, wcvp}, {matches, tax_mismatches, not_found}) do
    match = %{gf_id: plant.id, gf_name: plant.name, wcvp_id: wcvp.plant_name_id}

    mismatch = %{
      gf_species_id: plant.id,
      gf_name: plant.name,
      gf_family: plant.family,
      gf_genus: plant.genus,
      wcvp_accepted_name: wcvp.taxon_name,
      wcvp_family: wcvp.family,
      wcvp_genus: wcvp.genus,
      mismatch_type: "fuzzy_name",
      detail: "Fuzzy match: '#{plant.name}' matched WCVP '#{wcvp.taxon_name}'"
    }

    {[match | matches], [mismatch | tax_mismatches], not_found}
  end

  defp classify_match(plant, {:synonym, accepted}, {matches, tax_mismatches, not_found}) do
    match = %{gf_id: plant.id, gf_name: plant.name, wcvp_id: accepted.plant_name_id}

    mismatch = %{
      gf_species_id: plant.id,
      gf_name: plant.name,
      gf_family: plant.family,
      gf_genus: plant.genus,
      wcvp_accepted_name: accepted.taxon_name,
      wcvp_family: accepted.family,
      wcvp_genus: accepted.genus,
      mismatch_type: "synonym",
      detail:
        "Gallformers uses '#{plant.name}' which WCVP treats as synonym of '#{accepted.taxon_name}'"
    }

    {[match | matches], [mismatch | tax_mismatches], not_found}
  end

  defp classify_match(plant, {:no_match, closest}, {matches, tax_mismatches, not_found}) do
    entry = %{
      gf_species_id: plant.id,
      gf_name: plant.name,
      gf_family: plant.family,
      gf_genus: plant.genus,
      match_attempts: ["exact", "fuzzy", "synonym"],
      closest_wcvp_match: if(closest, do: closest.taxon_name)
    }

    {matches, tax_mismatches, [entry | not_found]}
  end

  defp check_taxonomy(gf_plant, wcvp_name) do
    diffs =
      Enum.reject(
        [
          if(gf_plant.family != wcvp_name.family, do: "family"),
          if(gf_plant.genus != wcvp_name.genus, do: "genus")
        ],
        &is_nil/1
      )

    if diffs == [] do
      nil
    else
      mismatches = Enum.join(diffs, ", ")

      %{
        gf_species_id: gf_plant.id,
        gf_name: gf_plant.name,
        gf_family: gf_plant.family,
        gf_genus: gf_plant.genus,
        wcvp_accepted_name: wcvp_name.taxon_name,
        wcvp_family: wcvp_name.family,
        wcvp_genus: wcvp_name.genus,
        mismatch_type: mismatches,
        detail: "Taxonomy differs: #{mismatches}"
      }
    end
  end

  # -- Range updates --

  defp find_range_updates(matches, dist_index, tdwg_lookup) do
    Enum.flat_map(matches, &compute_range_update(&1, dist_index, tdwg_lookup))
  end

  defp compute_range_update(match, dist_index, tdwg_lookup) do
    tdwg_codes = Map.get(dist_index, match.wcvp_id, [])

    if tdwg_codes == [] do
      []
    else
      {wcvp_places, _unknown} =
        Tdwg.convert_tdwg_codes_with_warnings(tdwg_codes, tdwg_lookup)

      current_codes = get_current_place_codes(match.gf_id)
      current_set = MapSet.new(current_codes)

      new_places =
        Enum.reject(wcvp_places, fn p -> MapSet.member?(current_set, p.code) end)

      build_range_entry(match, current_codes, wcvp_places, new_places)
    end
  end

  defp build_range_entry(_match, _current_codes, _wcvp_places, []), do: []

  defp build_range_entry(match, current_codes, wcvp_places, new_places) do
    [
      %{
        gf_species_id: match.gf_id,
        gf_name: match.gf_name,
        current_places: current_codes,
        wcvp_places: Enum.map(wcvp_places, & &1.code),
        new_places: Enum.map(new_places, & &1.code),
        new_precision: Map.new(new_places, fn p -> {p.code, p.precision} end)
      }
    ]
  end

  defp get_current_place_codes(species_id) do
    from(hr in "host_range",
      join: p in "place",
      on: hr.place_id == p.id,
      where: hr.species_id == ^species_id,
      select: p.code
    )
    |> Repo.all()
  end
end
