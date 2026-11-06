defmodule Gallformers.Curation.Review do
  @moduledoc """
  Review: each tray item's flags against current data (matter `ec2c`,
  `preview/1`), by the same rules as the import's Facts preview
  (`Gallformers.Import.Preview`):

    * a confirmation of a Fact Gallformers holds current is `{:held,
      sources}` (applying it changes nothing); of one it holds withdrawn,
      or one whose slot holds another value current, or another current
      Inducer of the Gall, `{:supersedes, statements}` — the Sources'
      statements it replaces, with their words and dates; else `:new`;
    * a denial of a Fact held current supersedes its confirmations; of one
      held withdrawn is held; else `:new`;
    * a correction is its denial and confirmation together: held when both
      are, superseding all either supersedes;
    * `:needs_reason` when it supersedes something and the evidence has
      neither text, an Observation nor a Source;
    * notes and editorial items are `:editorial`; a Gall's code and name
      parts `:needs_confirmation`;
    * `{:changed_since, user, at}` from the audit trail
      (`Gallformers.Curation.AuditTrail`);
    * `{:blocked, reason}`: a check that fails. An editorial item is
      applied in a transaction that is rolled back, so every check the
      apply makes (a code taken, a name the parts cannot derive) blocks it
      here; a Fact item whose Gall a statement cannot name, or whose key no
      longer names a Fact the Gall could have, is blocked too.

  Retracted Sources' attributions count for nothing.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Facts.RelationshipFact
  alias Gallformers.Curation.Applying
  alias Gallformers.Curation.AuditTrail
  alias Gallformers.Curation.Item
  alias Gallformers.Curation.Statements
  alias Gallformers.Curation.Wording
  alias Gallformers.Facts
  alias Gallformers.Facts.Fact
  alias Gallformers.Import.GallformersFragment
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa

  @typedoc "A Source's statement an item replaces."
  @type statement :: %{
          attribution_id: integer(),
          fact_id: integer(),
          source_id: integer(),
          source: String.t(),
          stance: :confirm | :deny,
          stated_on: Date.t() | nil,
          stated_precision: atom() | nil,
          words: String.t() | nil
        }

  @doc "The flags of a decorated draft `item`, with the set's `evidence` (decoded)."
  @spec flags(Actor.t(), Item.t(), map() | nil) :: [term()]
  def flags(actor, %Item{kind: :fact} = item, set_evidence) do
    evidence = Applying.evidence(item, set_evidence)

    case fact_parts(item.spec) do
      {:ok, parts} ->
        status = status(parts)

        [status] ++
          needs_reason(status, evidence) ++
          changed(actor, item, {:facts, existing_ids(parts)}) ++ unnamed(item, evidence)

      {:error, reason} ->
        [{:blocked, reason}]
    end
  end

  def flags(actor, %Item{kind: :note, spec: spec} = item, _set_evidence) do
    case Catalog.find_gall_fact(spec.gall_id, spec.key) do
      {:ok, fact_id} when is_integer(fact_id) ->
        [:editorial] ++ changed(actor, item, {:facts, [fact_id]})

      _ ->
        [:editorial, {:blocked, "Gallformers holds no such Fact to note"}]
    end
  end

  def flags(actor, %Item{kind: :editorial, spec: spec} = item, _set_evidence) do
    confirm = if spec.field in [:code, :name_parts], do: [:needs_confirmation], else: []

    target =
      case spec.subject do
        {:gall, id} -> {:gall_field, id, spec.field}
        {:plant, id} when spec.field == :range -> {:plant_range, Taxa.accepted_name(id)}
        {:plant, id} -> {:plant_names, id}
      end

    [:editorial] ++ confirm ++ changed(actor, item, target) ++ dry_run(actor, item)
  end

  # -- Facts ---------------------------------------------------------------------

  # Each statement's {stance, Fact}: the Fact its key names now (nil: none).
  defp fact_parts(%{gall_id: gall_id, action: action, key: key} = spec) do
    stances =
      case action do
        :add -> [{:confirm, key}]
        :withdraw -> [{:deny, key}]
        :correct -> [{:deny, key}, {:confirm, spec.to}]
      end

    Enum.reduce_while(stances, {:ok, []}, fn {stance, key}, {:ok, acc} ->
      case Catalog.find_gall_fact(gall_id, key) do
        {:ok, nil} -> {:cont, {:ok, acc ++ [{stance, key, nil}]}}
        {:ok, id} -> {:cont, {:ok, acc ++ [{stance, key, Facts.get_fact!(id)}]}}
        {:error, _} -> {:halt, {:error, "#{Wording.what(key)} is not a Fact this Gall can have"}}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, Enum.map(parts, &part_status(&1, gall_id))}
      error -> error
    end
  end

  defp existing_ids(parts), do: for({_status, %Fact{id: id}} <- parts, do: id)

  defp part_status({:confirm, key, fact}, gall_id) do
    own = fact && fact.id

    others =
      slot_current(Catalog.gall_fact_slot(gall_id, key), own) ++ other_inducers(key, gall_id, own)

    status =
      cond do
        fact && fact.standing == :withdrawn -> {:supersedes, statements([fact.id], :deny)}
        others != [] -> {:supersedes, statements(others, :confirm)}
        fact && fact.standing == :current -> {:held, statements([fact.id], :confirm)}
        true -> :new
      end

    {status, fact}
  end

  defp part_status({:deny, _key, nil}, _gall_id), do: {:new, nil}

  defp part_status({:deny, _key, %Fact{} = fact}, _gall_id) do
    case fact.standing do
      :current -> {{:supersedes, statements([fact.id], :confirm)}, fact}
      :withdrawn -> {{:held, statements([fact.id], :deny)}, fact}
      _ -> {:new, fact}
    end
  end

  # The current Facts in `slot` other than `own`.
  defp slot_current(nil, _own), do: []

  defp slot_current(slot, own) do
    Repo.all(
      from(f in Fact,
        where: f.slot == ^slot and f.standing == :current and f.id != ^(own || 0),
        select: f.id
      )
    )
  end

  # The Gall's other current Inducers, for a confirmation of an Inducer.
  defp other_inducers({:inducer, taxon_id}, gall_id, own) do
    Repo.all(
      from(r in RelationshipFact,
        join: f in Fact,
        on: f.id == r.fact_id,
        where:
          r.type == "inducer_of" and r.object_gall_id == ^gall_id and f.standing == :current and
            r.subject_taxon_id != ^taxon_id and f.id != ^(own || 0),
        select: f.id
      )
    )
  end

  defp other_inducers(_key, _gall_id, _own), do: []

  # One status for the item: superseding all its statements supersede,
  # held when every statement is, else new.
  defp status(parts) do
    statuses = Enum.map(parts, &elem(&1, 0))
    superseded = for {:supersedes, s} <- statuses, statement <- s, do: statement
    held = for {:held, s} <- statuses, statement <- s, do: statement

    cond do
      superseded != [] ->
        {:supersedes, Enum.uniq_by(superseded, & &1.attribution_id)}

      held != [] and Enum.all?(statuses, &match?({:held, _}, &1)) ->
        {:held,
         held |> Enum.uniq_by(& &1.source_id) |> Enum.map(&%{id: &1.source_id, name: &1.source})}

      true ->
        :new
    end
  end

  # The `stance` attributions of the Facts, newest first, as statements.
  defp statements(fact_ids, stance) do
    attributions =
      fact_ids |> Facts.list_attributions_for_facts() |> Map.values() |> List.flatten()

    retracted =
      attributions |> Enum.map(& &1.source_id) |> Enum.uniq() |> Sources.retracted_source_ids()

    sources =
      attributions
      |> Enum.map(& &1.source_id)
      |> Enum.uniq()
      |> Sources.list_sources_by_id()
      |> Map.new(&{&1.id, Wording.source_name(&1)})

    for a <- attributions, a.stance == stance, a.source_id not in retracted do
      %{
        attribution_id: a.id,
        fact_id: a.fact_id,
        source_id: a.source_id,
        source: sources[a.source_id],
        stance: a.stance,
        stated_on: a.stated_on,
        stated_precision: a.stated_precision,
        words: words(a)
      }
    end
    |> Enum.sort_by(&{&1.stated_on || ~D[0000-01-01], &1.attribution_id}, :desc)
  end

  defp words(a) do
    a.term || a.value_as_written || a.statement_text ||
      Enum.find_value(a.evidence, & &1.quote)
  end

  defp needs_reason({:supersedes, _statements}, evidence) do
    evidence = evidence || %{}

    reason? =
      is_binary(evidence[:text]) or (evidence[:observations] || []) != [] or
        is_integer(evidence[:source_id])

    if reason?, do: [], else: [:needs_reason]
  end

  defp needs_reason(_status, _evidence), do: []

  # A Gall a statement cannot name (neither Inducer nor Host).
  defp unnamed(%Item{spec: spec} = item, evidence) do
    summary = Catalog.gall_summary(spec.gall_id)
    facts = Statements.for_item(item.spec, evidence, Date.utc_today())

    case GallformersFragment.gall_batch(summary, facts) do
      {:ok, _batch} ->
        []

      {:error, :unidentified} ->
        [{:blocked, "the Gall has neither an Inducer nor a Host, so a statement cannot name it"}]
    end
  end

  # -- the rest ------------------------------------------------------------------

  defp changed(%Actor{id: user_id}, %Item{seen_at: since}, target) do
    case AuditTrail.changed_since(target, user_id, since) do
      nil -> []
      {user, at} -> [{:changed_since, user, at}]
    end
  end

  defp dry_run(actor, item) do
    case Applying.dry_run(actor, item) do
      :ok -> []
      {:error, reason} -> [{:blocked, reason}]
    end
  end
end
