defmodule Gallformers.Ingestions.SourceIngestionSpeciesEntries do
  @moduledoc false

  alias Gallformers.Ingestions
  alias Gallformers.Ingestions.SourceIngestionSpecies
  alias Gallformers.Utils

  @spec ensure_entries(integer(), [map()]) ::
          {:ok, [SourceIngestionSpecies.t()]} | {:error, Ecto.Changeset.t()}
  def ensure_entries(source_ingestion_id, records)
      when is_integer(source_ingestion_id) and is_list(records) do
    collated_records = collate_species_records(records)

    existing_entries_by_position =
      source_ingestion_id
      |> Ingestions.list_source_ingestion_species()
      |> Map.new(&{&1.position, &1})

    collated_records
    |> Enum.with_index()
    |> Enum.reduce_while(
      {:ok, []},
      &ensure_source_ingestion_species_entry(
        &1,
        &2,
        source_ingestion_id,
        existing_entries_by_position
      )
    )
    |> case do
      {:ok, species_entries} -> {:ok, Enum.reverse(species_entries)}
      error -> error
    end
  end

  defp ensure_source_ingestion_species_entry(
         {record, position},
         {:ok, acc},
         source_ingestion_id,
         existing_entries_by_position
       ) do
    case Map.fetch(existing_entries_by_position, position) do
      {:ok, existing_entry} -> {:cont, {:ok, [existing_entry | acc]}}
      :error -> create_source_ingestion_species_entry(source_ingestion_id, record, position, acc)
    end
  end

  defp create_source_ingestion_species_entry(source_ingestion_id, record, position, acc) do
    source_ingestion_id
    |> source_ingestion_species_attrs_from_record(record, position)
    |> Ingestions.create_source_ingestion_species()
    |> case do
      {:ok, species_entry} -> {:cont, {:ok, [species_entry | acc]}}
      {:error, changeset} -> {:halt, {:error, changeset}}
    end
  end

  defp collate_species_records(records) do
    records
    |> Enum.with_index()
    |> Enum.reduce([], fn {record, index}, acc ->
      group_key = species_record_group_key(record, index)
      merge_collated_record(acc, seed_collated_record(record, group_key), group_key)
    end)
  end

  defp merge_collated_record([], collated_record, _group_key), do: [collated_record]

  defp merge_collated_record([existing | rest], collated_record, group_key) do
    if Map.get(existing, :group_key) == group_key do
      [merge_collated_species_record(existing, collated_record) | rest]
    else
      [existing | merge_collated_record(rest, collated_record, group_key)]
    end
  end

  defp seed_collated_record(record, group_key) do
    gall_species = normalize_extracted_record_map(Utils.attr_value(record, :gall_species))
    description = string_or_nil(Utils.attr_value(record, :description))

    %{
      group_key: group_key,
      gall_species: gall_species,
      hosts: normalize_extracted_hosts(record),
      aliases: normalize_extracted_aliases(record),
      traits: normalize_extracted_traits(record),
      description_evidence: description_evidence_from_record(description),
      location: Utils.attr_value(record, :location),
      confidence: Utils.attr_value(record, :confidence)
    }
  end

  defp species_record_group_key(record, index) do
    gall_species = Utils.attr_value(record, :gall_species)
    name = gall_species |> Utils.nested_value(:name, nil) |> string_or_nil()
    authority = gall_species |> Utils.nested_value(:authority, nil) |> string_or_nil()

    if name do
      {:species, String.downcase(name), String.downcase(authority || "")}
    else
      {:ungrouped, index}
    end
  end

  defp merge_collated_species_record(existing, incoming) do
    %{
      existing
      | hosts: merge_extracted_hosts(existing.hosts, incoming.hosts),
        aliases: merge_string_lists(existing.aliases, incoming.aliases),
        traits: merge_extracted_traits(existing.traits, incoming.traits),
        description_evidence:
          merge_description_evidence(existing.description_evidence, incoming.description_evidence),
        location: existing.location || incoming.location,
        confidence: max_confidence(existing.confidence, incoming.confidence)
    }
  end

  defp merge_extracted_hosts(existing, incoming) do
    (List.wrap(existing) ++ List.wrap(incoming))
    |> Enum.uniq_by(fn host ->
      {
        host |> Utils.nested_value(:name, nil) |> string_or_nil(),
        host |> Utils.nested_value(:authority, nil) |> string_or_nil()
      }
    end)
  end

  defp merge_extracted_traits(existing, incoming) when existing == %{}, do: incoming
  defp merge_extracted_traits(existing, incoming) when incoming == %{}, do: existing

  defp merge_extracted_traits(existing, incoming) do
    Map.merge(existing, incoming, fn trait_name, existing_value, incoming_value ->
      merge_extracted_trait_value(trait_name, existing_value, incoming_value)
    end)
  end

  defp merge_extracted_trait_value("detachable", existing, incoming) do
    existing = string_or_nil(existing)
    incoming = string_or_nil(incoming)

    cond do
      existing in [nil, "unknown"] -> incoming || existing || "unknown"
      incoming in [nil, "unknown"] -> existing
      existing == incoming -> existing
      true -> "both"
    end
  end

  defp merge_extracted_trait_value(_trait_name, existing, incoming) do
    %{
      "original" =>
        merge_joined_evidence([
          Utils.nested_value(existing, :original, nil),
          Utils.nested_value(incoming, :original, nil)
        ]),
      "suggested" =>
        merge_string_lists(
          Utils.nested_value(existing, :suggested, []),
          Utils.nested_value(incoming, :suggested, [])
        )
    }
  end

  defp merge_description_evidence(existing, incoming) do
    (List.wrap(existing) ++ List.wrap(incoming))
    |> Enum.reduce([], &append_unique_description_evidence(&2, &1))
  end

  defp merged_description(record) do
    record
    |> description_evidence_from_record()
    |> Enum.map(&Utils.nested_value(&1, :text, nil))
    |> Enum.reject(&is_nil/1)
    |> merge_joined_evidence()
  end

  defp merge_joined_evidence(values) when is_list(values) do
    values
    |> Utils.normalize_string_list()
    |> Enum.uniq()
    |> case do
      [] -> nil
      joined -> Enum.join(joined, "\n\n")
    end
  end

  defp merge_string_lists(left, right) do
    (List.wrap(left) ++ List.wrap(right))
    |> Utils.normalize_string_list()
    |> Enum.uniq()
  end

  defp max_confidence(left, right) when is_number(left) and is_number(right), do: max(left, right)
  defp max_confidence(left, _right) when is_number(left), do: left
  defp max_confidence(_left, right) when is_number(right), do: right
  defp max_confidence(_left, _right), do: nil

  defp append_unique_description_evidence(acc, evidence) do
    case Utils.nested_value(evidence, :text, nil) |> string_or_nil() do
      nil ->
        acc

      text ->
        if Enum.any?(acc, &(Utils.nested_value(&1, :text, nil) == text)) do
          acc
        else
          acc ++ [%{"text" => text}]
        end
    end
  end

  defp source_ingestion_species_attrs_from_record(source_ingestion_id, record, position) do
    gall_species = Utils.attr_value(record, :gall_species)
    description = merged_description(record)

    %{
      source_ingestion_id: source_ingestion_id,
      position: position,
      status: "pending",
      extracted_name: Utils.nested_value(gall_species, :name, nil),
      extracted_authority: Utils.nested_value(gall_species, :authority, nil),
      description_prose: description || "",
      extraction_payload: %{
        "gall_species" => normalize_extracted_record_map(gall_species),
        "hosts" => normalize_extracted_hosts(record),
        "aliases" => normalize_extracted_aliases(record),
        "traits" => normalize_extracted_traits(record),
        "description_evidence" => description_evidence_from_record(record),
        "location" => Utils.attr_value(record, :location),
        "confidence" => Utils.attr_value(record, :confidence)
      }
    }
  end

  defp normalize_extracted_record_map(value) when is_map(value), do: value
  defp normalize_extracted_record_map(_value), do: %{}

  defp normalize_extracted_hosts(%{hosts: hosts}) when is_list(hosts), do: hosts
  defp normalize_extracted_hosts(%{"hosts" => hosts}) when is_list(hosts), do: hosts

  defp normalize_extracted_hosts(record) do
    record
    |> Utils.attr_value(:host_species)
    |> List.wrap()
    |> Enum.filter(fn host_species ->
      case Utils.nested_value(host_species, :name, nil) do
        name when is_binary(name) and name != "" -> true
        _ -> false
      end
    end)
  end

  defp normalize_extracted_aliases(%{aliases: aliases}) when is_list(aliases),
    do: Utils.normalize_string_list(aliases)

  defp normalize_extracted_aliases(%{"aliases" => aliases}) when is_list(aliases),
    do: Utils.normalize_string_list(aliases)

  defp normalize_extracted_aliases(_record), do: []

  defp normalize_extracted_traits(%{traits: traits}) when is_map(traits), do: traits
  defp normalize_extracted_traits(%{"traits" => traits}) when is_map(traits), do: traits
  defp normalize_extracted_traits(_record), do: %{}

  defp description_evidence_from_record(nil), do: []

  defp description_evidence_from_record(description) when is_binary(description) do
    case string_or_nil(description) do
      nil -> []
      text -> [%{"text" => text}]
    end
  end

  defp description_evidence_from_record(%{description_evidence: evidence}) when is_list(evidence),
    do: evidence

  defp description_evidence_from_record(%{"description_evidence" => evidence})
       when is_list(evidence),
       do: evidence

  defp description_evidence_from_record(record) do
    record
    |> merged_description()
    |> case do
      nil -> []
      description -> [%{"text" => description}]
    end
  end

  defp string_or_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp string_or_nil(_value), do: nil
end
