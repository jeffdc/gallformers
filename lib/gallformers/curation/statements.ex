defmodule Gallformers.Curation.Statements do
  @moduledoc """
  A Fact item as Gallformers' statements (`priv/import/GALLFORMERS_STATEMENTS.md`),
  in the form `Gallformers.Import.GallformersFragment.gall_batch/3` takes:
  add confirms the key's Fact, withdraw denies it, correct denies it and
  confirms `to`'s. Each statement is dated today, with the item's evidence
  (its own, or the set's): its text, its Observations, and the Source it
  follows as `cites` — Gallformers' statement made on that Source's word.
  A recorded occurrence's `when` is its `when_as_written`.

  Evidence with no text is worded from what it has ("Seen in iNaturalist
  observation 123.", "As Weld 1959 states.") or, with nothing, from the
  item ("A curator's statement: host: Quercus alba.").
  """
  alias Gallformers.Catalog
  alias Gallformers.Curation.Wording
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Places
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa

  @doc """
  The statements of a Fact item's decoded `spec`, given its `evidence`
  (`t:Gallformers.Curation.evidence/0` or nil), dated `on`.
  """
  @spec for_item(map(), map() | nil, Date.t()) :: [map()]
  def for_item(%{kind: :fact, action: action, key: key} = spec, evidence, on) do
    evidence = evidence_for(spec, evidence || %{}, on)

    stances =
      case action do
        :add -> [{"confirm", key}]
        :withdraw -> [{"deny", key}]
        :correct -> [{"deny", key}, {"confirm", spec.to}]
      end

    for {stance, key} <- stances do
      key
      |> fact()
      |> Map.merge(%{"stance" => stance, "evidence" => [evidence]})
      |> put_if("when_as_written", stance == "confirm" && spec[:when])
    end
  end

  @doc """
  The statements of a reading fix's decoded `spec` (matter `87a1`), for a
  batch `source.reading_of` its Source: the misread statement marked
  `unstated`, and what the Source does say in its place (each of `to`),
  marked `"replaces" => :unstated` (the batch gives it the unstated
  Fact's ID); when `to` is several values and the misread one is among
  them, it stays and the others are stated besides. Each carries the
  Source's words from its statement: its
  stance, quotes (the stored items by `gallformers_document_item_id`),
  pages, links, Observations, and its words as written for a value. `[]`
  when the Source no longer states the Fact.
  """
  @spec for_reading(map()) :: [map()]
  def for_reading(%{kind: :reading, gall_id: gall_id, source_id: source_id, key: key} = spec) do
    with {:ok, fact_id} when is_integer(fact_id) <- Catalog.find_gall_fact(gall_id, key),
         %Attribution{} = a <- Facts.get_attribution(fact_id, source_id) do
      a = Repo.preload(a, [:evidence, :observations])
      said = %{"stance" => Atom.to_string(a.stance), "evidence" => source_evidence(a)}

      tos = List.wrap(spec.to)

      # The misread value among several the Source gives stays stated; the
      # others are what it says too.
      if key in tos do
        for to <- List.delete(tos, key), do: Map.merge(as_written(fact(to), a), said)
      else
        [Map.merge(as_written(fact(key), a), Map.put(said, "unstated", true))] ++
          for to <- tos,
              do: Map.merge(as_written(fact(to), a), Map.put(said, "replaces", :unstated))
      end
    else
      _ -> []
    end
  end

  # The Source's quotes as written, with its Observations on the first.
  defp source_evidence(%Attribution{evidence: evidence, observations: observations}) do
    quotes =
      for e <- evidence do
        if(e.whole_item, do: %{"whole_item" => true}, else: %{"quote" => e.quote})
        |> put_if("gallformers_document_item_id", e.document_item_id)
        |> put_if("page", e.page)
        |> put_if("url", e.url)
        |> put_if("cites", e.cites_as_written && %{"as_written" => e.cites_as_written})
      end

    case {quotes, observations} do
      {[first | rest], [_ | _]} ->
        seen =
          Enum.map(observations, &%{"provider" => to_string(&1.provider), "id" => &1.external_id})

        [Map.put(first, "observations", seen) | rest]

      _ ->
        quotes
    end
  end

  # The Source's own words for a value: a Trait's term, a place as written,
  # when and at what stage a record was made.
  defp as_written(%{"kind" => "trait", "value" => value} = fact, a),
    do: %{
      fact
      | "value" => %{value | "as_written" => a.term || a.value_as_written || value["as_written"]}
    }

  defp as_written(%{"place" => place} = fact, a) do
    %{fact | "place" => %{place | "as_written" => a.value_as_written || place["as_written"]}}
    |> put_if("when_as_written", fact["kind"] == "occurrence" && a.when_as_written)
    |> put_if("stage_as_written", fact["kind"] == "occurrence" && a.stage_as_written)
  end

  # A Host or Inducer: the Source's own words for the taxon, read now as the
  # taxon the fix names (`name_reading`).
  defp as_written(%{"kind" => "relationship", "subject" => {:taxon, taxon}} = fact, a) do
    subject = Enum.find(Repo.preload(a, :names).names, &(&1.role == "subject"))

    case (subject && subject.name_as_written) || a.value_as_written do
      written when is_binary(written) ->
        %{fact | "subject" => {:taxon, Map.put(taxon, :name_as_written, written)}}

      nil ->
        fact
    end
  end

  defp as_written(fact, _a), do: fact

  defp fact({role, taxon_id}) when role in [:inducer, :host] do
    %{
      "kind" => "relationship",
      "type" => "#{role}_of",
      "subject" => {:taxon, taxon(taxon_id)},
      "object" => :gall
    }
  end

  defp fact({:trait, trait, value}) do
    %{
      "kind" => "trait",
      "gall" => :gall,
      "trait" => trait,
      "value" => %{"value" => value, "as_written" => value}
    }
  end

  defp fact({:alias, name}), do: %{"kind" => "alias", "gall" => :gall, "name" => name}

  defp fact({:range, adjustment, place_id}) do
    %{
      "kind" => "range",
      "gall" => :gall,
      "adjustment" => Atom.to_string(adjustment),
      "place" => place(place_id)
    }
  end

  defp fact({:occurrence, place_id}),
    do: %{"kind" => "occurrence", "gall" => :gall, "place" => place(place_id)}

  defp taxon(id) do
    taxon = Taxa.get_taxon!(id)
    %{taxon_id: id, name: Taxa.accepted_name(taxon), rank: taxon.rank}
  end

  defp place(id) do
    place = Places.get_place!(id)
    %{"value" => place.code, "as_written" => place.name}
  end

  defp evidence_for(spec, evidence, on) do
    observations = Map.get(evidence, :observations) || []
    source = Map.get(evidence, :source_id) && Sources.get_source(evidence.source_id)

    %{
      "statement" => %{
        "text" => text(spec, Map.get(evidence, :text), observations, source),
        "stated_on" => Date.to_iso8601(on)
      }
    }
    |> put_if(
      "observations",
      observations != [] && Enum.map(observations, &observation/1)
    )
    |> put_if(
      "cites",
      source && %{"as_written" => Wording.source_name(source), "source_id" => source.id}
    )
  end

  # An Observation as a statement cites it, with its quality grade and
  # thumbnail when it has them.
  defp observation(o) do
    %{"provider" => o.provider, "id" => to_string(o.id)}
    |> put_if("quality_grade", o[:quality_grade])
    |> put_if("thumbnail_url", o[:thumbnail_url])
  end

  defp text(_spec, text, _observations, _source) when is_binary(text) and text != "", do: text

  defp text(_spec, _text, [_ | _] = observations, _source) do
    "Seen in " <>
      Enum.map_join(observations, ", ", &"#{provider(&1.provider)} observation #{&1.id}") <> "."
  end

  defp text(_spec, _text, [], %{} = source), do: "As #{Wording.source_name(source)} states."

  defp text(spec, _text, _observations, _source),
    do: "A curator's statement: #{Wording.item_text(spec)}."

  defp provider("inaturalist"), do: "iNaturalist"
  defp provider("bugguide"), do: "BugGuide"
  defp provider(other), do: other

  defp put_if(map, _key, falsy) when falsy in [nil, false], do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
