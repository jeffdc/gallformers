defmodule Gallformers.Import.GallComparison do
  @moduledoc """
  Compares what a gall batch says of one of its Galls with a Gallformers
  Gall (`d213` Task 4, *Galls step design*), field by field, on what
  curators judge Galls by:

    * `:host` — the Source's resolved Hosts (`host_of` Facts and
      `identified_by.host`) against the Gall's current Hosts: agrees when
      one of them is among the Gall's (a genus on either side agrees with
      its species), else differs. Never a conflict: Hosts are often
      incomplete.
    * `:where` — where on the plant, compared coarsely: every leaf value
      (any containing "leaf") is one value, `leaf`; the petiole, bud, stem,
      flower, fruit and roots are their own. A different coarse part is a
      conflict.
    * `:detachable` — agrees or differs (`unknown` is not stated; `both`
      agrees with either).
    * `:generation` — generation and season: the Source's generation
      against the Gall's, and the Source's seasons among the Gall's. Either
      differing differs.
    * `:form` — the Gall's overall type: a different form is a conflict.

  Each field is `:agree`, `:differ`, `:conflict`, or `:none` when either
  side does not state it. A conflict is a reason for a curator to look,
  not a verdict: a match with one is never firm
  (`Gallformers.Import.GallMatcher`).
  """

  alias Gallformers.Catalog.ReadModels.GallSummary
  alias Gallformers.Taxa

  @type field :: :host | :where | :detachable | :generation | :form
  @type result :: :agree | :differ | :conflict | :none

  @typedoc "What the batch says of a Gall (`source_side/3`)."
  @type source :: %{
          hosts: [integer()],
          where: [String.t()],
          detachable: [String.t()],
          generation: String.t() | nil,
          season: [String.t()],
          form: [String.t()]
        }

  @type t :: %{
          gall_id: integer(),
          fields: %{field() => result()},
          agrees: non_neg_integer(),
          conflicts: [field()]
        }

  @fields [:host, :where, :detachable, :generation, :form]

  @doc "The compared fields, in the order they are shown."
  @spec fields() :: [field()]
  def fields, do: @fields

  @doc """
  What the batch says of Gall `gall` (a batch Gall): its resolved Hosts
  (`host_ids`, as the matcher resolved them), and from `identified_by` and
  its confirmed trait Facts in `facts` its plant parts, detachable, season,
  form and generation.
  """
  @spec source_side(map(), [map()], [integer()]) :: source()
  def source_side(gall, facts, host_ids) do
    ident = gall["identified_by"] || %{}
    traits = traits(gall["ref"], facts)

    %{
      hosts: Enum.uniq(host_ids),
      where:
        Enum.uniq(
          Enum.filter([get_in(ident, ["plant_part", "value"])], &is_binary/1) ++
            Map.get(traits, "plant_part", [])
        ),
      detachable: Map.get(traits, "detachable", []),
      generation: get_in(ident, ["generation", "value"]),
      season: Map.get(traits, "season", []),
      form: Map.get(traits, "form", [])
    }
  end

  # The Gall's confirmed trait values by Trait: format 4's category (one
  # value or several), format 3's value.
  defp traits(ref, facts) do
    for %{"kind" => "trait", "gall" => ^ref, "trait" => trait} = f <- List.wrap(facts),
        Map.get(f, "stance", "confirm") == "confirm",
        value <- List.wrap(get_in(f, ["category", "value"]) || get_in(f, ["value", "value"])),
        is_binary(value),
        reduce: %{} do
      acc -> Map.update(acc, trait, [value], &Enum.uniq(&1 ++ [value]))
    end
  end

  @doc "Compares what the batch says (`source_side/3`) with Gallformers Gall `summary`."
  @spec compare(source(), GallSummary.t()) :: t()
  def compare(source, %GallSummary{} = summary) do
    fields = %{
      host: host(source.hosts, Enum.map(summary.hosts, & &1.taxon_id)),
      where: where(source.where, trait(summary, "plant_part")),
      detachable: detachable(source.detachable, trait(summary, "detachable")),
      generation: generation(source, summary),
      form: form(source.form, trait(summary, "form"))
    }

    %{
      gall_id: summary.gall_id,
      fields: fields,
      agrees: Enum.count(@fields, &(fields[&1] == :agree)),
      conflicts: Enum.filter(@fields, &(fields[&1] == :conflict))
    }
  end

  @doc """
  `summaries` with their comparisons, the most agreeing fields first (ties
  keep their order).
  """
  @spec rank([GallSummary.t()], source()) :: [{GallSummary.t(), t()}]
  def rank(summaries, source) do
    summaries
    |> Enum.map(&{&1, compare(source, &1)})
    |> Enum.sort_by(fn {_summary, c} -> c.agrees end, :desc)
  end

  @doc "A comparison as a queue item's proposal holds it (string keys and values)."
  @spec to_proposal(t()) :: map()
  def to_proposal(c) do
    %{
      "gall_id" => c.gall_id,
      "agrees" => c.agrees,
      "conflicts" => Enum.map(c.conflicts, &Atom.to_string/1),
      "fields" => Map.new(c.fields, fn {k, v} -> {Atom.to_string(k), Atom.to_string(v)} end)
    }
  end

  @doc "A field's name, as a sentence uses it (\"it conflicts on where on the plant\")."
  @spec label(field()) :: String.t()
  def label(:host), do: "Host"
  def label(:where), do: "where on the plant"
  def label(:detachable), do: "detachable"
  def label(:generation), do: "generation and season"
  def label(:form), do: "form"

  @doc "A plant part, coarsely: every leaf value is `leaf`."
  @spec coarse_part(String.t()) :: String.t()
  def coarse_part(part) do
    if String.contains?(part, "leaf"), do: "leaf", else: part
  end

  defp trait(summary, name), do: Map.get(summary.traits, name, [])

  # -- fields --------------------------------------------------------------------

  defp host([], _gall_hosts), do: :none
  defp host(_source_hosts, []), do: :none

  defp host(source_hosts, gall_hosts) do
    if overlap?(lineage(source_hosts), gall_hosts) or overlap?(lineage(gall_hosts), source_hosts),
      do: :agree,
      else: :differ
  end

  defp where(source, gall) do
    compare_sets(Enum.map(source, &coarse_part/1), Enum.map(gall, &coarse_part/1), :conflict)
  end

  defp detachable(source, gall) do
    source = source -- ["unknown"]
    gall = gall -- ["unknown"]

    cond do
      source == [] or gall == [] -> :none
      "both" in source or "both" in gall -> :agree
      true -> compare_sets(source, gall, :differ)
    end
  end

  defp generation(source, summary) do
    both = [
      same_generation(source.generation, summary.generation),
      seasons(source.season, trait(summary, "season"))
    ]

    cond do
      :differ in both -> :differ
      :agree in both -> :agree
      true -> :none
    end
  end

  defp same_generation(nil, _gall), do: :none
  defp same_generation(_source, nil), do: :none
  defp same_generation(same, same), do: :agree
  defp same_generation(_source, _gall), do: :differ

  defp seasons([], _gall), do: :none
  defp seasons(_source, []), do: :none
  defp seasons(source, gall), do: if(Enum.all?(source, &(&1 in gall)), do: :agree, else: :differ)

  defp form(source, gall), do: compare_sets(source, gall, :conflict)

  defp compare_sets([], _gall, _otherwise), do: :none
  defp compare_sets(_source, [], _otherwise), do: :none

  defp compare_sets(source, gall, otherwise),
    do: if(overlap?(source, gall), do: :agree, else: otherwise)

  defp overlap?(a, b), do: Enum.any?(a, &(&1 in b))

  # The taxa and their ancestors.
  defp lineage(ids),
    do: Enum.uniq(ids ++ Enum.flat_map(ids, fn id -> Enum.map(Taxa.ancestors(id), & &1.id) end))
end
