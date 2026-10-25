defmodule Gallformers.CatalogMigration.LegacyFacts do
  @moduledoc """
  Today's gall data as legacy Facts (`9449` §6 *Legacy Facts*, Task 16;
  `b5bd` M0).

  One Source, **"Gallformers legacy data"** (kind `database`, no authored
  date), attributes every legacy Fact, so the site works before the
  backscan and any real Source outranks it: attributions are undated
  (`stated_on` nil, which sorts oldest) and carry no statement. What the
  Facts become at release is `b5bd` M0's open decision; this is only the
  mechanism. Today's NOT NULL `source` columns are filled for the old pages:
  no year (`pubyear` empty), Gallformers' site as the link, the Gallformers
  Source's license where there is one.

    * **Inducer** — `inducer_of` from each Gall's Inducer link
      (`Gallformers.CatalogMigration.Galls`): a species, or the genus or
      family of an undescribed Gall.
    * **Hosts** — `host_of` from each `gallhost` row; a genus placeholder
      host becomes its genus taxon (a genus-level Host). Two placeholders of
      one genus on one Gall make one Fact.
    * **Traits** — `trait_facts` from the nine Trait joins (`gall_color`,
      ...) and `gall_traits.detachable`, matched to `trait_values` by name
      (the contract's vocabulary is today's). Values the vocabulary lacks
      are reported, not migrated; detachability `unknown` states nothing
      and is not a Fact.

  Today's model holds no other Relationships (inquilines, parasitoids,
  ...): `gallhost` is its only link between organisms and Galls.

  ## Chunks

  Each Fact goes through `Gallformers.Catalog.assert_fact/4`, the importer's
  own path, which takes a transaction-scoped advisory lock per natural key.
  Tens of thousands of them in one transaction would overrun PostgreSQL's
  lock table (`max_locks_per_transaction`), so `plan/3` works out every
  assertion inside the migration's main transaction and `assert_all/2`
  makes them afterwards in transactions of 500.
  """

  alias Gallformers.Catalog
  alias Gallformers.CatalogMigration
  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Sources

  @title "Gallformers legacy data"
  @chunk 500

  @trait_tables [
    {"color", "color", "color"},
    {"walls", "walls", "walls"},
    {"cells", "cells", "cells"},
    {"shape", "shape", "shape"},
    {"texture", "texture", "texture"},
    {"alignment", "alignment", "alignment"},
    {"plant_part", "plant_part", "part"},
    {"form", "form", "form"},
    {"season", "season", "season"}
  ]

  @type assertion :: {Catalog.fact_kind(), map(), map()}

  @type plan :: %{source_id: integer(), assertions: [assertion()]}

  @doc "The legacy Source's title."
  @spec title() :: String.t()
  def title, do: @title

  @doc """
  Finds or creates the legacy Source and works out the legacy Facts of the
  migrated `galls` (`taxa` is the taxa step's crosswalk,
  `Gallformers.CatalogMigration.Taxa`), reporting what does not migrate.
  Writes nothing but the Source.
  """
  @spec plan(map(), [map()], Report.t()) :: {plan(), Report.t()}
  def plan(taxa, galls, report) do
    source = legacy_source!()
    attribution = %{source_id: source.id, stance: :confirm, stated: nil}
    gall_ids = Map.new(galls, &{&1.id, true})

    {inducers, report} = inducers(galls, attribution, report)
    {hosts, report} = hosts(taxa, gall_ids, attribution, report)
    {traits, report} = traits(gall_ids, attribution, report)

    {%{source_id: source.id, assertions: inducers ++ hosts ++ traits}, report}
  end

  @doc """
  Makes a plan's assertions as `actor`, in audited transactions of #{@chunk}.
  Raises on the first that fails (its chunk is rolled back).
  """
  @spec assert_all(Gallformers.Audit.Actor.t(), plan()) :: :ok
  def assert_all(actor, %{assertions: assertions}) do
    assertions
    |> Enum.chunk_every(@chunk)
    |> Enum.each(fn chunk ->
      {:ok, :ok} =
        CatalogMigration.transaction(actor, "catalog_migration.legacy_facts", fn ->
          Enum.each(chunk, &assert!(actor, &1))
        end)
    end)
  end

  @doc "Reconciles the plan with the attributions the legacy Source now holds."
  @spec reconcile(plan(), Report.t()) :: Report.t()
  def reconcile(%{source_id: source_id, assertions: assertions}, report) do
    held = Old.count("SELECT count(*) FROM attributions WHERE source_id = $1", [source_id])

    Report.reconcile(
      report,
      "Legacy Facts attributed to the legacy Source",
      length(assertions),
      held
    )
  end

  defp legacy_source! do
    gallformers = Sources.get_gallformers_source()

    attrs = %{
      title: @title,
      author: "Gallformers",
      authors: ["Gallformers"],
      pubyear: "",
      link: "https://gallformers.org",
      citation:
        "Gallformers legacy data: the Gallformers database as it stood before its data " <>
          "were attributed to Sources. Undated, so any dated Source outranks it.",
      license: (gallformers && gallformers.license) || "",
      licenselink: (gallformers && gallformers.licenselink) || "",
      kind: :database
    }

    case Sources.ensure_source(attrs) do
      {:ok, source} ->
        source

      {:error, changeset} ->
        raise "could not create the legacy Source: #{inspect(changeset.errors)}"
    end
  end

  # -- Inducers ------------------------------------------------------------------

  defp inducers(galls, attribution, report) do
    assertions =
      for %{inducer_id: inducer_id} = gall <- galls, inducer_id != nil do
        {:relationship,
         %{type: "inducer_of", subject_taxon_id: inducer_id, object_gall_id: gall.id},
         attribution}
      end

    {assertions,
     Report.reconcile(
       report,
       "Inducer Facts (Galls with an Inducer link)",
       Enum.count(galls, & &1.inducer_id),
       length(assertions)
     )}
  end

  # -- Hosts -----------------------------------------------------------------------

  defp hosts(taxa, gall_ids, attribution, report) do
    rows = Old.rows("SELECT gall_species_id, host_species_id FROM gallhost ORDER BY id")

    {keys, skipped} =
      Enum.reduce(rows, {[], []}, fn %{gall_species_id: gall, host_species_id: host},
                                     {keys, skipped} ->
        subject = Map.get(taxa.plants, host)

        cond do
          not Map.has_key?(gall_ids, gall) ->
            {keys, ["gallhost #{gall} → #{host}: #{gall} is not a gall row" | skipped]}

          subject == nil ->
            {keys, ["gallhost #{gall} → #{host}: #{host} is not a migrated plant" | skipped]}

          not plant?(subject, taxa) ->
            {keys, ["gallhost #{gall} → #{host}: its taxon is not in Plantae" | skipped]}

          true ->
            {[{subject, gall} | keys], skipped}
        end
      end)

    unique = keys |> Enum.reverse() |> Enum.uniq()

    assertions =
      for {subject, gall} <- unique do
        {:relationship, %{type: "host_of", subject_taxon_id: subject, object_gall_id: gall},
         attribution}
      end

    report =
      report
      |> Report.reconcile("Host links (gallhost)", length(rows), length(unique), [
        {"merged into the same genus Host", length(keys) - length(unique)},
        {"skipped", length(skipped)}
      ])
      |> Report.problems("host link not migrated", Enum.reverse(skipped))

    {assertions, report}
  end

  # A plant keeps its species ID; a genus Host's kingdom is its family's.
  defp plant?(taxon_id, taxa) do
    case taxa.taxa[taxon_id] do
      %{kingdom: kingdom} -> kingdom == "Plantae"
      nil -> false
    end
  end

  # -- Traits ----------------------------------------------------------------------

  defp traits(gall_ids, attribution, report) do
    vocabulary = Map.new(Catalog.list_trait_values(), &{{&1.trait, &1.value}, true})

    rows =
      (joined_traits() ++ detachable())
      |> Enum.filter(&Map.has_key?(gall_ids, &1.species_id))

    {unknown_detachable, rows} =
      Enum.split_with(rows, &(&1.trait == "detachable" and &1.value == "unknown"))

    {mapped, unmapped} = Enum.split_with(rows, &Map.has_key?(vocabulary, {&1.trait, &1.value}))

    assertions =
      for %{species_id: gall, trait: trait, value: value} <- mapped do
        {:trait, %{gall_id: gall, trait: trait, value: value},
         Map.put(attribution, :value_as_written, value)}
      end

    unmapped_lines =
      unmapped
      |> Enum.frequencies_by(&{&1.trait, &1.value})
      |> Enum.sort()
      |> Enum.map(fn {{trait, value}, n} -> "#{trait}: #{inspect(value)} on #{n} gall(s)" end)

    report =
      report
      |> Report.reconcile("Trait links (Trait joins, detachable)", length(rows), length(mapped), [
        {"values not in the vocabulary", length(unmapped)}
      ])
      |> Report.count("Galls with detachable \"unknown\" (no Fact)", length(unknown_detachable))
      |> Report.problems("Trait value not in the vocabulary", unmapped_lines)

    {assertions, report}
  end

  defp joined_traits do
    @trait_tables
    |> Enum.map_join(" UNION ALL ", fn {trait, table, column} ->
      "SELECT j.species_id, '#{trait}' AS trait, v.#{column} AS value " <>
        "FROM gall_#{table} j JOIN #{table} v ON v.id = j.#{table}_id"
    end)
    |> Kernel.<>(" ORDER BY species_id, trait, value")
    |> Old.rows()
  end

  defp detachable do
    Old.rows("""
    SELECT species_id, 'detachable' AS trait, detachable AS value
    FROM gall_traits WHERE detachable IS NOT NULL ORDER BY species_id
    """)
  end

  # -- asserting -------------------------------------------------------------------

  defp assert!(actor, {kind, key, attribution}) do
    case Catalog.assert_fact(kind, actor, key, attribution) do
      {:ok, _result} ->
        :ok

      {:error, changeset} ->
        raise "could not assert legacy #{kind} #{inspect(key)}: #{inspect(changeset.errors)}"
    end
  end
end
