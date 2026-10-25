defmodule Gallformers.Catalog.ReadModels.Flags do
  @moduledoc """
  Catalog flags for curators (`9449` §4; `8567` rule 8 and *Generation
  groups*), from current Facts:

    * `:unlinked_generations` — two Galls with the same species-level
      Inducer and different generations, with no current
      `alternate_generation_of` between them (either way round).
      `%{kind, inducer_id, gall_ids}`, the Galls by ID.
    * `:linked_inducers_differ` — a current `alternate_generation_of`
      between Galls whose current Inducers differ (both known; a link to a
      Gall with no Inducer is not flagged). `%{kind, fact_id, gall_ids,
      inducer_ids}`, `gall_ids` as `[subject, object]`.
    * `:generation_outside_groups` — a Gall's generation is not in a group
      that applies to its Inducer. The groups that apply are those mapped to
      the Inducer's nearest mapped ancestor, itself included (a deeper
      mapping overrides a higher one); if none is mapped, every group mapped
      below it. `reason` is `:no_groups` when no group applies at all (every
      generation is flagged until the groups are mapped to taxa) or
      `:other_group`. `%{kind, reason, gall_id, inducer_id, generation}`.

  "Species-level" is rank species or below. Computed on read.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Catalog.Vocab.GenerationGroupTaxon
  alias Gallformers.Catalog.Vocab.GenerationValue
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon

  @species_level [:species, :subspecies, :variety, :form]

  @type flag :: %{required(:kind) => atom(), optional(atom()) => term()}

  @doc "Alternate-generation mismatches, unlinked pairs first."
  @spec alternate_generations() :: [flag()]
  def alternate_generations do
    inducers = current_inducers()
    links = current_links()

    unlinked_generations(inducers, links) ++ linked_inducers_differ(inducers, links)
  end

  defp unlinked_generations(inducers, links) do
    linked = Map.new(links, fn {_fact_id, a, b} -> {Enum.sort([a, b]), true} end)

    inducers
    |> Enum.reject(fn {_gall, _inducer, generation_id} -> generation_id == nil end)
    |> Enum.group_by(fn {_gall, inducer, _gen} -> inducer end, fn {gall, _i, gen} ->
      {gall, gen}
    end)
    |> Enum.filter(fn {inducer, _galls} -> species_level?(inducer) end)
    |> Enum.sort()
    |> Enum.flat_map(fn {inducer, galls} ->
      for {a, gen_a} <- galls,
          {b, gen_b} <- galls,
          a < b,
          gen_a != gen_b,
          not Map.has_key?(linked, [a, b]),
          do: %{kind: :unlinked_generations, inducer_id: inducer, gall_ids: [a, b]}
    end)
  end

  defp linked_inducers_differ(inducers, links) do
    by_gall =
      Enum.group_by(inducers, fn {gall, _i, _g} -> gall end, fn {_g, inducer, _gen} -> inducer end)

    for {fact_id, subject, object} <- links,
        subject_inducers = by_gall |> Map.get(subject, []) |> Enum.sort(),
        object_inducers = by_gall |> Map.get(object, []) |> Enum.sort(),
        subject_inducers != [] and object_inducers != [],
        subject_inducers != object_inducers do
      %{
        kind: :linked_inducers_differ,
        fact_id: fact_id,
        gall_ids: [subject, object],
        inducer_ids: Enum.uniq(subject_inducers ++ object_inducers)
      }
    end
  end

  defp species_level?(taxon_id) do
    case Taxa.get_taxon(taxon_id) do
      %Taxon{rank: rank} -> rank in @species_level
      nil -> false
    end
  end

  @doc """
  Galls whose generation is outside their Inducer's generation groups; with
  `gall_ids`, only those Galls.
  """
  @spec generation_groups([integer()] | :all) :: [flag()]
  def generation_groups(gall_ids \\ :all) do
    mappings =
      Repo.all(from(m in GenerationGroupTaxon, select: {m.taxon_id, m.group_id}))
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    values = Repo.all(GenerationValue) |> Map.new(&{&1.id, &1})

    for {gall_id, inducer_id, generation_id} <- current_inducers(),
        gall_ids == :all or gall_id in gall_ids,
        generation_id != nil,
        %GenerationValue{group_id: group_id, value: value} = Map.fetch!(values, generation_id),
        groups = applicable_groups(inducer_id, mappings),
        group_id not in groups do
      %{
        kind: :generation_outside_groups,
        reason: if(groups == [], do: :no_groups, else: :other_group),
        gall_id: gall_id,
        inducer_id: inducer_id,
        generation: value
      }
    end
  end

  defp applicable_groups(_taxon_id, mappings) when map_size(mappings) == 0, do: []

  defp applicable_groups(taxon_id, mappings) do
    nearest =
      [taxon_id | Enum.map(Taxa.ancestors(taxon_id), & &1.id)]
      |> Enum.find_value(&Map.get(mappings, &1))

    case nearest do
      nil ->
        taxon_id
        |> Taxa.descendants()
        |> Enum.flat_map(&Map.get(mappings, &1.id, []))
        |> Enum.uniq()

      groups ->
        groups
    end
  end

  # {gall_id, inducer taxon_id, generation_value_id} for every current
  # inducer_of, by Gall then Inducer.
  defp current_inducers do
    from(r in Current.relationships("inducer_of"),
      join: g in Gall,
      on: g.id == r.object_gall_id,
      order_by: [g.id, r.subject_taxon_id],
      select: {g.id, r.subject_taxon_id, g.generation_value_id}
    )
    |> Repo.all()
  end

  # {fact_id, subject_gall_id, object_gall_id} for every current
  # alternate_generation_of.
  defp current_links do
    from(r in Current.relationships("alternate_generation_of"),
      order_by: r.fact_id,
      select: {r.fact_id, r.subject_gall_id, r.object_gall_id}
    )
    |> Repo.all()
  end
end
