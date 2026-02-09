defmodule Gallformers.Repo.Migrations.MarkSourcelessGallsUndescribed do
  use Gallformers.Migration

  import Ecto.Query

  def up do
    # 1. Mark galls as undescribed if they have no sources
    execute("""
    UPDATE gall_traits
    SET undescribed = 1
    WHERE undescribed = 0
      AND species_id NOT IN (
        SELECT species_id FROM species_source
      )
      AND species_id IN (
        SELECT id FROM species WHERE taxoncode = 'gall'
      )
    """)

    # 2. Fix Unknown genera that don't match the "Unknown (Family)" naming convention.
    #
    # Any genus starting with "Unknown" whose name is NOT "Unknown (Family)"
    # needs fixing: rename if no correctly-named one exists, or merge into the
    # existing one (reassign species, then delete the bad record).
    fix_unknown_genera()
  end

  def down do
    :ok
  end

  defp fix_unknown_genera do
    bad_genera =
      from(t in "taxonomy",
        join: p in "taxonomy", on: t.parent_id == p.id,
        where: t.type == "genus",
        where: like(t.name, "Unknown%"),
        where: t.name != fragment("'Unknown (' || ? || ')'", p.name),
        select: %{id: t.id, name: t.name, parent_id: t.parent_id, family_name: p.name}
      )
      |> repo().all()

    Enum.each(bad_genera, fn bad ->
      expected_name = "Unknown (#{bad.family_name})"

      existing =
        from(t in "taxonomy",
          where: t.name == ^expected_name and t.type == "genus" and t.parent_id == ^bad.parent_id,
          select: t.id
        )
        |> repo().one()

      if existing do
        execute(
          "UPDATE species_taxonomy SET taxonomy_id = #{existing} WHERE taxonomy_id = #{bad.id}"
        )

        execute("DELETE FROM taxonomy WHERE id = #{bad.id}")
      else
        execute(
          "UPDATE taxonomy SET name = '#{String.replace(expected_name, "'", "''")}' WHERE id = #{bad.id}"
        )
      end
    end)
  end
end
