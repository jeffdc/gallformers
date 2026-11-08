defmodule Gallformers.Import.MissedNames do
  @moduledoc """
  Names the producer missed, as questions (matter `c8c3` item 12): a name
  the Source prints that the tree holds but no batch of the package
  declares (`Gallformers.Import.UnusedNames`). Jeff (2026-11-08): no
  producer run for one; a curator dismisses it, or states by hand what the
  Source says with it.

  ## Items

  Resolving a package queues, on its gall batch, one `:missed_name` item
  per unused name, never holding approval. Its `statement_ref` is `"n:"`
  and the name's normalized form (`statement_ref/1`), stable across
  resolutions. Its `subject` is

      %{"name" => as first printed, "normalized" => ..., "taxon_ids" => the
        tree's taxa holding it, "items" => the first blocks it appears in
        (`#/texts/N`), "pages" => every page it appears on}

  and it has no proposal.

  ## Decisions

  | Decision | Does |
  |---|---|
  | `%{"dismiss" => true}` | nothing: the name says nothing to state |
  | `%{"state" => spec}` | states the name's taxon in one Relationship with a Gall |

  A `state` spec is `%{"kind" => "inducer_of" | "host_of", "taxon_id" =>
  id, "gall_id" => id, "items" => [ref, ...]}`: the taxon one the name's
  (`subject["taxon_ids"]`), a plant for a Host and not one for an Inducer;
  a Gall Gallformers holds; and one or more of the name's blocks
  (`subject["items"]`) as the evidence, each whole. Either may carry a
  `"note"`.

  ## Applying

  A stated decision is one Fact when the gall batch is applied (`facts/1`,
  written by `Gallformers.Import.ApplyGall` like the batch's own),
  attributed to the batch's Source, the name as written. Its statement ref
  is the item's, then `@` and the Gall's ID. Decided after the batch is
  applied, it is written with the decision, so its replay writes it too.
  """

  alias Gallformers.Catalog
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.UnusedNames
  alias Gallformers.Taxa

  @kind :missed_name

  # Longer names are shortened in the ref, with a hash to keep it unique.
  @max_name_bytes 200

  @doc "The kind of queue item for a missed name."
  @spec kind() :: QueueItem.kind()
  def kind, do: @kind

  @doc "Whether `item` (a queue item, or one about to be queued) is a missed name."
  @spec missed?(map()) :: boolean()
  def missed?(%{kind: kind}), do: kind == @kind

  @doc "The statement ref of the item for a name normalized as `normalized`."
  @spec statement_ref(String.t()) :: String.t()
  def statement_ref(normalized) do
    if byte_size(normalized) <= @max_name_bytes do
      "n:" <> normalized
    else
      hash = :crypto.hash(:sha256, normalized) |> Base.encode16(case: :lower)
      "n:" <> String.slice(normalized, 0, 100) <> "#" <> binary_part(hash, 0, 12)
    end
  end

  @doc """
  The items for `doc` (the decoded `document.json`) and `batches` (the
  package's decoded batch contents, denied ones left out): one per unused
  name, in the order the Source first prints them.
  """
  @spec queue_items(map() | nil, [map()]) :: [map()]
  def queue_items(nil, _batches), do: []

  def queue_items(doc, batches) do
    for name <- UnusedNames.list(doc, batches) do
      %{
        kind: @kind,
        statement_ref: statement_ref(name.normalized),
        subject: %{
          "name" => name.name,
          "normalized" => name.normalized,
          "taxon_ids" => name.taxon_ids,
          "items" => name.items,
          "pages" => name.pages
        },
        proposal: %{},
        reason: "the Source prints this name, which Gallformers holds, and no batch declares it"
      }
    end
  end

  # -- deciding ------------------------------------------------------------------

  @doc "The choices a missed name allows, as `{key, check}` (`Gallformers.Import.Queue.validate_decision/3`)."
  @spec choices(QueueItem.t()) :: [{String.t(), (term() -> boolean())}]
  def choices(item), do: [{"dismiss", &(&1 == true)}, {"state", &state?(item, &1)}]

  defp state?(%QueueItem{subject: subject}, %{"kind" => kind} = spec)
       when kind in ["inducer_of", "host_of"] do
    taxon_id = spec["taxon_id"]
    items = spec["items"]

    taxon_id in List.wrap(subject["taxon_ids"]) and plant?(taxon_id) == (kind == "host_of") and
      is_integer(spec["gall_id"]) and Catalog.get_gall(spec["gall_id"]) != nil and
      match?([_ | _], items) and Enum.uniq(items) == items and
      Enum.all?(items, &(&1 in List.wrap(subject["items"])))
  end

  defp state?(_item, _spec), do: false

  defp plant?(id) when is_integer(id), do: match?(%{kingdom: "Plantae"}, Taxa.get_taxon(id))
  defp plant?(_id), do: false

  # -- applying ------------------------------------------------------------------

  @doc """
  What the decided items `decided` state, in the contract's shape for the
  batch's Fact writer: `facts`, and the `taxa`, `declared` and `galls` they
  name (refs of their own, to IDs), merged with the batch's.
  """
  @spec facts([QueueItem.t()]) :: %{facts: [map()], taxa: map(), declared: map(), galls: map()}
  def facts(decided) do
    acc =
      for %QueueItem{kind: @kind, decision: %{"state" => spec}} = item <- decided,
          reduce: %{facts: [], taxa: %{}, declared: %{}, galls: %{}} do
        acc -> add_fact(acc, item, spec)
      end

    %{acc | facts: Enum.reverse(acc.facts)}
  end

  defp add_fact(acc, item, spec) do
    id = "#{item.statement_ref}@#{spec["gall_id"]}"
    taxon = id <> ":taxon"
    gall = id <> ":gall"

    fact = %{
      "id" => id,
      "stance" => "confirm",
      "kind" => "relationship",
      "type" => spec["kind"],
      "subject" => taxon,
      "object" => gall,
      "evidence" => Enum.map(spec["items"], &%{"item" => &1, "whole_item" => true})
    }

    %{
      acc
      | facts: [fact | acc.facts],
        taxa: Map.put(acc.taxa, taxon, spec["taxon_id"]),
        declared: Map.put(acc.declared, taxon, %{"name_as_written" => item.subject["name"]}),
        galls: Map.put(acc.galls, gall, spec["gall_id"])
    }
  end
end
