defmodule Mix.Tasks.Gallformers.Wcvp.Apply do
  @moduledoc """
  Applies changes from a WCVP reconciliation report.

  ## Usage

      # Dry run (default) — shows what would change
      mix gallformers.wcvp.apply path/to/report.json

      # Actually apply changes
      mix gallformers.wcvp.apply path/to/report.json --commit

      # Apply only specific species by ID
      mix gallformers.wcvp.apply path/to/report.json --commit --ids 1234,5678

  ## Report types

  The task auto-detects the report type from the filename:
    - `range-updates.json` — adds new range data to existing species
    - `taxonomy-mismatches.json` — updates taxonomy linkages
    - `in-wcvp-not-gf-*.json` — imports new species

  ## Safety

  Dry run is the default. You must pass `--commit` to write to the database.
  All writes go through existing context functions (Plants, Ranges, Taxonomy).
  """

  use Mix.Task

  @shortdoc "Apply changes from a WCVP reconciliation report"

  alias Gallformers.Places
  alias Gallformers.Plants
  alias Gallformers.Ranges
  alias Gallformers.Taxonomy.SpeciesLink
  alias Gallformers.Taxonomy.Tree

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [commit: :boolean, ids: :string],
        aliases: [c: :commit]
      )

    report_path =
      case positional do
        [path] -> path
        _ -> Mix.raise("Usage: mix gallformers.wcvp.apply <report.json> [--commit] [--ids 1,2,3]")
      end

    unless File.exists?(report_path) do
      Mix.raise("Report file not found: #{report_path}")
    end

    commit? = Keyword.get(opts, :commit, false)
    id_filter = parse_id_filter(Keyword.get(opts, :ids))

    items = report_path |> File.read!() |> Jason.decode!()
    report_type = detect_report_type(report_path)

    items = filter_by_ids(items, id_filter, report_type)

    IO.puts("Report: #{report_path}")
    IO.puts("Type: #{report_type}")
    IO.puts("Items: #{length(items)}")
    IO.puts("Mode: #{if commit?, do: "COMMIT", else: "DRY RUN"}")
    IO.puts("")

    apply_report(report_type, items, commit?)
  end

  defp parse_id_filter(nil), do: nil

  defp parse_id_filter(ids_str) do
    ids_str |> String.split(",") |> Enum.map(&String.trim/1) |> MapSet.new()
  end

  defp filter_by_ids(items, nil, _report_type), do: items

  defp filter_by_ids(items, id_filter, :new_species) do
    Enum.filter(items, fn item -> MapSet.member?(id_filter, to_string(item["wcvp_id"])) end)
  end

  defp filter_by_ids(items, id_filter, _report_type) do
    Enum.filter(items, fn item -> MapSet.member?(id_filter, to_string(item["gf_species_id"])) end)
  end

  defp detect_report_type(path) do
    basename = Path.basename(path)

    cond do
      String.contains?(basename, "range-updates") -> :range_updates
      String.contains?(basename, "taxonomy-mismatches") -> :taxonomy_mismatches
      String.contains?(basename, "in-wcvp-not-gf") -> :new_species
      true -> :unknown
    end
  end

  defp apply_report(:unknown, _items, _commit?) do
    Mix.raise("Cannot determine report type from filename")
  end

  defp apply_report(:range_updates, items, commit?) do
    Enum.each(items, &apply_range_update(&1, commit?))

    IO.puts(
      "\n#{if commit?, do: "Applied", else: "Would apply"} range updates for #{length(items)} species."
    )
  end

  defp apply_report(:taxonomy_mismatches, items, commit?) do
    Enum.each(items, &apply_taxonomy_update(&1, commit?))

    IO.puts(
      "\n#{if commit?, do: "Applied", else: "Would apply"} taxonomy updates for #{length(items)} species."
    )
  end

  defp apply_report(:new_species, items, commit?) do
    Enum.each(items, &apply_new_species(&1, commit?))

    IO.puts("\n#{if commit?, do: "Applied", else: "Would apply"} #{length(items)} new species.")
  end

  # -- Range updates --

  defp apply_range_update(item, commit?) do
    name = item["gf_name"]
    species_id = item["gf_species_id"]
    new_places = item["new_places"]
    precisions = item["new_precision"]

    IO.puts("#{name} (#{species_id}): +#{length(new_places)} places")

    Enum.each(new_places, fn code ->
      precision = Map.get(precisions, code, "exact")
      IO.puts("  + #{code} (#{precision})")

      if commit?, do: insert_place(species_id, code, precision)
    end)
  end

  defp insert_place(species_id, code, precision) do
    case Places.get_place_by_code(code) do
      nil ->
        IO.puts("    WARNING: place code #{code} not found in DB, skipping")

      place ->
        Ranges.add_place_to_host(species_id, place.id, precision)
    end
  end

  # -- Taxonomy updates --

  defp apply_taxonomy_update(item, commit?) do
    name = item["gf_name"]
    species_id = item["gf_species_id"]
    mismatch_type = item["mismatch_type"]

    IO.puts("#{name} (#{species_id}): #{mismatch_type}")
    IO.puts("  #{item["detail"]}")

    if mismatch_type == "synonym" do
      IO.puts("  WCVP accepted: #{item["wcvp_accepted_name"]}")
      IO.puts("  (Synonym renames require manual review — skipping auto-apply)")
    else
      IO.puts("  WCVP says: #{item["wcvp_family"]} > #{item["wcvp_genus"]}")
      IO.puts("  GF has:    #{item["gf_family"]} > #{item["gf_genus"]}")

      if commit? and String.contains?(mismatch_type, "genus") do
        reassign_genus(species_id, item["wcvp_genus"], item["wcvp_family"])
      end
    end
  end

  defp reassign_genus(species_id, wcvp_genus, wcvp_family) do
    family = Tree.get_taxonomy_by_name(wcvp_family, "family")

    unless family do
      IO.puts("    WARNING: family '#{wcvp_family}' not found, skipping")
    end

    if family do
      genus = Tree.get_taxonomy_by_name(wcvp_genus, "genus")

      genus_id =
        if genus do
          genus.id
        else
          IO.puts("    Creating genus '#{wcvp_genus}' under '#{wcvp_family}'")

          {:ok, new_genus} =
            Tree.create_taxonomy(%{
              "name" => wcvp_genus,
              "type" => "genus",
              "parent_id" => family.id
            })

          new_genus.id
        end

      SpeciesLink.link_species_to_taxonomy(species_id, genus_id)
      IO.puts("    Updated taxonomy link")
    end
  end

  # -- New species --

  defp apply_new_species(item, commit?) do
    name = item["wcvp_name"]
    family = item["wcvp_family"]
    genus = item["wcvp_genus"]
    distribution = item["wcvp_distribution"] || []

    IO.puts("#{name} (#{family} > #{genus}), #{length(distribution)} places")

    if commit?, do: create_species(name, genus, family)
  end

  defp create_species(name, genus_name, family_name) do
    if Plants.get_host_by_name(name) do
      IO.puts("  Already exists, skipping")
    else
      insert_new_species(name, genus_name, family_name)
    end
  end

  defp insert_new_species(name, genus_name, family_name) do
    genus_id = find_or_create_genus(genus_name, family_name)

    if genus_id do
      case Plants.create_host(%{"name" => name}) do
        {:ok, host} ->
          SpeciesLink.link_species_to_taxonomy(host.id, genus_id)
          IO.puts("  Created species #{host.id}")

        {:error, reason} ->
          IO.puts("  ERROR: #{inspect(reason)}")
      end
    end
  end

  defp find_or_create_genus(genus_name, family_name) do
    case Tree.get_taxonomy_by_name(genus_name, "genus") do
      %{id: id} ->
        id

      nil ->
        case Tree.get_taxonomy_by_name(family_name, "family") do
          nil ->
            IO.puts("    WARNING: family '#{family_name}' not found, skipping")
            nil

          family ->
            IO.puts("    Creating genus '#{genus_name}' under '#{family_name}'")

            {:ok, new_genus} =
              Tree.create_taxonomy(%{
                "name" => genus_name,
                "type" => "genus",
                "parent_id" => family.id
              })

            new_genus.id
        end
    end
  end
end
