defmodule Gallformers.Import.SourceDates do
  @moduledoc """
  A Source's two dates, derived, never typed (matter `f14c`, "Review queue
  and the Sources list"):

    * **Ingested** — when the first batch of its packages was applied.
    * **Updated** — when its data was last edited: the latest of its
      applied batches, a later write to an attribution of it
      (`Gallformers.Facts.last_attribution_changes/1`), a curator's
      correction to its Facts (`Gallformers.Import.SourceCorrection`) and a
      later edit of the Source itself (its details, a retraction — which
      changes the standing of the Facts it supports).

  A Source **from the old data** (`legacy?`) is one no package brought: it
  has no applied package, or it was in Gallformers before the first
  package that applied a batch of it (an import creates a new Source when
  it applies it). It has no Ingested date. Its Updated date is only of
  applied packages and what came after the first of them, and of the
  curators' corrections, so a Source with no applied package and no
  correction has no date at all: the pages show "From the original
  Gallformers data" instead.

  A removed attribution leaves no time of its own; a correction that
  withdraws one moves Updated by the correction's. A reading fix (a
  package reading a held Source again, matter `87a1`) brings nothing in:
  it moves Updated, never Ingested, and a Source only reading fixes reach
  is from the old data.
  """

  import Ecto.Query, only: [from: 2]

  # A batch reading a held Source again (matter `87a1`): it brings nothing in.
  defmacrop reading_fix(content) do
    quote do: fragment("coalesce(? -> 'source' \\? 'reading_of', false)", unquote(content))
  end

  alias Gallformers.Facts
  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package
  alias Gallformers.Import.SourceCorrection
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
             first: filter(min(b.applied_at), not reading_fix(b.content)),
             last: max(b.applied_at),
             first_package: filter(min(p.inserted_at), not reading_fix(b.content)),
             source_inserted: s.inserted_at,
             source_updated: s.updated_at
           }}
      )
      |> Repo.all()
      |> Map.new()

    attributions = applied |> Map.keys() |> Facts.last_attribution_changes()

    corrections =
      from(c in SourceCorrection,
        where: c.source_id in ^ids,
        group_by: c.source_id,
        select: {c.source_id, max(c.inserted_at)}
      )
      |> Repo.all()
      |> Map.new()

    Map.new(ids, fn id -> {id, dates(applied[id], attributions[id], corrections[id])} end)
  end

  defp dates(nil, _attribution, corrected),
    do: %{ingested: nil, updated: corrected, legacy?: true}

  defp dates(applied, attribution, corrected) do
    legacy? =
      is_nil(applied.first_package) or
        DateTime.compare(applied.source_inserted, applied.first_package) == :lt

    updated =
      [applied.last, attribution, applied.source_updated, corrected]
      |> Enum.reject(&is_nil/1)
      |> Enum.max(DateTime)

    %{ingested: if(legacy?, do: nil, else: applied.first), updated: updated, legacy?: legacy?}
  end
end
