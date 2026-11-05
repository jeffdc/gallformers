defmodule Gallformers.Import.SourceDates do
  @moduledoc """
  A Source's two dates, derived, never typed (matter `f14c`, "Review queue
  and the Sources list"):

    * **Ingested** — when the first batch of its packages was applied.
    * **Updated** — when its data was last edited: the latest of its
      applied batches, a later write to an attribution of it (a curator's
      correction to its Facts; `Gallformers.Facts.last_attribution_changes/1`)
      and a later edit of the Source itself (its details, a retraction —
      which changes the standing of the Facts it supports).

  A Source **from the old data** (`legacy?`) is one no package brought: it
  has no applied package, or it was in Gallformers before the first
  package that applied a batch of it (an import creates a new Source when
  it applies it). It has no Ingested date. Its Updated date is only of
  applied packages and what came after the first of them, so a Source
  with no applied package has no date at all: the pages show "From the
  original Gallformers data" instead.

  A removed attribution leaves no time, so it does not move Updated.
  """

  import Ecto.Query, only: [from: 2]

  alias Gallformers.Facts
  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package
  alias Gallformers.Repo
  alias Gallformers.Sources.Source

  @type dates :: %{
          ingested: DateTime.t() | nil,
          updated: DateTime.t() | nil,
          legacy?: boolean()
        }

  @doc "The dates of each of `source_ids` (every one asked for), by Source ID."
  @spec for_sources([integer()]) :: %{integer() => dates()}
  def for_sources([]), do: %{}

  def for_sources(source_ids) when is_list(source_ids) do
    ids = Enum.uniq(source_ids)

    applied =
      from(b in Batch,
        join: p in Package,
        on: p.id == b.package_id,
        join: s in Source,
        on: s.id == p.source_id,
        where: p.source_id in ^ids and b.status == :applied,
        group_by: [p.source_id, s.inserted_at, s.updated_at],
        select:
          {p.source_id,
           %{
             first: min(b.applied_at),
             last: max(b.applied_at),
             first_package: min(p.inserted_at),
             source_inserted: s.inserted_at,
             source_updated: s.updated_at
           }}
      )
      |> Repo.all()
      |> Map.new()

    attributions = applied |> Map.keys() |> Facts.last_attribution_changes()

    Map.new(ids, fn id -> {id, dates(applied[id], attributions[id])} end)
  end

  defp dates(nil, _attribution), do: %{ingested: nil, updated: nil, legacy?: true}

  defp dates(applied, attribution) do
    legacy? = DateTime.compare(applied.source_inserted, applied.first_package) == :lt

    updated =
      [applied.last, attribution, applied.source_updated]
      |> Enum.reject(&is_nil/1)
      |> Enum.max(DateTime)

    %{ingested: if(legacy?, do: nil, else: applied.first), updated: updated, legacy?: legacy?}
  end
end
