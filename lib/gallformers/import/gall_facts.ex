defmodule Gallformers.Import.GallFacts do
  @moduledoc """
  A Gall's Facts as its page shows them with the Fact inspector (matter
  `87a1`): `Gallformers.Import.gall_facts/1`.

  Each current Fact about the Gall (`Gallformers.Import.facts_for_gall/1`)
  in its group: the Inducer, the Hosts, the Traits by Trait (with the
  Traits not recorded, in the page's order), the range (adjustments and
  recorded occurrences) and the aliases. Each Fact carries:

    * `key`, what the change set calls it (`Gallformers.Curation.Key`), so
      every action on the Fact can name it;
    * `kind` (`:inducer`, `:host`, `:trait`, `:range`, `:occurrence`,
      `:alias`), `trait` for a Trait value, and `value` in Gallformers'
      terms (`Gallformers.Import.FactsView`'s);
    * `standing`: `{:holds, n}`, stated by n Sources whose statements
      count (Gallformers once, however many of its own Sources state it),
      or `:unconfirmed` when only Gallformers' undated original data (the
      legacy data Source) states it; for a Fact no longer current (`past`,
      to open from the full record), `:withdrawn` or `:superseded`;
    * who says so (`Gallformers.Import.FactsView.statements/1`):
      `gallformers`, Gallformers' statement (its newest, of the Gallformers
      Source and the original data; nil when it has stated nothing), and
      `sources`, every other Source's, newest first (undated last).
  """
  alias Gallformers.Import

  @trait_order ~w(detachable color texture shape season alignment walls plant_part form cells)

  @type fact :: %{
          key: tuple(),
          fact_id: integer(),
          kind: :inducer | :host | :trait | :range | :occurrence | :alias,
          trait: String.t() | nil,
          value: map(),
          standing: {:holds, non_neg_integer()} | :unconfirmed | :withdrawn | :superseded,
          gallformers: map() | nil,
          sources: [map()]
        }

  @type t :: %{
          gall_id: integer(),
          inducer: [fact()],
          hosts: [fact()],
          traits: [%{trait: String.t(), facts: [fact()]}],
          traits_missing: [String.t()],
          range: [fact()],
          aliases: [fact()],
          past: [fact()]
        }

  @doc "The Traits in the order the Gall page shows them."
  @spec trait_order() :: [String.t()]
  def trait_order, do: @trait_order

  @doc "See the module doc."
  @spec for_gall(integer()) :: t()
  def for_gall(gall_id) when is_integer(gall_id) do
    [%{facts: facts}] = Import.facts_for_gall(gall_id)

    traits =
      for {trait, entries} <- facts.traits,
          current = current(entries),
          current != [],
          do: %{trait: trait, facts: current}

    traits = Enum.sort_by(traits, &trait_index(&1.trait))
    recorded = Enum.map(traits, & &1.trait)

    %{
      gall_id: gall_id,
      inducer: current(facts.inducer),
      hosts: current(facts.hosts),
      traits: traits,
      traits_missing: @trait_order -- recorded,
      range: current(facts.range),
      aliases: current(facts.aliases),
      past: past(facts)
    }
  end

  defp current(entries),
    do: for(%{standing: :current} = e <- entries, do: fact(e))

  # The Facts no longer current, to open from the full record: their
  # standing `:withdrawn` or `:superseded`.
  defp past(facts) do
    entries =
      facts.inducer ++
        facts.hosts ++
        Enum.flat_map(facts.traits, fn {_trait, entries} -> entries end) ++
        facts.range ++ facts.aliases

    for %{standing: standing} = e <- entries,
        standing in [:withdrawn, :superseded],
        do: %{fact(e) | standing: standing}
  end

  defp trait_index(trait),
    do: Enum.find_index(@trait_order, &(&1 == trait)) || length(@trait_order)

  defp fact(entry) do
    {kind, key} = key(entry)
    {own, others} = Enum.split_with(entry.lines, & &1.own?)

    %{
      key: key,
      fact_id: entry.fact_id,
      kind: kind,
      trait: if(kind == :trait, do: entry.value.trait),
      value: entry.value,
      standing: standing(entry.lines, own),
      gallformers: newest(own),
      sources: newest_first(others)
    }
  end

  defp key(%{kind: :relationship, value: %{type: "inducer_of", subject: s}}),
    do: {:inducer, {:inducer, s.taxon_id}}

  defp key(%{kind: :relationship, value: %{type: "host_of", subject: s}}),
    do: {:host, {:host, s.taxon_id}}

  defp key(%{kind: :trait, value: %{trait: trait, value: value}}),
    do: {:trait, {:trait, trait, value}}

  defp key(%{kind: :range, value: %{adjustment: adjustment, place: place}}),
    do: {:range, {:range, adjustment, place.id}}

  defp key(%{kind: :occurrence, value: %{place: place}}),
    do: {:occurrence, {:occurrence, place.id}}

  defp key(%{kind: :alias, value: %{name: name}}), do: {:alias, {:alias, name}}

  # Who states it, among the statements that count: Gallformers once.
  defp standing(lines, own) do
    stating = Enum.filter(lines, &(&1.stance == :confirm and &1.state == :counts))
    {own_stating, others} = Enum.split_with(stating, & &1.own?)

    cond do
      others == [] and own_stating != [] and Enum.all?(own, &original_data?/1) -> :unconfirmed
      own_stating == [] -> {:holds, length(others)}
      true -> {:holds, length(others) + 1}
    end
  end

  # Gallformers' undated original data: its own, undated, not a change.
  defp original_data?(line), do: line.own? and not line.gallformers? and line.stated_on == nil

  defp newest([]), do: nil
  defp newest(lines), do: lines |> newest_first() |> hd()

  # Dated statements newest first, then the undated ones; the lines come
  # oldest first with the undated ones first.
  defp newest_first(lines) do
    {undated, dated} = Enum.split_with(lines, &(&1.stated_on == nil))
    Enum.reverse(dated) ++ undated
  end
end
