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
  alias Gallformers.Curation.Wording
  alias Gallformers.Places
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
      observations != [] &&
        Enum.map(observations, &%{"provider" => &1.provider, "id" => to_string(&1.id)})
    )
    |> put_if(
      "cites",
      source && %{"as_written" => Wording.source_name(source), "source_id" => source.id}
    )
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
