defmodule Gallformers.Catalog.Vocab.TermUsage do
  @moduledoc """
  How widely each Source term is used (matter `d213`, Task D), for the
  superadmin vocabulary page: the distinct Galls whose Trait attributions
  carry the term (`Gallformers.Facts.Attribution.term`, on any category)
  or that store it waiting or kept as text
  (`Gallformers.Catalog.PendingTraitTerm`), by Trait and normalized term.

  Terms are compared lowercased with spacing collapsed, in SQL, as
  `Gallformers.Catalog.Vocab.TraitTermMapping.normalize/1` compares them
  (without its Unicode normalization, which stored terms already share).
  """

  import Ecto.Query

  alias Gallformers.Catalog.Facts.TraitFact
  alias Gallformers.Catalog.PendingTraitTerm
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Facts.Attribution
  alias Gallformers.Repo

  @doc "The number of Galls using each term, `%{{trait, normalized term} => count}`."
  @spec gall_counts() :: %{{String.t(), String.t()} => pos_integer()}
  def gall_counts do
    carried =
      from(a in Attribution,
        join: d in TraitFact,
        on: d.fact_id == a.fact_id,
        join: v in TraitValue,
        on: v.id == d.trait_value_id,
        where: not is_nil(a.term),
        select: %{
          trait: v.trait,
          term: fragment("lower(regexp_replace(btrim(?), '\\s+', ' ', 'g'))", a.term),
          gall_id: d.gall_id
        }
      )

    waiting =
      from(p in PendingTraitTerm,
        select: %{trait: p.trait, term: p.normalized_term, gall_id: p.gall_id}
      )

    from(u in subquery(union(carried, ^waiting)),
      group_by: [u.trait, u.term],
      select: {u.trait, u.term, count(u.gall_id, :distinct)}
    )
    |> Repo.all()
    |> Map.new(fn {trait, term, n} -> {{trait, term}, n} end)
  end
end
