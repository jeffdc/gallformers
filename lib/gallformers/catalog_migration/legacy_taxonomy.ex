defmodule Gallformers.CatalogMigration.LegacyTaxonomy do
  @moduledoc """
  Today's non-plant tree as statements of the undated "Gallformers legacy
  data" Source (matter `f923` Task 3, "Today's tree is undated at
  cutover"): for every taxon outside Plantae, once the migration has built
  the tree,

    * its **placement** — under its parent, or at the root;
    * its **accepted name**, with its rank, authorship and sensu;
    * each **synonym** (the name, as a synonymy into the taxon);
    * each **common name**.

  Undated, they sort before every dated statement, so any accepted dated
  Source outranks them and a backscanned paper that disagrees raises a
  curator question. Gallformers' own Source counts without acceptance
  (`Gallformers.Facts`), so the tree follows them until then. Plants get
  none: plant data stays editorial (`8567`).

  ## Idempotent

  Each statement is found by its natural key and attributed as before
  (`Gallformers.Taxa.assert_act/4`), so running it again writes nothing.

  ## Chunks

  As `Gallformers.CatalogMigration.LegacyFacts`: each assertion takes an
  advisory lock per natural key, so `plan/1` works them out and
  `assert_all/2` makes them in transactions of #{500}.
  """

  alias Gallformers.Audit.Actor
  alias Gallformers.CatalogMigration
  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Sources
  alias Gallformers.Taxa

  @chunk 500

  @type assertion :: {Taxa.act_kind(), map(), map()}

  @doc """
  The statements of today's non-plant tree, attributed to Source
  `source_id` (the legacy data Source), undated. Writes nothing.
  """
  @spec plan(integer()) :: [assertion()]
  def plan(source_id) when is_integer(source_id) do
    attribution = %{source_id: source_id, stance: :confirm, stated: nil}

    placements =
      for %{id: id, parent_id: parent_id} <-
            Old.rows("SELECT t.id, t.parent_id FROM taxa t WHERE #{non_plant()} ORDER BY t.id") do
        {:placement, %{taxon_id: id, parent_id: parent_id}, attribution}
      end

    names =
      for n <- names("accepted") do
        {:name,
         %{
           taxon_id: n.taxon_id,
           name: n.name,
           rank: n.rank,
           sensu: n.sensu,
           authorship: n.authorship
         }, Map.put(attribution, :authorship_as_written, n.authorship)}
      end

    synonyms =
      for n <- names("synonym") do
        {:synonymy, %{name: n.name, accepted_taxon_id: n.taxon_id}, attribution}
      end

    common_names =
      for c <-
            Old.rows("""
            SELECT c.taxon_id, c.name FROM taxon_common_names c JOIN taxa t ON t.id = c.taxon_id
            WHERE #{non_plant()} ORDER BY c.taxon_id, c.id
            """) do
        {:common_name, %{taxon_id: c.taxon_id, common_name: c.name}, attribution}
      end

    placements ++ names ++ synonyms ++ common_names
  end

  defp names(status) do
    Old.rows(
      """
      SELECT n.taxon_id, n.name, t.rank, n.sensu, n.authorship
      FROM taxon_names n JOIN taxa t ON t.id = n.taxon_id
      WHERE n.status = $1 AND #{non_plant()} ORDER BY n.taxon_id, n.id
      """,
      [status]
    )
  end

  defp non_plant, do: "t.kingdom IS DISTINCT FROM 'Plantae'"

  @doc """
  Makes `assertions` as `actor`, in audited transactions of #{@chunk}.
  Raises on the first that fails (its chunk is rolled back).
  """
  @spec assert_all(Actor.t(), [assertion()]) :: :ok
  def assert_all(%Actor{} = actor, assertions) do
    assertions
    |> Enum.chunk_every(@chunk)
    |> Enum.each(fn chunk ->
      {:ok, :ok} =
        CatalogMigration.transaction(actor, "catalog_migration.legacy_taxonomy", fn ->
          Enum.each(chunk, &assert!(actor, &1))
        end)
    end)
  end

  @doc """
  Plans and makes the statements for the tree as it stands (the legacy
  data Source must exist). Running it again writes nothing.
  """
  @spec run(Actor.t()) :: :ok
  def run(%Actor{} = actor) do
    %{id: source_id} = Sources.get_legacy_data_source() || raise "no legacy data Source"
    assert_all(actor, plan(source_id))
  end

  @doc "Reconciles the planned statements with the legacy Source's taxonomic attributions."
  @spec reconcile([assertion()], integer(), Report.t()) :: Report.t()
  def reconcile(assertions, source_id, report) do
    held =
      Old.count(
        """
        SELECT count(*) FROM attributions a JOIN facts f ON f.id = a.fact_id
        WHERE a.source_id = $1 AND f.kind LIKE 'taxon\\_%'
        """,
        [source_id]
      )

    Report.reconcile(
      report,
      "Legacy taxonomic statements (non-plant placements, names, synonyms, common names)",
      length(assertions),
      held
    )
  end

  defp assert!(actor, {kind, key, attribution}) do
    case Taxa.assert_act(kind, actor, key, attribution) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        raise "could not assert legacy #{kind} #{inspect(key)}: #{inspect(reason)}"
    end
  end
end
