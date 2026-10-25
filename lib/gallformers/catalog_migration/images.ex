defmodule Gallformers.CatalogMigration.Images do
  @moduledoc """
  Gives each `image` row its typed reference (`9449` §6, Task 16): the Gall
  of a gall row (same ID), the taxon of a plant (same ID), or the genus
  taxon of a genus placeholder plant. Paths, `species_id` and everything
  else stay as they are.
  """

  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Repo

  @doc """
  Sets `image.gall_id` / `image.taxon_id`. `plants` maps plant species IDs
  to their taxa (`Gallformers.CatalogMigration.Taxa`).
  """
  @spec run(%{integer() => integer() | nil}, Report.t()) :: Report.t()
  def run(plants, report) do
    update!("UPDATE image i SET gall_id = i.species_id FROM galls g WHERE g.id = i.species_id")
    update!("UPDATE image i SET taxon_id = i.species_id FROM taxa t WHERE t.id = i.species_id")

    {species_ids, taxon_ids} =
      for {species_id, taxon_id} <- plants, taxon_id != nil, taxon_id != species_id do
        {species_id, taxon_id}
      end
      |> Enum.unzip()

    update!(
      """
      UPDATE image i SET taxon_id = m.taxon_id
      FROM unnest($1::bigint[], $2::bigint[]) AS m(species_id, taxon_id)
      WHERE i.species_id = m.species_id
      """,
      [species_ids, taxon_ids]
    )

    total = Old.count("SELECT count(*) FROM image")
    on_galls = Old.count("SELECT count(*) FROM image WHERE gall_id IS NOT NULL")
    on_taxa = Old.count("SELECT count(*) FROM image WHERE taxon_id IS NOT NULL")

    untyped =
      Old.rows(
        "SELECT id, species_id, path FROM image WHERE gall_id IS NULL AND taxon_id IS NULL ORDER BY id"
      )

    report
    |> Report.reconcile("Images (typed reference)", total, on_galls + on_taxa, [
      {"without one", length(untyped)}
    ])
    |> Report.count("Images of Galls", on_galls)
    |> Report.count("Images of taxa", on_taxa)
    |> Report.problems(
      "image without a typed reference",
      for(row <- untyped, do: "image #{row.id} (species #{row.species_id}): #{row.path}")
    )
  end

  defp update!(sql, params \\ []), do: Repo.query!(sql, params, timeout: :infinity)
end
