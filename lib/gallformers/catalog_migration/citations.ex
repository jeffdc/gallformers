defmodule Gallformers.CatalogMigration.Citations do
  @moduledoc """
  Today's record-level citations (`species_source` rows of every Source but
  the Gallformers Source) as legacy citations of their Galls (`9449` §6,
  Task 16; `Gallformers.Catalog.LegacyCitation`): the Source, narrative,
  `useasdefault` and deep link, kept for the Gall page until the backscan
  attributes their Facts. They are not Facts. (Which Source a Gall's page
  leads with is the Gall's `default_source_id`, set from `useasdefault` by
  `Gallformers.CatalogMigration.Galls`; the citation keeps the flag.) Citations of plants have no
  Gall to go to and are reported.
  """

  alias Gallformers.Catalog
  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report

  @doc """
  Carries the citations of the migrated Galls (`gall_ids`) over, as `actor`.
  `gallformers_id` is the Gallformers Source's ID (its rows are notes), or
  nil.
  """
  @spec run(Gallformers.Audit.Actor.t(), %{integer() => true}, integer() | nil, Report.t()) ::
          Report.t()
  def run(actor, gall_ids, gallformers_id, report) do
    rows =
      Old.rows(
        """
        SELECT id, species_id, source_id, description, useasdefault, externallink
        FROM species_source WHERE source_id IS DISTINCT FROM $1 ORDER BY id
        """,
        [gallformers_id]
      )

    {citations, skipped} = Enum.split_with(rows, &Map.has_key?(gall_ids, &1.species_id))

    {:ok, inserted} =
      Catalog.insert_legacy_citations(
        actor,
        for row <- citations do
          %{
            gall_id: row.species_id,
            source_id: row.source_id,
            description: row.description,
            useasdefault: row.useasdefault,
            externallink: row.externallink,
            legacy_id: row.id
          }
        end
      )

    report
    |> Report.reconcile("Citations (species_source, not Gallformers)", length(rows), inserted, [
      {"on species that are not Galls", length(skipped)}
    ])
    |> Report.problems(
      "citation not on a Gall (not migrated)",
      for(
        row <- skipped,
        do: "species_source #{row.id}: species #{row.species_id}, Source #{row.source_id}"
      )
    )
  end
end
