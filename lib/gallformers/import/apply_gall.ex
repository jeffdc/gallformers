defmodule Gallformers.Import.ApplyGall do
  @moduledoc """
  Applying a gall batch (`9449` §5, Task 13), inside the batch's one
  transaction:

    1. Taxa and Galls come from the batch's resolved statements, decisions
       already honoured (`Gallformers.Import.Queue`). A taxon the Source
       presents as new that no taxonomy batch created is created, unplaced.
       A Gall resolved `:new` (or decided new) is created: its name is its
       species-level Inducer's accepted name with the generation's name
       qualifier ("Andricus novus (agamic)"), or the Source's
       `name_as_written` for an undescribed Gall, made unique with " (2)",
       " (3)", ... — a provisional derived name until name derivation
       (`8567` rule 9) is built.
    2. Each Fact is written through `Gallformers.Import.Diff` with
       `Gallformers.Catalog`: Relationships and the other kinds first, then
       qualifiers (they point at a Relationship Fact of the batch). A Fact
       whose taxon or Gall did not resolve, or that a curator dropped (a
       disputed statement decided `skip`), is not written.
    3. `mode: replace` removes the Source's gall attributions the batch no
       longer states.
    4. Same-date conflicts the standings report, and the batch's Galls whose
       generation is outside their Inducer's groups (`:other_group`; while
       no group is mapped to any taxon nothing is flagged), become queue
       items.
  """

  alias Gallformers.Catalog
  alias Gallformers.Catalog.RelationshipTypes
  alias Gallformers.Facts
  alias Gallformers.Import.ApplyTaxonomy
  alias Gallformers.Import.Attributions
  alias Gallformers.Import.Diff
  alias Gallformers.Places
  alias Gallformers.Taxa

  @species_level [:species, :subspecies, :variety, :form]

  @doc """
  Applies the gall batch in `ctx` (see `Gallformers.Import.ApplyTaxonomy`
  for its fields). Returns the rows to record: Fact statements, updates to
  taxon and Gall statements, and queue items.
  """
  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(ctx) do
    content = ctx.batch.content
    declared = Map.new(List.wrap(content["taxa"]), &{&1["ref"], &1})

    with {:ok, taxa, taxon_updates} <- taxa(ctx, declared),
         {:ok, galls, gall_updates} <- galls(ctx, taxa) do
      diff = diff_context(ctx)
      facts = List.wrap(content["facts"])
      {qualifiers, others} = Enum.split_with(facts, &(&1["kind"] == "qualifier"))
      refs = %{taxa: taxa, galls: galls, declared: declared, facts: %{}}

      with {:ok, outcomes, refs} <- write_all(ctx, diff, others, refs),
           {:ok, q_outcomes, _refs} <- write_all(ctx, diff, qualifiers, refs),
           outcomes = outcomes ++ q_outcomes,
           stated = for({_ref, %{fact_id: id}} <- outcomes, is_integer(id), do: id),
           {:ok, removal_conflicts} <- Diff.remove_unstated(diff, ctx.batch.mode, stated) do
        {:ok,
         %{
           statements: Enum.map(outcomes, &statement_row/1),
           updates: taxon_updates ++ gall_updates,
           queue:
             conflict_items(outcomes, removal_conflicts) ++ generation_items(galls, ctx.galls)
         }}
      end
    end
  end

  defp diff_context(ctx) do
    %{
      actor: ctx.actor,
      source: ctx.source,
      existing: Facts.list_source_attributions(ctx.source.id, "gall_"),
      find: &Catalog.find_fact/2,
      assert: &Catalog.assert_fact/4
    }
  end

  # -- taxa and Galls ----------------------------------------------------------

  # The batch's taxa by ref: resolved ones, and new ones created now.
  defp taxa(ctx, declared) do
    collect(ctx.taxa, fn ref, s ->
      cond do
        is_integer(s.taxon_id) and s.resolution in [:resolved, :new] -> {:found, s.taxon_id}
        s.resolution == :new and "skipped" not in s.flags -> create_taxon(ctx, s, declared[ref])
        true -> :none
      end
    end)
  end

  defp create_taxon(ctx, s, declared) do
    with {:ok, taxon, flags} <- ApplyTaxonomy.create_new_taxon(ctx.actor, declared, nil) do
      {:created, taxon.id,
       %{id: s.id, taxon_id: taxon.id, method: "created", flags: s.flags ++ flags}}
    end
  end

  # The batch's Galls by ref: resolved ones, and new ones created now.
  defp galls(ctx, taxa) do
    content_galls = Map.new(List.wrap(ctx.batch.content["galls"]), &{&1["ref"], &1})

    collect(ctx.galls, fn ref, s ->
      cond do
        s.resolution == :resolved and is_integer(s.gall_id) ->
          {:found, s.gall_id}

        s.resolution == :new and "skipped" not in s.flags ->
          with {:ok, gall} <- create_gall(ctx, content_galls[ref], taxa) do
            {:created, gall.id, %{id: s.id, gall_id: gall.id, method: "created"}}
          end

        true ->
          :none
      end
    end)
  end

  # Runs `fun` on each statement in ref order: {ids by ref, statement updates}.
  defp collect(statements, fun) do
    statements
    |> Enum.sort_by(fn {ref, _s} -> ref_number(ref) end)
    |> Enum.reduce_while({:ok, %{}, []}, fn {ref, s}, {:ok, ids, updates} ->
      case fun.(ref, s) do
        {:found, id} -> {:cont, {:ok, Map.put(ids, ref, id), updates}}
        {:created, id, update} -> {:cont, {:ok, Map.put(ids, ref, id), [update | updates]}}
        :none -> {:cont, {:ok, ids, updates}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp create_gall(ctx, g, taxa) do
    ident = g["identified_by"] || %{}
    generation = get_in(ident, ["generation", "value"])
    generation_value = generation && Catalog.get_generation_value(generation)

    base =
      case taxa[ident["inducer"]] && Taxa.get_taxon!(taxa[ident["inducer"]]) do
        %{rank: rank} = taxon when rank in @species_level -> Taxa.accepted_name(taxon)
        _ -> String.trim(g["name_as_written"])
      end

    name =
      if generation_value && generation_value.name_qualifier,
        do: "#{base} (#{generation_value.name_qualifier})",
        else: base

    Catalog.create_gall(ctx.actor, %{
      name: unique_name(name),
      generation_value_id: generation_value && generation_value.id
    })
  end

  defp unique_name(name), do: unique_name(name, 1)

  defp unique_name(name, n) do
    candidate = if n == 1, do: name, else: "#{name} (#{n})"
    if Catalog.gall_name_taken?(candidate), do: unique_name(name, n + 1), else: candidate
  end

  # -- Facts -------------------------------------------------------------------

  defp write_all(ctx, diff, facts, refs) do
    Enum.reduce_while(facts, {:ok, [], refs}, fn fact, {:ok, outcomes, refs} ->
      case write_fact(ctx, diff, fact, refs) do
        {:ok, outcome} ->
          refs = put_in(refs, [:facts, fact["id"]], outcome.fact_id)
          {:cont, {:ok, outcomes ++ [{fact["id"], outcome}], refs}}

        {:error, reason} ->
          {:halt, {:error, {fact["id"], reason}}}
      end
    end)
  end

  defp write_fact(ctx, diff, fact, refs) do
    if Map.has_key?(ctx.drop, fact["id"]) do
      {:ok, Diff.unresolved("dropped by a curator: #{ctx.drop[fact["id"]]}")}
    else
      case key_and_extra(fact, refs) do
        {:ok, kind, key, extra} ->
          attribution =
            Attributions.build(fact, ctx.source.kind, ctx.batch.id, ctx.items, extra)

          Diff.write(diff, %{kind: kind, key: key, attribution: attribution})

        {:skip, reason} ->
          {:ok, Diff.unresolved(reason)}
      end
    end
  end

  defp key_and_extra(%{"kind" => "relationship"} = f, refs) do
    case RelationshipTypes.get(f["type"]) do
      %{endpoints: endpoints} -> relationship(endpoints, f, refs)
      nil -> {:skip, "unknown Relationship type #{f["type"]}"}
    end
  end

  defp key_and_extra(%{"kind" => "qualifier"} = f, refs) do
    with {:ok, of_fact_id} <- fetch(refs.facts, f["of"], "its Relationship #{f["of"]}") do
      {:ok, :qualifier,
       %{of_fact_id: of_fact_id, qualifier: f["qualifier"], value: f["value"]["value"]},
       %{value_as_written: f["value"]["as_written"]}}
    end
  end

  defp key_and_extra(%{"kind" => "trait"} = f, refs) do
    with {:ok, gall_id} <- gall(refs, f["gall"]) do
      {:ok, :trait, %{gall_id: gall_id, trait: f["trait"], value: f["value"]["value"]},
       %{value_as_written: f["value"]["as_written"]}}
    end
  end

  defp key_and_extra(%{"kind" => "range"} = f, refs) do
    with {:ok, gall_id} <- gall(refs, f["gall"]),
         {:ok, place_id} <- place(f["place"]["value"]) do
      {:ok, :range, %{gall_id: gall_id, adjustment: f["adjustment"], place_id: place_id},
       %{value_as_written: f["place"]["as_written"]}}
    end
  end

  defp key_and_extra(%{"kind" => "occurrence"} = f, refs) do
    with {:ok, gall_id} <- gall(refs, f["gall"]),
         {:ok, place_id} <- place(f["place"]["value"]) do
      {:ok, :occurrence, %{gall_id: gall_id, place_id: place_id},
       %{
         value_as_written: f["place"]["as_written"],
         when_as_written: f["when_as_written"],
         stage_as_written: f["stage_as_written"]
       }}
    end
  end

  defp key_and_extra(%{"kind" => "alias"} = f, refs) do
    with {:ok, gall_id} <- gall(refs, f["gall"]) do
      {:ok, :alias, %{gall_id: gall_id, name: f["name"]}, %{}}
    end
  end

  defp key_and_extra(%{"kind" => "description"} = f, refs) do
    with {:ok, gall_id} <- gall(refs, f["gall"]) do
      {:ok, :description, %{gall_id: gall_id}, %{}}
    end
  end

  defp key_and_extra(f, _refs), do: {:skip, "unknown Fact kind #{f["kind"]}"}

  defp relationship(:taxon_to_gall, f, refs) do
    with {:ok, subject} <- taxon(refs, f["subject"]),
         {:ok, object} <- gall(refs, f["object"]) do
      {:ok, :relationship, %{type: f["type"], subject_taxon_id: subject, object_gall_id: object},
       %{
         names:
           Attributions.names([
             Attributions.name(refs.declared[f["subject"]], subject, "subject")
           ])
       }}
    end
  end

  defp relationship(:gall_to_gall, f, refs) do
    with {:ok, subject} <- gall(refs, f["subject"]),
         {:ok, object} <- gall(refs, f["object"]) do
      {:ok, :relationship, %{type: f["type"], subject_gall_id: subject, object_gall_id: object},
       %{}}
    end
  end

  defp relationship(:taxon_to_taxon_in_gall, f, refs) do
    with {:ok, subject} <- taxon(refs, f["subject"]),
         {:ok, object} <- taxon(refs, f["object"]),
         {:ok, context} <- gall(refs, f["gall_context"]) do
      {:ok, :relationship,
       %{
         type: f["type"],
         subject_taxon_id: subject,
         object_taxon_id: object,
         gall_context_id: context
       },
       %{
         names:
           Attributions.names([
             Attributions.name(refs.declared[f["subject"]], subject, "subject"),
             Attributions.name(refs.declared[f["object"]], object, "object")
           ])
       }}
    end
  end

  defp taxon(refs, ref), do: fetch(refs.taxa, ref, "taxon #{ref}")
  defp gall(refs, ref), do: fetch(refs.galls, ref, "Gall #{ref}")

  defp fetch(map, ref, what) do
    case Map.get(map, ref) do
      id when is_integer(id) -> {:ok, id}
      _ -> {:skip, "#{what} is not resolved"}
    end
  end

  defp place(code) do
    case Places.get_place_by_code(code) do
      %{id: id} -> {:ok, id}
      nil -> {:skip, "no place has code #{code}"}
    end
  end

  # -- recording ---------------------------------------------------------------

  defp statement_row({ref, outcome}) do
    %{
      kind: :fact,
      ref: ref,
      resolution: outcome.resolution,
      method: nil,
      fact_id: outcome.fact_id,
      delta: outcome.delta,
      flags: outcome.flags,
      detail: outcome.detail
    }
  end

  @doc false
  @spec conflict_items([{String.t(), map()}], list()) :: [map()]
  def conflict_items(outcomes, extra_conflicts) do
    by_fact = Map.new(outcomes, fn {ref, o} -> {o.fact_id, ref} end)

    from_statements =
      for {ref, %{conflicts: conflicts}} <- outcomes, c <- conflicts, do: {ref, c}

    from_removals =
      for c <- extra_conflicts,
          ref = Enum.find_value(c.fact_ids, &by_fact[&1]) || "removed",
          do: {ref, c}

    (from_statements ++ from_removals)
    |> Enum.uniq_by(fn {ref, _c} -> ref end)
    |> Enum.map(fn {ref, c} ->
      %{
        kind: :same_date_conflict,
        statement_ref: ref,
        subject: %{
          "type" => Atom.to_string(c.type),
          "fact_id" => hd(c.fact_ids),
          "fact_ids" => c.fact_ids
        },
        proposal: %{},
        reason:
          "Sources with the same date disagree; the Fact keeps its standing until decided " <>
            "(a dated Gallformers statement settles it)"
      }
    end)
  end

  defp generation_items(galls, statements) do
    by_gall = Map.new(galls, fn {ref, id} -> {id, ref} end)

    for %{reason: :other_group} = flag <- Catalog.generation_group_flags(Map.values(galls)),
        ref = by_gall[flag.gall_id],
        Map.has_key?(statements, ref) do
      %{
        kind: :generation_outside_group,
        statement_ref: ref,
        subject: %{
          "gall_id" => flag.gall_id,
          "inducer_id" => flag.inducer_id,
          "generation" => flag.generation
        },
        proposal: %{},
        reason: "the generation is outside the groups that apply to its Inducer"
      }
    end
  end

  defp ref_number(ref) do
    case Integer.parse(String.slice(ref, 1..-1//1)) do
      {n, ""} -> n
      _ -> 0
    end
  end
end
