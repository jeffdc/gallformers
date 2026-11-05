defmodule Gallformers.Import.SetAside do
  @moduledoc """
  What a producer set aside as hedged or not a Fact (a batch's `unmapped`
  entries, `Gallformers.Import.BatchUnmapped`) as queue items a curator may
  answer (`6611` Task 2). They never hold approval: left alone, a
  set-aside statement stays out.

  Entries with a Trait slot (detachable, plant_part, form, shape, color,
  texture, alignment, walls, cells, season; format 3 only) are Trait terms:
  `Gallformers.Import.TraitTerms` places them, as it places the terms of
  trait Facts. (Before it, they were `:set_aside_term` items; no new ones
  are made.)

  ## Items

  Resolving a batch (gall or taxonomy) queues one `:set_aside_statement`
  item per term of any other slot (generation, relationship_type, place,
  taxonomic_act, other, ...). Entries with the same slot and the same
  normalized term (`Gallformers.Catalog.Vocab.TraitTermMapping.normalize/1`)
  are one item, so one answer covers every Gall they were set aside for.
  Its `statement_ref` is `"u:<slot>:<normalized term>"` (`statement_ref/2`):
  stable across resolutions, so an open item keeps its ID and a decided
  one its decision, and the replay log finds it by batch, kind and ref.
  Its `subject` is

      %{"slot" => slot, "topic" => the first entry's topic | nil,
        "term" => the first entry's term as written,
        "covers" => [%{"gall" => ref | nil, "name_as_written" => the Gall's,
                       "term" => as written, "evidence" => [...],
                       "note" => the producer's note | nil,
                       "position" => the entry's position in the batch}]}

  and its `proposal` `%{"keep" => true}`: keep the statement out.

  ## Decisions

  | Decision | Does |
  |---|---|
  | `%{"keep" => true}` | nothing: the statement stays out |
  | `%{"state" => spec}` | states what the curator built with pickers (below) |

  A `state` spec is one of `%{"kind" => "trait", "trait" => t, "value" => v}`
  (a Trait value), `%{"kind" => "host_of", "taxon_id" => id}` (a plant as
  the Host) or `%{"kind" => "occurrence", "place" => code}` (seen in a
  place). Stating needs a covered Gall.

  ## Applying

  A stated decision becomes one Fact per covered Gall when the gall batch
  is applied (`facts/1`, written by `Gallformers.Import.ApplyGall` like the
  batch's own Facts), attributed to the batch's Source with the entries'
  evidence. Its statement ref is the item's, then `@` and the Gall's ref
  (`"u:place:throughout the hills@g1"`). A covered Gall that is not
  resolved or created is skipped with the reason, as any Fact about it
  would be. Decided after the batch is applied, the Facts are written with
  the decision (`Gallformers.Import.apply_set_aside_decision/2`, with the
  context applying builds), so its replay writes them too.

  A Trait Fact a curator dropped from a dispute stays as text too: the
  decision adds an `unmapped` entry for it (`Gallformers.Import.Disputes`),
  with no item of its own.
  """

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Import.QueueItem
  alias Gallformers.Places
  alias Gallformers.Taxa

  @kinds [:set_aside_statement]

  # Longer normalized terms are shortened in the ref, with a hash to keep it unique.
  @max_term_bytes 200

  @doc "The kinds of queue item for what producers set aside."
  @spec kinds() :: [QueueItem.kind()]
  def kinds, do: @kinds

  @doc "Whether `item` (a queue item, or one about to be queued) is about something set aside."
  @spec set_aside?(map()) :: boolean()
  def set_aside?(%{kind: kind}), do: kind in @kinds

  @doc "The statement ref of the item for `term` set aside in `slot`."
  @spec statement_ref(String.t(), String.t()) :: String.t()
  def statement_ref(slot, term) do
    normalized = TraitTermMapping.normalize(term)

    term_part =
      if byte_size(normalized) <= @max_term_bytes do
        normalized
      else
        hash = :crypto.hash(:sha256, normalized) |> Base.encode16(case: :lower)
        String.slice(normalized, 0, 100) <> "#" <> binary_part(hash, 0, 12)
      end

    "u:#{slot}:#{term_part}"
  end

  # -- queueing ----------------------------------------------------------------

  @doc """
  The queue items for the `unmapped` entries of `content` (a decoded
  batch) that are not Trait terms, one per slot and normalized term, in
  the order the terms first appear.
  """
  @spec queue_items(map()) :: [map()]
  def queue_items(content) do
    names = Map.new(List.wrap(content["galls"]), &{&1["ref"], &1["name_as_written"]})

    content
    |> Map.get("unmapped", [])
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.reject(fn {e, _i} -> e["slot"] in TraitValue.traits() end)
    |> Enum.group_by(fn {e, _i} -> statement_ref(e["slot"], e["term"]) end)
    |> Enum.sort_by(fn {_ref, [{_e, first} | _]} -> first end)
    |> Enum.map(fn {ref, [{first, _} | _] = entries} ->
      %{
        kind: :set_aside_statement,
        statement_ref: ref,
        subject: %{
          "slot" => first["slot"],
          "topic" => first["topic"],
          "term" => first["term"],
          "covers" => Enum.map(entries, fn {e, i} -> cover(e, i, names) end)
        },
        proposal: %{"keep" => true},
        reason: "set aside as hedged or not a Fact; it stays out unless stated"
      }
    end)
  end

  defp cover(entry, position, names) do
    %{
      "gall" => entry["gall"],
      "name_as_written" => entry["gall"] && names[entry["gall"]],
      "term" => entry["term"],
      "evidence" => List.wrap(entry["evidence"]),
      "note" => entry["note"],
      "position" => position
    }
  end

  # -- deciding ----------------------------------------------------------------

  @doc """
  The choices a set-aside item allows, as `{key, check}`
  (`Gallformers.Import.Queue.validate_decision/3`).
  """
  @spec choices(QueueItem.t()) :: [{String.t(), (term() -> boolean())}]
  def choices(%QueueItem{kind: :set_aside_statement} = item) do
    [
      {"keep", &(&1 == true)},
      {"state", &(galls?(item) and valid_state?(&1))}
    ]
  end

  defp galls?(item), do: covered_galls(item) != []

  @doc "Whether `spec` is a `state` decision's spec that names an existing value, plant or place."
  @spec valid_state?(term()) :: boolean()
  def valid_state?(%{"kind" => "trait", "trait" => trait, "value" => value} = spec)
      when map_size(spec) == 3 and is_binary(trait) and is_binary(value),
      do: trait in TraitValue.traits() and Catalog.get_trait_value(trait, value) != nil

  def valid_state?(%{"kind" => "host_of", "taxon_id" => id} = spec)
      when map_size(spec) == 2 and is_integer(id),
      do: match?(%{kingdom: "Plantae"}, Taxa.get_taxon(id))

  def valid_state?(%{"kind" => "occurrence", "place" => code} = spec)
      when map_size(spec) == 2 and is_binary(code),
      do: Places.get_place_by_code(code) != nil

  def valid_state?(_spec), do: false

  # -- applying ----------------------------------------------------------------

  @doc """
  What a gall batch's decided set-aside items state, in the contract's
  Fact shape so the batch's Fact writer writes them: `facts`, one per
  covered Gall of each stated item (its id the item's ref, `@`
  and the Gall's ref), and for a stated Host the `taxa` (synthetic ref to
  taxon ID) and `declared` (synthetic ref to the name as written) its
  subject needs.
  """
  @spec facts([QueueItem.t()]) :: %{facts: [map()], taxa: map(), declared: map()}
  def facts(decided) do
    acc =
      for %QueueItem{kind: kind, decision: decision} = item <- decided,
          kind in @kinds,
          statement = statement(decision),
          {gall, covers} <- covered_galls(item),
          reduce: %{facts: [], taxa: %{}, declared: %{}} do
        acc -> add_fact(acc, statement, "#{item.statement_ref}@#{gall}", gall, covers)
      end

    %{acc | facts: Enum.reverse(acc.facts)}
  end

  # What a decision states, or nil.
  defp statement(%{"state" => %{"kind" => "trait"} = s}), do: {:trait, s["trait"], s["value"]}

  defp statement(%{"state" => %{"kind" => "host_of", "taxon_id" => id}}),
    do: {:host_of, id}

  defp statement(%{"state" => %{"kind" => "occurrence", "place" => code}}),
    do: {:occurrence, code}

  defp statement(_decision), do: nil

  # The Galls the item covers, in order, each with its covers.
  defp covered_galls(%QueueItem{subject: subject}) do
    subject
    |> Map.get("covers", [])
    |> Enum.filter(&is_binary(&1["gall"]))
    |> Enum.group_by(& &1["gall"])
    |> Enum.sort_by(fn {_gall, [first | _]} -> first["position"] || 0 end)
  end

  defp add_fact(acc, statement, id, gall, [first | _] = covers) do
    as_written = first["term"]

    base = %{
      "id" => id,
      "stance" => "confirm",
      "evidence" => Enum.flat_map(covers, & &1["evidence"])
    }

    case statement do
      {:trait, trait, value} ->
        fact =
          Map.merge(base, %{
            "kind" => "trait",
            "gall" => gall,
            "trait" => trait,
            "value" => %{"value" => value, "as_written" => as_written}
          })

        %{acc | facts: [fact | acc.facts]}

      {:host_of, taxon_id} ->
        ref = id <> ":host"

        fact =
          Map.merge(base, %{
            "kind" => "relationship",
            "type" => "host_of",
            "subject" => ref,
            "object" => gall
          })

        %{
          acc
          | facts: [fact | acc.facts],
            taxa: Map.put(acc.taxa, ref, taxon_id),
            declared: Map.put(acc.declared, ref, %{"name_as_written" => as_written})
        }

      {:occurrence, code} ->
        fact =
          Map.merge(base, %{
            "kind" => "occurrence",
            "gall" => gall,
            "place" => %{"value" => code, "as_written" => as_written}
          })

        %{acc | facts: [fact | acc.facts]}
    end
  end
end
