defmodule Gallformers.CatalogMigration.Notes do
  @moduledoc """
  Gallformers ID Notes (the Gallformers Source's `species_source` rows,
  Source 58) as each Gall's note, verbatim (`9449` §6, Task 16; `20e5`).

  Each note becomes one undated `:note` document of the Gallformers Source
  (`Gallformers.Sources.store_note/5`): the text in the private bucket and
  one document item holding all of it, so Facts extracted from the note
  after release can quote it. Nothing is extracted now. Empty notes, and
  notes on species that are not Galls, are reported and not migrated.

  Today's `useasdefault` and `externallink` on these rows are counted for
  the open decision on the default description (`b5bd` M2); the note
  documents do not carry them.
  """

  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Sources
  alias Gallformers.Sources.Source

  @doc "Stores the notes of the migrated Galls (`gall_ids`), as `actor`."
  @spec run(Gallformers.Audit.Actor.t(), %{integer() => true}, Source.t() | nil, Report.t()) ::
          Report.t()
  def run(_actor, _gall_ids, nil, report) do
    report
    |> Report.reconcile("Gallformers notes", 0, 0)
    |> Report.problems("Gallformers notes", ["there is no Gallformers Source: no notes migrated"])
  end

  def run(actor, gall_ids, %Source{} = gallformers, report) do
    rows =
      Old.rows(
        """
        SELECT id, species_id, description, useasdefault, externallink
        FROM species_source WHERE source_id = $1 ORDER BY id
        """,
        [gallformers.id]
      )

    {on_galls, elsewhere} = Enum.split_with(rows, &Map.has_key?(gall_ids, &1.species_id))
    {empty, notes} = Enum.split_with(on_galls, &(String.trim(&1.description) == ""))

    for row <- notes do
      case Sources.store_note(actor, gallformers, row.species_id, row.description) do
        {:ok, _document} ->
          :ok

        {:error, reason} ->
          raise "could not store the note of Gall #{row.species_id}: #{inspect(reason)}"
      end
    end

    report
    |> Report.reconcile("Gallformers notes", length(rows), length(notes), [
      {"empty", length(empty)},
      {"on species that are not Galls", length(elsewhere)}
    ])
    |> Report.count(
      "Gallformers notes marked as the default description",
      Enum.count(rows, & &1.useasdefault)
    )
    |> Report.count(
      "Gallformers notes with a deep link",
      Enum.count(rows, &(String.trim(&1.externallink) != ""))
    )
    |> Report.problems(
      "Gallformers note not migrated",
      for(row <- empty ++ elsewhere, do: "species_source #{row.id}: species #{row.species_id}")
    )
  end
end
