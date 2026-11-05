defmodule Gallformers.CatalogMigration.UndescribedGalls do
  @moduledoc """
  An undescribed Gall's legacy Facts as Gallformers' own statements (`20e5`,
  decided 2026-10-30).

  For an undescribed Gall (today's `gall_traits.undescribed`) Gallformers is
  the only Source: its Inducer, Hosts and Traits are what Gallformers
  recorded, not what a publication says. So each of its legacy Facts
  (`Gallformers.CatalogMigration.LegacyFacts`) is also confirmed by the
  Gallformers Source, dated `stated_on` — the run's day, which in the
  maintenance window is the cutover date (`8567` Sources–Facts point 7) — so
  it is not shown as unconfirmed. The legacy attribution stays. A Gall's note
  adds what it says on top when it is processed.
  """

  alias Gallformers.CatalogMigration.LegacyFacts
  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Sources.Source

  @statement "Recorded by Gallformers for this undescribed Gall, carried over from the " <>
               "Gallformers database as it stood before its data were attributed to Sources."

  @doc """
  The Gallformers assertions for the undescribed Galls' Facts in `plan`,
  dated `stated_on`; none without a Gallformers Source.
  """
  @spec assertions(LegacyFacts.plan(), Source.t() | nil, Date.t(), Report.t()) ::
          {[LegacyFacts.assertion()], Report.t()}
  def assertions(_plan, nil, _stated_on, report), do: {[], report}

  def assertions(plan, %Source{id: source_id}, %Date{} = stated_on, report) do
    undescribed =
      "SELECT species_id FROM gall_traits WHERE undescribed"
      |> Old.rows()
      |> MapSet.new(& &1.species_id)

    attribution = %{
      source_id: source_id,
      stance: :confirm,
      stated: Date.to_iso8601(stated_on),
      statement_text: @statement
    }

    assertions =
      for {kind, key, legacy} <- plan.assertions,
          MapSet.member?(undescribed, gall_of(kind, key)) do
        {kind, key, Map.merge(attribution, Map.take(legacy, [:value_as_written]))}
      end

    {assertions,
     Report.count(
       report,
       "Undescribed Galls' legacy Facts confirmed by Gallformers",
       length(assertions)
     )}
  end

  defp gall_of(:relationship, %{object_gall_id: gall_id}), do: gall_id
  defp gall_of(:trait, %{gall_id: gall_id}), do: gall_id
  defp gall_of(_kind, _key), do: nil
end
