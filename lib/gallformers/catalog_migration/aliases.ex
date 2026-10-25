defmodule Gallformers.CatalogMigration.Aliases do
  @moduledoc """
  Today's aliases (`alias` with `alias_species` and `taxonomy_alias`)
  sorted by meaning, not by field (`9449` Task 17; `b5bd` M2). Most
  "scientific" aliases are synonyms, but not all: a former undescribed-gall
  label or an informal code in taxon synonymy would feed import name
  resolution and cause silent wrong matches. So each alias gets a meaning:

    * `synonym` — a synonym of a taxon (`Gallformers.Taxa.add_synonym/4`):
      by default the owner's taxon (a Gall's species-level Inducer, a
      plant, a genus placeholder's genus, a higher taxon); `target` names
      another taxon by its accepted name.
    * `common_name` — on a Gall, a gall alias Fact (common names of Galls
      are the Catalog's); on a plant or higher taxon, a common name of the
      taxon (`Gallformers.Taxa.add_common_name/3`).
    * `former_label`, `code` — a Gall's former label or informal code: a
      gall alias Fact, **never** a taxon name. Only Galls have them.
    * `drop` — not migrated.

  Gall alias Facts are legacy Facts, attributed to the "Gallformers legacy
  data" Source (none has a Source today).

  ## Decisions

  `priv/catalog_migration/aliases.csv`: `owner, owner_id, alias_id, name,
  type, decision, target, note`, one row per alias and owner (`owner` is
  `gall`, `plant` or `taxonomy`; `name` is for reading). A row with `*` as
  both `owner_id` and `alias_id` applies to every alias of that owner kind
  and `type` without a row of its own.

  Without a row, what the design already decides applies (`decided_by`
  `mechanical` in the worksheet): common names of Galls become gall aliases
  (`b5bd` M2), common names of plants and higher taxa become taxon common
  names (`9449` §3), and `former_undescribed` aliases of Galls are former
  labels. Every other alias — every "scientific" one — needs a decision,
  and a decision that cannot apply (a former label on a plant, a synonym
  of a Gall with no species-level Inducer and no `target`) is pending too.
  """

  alias Gallformers.Audit.Actor
  alias Gallformers.CatalogMigration.Curated
  alias Gallformers.CatalogMigration.Old
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer

  @input "aliases.csv"
  @owners ~w(gall plant taxonomy)
  @meanings ~w(synonym common_name former_label code drop)

  @mechanical %{
    {"gall", "common"} => "common_name",
    {"gall", "former_undescribed"} => "former_label",
    {"plant", "common"} => "common_name",
    {"taxonomy", "common"} => "common_name"
  }

  @columns ~w(owner owner_id owner_name alias_id name type decision target note decided_by applied)

  @type decision :: %{decision: String.t(), target: String.t(), note: String.t()}
  @type key :: {String.t(), integer(), integer()} | {String.t(), :any, String.t()}

  @doc "Reads the decisions, by `{owner, owner_id, alias_id}` or `{owner, :any, type}`."
  @spec load(String.t()) :: {:ok, %{key() => decision()}} | {:error, String.t()}
  def load(path) do
    with {:ok, rows} <-
           Curated.read(path, ~w(owner owner_id alias_id decision), ~w(name type target note)),
         {:ok, parsed} <- Curated.parse_rows(path, rows, &parse/1) do
      with {:ok, indexed} <- Curated.index(path, parsed, &elem(&1, 0)) do
        {:ok, Map.new(indexed, fn {key, {_key, decision}} -> {key, decision} end)}
      end
    end
  end

  defp parse(row) do
    with :ok <- one_of(row["owner"], @owners, "owner"),
         {:ok, key} <- key(row),
         :ok <- one_of(row["decision"], @meanings, "decision") do
      {:ok, {key, %{decision: row["decision"], target: row["target"], note: row["note"]}}}
    end
  end

  defp key(%{"owner_id" => "*", "alias_id" => "*", "type" => ""}),
    do: {:error, "a row for every alias (owner_id and alias_id *) needs a type"}

  defp key(%{"owner_id" => "*", "alias_id" => "*"} = row),
    do: {:ok, {row["owner"], :any, row["type"]}}

  defp key(row) do
    with {:ok, owner_id} <- Curated.integer(row["owner_id"], "owner_id"),
         {:ok, alias_id} <- Curated.integer(row["alias_id"], "alias_id") do
      {:ok, {row["owner"], owner_id, alias_id}}
    end
  end

  defp one_of(value, allowed, column) do
    if value in allowed,
      do: :ok,
      else:
        {:error, "#{column} must be one of #{Enum.join(allowed, ", ")}, got #{inspect(value)}"}
  end

  @doc """
  Sorts the aliases of the migrated Galls and taxa, as `actor`: adds the
  synonyms and taxon common names, and returns the gall alias Facts to
  assert (attributed with `legacy`). `taxa` is the taxa step's crosswalk,
  `galls` the Galls as migrated.
  """
  @spec run(Actor.t(), %{key() => decision()}, map(), [map()], map(), Report.t()) ::
          {[tuple()], Report.t()}
  def run(actor, decisions, taxa, galls, legacy, report) do
    galls = Map.new(galls, &{&1.id, &1})
    {rows, unmigrated} = Enum.split_with(old_aliases(), &owner_migrated?(&1, galls, taxa))

    planned =
      for row <- rows do
        decision = decision(row, decisions)
        Map.merge(row, %{decision: decision, action: action(row, decision, galls, taxa)})
      end

    {planned, assertions} = apply_all(actor, planned, legacy)

    report =
      report
      |> Report.curation("aliases", @columns, Enum.map(planned, &worksheet_row/1))
      |> Report.pending(@input, pending(planned))
      |> Report.problems(
        "alias of a species row that is not migrated",
        for(row <- unmigrated, do: "#{label(row)} #{inspect(row.name)}")
      )
      |> counts(planned)

    {assertions, report}
  end

  @doc "Reconciles the planned gall alias Facts with those now held."
  @spec reconcile([tuple()], Report.t()) :: Report.t()
  def reconcile(assertions, report) do
    Report.reconcile(
      report,
      "Gall alias Facts (aliases.csv)",
      Enum.count(assertions, &match?({:alias, _key, _attribution}, &1)),
      Old.count("SELECT count(*) FROM alias_facts")
    )
  end

  defp old_aliases do
    Old.rows("""
    SELECT s.taxoncode AS owner, s.id AS owner_id, s.name AS owner_name,
           a.id AS alias_id, a.name, a.type
    FROM alias_species x JOIN alias a ON a.id = x.alias_id JOIN species s ON s.id = x.species_id
    UNION ALL
    SELECT 'taxonomy', t.id, t.name, a.id, a.name, a.type
    FROM taxonomy_alias x JOIN alias a ON a.id = x.alias_id JOIN taxonomy t ON t.id = x.taxonomy_id
    ORDER BY 1, 2, 4
    """)
  end

  defp owner_migrated?(%{owner: "gall", owner_id: id}, galls, _taxa), do: Map.has_key?(galls, id)
  defp owner_migrated?(%{owner: "plant", owner_id: id}, _galls, taxa), do: taxa.plants[id] != nil

  defp owner_migrated?(%{owner: "taxonomy", owner_id: id}, _galls, taxa),
    do: taxon_of_row(id, taxa) != nil

  defp owner_migrated?(_row, _galls, _taxa), do: false

  # The taxon made from a taxonomy row (not a placeholder or a skipped rank,
  # whose anchors are other rows' taxa).
  defp taxon_of_row(id, taxa) do
    with %{} = row <- taxa.rows[id],
         taxon_id when taxon_id != nil <- taxa.anchors[id],
         %{name: name} <- taxa.taxa[taxon_id],
         true <- name == String.trim(row.name) and not row.is_placeholder do
      taxon_id
    else
      _ -> nil
    end
  end

  defp decision(row, decisions) do
    case decisions[{row.owner, row.owner_id, row.alias_id}] ||
           decisions[{row.owner, :any, row.type}] do
      %{} = decision ->
        Map.put(decision, :decided_by, @input)

      nil ->
        case @mechanical[{row.owner, row.type}] do
          nil -> nil
          meaning -> %{decision: meaning, target: "", note: "", decided_by: "mechanical"}
        end
    end
  end

  # What a decision does to a row: {:synonym | :common_name, taxon_id},
  # {:alias_fact, gall_id}, :drop, {:pending, why}.
  defp action(_row, nil, _galls, _taxa), do: {:pending, "needs a decision"}
  defp action(_row, %{decision: "drop"}, _galls, _taxa), do: :drop

  defp action(row, %{decision: "synonym", target: target}, galls, taxa) do
    case synonym_taxon(row, target, galls, taxa) do
      {:ok, taxon_id} -> {:synonym, taxon_id}
      {:error, why} -> {:pending, why}
    end
  end

  defp action(%{owner: "gall", owner_id: id}, %{decision: meaning}, _galls, _taxa)
       when meaning in ~w(common_name former_label code),
       do: {:alias_fact, id}

  defp action(row, %{decision: "common_name"}, _galls, taxa),
    do: {:common_name, owner_taxon(row, taxa)}

  defp action(_row, %{decision: meaning}, _galls, _taxa),
    do: {:pending, "#{meaning} applies to Galls only"}

  defp synonym_taxon(_row, target, _galls, _taxa) when target != "" do
    case Taxa.resolve_name(target) do
      {:ok, %{matched_name: %{status: :accepted}} = taxon} -> {:ok, taxon.id}
      _ -> {:error, "target #{inspect(target)} is not the accepted name of one taxon"}
    end
  end

  defp synonym_taxon(%{owner: "gall", owner_id: id}, _target, galls, _taxa) do
    case galls[id] do
      %{level: :species, inducer_id: inducer} -> {:ok, inducer}
      _ -> {:error, "the Gall has no species-level Inducer: give a target taxon"}
    end
  end

  defp synonym_taxon(row, _target, _galls, taxa), do: {:ok, owner_taxon(row, taxa)}

  defp owner_taxon(%{owner: "plant", owner_id: id}, taxa), do: taxa.plants[id]
  defp owner_taxon(%{owner: "taxonomy", owner_id: id}, taxa), do: taxon_of_row(id, taxa)

  # -- applying ----------------------------------------------------------------------

  defp apply_all(actor, planned, legacy) do
    {planned, {_seen, assertions}} =
      Enum.map_reduce(planned, {MapSet.new(), []}, fn row, {seen, assertions} ->
        {applied, seen, assertions} = apply_row(actor, row, seen, assertions, legacy)
        {Map.put(row, :applied, applied), {seen, assertions}}
      end)

    {planned, Enum.reverse(assertions)}
  end

  defp apply_row(_actor, %{action: {:pending, why}}, seen, assertions, _legacy),
    do: {"pending: #{why}", seen, assertions}

  defp apply_row(_actor, %{action: :drop}, seen, assertions, _legacy),
    do: {"dropped", seen, assertions}

  defp apply_row(actor, %{action: {:synonym, taxon_id}, name: name}, seen, assertions, _legacy) do
    key = {:synonym, taxon_id, NameNormalizer.normalize(name)}

    cond do
      MapSet.member?(seen, key) ->
        {"synonym (already added)", seen, assertions}

      key in existing_names(taxon_id) ->
        {"already a name of #{Taxa.accepted_name(taxon_id)}", MapSet.put(seen, key), assertions}

      true ->
        {:ok, _name} = Taxa.add_synonym(actor, taxon_id, String.trim(name))
        {"synonym of #{Taxa.accepted_name(taxon_id)}", MapSet.put(seen, key), assertions}
    end
  end

  defp apply_row(
         actor,
         %{action: {:common_name, taxon_id}, name: name},
         seen,
         assertions,
         _legacy
       ) do
    key = {:common_name, taxon_id, String.downcase(String.trim(name))}

    if MapSet.member?(seen, key) or key in existing_common_names(taxon_id) do
      {"common name (already held)", MapSet.put(seen, key), assertions}
    else
      {:ok, _name} = Taxa.add_common_name(actor, taxon_id, String.trim(name))
      {"common name of #{Taxa.accepted_name(taxon_id)}", MapSet.put(seen, key), assertions}
    end
  end

  defp apply_row(_actor, %{action: {:alias_fact, gall_id}, name: name}, seen, assertions, legacy) do
    key = {:alias, gall_id, String.downcase(String.trim(name))}

    if MapSet.member?(seen, key) do
      {"gall alias (already added)", seen, assertions}
    else
      fact = {:alias, %{gall_id: gall_id, name: String.trim(name)}, legacy}
      {"gall alias", MapSet.put(seen, key), [fact | assertions]}
    end
  end

  defp existing_names(taxon_id) do
    for name <- Taxa.get_taxon!(taxon_id).names, do: {:synonym, taxon_id, name.normalized_name}
  end

  defp existing_common_names(taxon_id) do
    for name <- Taxa.list_common_names(taxon_id),
        do: {:common_name, taxon_id, String.downcase(name.name)}
  end

  # -- report ------------------------------------------------------------------------

  defp pending(planned) do
    for %{action: {:pending, why}} = row <- planned do
      meaning = if row.decision, do: " as #{row.decision.decision}", else: ""

      {{row.owner, row.owner_id, row.alias_id},
       "#{label(row)}: #{row.type} alias #{inspect(row.name)} (#{row.alias_id})#{meaning}: #{why}"}
    end
  end

  defp label(row), do: "#{row.owner} #{row.owner_id} #{row.owner_name}"

  defp worksheet_row(row) do
    decision = row.decision || %{}

    %{
      "owner" => row.owner,
      "owner_id" => row.owner_id,
      "owner_name" => row.owner_name,
      "alias_id" => row.alias_id,
      "name" => row.name,
      "type" => row.type,
      "decision" => decision[:decision],
      "target" => decision[:target],
      "note" => decision[:note],
      "decided_by" => decision[:decided_by],
      "applied" => row.applied
    }
  end

  defp counts(report, planned) do
    by_meaning =
      Enum.frequencies_by(planned, fn
        %{action: {:pending, _}} -> "pending"
        %{decision: %{decision: meaning}} -> meaning
      end)

    Enum.reduce(@meanings ++ ["pending"], report, fn meaning, acc ->
      Report.count(acc, "Aliases sorted as #{meaning}", Map.get(by_meaning, meaning, 0))
    end)
  end
end
