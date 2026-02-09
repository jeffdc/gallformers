defmodule Gallformers.Repo.Migrations.FixUnknownSpeciesNames do
  use Gallformers.Migration

  import Ecto.Query

  @moduledoc """
  Renames gall species that use old Unknown naming conventions to match
  the corrected genus names from the previous migration.

  Old formats:
    "Unknown-cynipidae q-alba-leaf-gall"  (dash-prefix with family abbreviation)
    "Unknown m-fistulosa-apical-rosette-gall"  (bare Unknown)
  New format:
    "Unknown (Cynipidae) q-alba-leaf-gall"

  Derives the correct prefix from the species' linked genus, which was already
  fixed to "Unknown (Family)" format by MarkSourcelessGallsUndescribed.
  """

  def up do
    bad_species =
      from(s in "species",
        join: st in "species_taxonomy", on: st.species_id == s.id,
        join: t in "taxonomy", on: t.id == st.taxonomy_id and t.type == "genus",
        where: s.taxoncode == "gall",
        where: like(s.name, "Unknown%"),
        where: not like(s.name, "Unknown (%"),
        select: %{id: s.id, name: s.name, genus_name: t.name}
      )
      |> repo().all()

    Enum.each(bad_species, fn sp ->
      # Epithet is everything after the first space: "Unknown-cecid q-alba-gall" -> " q-alba-gall"
      epithet =
        case :binary.match(sp.name, " ") do
          {pos, _} -> binary_part(sp.name, pos, byte_size(sp.name) - pos)
          :nomatch -> ""
        end

      new_name = sp.genus_name <> epithet

      # Check for collision and append suffix if needed
      collision =
        from(s in "species", where: s.name == ^new_name and s.id != ^sp.id, select: s.id)
        |> repo().one()

      final_name = if collision, do: find_unique_name(new_name, 2), else: new_name

      escaped = String.replace(final_name, "'", "''")
      execute("UPDATE species SET name = '#{escaped}' WHERE id = #{sp.id}")
      execute("UPDATE species_fts SET name = '#{escaped}' WHERE species_id = #{sp.id}")
    end)
  end

  def down do
    :ok
  end

  defp find_unique_name(base_name, n) do
    candidate = "#{base_name}-#{n}"

    exists =
      from(s in "species", where: s.name == ^candidate, select: s.id)
      |> repo().one()

    if exists, do: find_unique_name(base_name, n + 1), else: candidate
  end
end
