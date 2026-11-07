defmodule Gallformers.Catalog.ReadModels.SpeciesSources do
  @moduledoc """
  The Sources a species page lists (matter `803b`, "The species page"):
  everything citing the organism or one of its Galls.

    * **Its Galls:** each Gall's Sources as `Gallformers.Catalog.gall_sources/1`
      reads them: legacy citations, Gallformers notes and the Sources
      attributing current Facts about it.
    * **The organism:** the Sources of the taxonomic statements about the
      taxon (its placement and name, the synonymies, common names and
      splits naming it), of any standing: a paper that disagrees cites it
      too.

  Gallformers' own Sources (`Gallformers.Sources.own_source_ids/0`: the
  Gallformers Source of the notes and the legacy data) are left out: they
  are no paper. Each Source once, with the Galls it covers (`gall_ids`) and
  whether it speaks of the taxonomy (`taxonomy`), by year (undated last),
  then title.
  """
  import Ecto.Query, only: [from: 2, union_all: 2]

  alias Gallformers.Catalog.LegacyCitation
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Facts.Attribution
  alias Gallformers.Facts.Fact
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa.ActFacts.CommonNameFact
  alias Gallformers.Taxa.ActFacts.SplitFact
  alias Gallformers.Taxa.ActFacts.SynonymyFact

  @type entry :: %{
          id: integer(),
          title: String.t(),
          author: String.t() | nil,
          pubyear: String.t() | nil,
          gall_ids: [integer()],
          taxonomy: boolean()
        }

  @doc "The Sources citing taxon `taxon_id` or one of `gall_ids` (see the module doc)."
  @spec for_taxon(integer(), [integer()]) :: [entry()]
  def for_taxon(taxon_id, gall_ids) when is_integer(taxon_id) and is_list(gall_ids) do
    own = MapSet.new(Sources.own_source_ids())

    by_gall =
      for gall_id <- Enum.uniq(gall_ids),
          source_id <- gall_source_ids(gall_id),
          do: {source_id, gall_id}

    taxonomic = taxon_id |> taxonomic_source_ids() |> MapSet.new()
    galls_of = Enum.group_by(by_gall, &elem(&1, 0), &elem(&1, 1))

    (Map.keys(galls_of) ++ MapSet.to_list(taxonomic))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(own, &1))
    |> Sources.list_sources_by_id()
    |> Enum.map(fn source ->
      %{
        id: source.id,
        title: source.title,
        author: source.author,
        pubyear: source.pubyear,
        gall_ids: galls_of |> Map.get(source.id, []) |> Enum.uniq() |> Enum.sort(),
        taxonomy: MapSet.member?(taxonomic, source.id)
      }
    end)
    |> Enum.sort_by(&{&1.pubyear in [nil, ""], &1.pubyear, &1.title, &1.id})
  end

  @doc """
  The IDs of Gall `gall_id`'s Sources, each once: those citing it (legacy
  citations), the Source of its Gallformers notes, and those attributing
  current Facts about it (`Gallformers.Catalog.gall_sources/1`).
  """
  @spec gall_source_ids(integer()) :: [integer()]
  def gall_source_ids(gall_id) do
    cited = Repo.all(from(c in LegacyCitation, where: c.gall_id == ^gall_id, select: c.source_id))
    noted = gall_id |> Sources.list_gall_notes() |> Enum.map(& &1.source_id)
    attributing = gall_id |> Current.source_ids_attributing() |> Repo.all()
    Enum.uniq(cited ++ noted ++ attributing)
  end

  # The Sources stating anything about the taxon's taxonomy.
  defp taxonomic_source_ids(taxon_id) do
    slots = ["taxon:#{taxon_id}:placement", "taxon:#{taxon_id}:name"]

    about =
      from(f in Fact, where: f.slot in ^slots, select: f.id)
      |> union_all(
        ^from(s in SynonymyFact, where: s.accepted_taxon_id == ^taxon_id, select: s.fact_id)
      )
      |> union_all(^from(c in CommonNameFact, where: c.taxon_id == ^taxon_id, select: c.fact_id))
      |> union_all(
        ^from(s in SplitFact,
          where: s.taxon_id == ^taxon_id or ^taxon_id in s.into_taxon_ids,
          select: s.fact_id
        )
      )

    Repo.all(
      from(a in Attribution,
        where: a.fact_id in subquery(about),
        distinct: true,
        select: a.source_id
      )
    )
  end
end
