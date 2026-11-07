defmodule Gallformers.Taxa.Records do
  @moduledoc """
  What deleting and merging taxa (matter `ec2c`, "Deletes") needs from
  Taxa: the taxonomic-act Facts that name a taxon, deleting them, moving a
  merged plant's names onto the plant it is merged into, and the
  redirects a merged plant's ID leaves (`Gallformers.Taxa.TaxonRedirect`).

  Called through `Gallformers.Taxa`; the deletes and merges themselves
  are `Gallformers.Import`'s, which also handles the Galls and Facts the
  Catalog holds.
  """
  import Ecto.Query

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Repo
  alias Gallformers.Taxa.ActFacts.CommonNameFact
  alias Gallformers.Taxa.ActFacts.NameFact
  alias Gallformers.Taxa.ActFacts.PlacementFact
  alias Gallformers.Taxa.ActFacts.SplitFact
  alias Gallformers.Taxa.ActFacts.SynonymyFact
  alias Gallformers.Taxa.CommonName
  alias Gallformers.Taxa.LegacyId
  alias Gallformers.Taxa.TaxonName
  alias Gallformers.Taxa.TaxonNote
  alias Gallformers.Taxa.TaxonRedirect

  @typedoc """
  A taxonomic-act Fact that names a taxon: its Fact ID and kind
  (`facts.kind`), the taxon among those asked about that it names
  (`taxon_id`) and its words.
  """
  @type act_fact :: %{
          fact_id: integer(),
          kind: String.t(),
          taxon_id: integer(),
          text: String.t()
        }

  @doc """
  The taxonomic-act Facts naming any of `taxon_ids`: a placement of one, or
  under one; a name, split or common name of one; a synonymy into one; a
  split into one. A Fact naming two of them is listed once.
  """
  @spec act_facts([integer()]) :: [act_fact()]
  def act_facts([]), do: []

  def act_facts(taxon_ids) when is_list(taxon_ids) do
    placements =
      from(p in PlacementFact,
        where: p.taxon_id in ^taxon_ids or p.parent_id in ^taxon_ids,
        select: {p.fact_id, "taxon_placement", p.taxon_id, p.parent_id}
      )
      |> Repo.all()
      |> Enum.map(fn {fact_id, kind, taxon_id, parent_id} ->
        about = if taxon_id in taxon_ids, do: taxon_id, else: parent_id
        {fact_id, kind, about, "placement under #{name(parent_id)}"}
      end)

    names =
      from(n in NameFact,
        where: n.taxon_id in ^taxon_ids,
        select: {n.fact_id, "taxon_name", n.taxon_id, n.name}
      )
      |> Repo.all()
      |> Enum.map(fn {f, k, t, name} -> {f, k, t, "name: #{name}"} end)

    synonymies =
      from(s in SynonymyFact,
        where: s.accepted_taxon_id in ^taxon_ids,
        select: {s.fact_id, "taxon_synonymy", s.accepted_taxon_id, s.name}
      )
      |> Repo.all()
      |> Enum.map(fn {f, k, t, name} -> {f, k, t, "synonym: #{name}"} end)

    splits =
      from(s in SplitFact,
        left_join: d in "split_fact_daughters",
        on: d.fact_id == s.fact_id,
        where: s.taxon_id in ^taxon_ids or d.taxon_id in ^taxon_ids,
        distinct: true,
        select: {s.fact_id, "taxon_split", s.taxon_id, d.taxon_id}
      )
      |> Repo.all()
      |> Enum.map(fn {f, k, t, daughter} ->
        about = if t in taxon_ids, do: t, else: daughter
        {f, k, about, "split of #{name(t)}"}
      end)

    common =
      from(c in CommonNameFact,
        where: c.taxon_id in ^taxon_ids,
        select: {c.fact_id, "taxon_common_name", c.taxon_id, c.common_name}
      )
      |> Repo.all()
      |> Enum.map(fn {f, k, t, name} -> {f, k, t, "common name: #{name}"} end)

    (placements ++ names ++ synonymies ++ splits ++ common)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.sort()
    |> Enum.map(fn {fact_id, kind, taxon_id, text} ->
      %{fact_id: fact_id, kind: kind, taxon_id: taxon_id, text: text}
    end)
  end

  @doc """
  Deletes the taxonomic-act Facts `fact_ids` (`act_facts/1`): their details,
  then the Facts with their attributions (`Gallformers.Facts.delete_facts/2`).
  IDs of other Facts are left alone. Returns how many were deleted.
  """
  @spec delete_act_facts(Actor.t(), [integer()]) :: {:ok, non_neg_integer()}
  def delete_act_facts(%Actor{} = actor, fact_ids) when is_list(fact_ids) do
    Audit.transaction(actor, "taxa.delete_act_facts", fn ->
      ids =
        Enum.flat_map(
          [PlacementFact, NameFact, SynonymyFact, SplitFact, CommonNameFact],
          fn schema ->
            {_count, deleted} =
              from(d in schema, where: d.fact_id in ^fact_ids, select: d.fact_id)
              |> Repo.delete_all()

            deleted
          end
        )

      {:ok, _conflicts} = Facts.delete_facts(actor, ids)
      length(ids)
    end)
  end

  @typedoc "What merging one plant's names into another's moved."
  @type merged_names :: %{synonyms: [String.t()], common_names: [String.t()]}

  @doc """
  Moves taxon `absorbed_id`'s names onto `survivor_id`, as a plant merge
  does: its accepted name and synonyms become the survivor's synonyms
  (one the survivor already holds, same normalized name and sensu, is
  dropped), its common names join the survivor's (ignoring case), and its
  crosswalk entries and "based on" notes follow it. Returns the names
  moved.
  """
  @spec merge_names(Actor.t(), integer(), integer()) :: {:ok, merged_names()}
  def merge_names(%Actor{} = actor, absorbed_id, survivor_id) do
    Audit.transaction(actor, "taxa.merge_names", fn ->
      held =
        from(n in TaxonName,
          where: n.taxon_id == ^survivor_id,
          select: {n.normalized_name, n.sensu}
        )
        |> Repo.all()
        |> MapSet.new()

      {moving, dropping} =
        from(n in TaxonName, where: n.taxon_id == ^absorbed_id, order_by: [n.status, n.id])
        |> Repo.all()
        |> Enum.split_with(&(not MapSet.member?(held, {&1.normalized_name, &1.sensu})))

      held_common =
        from(c in CommonName,
          where: c.taxon_id == ^survivor_id,
          select: fragment("lower(?)", c.name)
        )
        |> Repo.all()
        |> MapSet.new()

      {common, common_dropped} =
        from(c in CommonName, where: c.taxon_id == ^absorbed_id, order_by: c.id)
        |> Repo.all()
        |> Enum.split_with(&(not MapSet.member?(held_common, String.downcase(&1.name))))

      Enum.each(dropping, &Repo.delete!/1)
      Enum.each(common_dropped, &Repo.delete!/1)

      Enum.each(moving, fn name ->
        name
        |> Ecto.Changeset.change(taxon_id: survivor_id, status: :synonym)
        |> Repo.update!()
      end)

      Enum.each(common, &(&1 |> Ecto.Changeset.change(taxon_id: survivor_id) |> Repo.update!()))

      for schema <- [LegacyId, TaxonNote] do
        from(r in schema, where: r.taxon_id == ^absorbed_id)
        |> Repo.update_all(set: [taxon_id: survivor_id])
      end

      %{synonyms: Enum.map(moving, & &1.name), common_names: Enum.map(common, & &1.name)}
    end)
  end

  @doc """
  Records that taxon `from_id` (merged away) is now `to_id`, and re-points
  the redirects that pointed at `from_id`.
  """
  @spec add_redirect(Actor.t(), integer(), integer()) :: {:ok, TaxonRedirect.t()}
  def add_redirect(%Actor{} = actor, from_id, to_id)
      when is_integer(from_id) and is_integer(to_id) do
    Audit.transaction(actor, "taxa.add_redirect", fn ->
      from(r in TaxonRedirect, where: r.taxon_id == ^from_id)
      |> Repo.update_all(set: [taxon_id: to_id])

      Repo.insert!(%TaxonRedirect{from_taxon_id: from_id, taxon_id: to_id},
        on_conflict: {:replace, [:taxon_id]},
        conflict_target: :from_taxon_id
      )
    end)
  end

  @doc "The taxon a merged-away taxon ID now is, or nil."
  @spec redirect(integer()) :: integer() | nil
  def redirect(id) when is_integer(id),
    do: Repo.one(from(r in TaxonRedirect, where: r.from_taxon_id == ^id, select: r.taxon_id))

  @doc """
  The taxa merged into `taxon_id` (lumps: the redirects pointing at it,
  merges into a taxon since merged into it included), by when: each
  `%{taxon_id, name, at}`, its `name` the accepted name it had, read from
  the audit trail (its accepted name's row moved onto the survivor, or
  deleted as one the survivor held already), nil when the trail holds none.
  """
  @spec merged_into(integer()) :: [
          %{taxon_id: integer(), name: String.t() | nil, at: DateTime.t()}
        ]
  def merged_into(taxon_id) when is_integer(taxon_id) do
    redirects =
      Repo.all(
        from(r in TaxonRedirect,
          where: r.taxon_id == ^taxon_id,
          order_by: [r.inserted_at, r.from_taxon_id]
        )
      )

    names = redirects |> Enum.map(& &1.from_taxon_id) |> merged_names()

    for r <- redirects,
        do: %{taxon_id: r.from_taxon_id, name: names[r.from_taxon_id], at: r.inserted_at}
  end

  # The last accepted name each merged-away taxon had, from the audit trail
  # (`Gallformers.Audit.Migration`: updates keep the values they replaced).
  defp merged_names([]), do: %{}

  defp merged_names(taxon_ids) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT DISTINCT ON (named.taxon_id) named.taxon_id, named.name
        FROM (
          SELECT c.id,
                 (coalesce(c.changed_from->>'taxon_id', c.data->>'taxon_id'))::bigint AS taxon_id,
                 c.data->>'name' AS name
          FROM carbonite_default.changes c
          WHERE c.table_prefix = 'public' AND c.table_name = 'taxon_names'
            AND ((c.op = 'update' AND c.changed_from ? 'taxon_id'
                  AND coalesce(c.changed_from->>'status', c.data->>'status') = 'accepted')
              OR (c.op = 'delete' AND c.data->>'status' = 'accepted'))
        ) named
        WHERE named.taxon_id = ANY($1)
        ORDER BY named.taxon_id, named.id DESC
        """,
        [taxon_ids]
      )

    Map.new(rows, fn [id, name] -> {id, name} end)
  end

  defp name(nil), do: "the root"

  defp name(taxon_id) do
    Repo.one(
      from(n in TaxonName,
        where: n.taxon_id == ^taxon_id and n.status == :accepted,
        select: n.name
      )
    ) || "taxon #{taxon_id}"
  end
end
