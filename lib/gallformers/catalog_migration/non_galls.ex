defmodule Gallformers.CatalogMigration.NonGalls do
  @moduledoc """
  Non-galls (`9449` Task 17; `b5bd` M2): gall rows with the form
  "non-gall" — gall lookalikes — are reviewed by hand and not migrated.

  `priv/catalog_migration/non_galls.csv` holds the decisions, one row per
  gall row (`gall_id, name, decision, note`):

    * `exclude` — not migrated: no Gall, so nothing hangs off it (Hosts,
      Traits, citations, notes and images are reported as not on a Gall).
      Each is recorded in `non_gall_redirects`
      (`Gallformers.Catalog.NonGallRedirect`), for the redirect of its old
      `/gall/:id` URL to the gall-lookalikes Article (`b5bd` M3).
    * `migrate` — migrated like any gall row (it is a gall after all).

  Any gall row may be excluded, flagged or not. A flagged row with no
  decision is pending: a strict run stops on it, a lenient run migrates it.
  The worksheet (`"non_galls"`) lists every flagged or decided row.
  """

  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.CatalogMigration.Curated
  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report

  @input "non_galls.csv"
  @columns ~w(gall_id name decision note flagged)

  @type decision :: %{
          gall_id: integer(),
          name: String.t(),
          decision: :exclude | :migrate,
          note: String.t()
        }

  @doc "Reads the decisions, by gall ID."
  @spec load(String.t()) :: {:ok, %{integer() => decision()}} | {:error, String.t()}
  def load(path) do
    with {:ok, rows} <- Curated.read(path, ~w(gall_id decision), ~w(name note)),
         {:ok, parsed} <- Curated.parse_rows(path, rows, &parse/1) do
      Curated.index(path, parsed, & &1.gall_id)
    end
  end

  defp parse(row) do
    with {:ok, id} <- Curated.integer(row["gall_id"], "gall_id"),
         {:ok, decision} <- decision(row["decision"]) do
      {:ok, %{gall_id: id, name: row["name"], decision: decision, note: row["note"]}}
    end
  end

  defp decision("exclude"), do: {:ok, :exclude}
  defp decision("migrate"), do: {:ok, :migrate}

  defp decision(other),
    do: {:error, "decision must be exclude or migrate, got #{inspect(other)}"}

  @doc """
  The gall rows not to migrate (the decided exclusions), with the worksheet,
  pending rows and counts added to the report. Each exclusion is recorded,
  as `actor`, for the redirect of its old URL
  (`Gallformers.Catalog.insert_non_gall_redirects/2`).
  """
  @spec run(Actor.t(), %{integer() => decision()}, Report.t()) ::
          {MapSet.t(integer()), Report.t()}
  def run(actor, decisions, report) do
    flagged = flagged()
    flagged_ids = MapSet.new(flagged, & &1.id)
    names = galls_named(Enum.uniq(Map.keys(decisions) ++ Enum.map(flagged, & &1.id)))

    excluded =
      for {id, %{decision: :exclude}} <- decisions,
          Map.has_key?(names, id),
          into: MapSet.new(),
          do: id

    rows =
      names
      |> Enum.sort()
      |> Enum.map(fn {id, name} ->
        decision = decisions[id]

        %{
          "gall_id" => id,
          "name" => name,
          "decision" => decision && to_string(decision.decision),
          "note" => decision && decision.note,
          "flagged" => if(MapSet.member?(flagged_ids, id), do: "non-gall form", else: "")
        }
      end)

    pending =
      for %{id: id, name: name} <- flagged, not Map.has_key?(decisions, id) do
        {id, "#{id} #{name} (form non-gall): exclude or migrate?"}
      end

    stale =
      for {id, decision} <- Enum.sort(decisions), problem = stale(id, decision, names) do
        problem
      end

    {:ok, redirects} =
      Catalog.insert_non_gall_redirects(
        actor,
        for(id <- Enum.sort(excluded), do: %{species_id: id, name: names[id]})
      )

    report =
      report
      |> Report.curation("non_galls", @columns, rows)
      |> Report.pending(@input, pending)
      |> Report.count("Gall rows with the form non-gall", length(flagged))
      |> Report.count("Gall rows excluded as non-galls (non_galls.csv)", MapSet.size(excluded))
      |> Report.reconcile(
        "Non-gall URLs (→ the gall-lookalikes Article)",
        MapSet.size(excluded),
        redirects
      )
      |> Report.problems("non_galls.csv", stale)

    {excluded, report}
  end

  defp stale(id, _decision, names) when not is_map_key(names, id),
    do: "#{id} is not a gall row; its decision is not used"

  defp stale(id, %{name: decided}, names) when decided != "" do
    if decided != names[id], do: "#{id} is now named #{names[id]} (decided as #{decided})"
  end

  defp stale(_id, _decision, _names), do: nil

  defp flagged do
    Old.rows("""
    SELECT DISTINCT s.id, s.name
    FROM species s
    JOIN gall_form gf ON gf.species_id = s.id
    JOIN form f ON f.id = gf.form_id
    WHERE s.taxoncode = 'gall' AND f.form = 'non-gall'
    ORDER BY s.id
    """)
  end

  defp galls_named(ids) do
    "SELECT id, name FROM species WHERE taxoncode = 'gall' AND id = ANY($1)"
    |> Old.rows([ids])
    |> Map.new(&{&1.id, &1.name})
  end
end
