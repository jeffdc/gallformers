defmodule Gallformers.Import.TaxonomyStatements do
  @moduledoc """
  The taxonomy admin's changes to non-plant taxa, credited to the Source
  they follow (matter `f923` Task 8, "The taxonomy admin no longer edits
  non-plant taxa directly"). The tree follows the taxonomic Facts
  (`Gallformers.Taxa.Sync`), so a change is not an edit of the tree: it is
  recorded as a Source's taxonomic statement (`Gallformers.Taxa.assert_act/4`),
  dated by the Source, and accepted at once by the curator making it
  (`Gallformers.Facts.accept/3`, through
  `Gallformers.Import.TaxonomicDecisions`), so the tree follows it where it
  wins. When the backscan later imports the same paper, its statement of
  the act is the same Fact and attribution: no question.

  ## The basis

    * `{:source, source_id}` — a Source Gallformers holds. It needs a date
      (the statement competes by it); a retracted Source or one of
      Gallformers' own can't be the basis.
    * `{:citation, attrs}` — a new Source made on the spot from a citation
      (title, authors, date, optional DOI:
      `Gallformers.Import.SourceEdits.record_create/2`, audited, logged).
    * `{:gallformers, reason}` — no Source: Gallformers' own position, the
      rare exception (an undescribed Gall's Inducer; a position no paper
      supports). A Gallformers statement with the reason as its text,
      dated today; it counts without acceptance. The reason is required.

  ## The changes

    * `{:place, taxon, parent}` — a placement (parent nil: at the root);
    * `{:name, taxon, attrs}` — the accepted name, with `:name`, `:rank`
      and `:authorship` (each defaults to the tree's; the sensu is kept):
      a rename, a rank or an authorship;
    * `{:add_synonym, taxon, name}`, `{:remove_synonym, synonym}` — a
      synonymy confirmed or denied;
    * `{:add_common_name, taxon, name}`, `{:remove_common_name, common}` —
      a common name confirmed or denied;
    * `{:create_taxon, attrs, child_ids}` — a new taxon (`:name`, `:rank`,
      `:parent_id`, `:kingdom`; made in the tree through
      `Gallformers.Import.record_taxonomy_edit/2`), with its placement and
      name as the Source's statements, and each of `child_ids` placed
      under it;
    * `{:move_all, taxon_ids, parent}` — several placements.

  A plant is refused (`{:error, :plant}`): plant data is editorial
  (`Gallformers.Import.record_taxonomy_edit/2`).

  ## When the tree won't follow

  After the statements are accepted, each Fact must be in effect (a
  confirmation current, a denial withdrawn). If an accepted newer paper
  already decides it, nothing changes and the reason says so:
  `{:error, {:outranked, "Weld 2019 already places Basa under
  Otherbasisidae: this 2008 Source won't change the tree. Nothing was
  changed."}}`. A synonym that is the taxon's earlier accepted name stays
  one (`{:error, {:still_held, message}}`). A change the tree refuses (a
  cycle) is `{:error, {:rejected, Gallformers.Taxa.Sync, reason}}`.

  ## The replay log

  A statement is a `:taxonomic_statement` entry, keyed by the Source (its
  title), the act's kind and natural key (taxa as stable references, taken
  before the change: `Gallformers.Import.TaxonomicDecisions.encode_key/2`),
  payload its `"stance"` and, for a Gallformers statement, `"stated"` and
  `"statement_text"` (a name's `"authorship_as_written"` too). Its
  acceptance is the `:taxonomic_decision` entry after it; a new citation
  the `:source_edit` `"create"` entry before it. Replay records the
  statement again (`replay/3`); a statement already held is unchanged.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Facts.Fact
  alias Gallformers.Import
  alias Gallformers.Import.ReplayLog
  alias Gallformers.Import.SourceEdits
  alias Gallformers.Import.StableRef
  alias Gallformers.Import.TaxonomicDecisions
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Sources.PartialDate
  alias Gallformers.Sources.Source
  alias Gallformers.Taxa
  alias Gallformers.Taxa.CommonName
  alias Gallformers.Taxa.TaxonName

  @typedoc "What a change is credited to."
  @type basis :: {:source, integer()} | {:citation, map()} | {:gallformers, String.t()}

  @typedoc "A change to a non-plant taxon."
  @type change ::
          {:place, Taxa.taxon_ref(), Taxa.taxon_ref() | nil}
          | {:name, Taxa.taxon_ref(), map()}
          | {:add_synonym, Taxa.taxon_ref(), String.t()}
          | {:remove_synonym, TaxonName.t() | integer()}
          | {:add_common_name, Taxa.taxon_ref(), String.t()}
          | {:remove_common_name, CommonName.t() | integer()}
          | {:create_taxon, map(), [integer()]}
          | {:move_all, [integer()], Taxa.taxon_ref()}

  # An act to state: its kind, natural key, stance and attribution extras.
  @typep act :: {Taxa.act_kind(), map(), :confirm | :deny, map()}

  @doc """
  Makes `change` as `basis`'s statements, accepted, in one transaction
  audited as `actor` (see the module doc). Returns the taxon changed (or
  created; for `:move_all`, how many moved).
  """
  @spec record(Actor.t(), basis(), change()) :: {:ok, term()} | {:error, term()}
  def record(%Actor{} = actor, basis, change) do
    Audit.transaction(actor, "import.record_taxonomy_change", fn ->
      with :ok <- follows_facts(change),
           {:ok, source, attribution} <- basis(actor, basis),
           removed = removed_synonym(change),
           {:ok, subject, acts} <- prepare(actor, change),
           {:ok, stated} <- state_all(actor, source, attribution, acts),
           :ok <- in_effect(stated, source),
           :ok <- still_held(removed) do
        result(change, subject)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # -- plants ------------------------------------------------------------------

  defp follows_facts(change) do
    if Enum.all?(subject_kingdoms(change), &Taxa.follows_facts?/1),
      do: :ok,
      else: {:error, :plant}
  end

  defp subject_kingdoms({:create_taxon, attrs, child_ids}) do
    kingdom =
      case attrs[:parent_id] do
        nil -> attrs[:kingdom]
        parent_id -> attrs[:kingdom] || Taxa.get_taxon!(parent_id).kingdom
      end

    [kingdom | Enum.map(child_ids, &kingdom/1)]
  end

  defp subject_kingdoms({:move_all, ids, _parent}), do: Enum.map(ids, &kingdom/1)

  defp subject_kingdoms({op, row}) when op in [:remove_synonym, :remove_common_name] do
    case fetch_row(op, row) do
      nil -> []
      found -> [kingdom(found.taxon_id)]
    end
  end

  defp subject_kingdoms(change), do: [kingdom(elem(change, 1))]

  defp kingdom(taxon), do: Taxa.get_taxon!(taxon_id(taxon)).kingdom

  # -- the basis ---------------------------------------------------------------

  defp basis(_actor, {:source, source_id}) when is_integer(source_id) do
    case Sources.get_source(source_id) do
      nil ->
        {:error, :not_found}

      %Source{} = source ->
        cond do
          source.id in Sources.own_source_ids() -> {:error, :own_source}
          source.retracted_by_id != nil -> {:error, :retracted_source}
          is_nil(source.authored_date) -> {:error, :undated_source}
          true -> {:ok, source, %{source_id: source.id}}
        end
    end
  end

  defp basis(actor, {:citation, attrs}) when is_map(attrs) do
    with {:ok, source} <- SourceEdits.record_create(actor, attrs),
         do: {:ok, source, %{source_id: source.id}}
  end

  defp basis(_actor, {:gallformers, reason}) when is_binary(reason) do
    case {String.trim(reason), Sources.get_gallformers_source()} do
      {"", _source} ->
        {:error, :reason_required}

      {_reason, nil} ->
        {:error, :no_gallformers_source}

      {reason, source} ->
        {:ok, source,
         %{
           source_id: source.id,
           stated: Date.to_iso8601(Date.utc_today()),
           statement_text: reason
         }}
    end
  end

  # -- the acts ----------------------------------------------------------------

  @spec prepare(Actor.t(), change()) :: {:ok, term(), [act()]} | {:error, term()}
  defp prepare(_actor, {:place, taxon, parent}) do
    id = taxon_id(taxon)
    {:ok, id, [placement(id, parent && taxon_id(parent))]}
  end

  defp prepare(_actor, {:name, taxon, attrs}) do
    id = taxon_id(taxon)
    current = accepted_row(id)

    authorship =
      if Map.has_key?(attrs, :authorship),
        do: blank_to_nil(attrs.authorship),
        else: current.authorship

    key = %{
      taxon_id: id,
      name: blank_to_nil(attrs[:name]) || current.name,
      rank: attrs[:rank] || Taxa.get_taxon!(id).rank,
      sensu: current.sensu,
      authorship: authorship
    }

    extra = if authorship, do: %{authorship_as_written: authorship}, else: %{}
    {:ok, id, [{:name, key, :confirm, extra}]}
  end

  defp prepare(_actor, {:add_synonym, taxon, name}) do
    id = taxon_id(taxon)
    {:ok, id, [{:synonymy, %{name: String.trim(name), accepted_taxon_id: id}, :confirm, %{}}]}
  end

  defp prepare(_actor, {:remove_synonym, row}) do
    case fetch_row(:remove_synonym, row) do
      %TaxonName{status: :synonym} = synonym ->
        key = %{name: synonym.name, accepted_taxon_id: synonym.taxon_id}
        {:ok, synonym.taxon_id, [{:synonymy, key, :deny, %{}}]}

      %TaxonName{} ->
        {:error, :accepted_name}

      nil ->
        {:error, :not_found}
    end
  end

  defp prepare(_actor, {:add_common_name, taxon, name}) do
    id = taxon_id(taxon)
    {:ok, id, [{:common_name, %{taxon_id: id, common_name: String.trim(name)}, :confirm, %{}}]}
  end

  defp prepare(_actor, {:remove_common_name, row}) do
    case fetch_row(:remove_common_name, row) do
      %CommonName{} = common ->
        key = %{taxon_id: common.taxon_id, common_name: common.name}
        {:ok, common.taxon_id, [{:common_name, key, :deny, %{}}]}

      nil ->
        {:error, :not_found}
    end
  end

  defp prepare(actor, {:create_taxon, attrs, child_ids}) do
    attrs = attrs |> Map.take([:name, :rank, :parent_id, :kingdom]) |> Map.put(:origin, :curated)

    with {:ok, taxon} <- Import.record_taxonomy_edit(actor, {:create_taxon, attrs}) do
      name = %{taxon_id: taxon.id, name: Taxa.accepted_name(taxon), rank: taxon.rank}

      {:ok, taxon.id,
       [placement(taxon.id, taxon.parent_id), {:name, name, :confirm, %{}}] ++
         Enum.map(child_ids, &placement(&1, taxon.id))}
    end
  end

  defp prepare(_actor, {:move_all, ids, parent}) do
    parent_id = taxon_id(parent)
    {:ok, length(ids), Enum.map(ids, &placement(&1, parent_id))}
  end

  defp placement(taxon_id, parent_id),
    do: {:placement, %{taxon_id: taxon_id, parent_id: parent_id}, :confirm, %{}}

  # Each act stated, then accepted where it needs it: `{act, fact_id}`s.
  defp state_all(actor, source, attribution, acts) do
    Enum.reduce_while(acts, {:ok, []}, fn {kind, key, stance, extra} = act, {:ok, stated} ->
      attrs = attribution |> Map.merge(extra) |> Map.put(:stance, stance)

      with {:ok, %{fact: fact, attribution: a}} <- state(actor, source.id, kind, key, attrs),
           :ok <- accept(actor, fact, a) do
        {:cont, {:ok, stated ++ [{act, fact.id}]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp accept(actor, %Fact{kind: kind}, %Attribution{id: id, source_id: source_id}) do
    if Facts.needs_acceptance?(kind, source_id) do
      with {:ok, _} <- TaxonomicDecisions.decide(actor, :accept, id), do: :ok
    else
      :ok
    end
  end

  @doc """
  Records Source `source_id`'s statement of an act of `kind` with natural
  key `key` (`Gallformers.Taxa.assert_act/4`; `attrs` the attribution's,
  without `:source_id`) and logs it for replay, in one transaction audited
  as `actor`. Not accepted: `record/3` accepts it after.
  """
  @spec state(Actor.t(), integer(), Taxa.act_kind(), map(), map()) ::
          {:ok, Gallformers.Taxa.ActFacts.result()} | {:error, term()}
  def state(%Actor{} = actor, source_id, kind, key, attrs) do
    Audit.transaction(actor, "import.record_taxonomic_statement", fn ->
      entry_key = %{
        "source" => StableRef.source(source_id),
        "kind" => Atom.to_string(kind),
        "fact" => TaxonomicDecisions.encode_key(kind, key)
      }

      payload =
        for {field, value} <-
              Map.take(attrs, [:stance, :stated, :statement_text, :authorship_as_written]),
            value != nil,
            into: %{},
            do: {Atom.to_string(field), to_string(value)}

      case Taxa.assert_act(kind, actor, key, Map.put(attrs, :source_id, source_id)) do
        {:ok, result} ->
          ReplayLog.append!(:taxonomic_statement, entry_key, payload)
          result

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Replays a logged statement: the Source found by its title, the act's
  taxa by their stable references, recorded again (`state/5`). A statement
  the Source already makes is left as it is.
  """
  @spec replay(Actor.t(), map(), map()) :: :ok | {:error, term()}
  def replay(%Actor{} = actor, %{"source" => source, "kind" => kind, "fact" => fact}, payload) do
    with {:ok, kind} <- TaxonomicDecisions.kind(kind) |> or_error({:unknown_kind, kind}),
         {:ok, source_id} <- StableRef.resolve_source(source),
         {:ok, key} <- TaxonomicDecisions.decode_key(kind, fact) do
      attrs =
        %{stance: String.to_existing_atom(payload["stance"])}
        |> put_present(:stated, payload["stated"])
        |> put_present(:statement_text, payload["statement_text"])
        |> put_present(:authorship_as_written, payload["authorship_as_written"])

      case state(actor, source_id, kind, key, attrs) do
        {:ok, _result} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp or_error({:ok, value}, _error), do: {:ok, value}
  defp or_error(:error, error), do: {:error, error}

  defp put_present(map, _field, nil), do: map
  defp put_present(map, field, value), do: Map.put(map, field, value)

  # -- in effect ---------------------------------------------------------------

  # Each stated Fact must now be in effect: a confirmation current, a
  # denial withdrawn. Otherwise something newer decides it.
  defp in_effect(stated, source) do
    Enum.reduce_while(stated, :ok, fn {{kind, _key, stance, _extra}, fact_id}, :ok ->
      fact = Facts.get_fact!(fact_id)

      if fact.standing == wanted(stance),
        do: {:cont, :ok},
        else: {:halt, {:error, {:outranked, explain(kind, fact, stance, source)}}}
    end)
  end

  defp wanted(:confirm), do: :current
  defp wanted(:deny), do: :withdrawn

  # A synonym that is the taxon's earlier accepted name (a superseded name
  # Fact) is kept by the tree whatever a synonymy says.
  defp removed_synonym({:remove_synonym, row}), do: fetch_row(:remove_synonym, row)
  defp removed_synonym(_change), do: nil

  defp still_held(%TaxonName{} = synonym) do
    if Repo.exists?(
         from(n in TaxonName,
           where:
             n.taxon_id == ^synonym.taxon_id and n.status == :synonym and
               n.normalized_name == ^synonym.normalized_name
         )
       ) do
      {:error,
       {:still_held,
        "#{synonym.name} stays a synonym: it was this taxon's accepted name in a Source's " <>
          "statement, and an earlier accepted name is kept as a synonym. Nothing was changed."}}
    else
      :ok
    end
  end

  defp still_held(nil), do: :ok

  defp result({:move_all, _ids, _parent}, count), do: count
  defp result(_change, taxon_id), do: Taxa.get_taxon!(taxon_id)

  # -- why the tree won't follow -------------------------------------------------

  defp explain(kind, fact, stance, source) do
    ours = Facts.get_attribution(fact.id, source.id)
    subject = subject_name(kind, fact.id)

    case decider(fact, stance) do
      {attribution, decider_fact} ->
        decider_source = Sources.get_source!(attribution.source_id)
        what = states(kind, decider_fact.id, attribution.stance, subject)

        if newer?(attribution, ours) do
          "#{who(decider_source, attribution)} already #{what}: " <>
            "this #{when_stated(ours)} Source won't change the tree. Nothing was changed."
        else
          "#{who(decider_source, attribution)}, of the same date, #{what}: " <>
            "this Source won't change the tree until a curator settles which is followed. " <>
            "Nothing was changed."
        end

      nil ->
        "This Source's statement doesn't decide the tree. Nothing was changed."
    end
  end

  # The counting statement that decides against ours: in a slot, the
  # newest confirmation of another of its Facts; otherwise the newest of
  # the Fact's own statements taking the other stance.
  defp decider(%Fact{slot: slot} = fact, :confirm) when is_binary(slot) do
    others =
      Repo.all(from(f in Fact, where: f.slot == ^slot and f.id != ^fact.id))

    others
    |> Enum.flat_map(fn other ->
      for a <- counting(other), a.stance == :confirm, do: {a, other}
    end)
    |> newest()
  end

  defp decider(fact, stance) do
    other = if stance == :confirm, do: :deny, else: :confirm
    fact |> counting() |> Enum.filter(&(&1.stance == other)) |> Enum.map(&{&1, fact}) |> newest()
  end

  defp counting(%Fact{id: id, kind: kind}) do
    attributions = Facts.list_attributions(id)
    retracted = attributions |> Enum.map(& &1.source_id) |> Sources.retracted_source_ids()
    own = Sources.own_source_ids()

    Enum.filter(attributions, &(&1.source_id not in retracted and Facts.counts?(kind, &1, own)))
  end

  defp newest([]), do: nil

  defp newest(pairs),
    do: Enum.max_by(pairs, fn {a, _fact} -> a.stated_on || ~D[0000-01-01] end, Date)

  # Newer as the standing rules have it: compared at the coarser precision
  # of the two, so "2008" ties with "2008-05".
  defp newer?(%Attribution{stated_on: %Date{}}, %Attribution{stated_on: nil}), do: true

  defp newer?(
         %Attribution{stated_on: %Date{} = t} = theirs,
         %Attribution{stated_on: %Date{} = o} = ours
       ) do
    precisions = [theirs.stated_precision, ours.stated_precision]

    at = fn date ->
      cond do
        :year in precisions -> {date.year}
        :month in precisions -> {date.year, date.month}
        true -> {date.year, date.month, date.day}
      end
    end

    at.(t) > at.(o)
  end

  defp newer?(_theirs, _ours), do: false

  defp who(%Source{kind: :gallformers}, attribution),
    do: "Gallformers' own position of #{when_stated(attribution)}"

  defp who(source, _attribution), do: Sources.short_name(source) || source.title

  defp when_stated(%Attribution{stated_on: %Date{} = date, stated_precision: precision}),
    do: PartialDate.format(date, precision || :day)

  defp when_stated(_attribution), do: "undated"

  defp subject_name(kind, fact_id) do
    case Taxa.act_fact(fact_id) do
      {^kind, %{taxon_id: id}} -> Taxa.accepted_name(id)
      {^kind, %{accepted_taxon_id: id}} -> Taxa.accepted_name(id)
      _ -> "it"
    end
  end

  defp states(_kind, fact_id, stance, subject) do
    case {Taxa.act_fact(fact_id), stance} do
      {{:placement, %{parent_id: nil}}, _} ->
        "places #{subject} at the root"

      {{:placement, %{parent_id: parent_id}}, _} ->
        "places #{subject} under #{Taxa.accepted_name(parent_id)}"

      {{:name, %{name: name, rank: rank}}, _} ->
        "names it #{name} (#{rank})"

      {{:synonymy, %{name: name}}, :confirm} ->
        "treats #{name} as a synonym of #{subject}"

      {{:synonymy, %{name: name}}, :deny} ->
        "doesn't treat #{name} as a synonym of #{subject}"

      {{:common_name, %{common_name: name}}, :confirm} ->
        "gives #{subject} the common name #{name}"

      {{:common_name, %{common_name: name}}, :deny} ->
        "doesn't give #{subject} the common name #{name}"

      _ ->
        "states otherwise"
    end
  end

  # -- helpers -----------------------------------------------------------------

  defp fetch_row(:remove_synonym, %TaxonName{id: id}), do: Repo.get(TaxonName, id)
  defp fetch_row(:remove_synonym, id) when is_integer(id), do: Repo.get(TaxonName, id)
  defp fetch_row(:remove_common_name, %CommonName{id: id}), do: Repo.get(CommonName, id)
  defp fetch_row(:remove_common_name, id) when is_integer(id), do: Repo.get(CommonName, id)

  defp accepted_row(taxon_id),
    do: Repo.one!(from(n in TaxonName, where: n.taxon_id == ^taxon_id and n.status == :accepted))

  defp taxon_id(%Taxa.Taxon{id: id}), do: id
  defp taxon_id(%{id: id}) when is_integer(id), do: id
  defp taxon_id(id) when is_integer(id), do: id

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      text -> text
    end
  end
end
