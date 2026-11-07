defmodule Gallformers.Taxa.Sync do
  @moduledoc """
  The tree follows the Facts (matter `f923` Task 5, "The tree is a copy
  kept in step with the Facts"). The tree tables (`taxa`, `taxon_names`,
  `taxon_common_names`) stay what every page, search, Gall name and the
  API read; this keeps them in step with the current taxonomic-act Facts
  (`Gallformers.Taxa.ActFacts`) of every taxon outside Plantae. Plant data
  is editorial (`8567`): plants' Facts never move them.

  ## Following the Facts

  A "Facts changed" listener (`Gallformers.Facts.Events`, registered in
  `config/config.exs`): when a taxonomic Fact's standing changes (a
  curator's acceptance or decline, a retraction, a Gallformers statement,
  the legacy statements at cutover), `facts_changed/1` reads the winner of
  each slot the change touches and rewrites the tree rows that differ,
  through the Taxa writers, in the same transaction, so the "taxon changed"
  listeners propose the Gall renames that follow:

    * **placement** — the taxon goes under the current placement's parent
      (`Gallformers.Taxa.place/3`, through the tree validator);
    * **name** — the current name Fact's name (`rename/3`: the old accepted
      name stays a synonym while a Fact backs it as one), rank
      (`set_rank/3`), authorship and sensu;
    * **synonyms** — the taxon holds the names current synonymies give it
      and the names of its outranked (superseded) name Facts; a synonym a
      synonymy states but no current Fact backs is removed. A current
      synonymy of a name that is another taxon's accepted name is a lump:
      that taxon is merged into this one (`merge/3`). A synonymy older
      than a dated statement of its name as another taxon's name (a
      revalidated name) is not current (`Gallformers.Facts`, "A
      revalidated name outranks an older synonymy of it"): the name leaves
      this taxon's synonyms and is no lump;
    * **common names** — as synonyms, from common-name Facts;
    * **splits** — a split coming into effect is a `:split` event
      (`split/4`, with the split Fact); its Galls' questions are
      `Gallformers.Import.SplitQuestions`'s.

  A slot with no current Fact leaves its rows as they are. A rewrite the
  tree refuses (a cycle, a rank inversion, a lump of a taxon with taxa
  under it) fails the whole transaction with
  `{:tree, taxon_id, validation, message}`: an acceptance that would break
  the tree is refused (`{:error, {:rejected, Gallformers.Taxa.Sync, reason}}`).

  ## The check

  `check/0` rebuilds the expected tree from the Facts and lists the rows
  that differ (`mix gallformers.taxa.check_sync`); a test asserts it is
  clean on the built test database.
  """
  @behaviour Gallformers.Facts.Events

  import Ecto.Query

  alias Ecto.Changeset
  alias Gallformers.Audit
  alias Gallformers.Facts.Fact
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.ActFacts.CommonNameFact
  alias Gallformers.Taxa.ActFacts.NameFact
  alias Gallformers.Taxa.ActFacts.PlacementFact
  alias Gallformers.Taxa.ActFacts.SplitFact
  alias Gallformers.Taxa.ActFacts.SynonymyFact
  alias Gallformers.Taxa.CommonName
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.TaxonName

  # A plant: its data is editorial, never following the Facts.
  defmacrop plant(t) do
    quote do: fragment("? IS NOT DISTINCT FROM 'Plantae'", unquote(t).kingdom)
  end

  @typedoc "Why the tree refused a rewrite."
  @type refusal :: {:tree, integer(), atom(), String.t()}

  @typedoc """
  A tree row that differs from what the Facts give: the taxon, its
  accepted name, the aspect (`:placement`, `:name`, `:rank`,
  `:authorship`, `:sensu`, `:synonym`, `:common_name`), what the Facts give
  (`:none` when no current Fact places or names it; nil for a synonym or
  common name no Fact backs) and what the tree holds (nil for one missing).
  """
  @type difference :: %{
          taxon_id: integer(),
          name: String.t() | nil,
          aspect: atom(),
          expected: term(),
          actual: term()
        }

  # -- following the Facts -----------------------------------------------------

  @impl true
  def facts_changed(fact_ids) when is_list(fact_ids) do
    # The sync's own writes (a lump moving statements) change standings
    # too; the outer sync settles the taxa it is rewriting.
    if Process.get(__MODULE__) do
      :ok
    else
      Process.put(__MODULE__, true)

      try do
        apply_changes(fact_ids)
      after
        Process.delete(__MODULE__)
      end
    end
  end

  @doc """
  Runs `fun` with the tree not following the Facts it changes, for a Taxa
  operation that moves statements between Facts while keeping each slot's
  winner as it is (a lump, `Gallformers.Taxa.Lump`).
  """
  @spec without_following((-> result)) :: result when result: var
  def without_following(fun) when is_function(fun, 0) do
    previous = Process.get(__MODULE__)
    Process.put(__MODULE__, true)

    try do
      fun.()
    after
      if previous, do: Process.put(__MODULE__, previous), else: Process.delete(__MODULE__)
    end
  end

  defp apply_changes(fact_ids) do
    case taxonomic(fact_ids) do
      [] ->
        :ok

      ids ->
        {:ok, actor} = Audit.current_actor()
        changed = changed_details(ids)

        placed = for %PlacementFact{taxon_id: t} <- changed, uniq: true, do: t
        named = for %NameFact{taxon_id: t} <- changed, uniq: true, do: t
        synonymous = for %SynonymyFact{accepted_taxon_id: t} <- changed, uniq: true, do: t
        commons = for %CommonNameFact{taxon_id: t} <- changed, uniq: true, do: t
        splits = for %SplitFact{} = s <- changed, current?(s.fact_id), do: s

        split_taxa = for %SplitFact{taxon_id: t} <- splits, uniq: true, do: t
        followed = followed_taxa(placed ++ named ++ synonymous ++ commons ++ split_taxa)
        follow = &Enum.filter(&1, fn id -> Map.has_key?(followed, id) end)
        expected = expected(Map.keys(followed))

        with :ok <- positions(actor, follow.(placed), follow.(named), followed, expected),
             :ok <- each(follow.(named), &name(actor, &1, expected)),
             :ok <-
               each(follow.(named ++ synonymous) |> Enum.uniq(), &synonyms(actor, &1, expected)),
             :ok <- each(follow.(commons), &common_names(actor, &1, expected)) do
          each(splits, &split(actor, &1, followed))
        end
    end
  end

  defp taxonomic(fact_ids) do
    Repo.all(
      from(f in Fact, where: f.id in ^fact_ids and like(f.kind, "taxon\\_%"), select: f.id)
    )
  end

  defp changed_details(ids) do
    Enum.flat_map(
      [PlacementFact, NameFact, SynonymyFact, CommonNameFact, SplitFact],
      &Repo.all(from(d in &1, where: d.fact_id in ^ids))
    )
  end

  defp current?(fact_id),
    do: Repo.exists?(from(f in Fact, where: f.id == ^fact_id and f.standing == :current))

  # The taxa among `ids` the tree follows the Facts for (not plants), by ID.
  defp followed_taxa(ids) do
    from(t in Taxon, where: t.id in ^Enum.uniq(ids) and not plant(t))
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp each(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # -- placement and rank --------------------------------------------------------

  # Each taxon whose placement or name changed goes where its Facts put it,
  # higher ranks first so a taxon's new parent is placed before it.
  defp positions(actor, placed, named, followed, expected) do
    targets =
      for id <- Enum.uniq(placed ++ named) do
        exp = Map.fetch!(expected, id)

        parent =
          case {id in placed, exp.parent} do
            {true, {:ok, parent_id}} -> {:ok, parent_id}
            _ -> :keep
          end

        rank =
          case {id in named, exp.name} do
            {true, %NameFact{rank: rank}} -> {:ok, rank}
            _ -> :keep
          end

        {Map.fetch!(followed, id), parent, rank}
      end

    targets
    |> Enum.sort_by(fn {taxon, _parent, rank} -> rank_index(rank, taxon.rank) end)
    |> each(fn {taxon, parent, rank} -> position(actor, taxon.id, parent, rank) end)
  end

  defp rank_index({:ok, rank}, _current), do: Enum.find_index(Rank.all(), &(&1 == rank))
  defp rank_index(:keep, current), do: Enum.find_index(Rank.all(), &(&1 == current))

  defp position(actor, id, parent, rank) do
    taxon = Repo.get!(Taxon, id)
    move? = match?({:ok, p} when p != taxon.parent_id, parent)
    rerank? = match?({:ok, r} when r != taxon.rank, rank)

    cond do
      not move? and not rerank? ->
        :ok

      not rerank? ->
        place(actor, id, elem(parent, 1))

      not move? ->
        set_rank(actor, id, elem(rank, 1))

      # A rank the current parent allows first, else the move first.
      Taxa.check_rank(id, elem(rank, 1)) == :ok ->
        with :ok <- set_rank(actor, id, elem(rank, 1)), do: place(actor, id, elem(parent, 1))

      true ->
        with :ok <- place(actor, id, elem(parent, 1)), do: set_rank(actor, id, elem(rank, 1))
    end
  end

  # Checked before writing: a refused nested write would roll the whole
  # transaction back before the reason could be returned.
  defp place(actor, id, parent_id) do
    with :ok <- refusal(id, Taxa.check_place(id, parent_id)),
         {:ok, _} <- Taxa.place(actor, id, parent_id),
         do: :ok
  end

  defp set_rank(actor, id, rank) do
    with :ok <- refusal(id, Taxa.check_rank(id, rank)),
         {:ok, _} <- Taxa.set_rank(actor, id, rank),
         do: :ok
  end

  defp refusal(_id, :ok), do: :ok

  defp refusal(id, {:error, %Changeset{errors: errors}}) do
    {field, {message, opts}} =
      Enum.find(errors, hd(errors), fn {field, _} -> field in [:parent_id, :rank] end)

    {:error,
     {:tree, id, Keyword.get(opts, :validation, field), "#{Taxa.accepted_name(id)}: #{message}"}}
  end

  # -- names -----------------------------------------------------------------------

  defp name(actor, id, expected) do
    case Map.fetch!(expected, id).name do
      %NameFact{} = winner ->
        accepted = accepted_row(id)

        with :ok <- rename(actor, id, accepted, winner, Map.fetch!(expected, id)),
             :ok <- detail(actor, id, :authorship, winner.authorship),
             do: detail(actor, id, :sensu, winner.sensu)

      :none ->
        :ok
    end
  end

  defp rename(_actor, _id, %TaxonName{name: name}, %NameFact{name: name}, _exp), do: :ok

  defp rename(actor, id, old, %NameFact{name: new}, exp) do
    with {:ok, _} <- Taxa.rename(actor, id, new) do
      # The old accepted name stays a synonym only while a Fact backs it.
      old_key = NameNormalizer.normalize(old.name)

      if old_key != NameNormalizer.normalize(new) and not Map.has_key?(exp.synonyms, old_key) do
        remove_synonyms(actor, id, old_key)
      else
        :ok
      end
    end
  end

  defp detail(actor, id, field, value) do
    accepted = accepted_row(id)

    if Map.fetch!(accepted, field) == value do
      :ok
    else
      setter = if field == :authorship, do: &Taxa.set_authorship/3, else: &Taxa.set_sensu/3

      case setter.(actor, id, value) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp accepted_row(id),
    do: Repo.one!(from(n in TaxonName, where: n.taxon_id == ^id and n.status == :accepted))

  # -- synonyms ----------------------------------------------------------------------

  defp synonyms(actor, id, expected) do
    case Repo.get(Taxon, id) do
      # Merged into another by a lump earlier in this sync.
      nil -> :ok
      _taxon -> reconcile_synonyms(actor, id, Map.fetch!(expected, id))
    end
  end

  defp reconcile_synonyms(actor, id, exp) do
    accepted_key = NameNormalizer.normalize(accepted_row(id).name)
    held = held_synonyms(id)

    missing =
      for {key, name} <- exp.synonyms,
          key != accepted_key,
          not Map.has_key?(held, key),
          do: {key, name}

    extra =
      for {key, _rows} <- held,
          MapSet.member?(exp.stated_synonyms, key),
          not Map.has_key?(exp.synonyms, key),
          do: key

    with :ok <- each(missing, &add_synonym(actor, id, &1, exp)),
         do: each(extra, &remove_synonyms(actor, id, &1))
  end

  defp held_synonyms(id) do
    from(n in TaxonName, where: n.taxon_id == ^id and n.status == :synonym)
    |> Repo.all()
    |> Enum.group_by(& &1.normalized_name)
  end

  # A current synonymy of another taxon's accepted name is a lump. A lump
  # earlier in the loop may have brought the name already.
  defp add_synonym(actor, id, {key, name}, exp) do
    if Map.has_key?(held_synonyms(id), key),
      do: :ok,
      else: add_new_synonym(actor, id, {key, name}, exp)
  end

  defp add_new_synonym(actor, id, {key, name}, exp) do
    lumped =
      if MapSet.member?(exp.synonymy_keys, key),
        do:
          Repo.all(
            from(n in TaxonName,
              join: t in Taxon,
              on: t.id == n.taxon_id,
              where:
                n.normalized_name == ^key and n.status == :accepted and t.id != ^id and
                  not plant(t),
              select: t.id
            )
          ),
        else: []

    case lumped do
      [] ->
        ok(Taxa.add_synonym(actor, id, name))

      [absorbed] ->
        lump(actor, absorbed, id)

      several ->
        {:error,
         {:tree, id, :ambiguous_lump,
          "#{name} is the accepted name of #{length(several)} taxa: which is merged is not clear"}}
    end
  end

  defp lump(actor, absorbed, survivor) do
    if Repo.exists?(from(t in Taxon, where: t.parent_id == ^absorbed)) do
      {:error,
       {:tree, absorbed, :has_children,
        "#{Taxa.accepted_name(absorbed)} has taxa under it: it can be merged into " <>
          "#{Taxa.accepted_name(survivor)} once their placements move them"}}
    else
      ok(Taxa.merge(actor, absorbed, survivor))
    end
  end

  defp remove_synonyms(actor, id, key) do
    id
    |> held_synonyms()
    |> Map.get(key, [])
    |> each(&ok(Taxa.remove_synonym(actor, &1)))
  end

  # -- common names ------------------------------------------------------------------

  defp common_names(actor, id, expected) do
    exp = Map.fetch!(expected, id)
    held = held_common_names(id)

    missing = for {key, name} <- exp.common_names, not Map.has_key?(held, key), do: name

    extra =
      for {key, row} <- held,
          MapSet.member?(exp.stated_common_names, key),
          not Map.has_key?(exp.common_names, key),
          do: row

    with :ok <- each(missing, &ok(Taxa.add_common_name(actor, id, &1))),
         do: each(extra, &ok(Taxa.remove_common_name(actor, &1)))
  end

  defp held_common_names(id) do
    from(c in CommonName, where: c.taxon_id == ^id)
    |> Repo.all()
    |> Map.new(&{String.downcase(&1.name), &1})
  end

  # -- splits --------------------------------------------------------------------------

  defp split(actor, %SplitFact{taxon_id: id, into_taxon_ids: into, fact_id: fact_id}, followed) do
    if Map.has_key?(followed, id),
      do: ok(Taxa.split(actor, id, into, fact_id: fact_id)),
      else: :ok
  end

  defp ok({:ok, _}), do: :ok
  defp ok({:error, reason}), do: {:error, reason}

  # -- what the Facts give -------------------------------------------------------------

  # For each of `ids`: its current placement's parent (`{:ok, parent_id}`,
  # or `:none`), its current name Fact (or `:none`), the synonyms and
  # common names the Facts give it (normalized key => name), and the
  # synonyms and common names any Fact states for it.
  defp expected(ids) do
    placements = current_by_taxon(PlacementFact, :taxon_id, ids)
    names = current_by_taxon(NameFact, :taxon_id, ids)
    superseded = details(NameFact, :taxon_id, ids, [:superseded])
    synonymies = details(SynonymyFact, :accepted_taxon_id, ids, :any)
    commons = details(CommonNameFact, :taxon_id, ids, :any)

    Map.new(ids, fn id ->
      current_synonymies = for {s, :current} <- Map.get(synonymies, id, []), do: s

      synonyms =
        Map.merge(
          Map.new(Map.get(superseded, id, []), fn {n, _} -> {n.normalized_name, n.name} end),
          Map.new(current_synonymies, &{&1.normalized_name, &1.name})
        )

      {id,
       %{
         parent:
           case placements[id] do
             %PlacementFact{parent_id: parent_id} -> {:ok, parent_id}
             nil -> :none
           end,
         name: names[id] || :none,
         synonyms: synonyms,
         synonymy_keys: MapSet.new(current_synonymies, & &1.normalized_name),
         stated_synonyms:
           MapSet.new(Map.get(synonymies, id, []), fn {s, _} -> s.normalized_name end),
         common_names:
           for({c, :current} <- Map.get(commons, id, []), into: %{}, do: {key(c), c.common_name}),
         stated_common_names: MapSet.new(Map.get(commons, id, []), fn {c, _} -> key(c) end)
       }}
    end)
  end

  defp key(%CommonNameFact{common_name: name}), do: String.downcase(name)

  # Each taxon's current Fact of `schema` (the newest, should a tie leave two).
  defp current_by_taxon(schema, field, ids) do
    schema
    |> details(field, ids, [:current])
    |> Map.new(fn {id, rows} ->
      {id, rows |> Enum.max_by(fn {d, _} -> d.fact_id end) |> elem(0)}
    end)
  end

  defp details(schema, field, ids, standings) do
    from(d in schema,
      join: f in Fact,
      on: f.id == d.fact_id,
      where: field(d, ^field) in ^ids,
      select: {d, f.standing}
    )
    |> then(fn q ->
      if standings == :any, do: q, else: where(q, [_d, f], f.standing in ^standings)
    end)
    |> Repo.all()
    |> Enum.group_by(fn {d, _} -> Map.fetch!(d, field) end)
  end

  # -- the check -------------------------------------------------------------------------

  @doc """
  Rebuilds the expected tree from the current taxonomic Facts and lists
  the rows that differ (`t:difference/0`), by taxon: every taxon outside
  Plantae is compared on its parent, accepted name, rank, authorship,
  sensu, synonyms and common names. Empty when the tree follows the Facts.
  Reads only.
  """
  @spec check() :: [difference()]
  def check do
    taxa =
      from(t in Taxon, where: not plant(t), order_by: t.id, preload: [:names, :common_names])
      |> Repo.all()

    expected = expected(Enum.map(taxa, & &1.id))
    Enum.flat_map(taxa, &differences(&1, Map.fetch!(expected, &1.id)))
  end

  @doc "`check/0`'s differences as lines to print."
  @spec format([difference()]) :: [String.t()]
  def format([]), do: ["The tree follows the Facts: no differences."]

  def format(differences) do
    n = length(differences)

    head =
      if n == 1,
        do: "1 tree row differs from the Facts:",
        else: "#{n} tree rows differ from the Facts:"

    [head | Enum.map(differences, &line/1)]
  end

  defp line(%{taxon_id: id, name: name, aspect: aspect} = d) do
    aspect_label = aspect |> Atom.to_string() |> String.replace("_", " ")
    "  #{id} #{name} — #{aspect_label}: #{says(d.expected, d.actual)}"
  end

  defp says(:none, actual), do: "no current Fact, the tree has #{show(actual)}"
  defp says(nil, actual), do: "no Fact backs #{show(actual)}"
  defp says(expected, nil), do: "the Facts give #{show(expected)}, the tree lacks it"

  defp says(expected, actual),
    do: "the Facts give #{show(expected)}, the tree has #{show(actual)}"

  defp show(nil), do: "nothing"
  defp show(value) when is_binary(value), do: inspect(value)
  defp show(value), do: to_string(value)

  defp differences(taxon, exp) do
    accepted = Enum.find(taxon.names, &(&1.status == :accepted)) || %TaxonName{}

    diff = fn aspect, e, a ->
      %{taxon_id: taxon.id, name: accepted.name, aspect: aspect, expected: e, actual: a}
    end

    expected_synonyms = Map.delete(exp.synonyms, accepted.normalized_name)

    held_synonyms =
      for n <- taxon.names, n.status == :synonym, into: %{}, do: {n.normalized_name, n.name}

    held_common = Map.new(taxon.common_names, &{String.downcase(&1.name), &1.name})

    placement_differences(exp.parent, taxon, diff) ++
      name_differences(exp.name, taxon, accepted, diff) ++
      set_differences(:synonym, expected_synonyms, held_synonyms, diff) ++
      set_differences(:common_name, exp.common_names, held_common, diff)
  end

  defp placement_differences({:ok, parent_id}, %Taxon{parent_id: parent_id}, _diff), do: []

  defp placement_differences({:ok, parent_id}, taxon, diff),
    do: [diff.(:placement, parent_id, taxon.parent_id)]

  defp placement_differences(:none, taxon, diff), do: [diff.(:placement, :none, taxon.parent_id)]

  defp name_differences(:none, _taxon, accepted, diff), do: [diff.(:name, :none, accepted.name)]

  defp name_differences(%NameFact{} = n, taxon, accepted, diff) do
    for {aspect, e, a} <- [
          {:name, n.name, accepted.name},
          {:rank, n.rank, taxon.rank},
          {:authorship, n.authorship, accepted.authorship},
          {:sensu, n.sensu, accepted.sensu}
        ],
        e != a,
        do: diff.(aspect, e, a)
  end

  defp set_differences(aspect, expected, held, diff) do
    missing =
      for {k, v} <- Enum.sort(expected), not Map.has_key?(held, k), do: diff.(aspect, v, nil)

    extra =
      for {k, v} <- Enum.sort(held), not Map.has_key?(expected, k), do: diff.(aspect, nil, v)

    missing ++ extra
  end
end
