defmodule Gallformers.Import.ApplyGall do
  @moduledoc """
  Applying a gall batch (`9449` §5, Task 13), inside the batch's one
  transaction:

    1. Taxa and Galls come from the batch's resolved statements, decisions
       already honoured (`Gallformers.Import.Queue`). A taxon the Source
       presents as new that no taxonomy batch created is created, unplaced.
       A Gall resolved `:new` (or decided new) is created with its name
       parts and the name they derive (`Gallformers.Catalog.GallName`,
       `86e7` §5): its generation, and
         * a described Gall (Inducer at species rank or below): a Host
           qualifier when the batch identifies it by its Host (a plant) —
           "Andricus novus (sexgen) (on Quercus lobata)". A name already
           shown, ignoring case, gets an override numbered " (2)", " (3)", ….
         * an undescribed Gall: a descriptor in today's convention, its
           Host's genus initial and epithet then the Source's wording,
           slugged (lowercase ASCII, hyphenated, at most 60 characters) —
           "Andricus q-lobata-a-small-spindle-shaped-gall-on-the-leaf-midrib"
           (just the wording without a Host). The descriptor seeds the
           Gallformers code; a name or code already taken numbers it "-2",
           "-3", …. Parts that derive no name (an Inducer outside a family)
           leave the Source's wording as the name and its override.
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
  alias Gallformers.Catalog.GallName
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

  # A new Gall: its name parts from the batch and the name they derive.
  defp create_gall(ctx, g, taxa) do
    ident = g["identified_by"] || %{}
    generation = get_in(ident, ["generation", "value"])
    generation_value = generation && Catalog.get_generation_value(generation)
    inducer = get_taxon(taxa, ident["inducer"])
    host = get_taxon(taxa, ident["host"])

    parts = %{
      inducer_taxon_id: inducer && inducer.id,
      generation_value_id: generation_value && generation_value.id
    }

    attrs =
      case inducer do
        %{rank: rank} when rank in @species_level ->
          described(Map.put(parts, :host_qualifier_taxon_id, plant_id(host)))

        _ ->
          undescribed(parts, descriptor(host, g["name_as_written"]), g["name_as_written"])
      end

    Catalog.create_gall(ctx.actor, Map.delete(attrs, :inducer_taxon_id))
  end

  defp get_taxon(taxa, ref), do: taxa[ref] && Taxa.get_taxon!(taxa[ref])

  defp plant_id(%{kingdom: "Plantae", id: id}), do: id
  defp plant_id(_host), do: nil

  # A species-rank Inducer always gives a name; one already shown gets a
  # numbered override.
  defp described(parts) do
    {:ok, name} = GallName.derive(parts)
    shown = first_free(&numbered(name, &1, " (#{&1})"), &(not Catalog.gall_name_taken?(&1)))
    Map.merge(parts, %{name: name, name_override: if(shown != name, do: shown)})
  end

  # The first numbering of `descriptor` whose name and code are both free;
  # without a derivable name, the Source's wording is the name and override.
  defp undescribed(parts, descriptor, as_written) do
    case GallName.derive(Map.put(parts, :descriptor, descriptor)) do
      {:ok, _name} ->
        {descriptor, name} =
          first_free(
            fn n ->
              d = numbered(descriptor, n, "-#{n}")
              {:ok, name} = GallName.derive(Map.put(parts, :descriptor, d))
              {d, name}
            end,
            fn {d, name} -> code_free?(d) and not Catalog.gall_name_taken?(name) end
          )

        Map.merge(parts, %{name: name, descriptor: descriptor, gallformers_code: descriptor})

      {:error, _reason} ->
        descriptor = first_free(&numbered(descriptor, &1, "-#{&1}"), &code_free?/1)
        wording = String.trim(as_written)
        name = first_free(&numbered(wording, &1, " (#{&1})"), &(not Catalog.gall_name_taken?(&1)))

        Map.merge(parts, %{
          name: name,
          name_override: name,
          descriptor: descriptor,
          gallformers_code: descriptor
        })
    end
  end

  defp code_free?(code), do: not Catalog.gallformers_code_taken?(code)

  defp numbered(text, 1, _suffix), do: text
  defp numbered(text, _n, suffix), do: text <> suffix

  # The first of `candidate.(1)`, `candidate.(2)`, … that `free?` accepts.
  defp first_free(candidate, free?) do
    1 |> Stream.iterate(&(&1 + 1)) |> Stream.map(candidate) |> Enum.find(free?)
  end

  @descriptor_length 60

  # Today's undescribed convention: "<host genus initial>-<host epithet>-
  # <the Source's wording>", slugged and trimmed to whole words.
  defp descriptor(host, as_written) do
    [host && host_part(host), slug(as_written)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("-")
    |> trim_words(@descriptor_length)
    |> case do
      "" -> "gall"
      descriptor -> descriptor
    end
  end

  # "Quercus lobata" → "q-lobata"; a genus, "Quercus" → "quercus".
  defp host_part(host) do
    case host |> Taxa.accepted_name() |> String.split() |> Enum.reject(&(&1 == "×")) do
      [genus, epithet | _] -> slug(String.first(genus) <> " " <> epithet)
      words -> slug(Enum.join(words, " "))
    end
  end

  # Lowercase ASCII words joined by single hyphens.
  defp slug(text) do
    text
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[^\x00-\x7F]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp trim_words(slug, max) when byte_size(slug) <= max, do: slug

  defp trim_words(slug, max) do
    [first | rest] = String.split(slug, "-")

    Enum.reduce_while(rest, binary_part(first, 0, min(byte_size(first), max)), fn word, acc ->
      next = acc <> "-" <> word
      if byte_size(next) <= max, do: {:cont, next}, else: {:halt, acc}
    end)
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

  # The contract's alias Facts are common names: no kind given, so a new
  # alias is a common name and one already held (a former label, a code)
  # keeps its kind.
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
