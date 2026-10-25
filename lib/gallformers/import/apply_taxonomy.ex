defmodule Gallformers.Import.ApplyTaxonomy do
  @moduledoc """
  Applying a taxonomy batch under the phase 1 rule (`9449` §3, Jeff
  2026-10-24), inside the batch's one transaction:

    1. **New taxa.** Each taxon the Source presents as new (`taxa[].new`,
       resolved `:new`) is created in the editorial tree — under the parent
       its `placement` act names when that parent resolves (or is itself
       new), otherwise unplaced (flagged `"unplaced"` for a curator).
    2. **Every act is recorded** as a Fact (`Gallformers.Taxa.assert_*`)
       with the Source's attribution: quotes as evidence, `status_as_written`,
       the name act's `authorship_as_written`, and the taxa it names
       (`attribution_names`). A name the tree holds as a synonym while this
       Source treats it as valid is recorded against the tree's taxon.
       Attributions are diffed like a gall batch's (`Gallformers.Import.Diff`).
    3. **Disagreements are flagged, never applied.** An act that disagrees
       with the tree — a synonymy the tree does not hold, a placement under
       another parent, a name or rank other than the tree's, a common name
       it lacks, any split (assigning records to the daughters is curator
       work), or a denial of what the tree holds — becomes a
       `:taxonomy_disagreement` queue item for a curator to apply
       editorially or leave. The tree is otherwise unchanged.

  ## The context

  `run/1` takes a map: `:actor`, `:source`, `:batch` (with its decoded
  `content`), `:items` (the stored document's item IDs by ref), `:taxa` and
  `:galls` (the batch's resolved taxon and Gall statements by ref, decisions
  honoured), and `:drop` (statement refs a curator dropped, with why).
  """

  alias Gallformers.Facts
  alias Gallformers.Import.ApplyGall
  alias Gallformers.Import.Attributions
  alias Gallformers.Import.Diff
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer

  @doc "Applies the taxonomy batch in `ctx`."
  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(ctx) do
    content = ctx.batch.content
    declared = Map.new(List.wrap(content["taxa"]), &{&1["ref"], &1})
    acts = List.wrap(content["acts"])

    with {:ok, taxa, created, updates} <- taxa(ctx, declared, placements(acts)) do
      diff = %{
        actor: ctx.actor,
        source: ctx.source,
        existing: Facts.list_source_attributions(ctx.source.id, "taxon_"),
        find: &Taxa.find_act_fact/2,
        assert: &Taxa.assert_act/4
      }

      refs = %{taxa: taxa, declared: declared, created: created}

      with {:ok, outcomes, disagreements} <- write_all(ctx, diff, acts, refs),
           stated = for({_ref, %{fact_id: id}} <- outcomes, is_integer(id), do: id),
           {:ok, removal_conflicts} <- Diff.remove_unstated(diff, ctx.batch.mode, stated) do
        {:ok,
         %{
           statements: Enum.map(outcomes, &statement_row/1),
           updates: updates,
           queue: disagreements ++ ApplyGall.conflict_items(outcomes, removal_conflicts)
         }}
      end
    end
  end

  # The parent each taxon's (confirmed) placement act names, by ref.
  defp placements(acts) do
    for %{"kind" => "placement", "stance" => "confirm"} = a <- acts,
        reduce: %{},
        do: (acc -> Map.put_new(acc, a["taxon"], a["parent"]))
  end

  # -- taxa --------------------------------------------------------------------

  defp taxa(ctx, declared, placements) do
    known =
      for {ref, s} <- ctx.taxa, id = known_id(s), into: %{}, do: {ref, id}

    new_refs =
      for {ref, s} <- ctx.taxa,
          s.resolution == :new and is_nil(s.taxon_id) and "skipped" not in s.flags,
          do: ref

    new_refs
    |> Enum.sort_by(&ref_number/1)
    |> Enum.reduce_while({:ok, known, [], []}, fn ref, acc ->
      case create(ctx, ref, declared, placements, acc, []) do
        {:ok, _id, acc} -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ref_number(ref) do
    case Integer.parse(String.slice(ref, 1..-1//1)) do
      {n, ""} -> n
      _ -> 0
    end
  end

  defp known_id(%{resolution: resolution, taxon_id: id})
       when resolution in [:resolved, :new] and is_integer(id),
       do: id

  # A name held as a synonym while this Source treats it as valid: its acts
  # are recorded against the tree's taxon.
  defp known_id(%{resolution: :unresolved, flags: flags, candidate_ids: [id | _]}) do
    if "synonym_held_valid" in flags, do: id
  end

  defp known_id(_statement), do: nil

  # Creates a new taxon, its new parent first; `visiting` guards cycles.
  defp create(ctx, ref, declared, placements, {:ok, ids, _created, _updates} = acc, visiting) do
    cond do
      Map.has_key?(ids, ref) ->
        {:ok, ids[ref], acc}

      ref in visiting ->
        {:ok, nil, acc}

      true ->
        parent_ref = placements[ref]

        parent =
          cond do
            parent_ref == nil ->
              {:ok, nil, acc}

            Map.has_key?(ids, parent_ref) ->
              {:ok, ids[parent_ref], acc}

            new?(ctx, parent_ref) ->
              create(ctx, parent_ref, declared, placements, acc, [ref | visiting])

            true ->
              {:ok, nil, acc}
          end

        with {:ok, parent_id, {:ok, ids, created, updates}} <- parent,
             {:ok, taxon, flags} <- create_new_taxon(ctx.actor, declared[ref], parent_id) do
          s = ctx.taxa[ref]
          update = %{id: s.id, taxon_id: taxon.id, method: "created", flags: s.flags ++ flags}

          {:ok, taxon.id,
           {:ok, Map.put(ids, ref, taxon.id), [taxon.id | created], [update | updates]}}
        end
    end
  end

  defp new?(ctx, ref) do
    case ctx.taxa[ref] do
      %{resolution: :new, taxon_id: nil, flags: flags} -> "skipped" not in flags
      _ -> false
    end
  end

  @doc """
  Creates a taxon the Source presents as new (a declared `taxa[]` entry)
  under `parent_id`. Without a parent, or where the tree refuses the parent
  (a rank inversion), it is created unplaced and flagged `"unplaced"`.
  """
  @spec create_new_taxon(Gallformers.Audit.Actor.t(), map(), integer() | nil) ::
          {:ok, Taxa.Taxon.t(), [String.t()]} | {:error, term()}
  def create_new_taxon(actor, declared, parent_id) do
    attrs = %{
      rank: declared["rank"],
      origin: :curated,
      name: declared["name_reading"] || declared["name_as_written"],
      sensu: declared["sensu"],
      parent_id: parent_id
    }

    case {parent_id, Taxa.create_taxon(actor, attrs)} do
      {nil, {:ok, taxon}} ->
        {:ok, taxon, ["unplaced"]}

      {_parent, {:ok, taxon}} ->
        {:ok, taxon, []}

      {parent, {:error, %Ecto.Changeset{errors: errors}}} when parent != nil ->
        if Keyword.has_key?(errors, :parent_id) do
          with {:ok, taxon} <- Taxa.create_taxon(actor, %{attrs | parent_id: nil}) do
            {:ok, taxon, ["unplaced"]}
          end
        else
          {:error, {declared["ref"], errors}}
        end

      {_parent, {:error, reason}} ->
        {:error, {declared["ref"], reason}}
    end
  end

  # -- acts --------------------------------------------------------------------

  defp write_all(ctx, diff, acts, refs) do
    Enum.reduce_while(acts, {:ok, [], []}, fn act, {:ok, outcomes, disagreements} ->
      case write_act(ctx, diff, act, refs) do
        {:ok, outcome, key} ->
          disagreements = disagreements ++ disagreement_items(act, outcome, key, refs)
          {:cont, {:ok, outcomes ++ [{act["id"], outcome}], disagreements}}

        {:error, reason} ->
          {:halt, {:error, {act["id"], reason}}}
      end
    end)
  end

  # A recorded act that disagrees with the tree is one queue item.
  defp disagreement_items(_act, %{fact_id: nil}, _key, _refs), do: []

  defp disagreement_items(act, _outcome, key, refs) do
    case disagreement(act, key, refs) do
      reason when is_binary(reason) -> [disagreement_item(act, reason)]
      nil -> []
    end
  end

  defp write_act(ctx, diff, act, refs) do
    if Map.has_key?(ctx.drop, act["id"]) do
      {:ok, Diff.unresolved("dropped by a curator: #{ctx.drop[act["id"]]}"), nil}
    else
      case key_and_extra(act, refs) do
        {:ok, kind, key, extra} ->
          attribution = Attributions.build(act, ctx.source.kind, ctx.batch.id, ctx.items, extra)

          with {:ok, outcome} <-
                 Diff.write(diff, %{kind: kind, key: key, attribution: attribution}) do
            {:ok, outcome, key}
          end

        {:skip, reason} ->
          {:ok, Diff.unresolved(reason), nil}
      end
    end
  end

  defp key_and_extra(%{"kind" => "name"} = a, refs) do
    with {:ok, taxon_id} <- taxon(refs, a["taxon"]) do
      declared = refs.declared[a["taxon"]]

      {:ok, :name, %{taxon_id: taxon_id, name: declared_name(declared), rank: declared["rank"]},
       %{authorship_as_written: get_in(a, ["authorship", "as_written"])}
       |> Map.reject(fn {_k, v} -> is_nil(v) end)
       |> Map.put(:names, names(refs, [{a["taxon"], "taxon"}]))}
    end
  end

  defp key_and_extra(%{"kind" => "placement"} = a, refs) do
    with {:ok, taxon_id} <- taxon(refs, a["taxon"]),
         {:ok, parent_id} <- taxon(refs, a["parent"]) do
      {:ok, :placement, %{taxon_id: taxon_id, parent_id: parent_id},
       %{names: names(refs, [{a["taxon"], "taxon"}, {a["parent"], "parent"}])}}
    end
  end

  defp key_and_extra(%{"kind" => "synonymy"} = a, refs) do
    with {:ok, accepted_id} <- taxon(refs, a["accepted"]) do
      {:ok, :synonymy,
       %{name: declared_name(refs.declared[a["name"]]), accepted_taxon_id: accepted_id},
       %{names: names(refs, [{a["name"], "name"}, {a["accepted"], "accepted"}])}}
    end
  end

  defp key_and_extra(%{"kind" => "split"} = a, refs) do
    into = List.wrap(a["into"])

    with {:ok, taxon_id} <- taxon(refs, a["taxon"]),
         {:ok, into_ids} <- all_taxa(refs, into) do
      {:ok, :split, %{taxon_id: taxon_id, into_taxon_ids: into_ids},
       %{names: names(refs, [{a["taxon"], "taxon"} | Enum.map(into, &{&1, "into"})])}}
    end
  end

  defp key_and_extra(%{"kind" => "common_name"} = a, refs) do
    with {:ok, taxon_id} <- taxon(refs, a["taxon"]) do
      {:ok, :common_name, %{taxon_id: taxon_id, common_name: a["common_name"]},
       %{names: names(refs, [{a["taxon"], "taxon"}])}}
    end
  end

  defp key_and_extra(a, _refs), do: {:skip, "unknown act kind #{a["kind"]}"}

  defp all_taxa(refs, into) do
    Enum.reduce_while(into, {:ok, []}, fn ref, {:ok, ids} ->
      case taxon(refs, ref) do
        {:ok, id} -> {:cont, {:ok, ids ++ [id]}}
        skip -> {:halt, skip}
      end
    end)
  end

  defp taxon(refs, ref) do
    case Map.get(refs.taxa, ref) do
      id when is_integer(id) -> {:ok, id}
      _ -> {:skip, "taxon #{ref} is not resolved"}
    end
  end

  defp names(refs, roles) do
    Attributions.names(
      for {ref, role} <- roles, do: Attributions.name(refs.declared[ref], refs.taxa[ref], role)
    )
  end

  defp declared_name(nil), do: nil
  defp declared_name(declared), do: declared["name_reading"] || declared["name_as_written"]

  # -- disagreements -----------------------------------------------------------

  # Why the act disagrees with the editorial tree, or nil.
  defp disagreement(%{"kind" => "placement", "stance" => stance}, key, refs) do
    taxon = Taxa.get_taxon!(key.taxon_id)
    there? = taxon.parent_id == key.parent_id

    cond do
      stance == "confirm" and there? ->
        nil

      stance == "confirm" and key.taxon_id in refs.created ->
        nil

      stance == "confirm" ->
        "the tree places #{name(taxon)} #{where(taxon.parent_id)}"

      there? ->
        "the tree places #{name(taxon)} under #{name(key.parent_id)}, which the Source denies"

      true ->
        nil
    end
  end

  defp disagreement(%{"kind" => "name", "stance" => stance}, key, _refs) do
    taxon = Taxa.get_taxon!(key.taxon_id)
    same? = same_name?(Taxa.accepted_name(taxon), key.name) and to_string(taxon.rank) == key.rank

    cond do
      stance == "confirm" and same? -> nil
      stance == "confirm" -> "the tree names it #{name(taxon)} at rank #{taxon.rank}"
      same? -> "the tree holds #{name(taxon)}, which the Source denies"
      true -> nil
    end
  end

  defp disagreement(%{"kind" => "synonymy", "stance" => stance}, key, _refs) do
    accepted = Taxa.get_taxon!(key.accepted_taxon_id)

    held? =
      Enum.any?(accepted.names, &(&1.status == :synonym and same_name?(&1.name, key.name)))

    cond do
      stance == "confirm" and held? ->
        nil

      stance == "confirm" ->
        "the tree does not hold #{key.name} as a synonym of #{name(accepted)}" <>
          held_elsewhere(key.name, accepted.id)

      held? ->
        "the tree holds #{key.name} as a synonym of #{name(accepted)}, which the Source denies"

      true ->
        nil
    end
  end

  defp disagreement(%{"kind" => "split", "stance" => "confirm"}, key, _refs) do
    "a split of #{name(key.taxon_id)}: assigning existing records to the daughters is curator work"
  end

  defp disagreement(%{"kind" => "common_name", "stance" => stance}, key, _refs) do
    held? =
      key.taxon_id
      |> Taxa.list_common_names()
      |> Enum.any?(&(String.downcase(&1.name) == String.downcase(key.common_name)))

    cond do
      stance == "confirm" and not held? ->
        "the tree does not hold the common name #{key.common_name} for #{name(key.taxon_id)}"

      stance == "deny" and held? ->
        "the tree holds the common name #{key.common_name}, which the Source denies"

      true ->
        nil
    end
  end

  defp disagreement(_act, _key, _refs), do: nil

  defp held_elsewhere(name, accepted_id) do
    case Taxa.resolve_name(name) do
      {:ok, %{id: id} = other} when id != accepted_id ->
        status =
          if other.matched_name.status == :accepted, do: "the accepted name", else: "a synonym"

        "; it is #{status} of another taxon, #{name(other)}"

      {:ambiguous, _taxa} ->
        "; several taxa have this name"

      _ ->
        ""
    end
  end

  defp disagreement_item(act, reason) do
    %{
      kind: :taxonomy_disagreement,
      statement_ref: act["id"],
      subject:
        act
        |> Map.take([
          "kind",
          "stance",
          "taxon",
          "parent",
          "name",
          "accepted",
          "into",
          "common_name"
        ])
        |> Map.put("status_as_written", act["status_as_written"])
        |> Map.reject(fn {_k, v} -> is_nil(v) end),
      proposal: %{},
      reason: reason
    }
  end

  defp same_name?(a, b), do: NameNormalizer.normalize(a) == NameNormalizer.normalize(b)

  defp name(%Taxa.Taxon{} = taxon), do: Taxa.accepted_name(taxon)
  defp name(id) when is_integer(id), do: Taxa.accepted_name(id)

  defp where(nil), do: "at the root"
  defp where(parent_id), do: "under #{name(parent_id)}"

  defp statement_row({ref, outcome}) do
    %{
      kind: :act,
      ref: ref,
      resolution: outcome.resolution,
      method: nil,
      fact_id: outcome.fact_id,
      delta: outcome.delta,
      flags: outcome.flags,
      detail: outcome.detail
    }
  end
end
