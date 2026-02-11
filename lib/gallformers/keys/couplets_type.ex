defmodule Gallformers.Keys.CoupletsType do
  @moduledoc """
  Custom Ecto type for storing dichotomous key couplets as a JSON object in SQLite.

  Handles serialization between atom-keyed Elixir maps (used at runtime) and
  JSON strings (stored in the database).

  On `cast`, validates the couplet structure:
  - Must be a map with string-integer keys
  - Couplet "1" must exist (entry point)
  - Each couplet must have a `leads` list with at least 2 items
  - Each lead must have `text` (string) and `destination` (map)
  - Destinations must have a valid `type` ("couplet" or "taxon")
  - Couplet destinations must reference existing couplet numbers

  On `load`, converts from JSON to atom-keyed maps matching the structure
  used by the key components.
  """
  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(couplets) when is_binary(couplets) do
    case Jason.decode(couplets) do
      {:ok, map} when is_map(map) -> validate_and_convert(map)
      {:ok, _} -> {:error, message: "couplets must be a JSON object"}
      {:error, _} -> {:error, message: "invalid JSON"}
    end
  end

  def cast(couplets) when is_map(couplets) do
    # Could be string-keyed (from JSON) or atom-keyed (already parsed)
    if atom_keyed?(couplets) do
      {:ok, couplets}
    else
      validate_and_convert(couplets)
    end
  end

  def cast(nil), do: {:error, message: "couplets are required"}
  def cast(_), do: {:error, message: "couplets must be a map or JSON string"}

  @impl true
  def load(nil), do: {:ok, %{}}
  def load(""), do: {:ok, %{}}

  def load(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, map} when is_map(map) -> {:ok, to_atom_keys(map)}
      _ -> {:ok, %{}}
    end
  end

  @impl true
  def dump(couplets) when is_map(couplets) do
    {:ok, Jason.encode!(to_string_keys(couplets))}
  end

  def dump(nil), do: {:error, message: "couplets are required"}
  def dump(_), do: :error

  @impl true
  def equal?(a, b), do: a == b

  @impl true
  def embed_as(_format), do: :self

  # Validation

  defp validate_and_convert(map) do
    with :ok <- validate_entry_point(map),
         :ok <- validate_couplets(map),
         :ok <- validate_references(map) do
      {:ok, to_atom_keys(map)}
    end
  end

  defp validate_entry_point(map) do
    if Map.has_key?(map, "1") do
      :ok
    else
      {:error, message: "couplet \"1\" must exist as the entry point"}
    end
  end

  defp validate_couplets(map) do
    Enum.reduce_while(map, :ok, fn {number, couplet}, :ok ->
      case validate_couplet(number, couplet) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_couplet(number, couplet) when is_map(couplet) do
    leads = couplet["leads"] || []

    cond do
      not is_list(leads) ->
        {:error, message: "couplet #{number}: leads must be a list"}

      length(leads) < 2 ->
        {:error, message: "couplet #{number}: must have at least 2 leads"}

      true ->
        validate_leads(number, leads)
    end
  end

  defp validate_couplet(number, _) do
    {:error, message: "couplet #{number}: must be a map"}
  end

  defp validate_leads(number, leads) do
    leads
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {lead, index}, :ok ->
      case validate_lead(number, index, lead) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_lead(number, index, lead) when is_map(lead) do
    cond do
      not is_binary(lead["text"]) or lead["text"] == "" ->
        {:error, message: "couplet #{number}, lead #{index}: text is required"}

      lead["destination"] != nil and not is_map(lead["destination"]) ->
        {:error, message: "couplet #{number}, lead #{index}: destination must be a map"}

      lead["destination"] != nil ->
        validate_destination(number, index, lead["destination"])

      true ->
        :ok
    end
  end

  defp validate_lead(number, index, _) do
    {:error, message: "couplet #{number}, lead #{index}: must be a map"}
  end

  defp validate_destination(number, index, dest) do
    case dest["type"] do
      "couplet" ->
        if dest["number"] do
          :ok
        else
          {:error,
           message: "couplet #{number}, lead #{index}: couplet destination requires number"}
        end

      "taxon" ->
        if is_binary(dest["name"]) and dest["name"] != "" do
          :ok
        else
          {:error, message: "couplet #{number}, lead #{index}: taxon destination requires name"}
        end

      nil ->
        {:error, message: "couplet #{number}, lead #{index}: destination requires type"}

      other ->
        {:error,
         message: "couplet #{number}, lead #{index}: unknown destination type \"#{other}\""}
    end
  end

  defp validate_references(map) do
    couplet_numbers = MapSet.new(Map.keys(map))

    map
    |> Enum.flat_map(fn {_number, couplet} ->
      (couplet["leads"] || [])
      |> Enum.filter(fn lead ->
        lead["destination"] != nil and lead["destination"]["type"] == "couplet"
      end)
      |> Enum.map(fn lead -> lead["destination"]["number"] end)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce_while(:ok, fn ref, :ok ->
      if MapSet.member?(couplet_numbers, ref) do
        {:cont, :ok}
      else
        {:halt,
         {:error, message: "couplet destination references non-existent couplet \"#{ref}\""}}
      end
    end)
  end

  # Conversion: string-keyed JSON maps → atom-keyed runtime maps

  defp to_atom_keys(couplets_map) do
    Map.new(couplets_map, fn {number, couplet} ->
      {to_string(number), convert_couplet(couplet)}
    end)
  end

  defp convert_couplet(data) when is_map(data) do
    %{
      leads: Enum.map(data["leads"] || [], &convert_lead/1)
    }
  end

  defp convert_lead(data) when is_map(data) do
    %{
      text: data["text"],
      notes: data["notes"],
      images: Enum.map(data["images"] || [], &convert_image/1),
      destination: convert_destination(data["destination"])
    }
  end

  defp convert_image(data) when is_map(data) do
    %{
      ref: data["ref"],
      file: data["file"],
      caption: data["caption"]
    }
  end

  defp convert_destination(nil), do: nil

  defp convert_destination(data) when is_map(data) do
    base = %{type: data["type"]}

    case data["type"] do
      "couplet" ->
        base
        |> Map.put(:number, data["number"])
        |> Map.put(:label, data["label"])

      "taxon" ->
        base
        |> Map.put(:name, data["name"])
        |> Map.put(:context, data["context"])
        |> Map.put(:species_ids, normalize_species_ids(data["species_id"]))

      _ ->
        base
    end
  end

  defp normalize_species_ids(nil), do: []
  defp normalize_species_ids(id) when is_integer(id), do: [id]
  defp normalize_species_ids(ids) when is_list(ids), do: ids

  # Conversion: atom-keyed runtime maps → string-keyed maps for JSON storage
  # Maps may have atom or string keys depending on origin, so `get/2` handles both.

  defp get(map, key) when is_atom(key), do: map[key] || map[Atom.to_string(key)]

  defp to_string_keys(couplets_map) do
    Map.new(couplets_map, fn {number, couplet} ->
      {to_string(number), unconvert_couplet(couplet)}
    end)
  end

  defp unconvert_couplet(couplet) when is_map(couplet) do
    %{"leads" => Enum.map(get(couplet, :leads) || [], &unconvert_lead/1)}
  end

  defp unconvert_lead(lead) when is_map(lead) do
    %{
      "text" => get(lead, :text),
      "notes" => get(lead, :notes),
      "images" => Enum.map(get(lead, :images) || [], &unconvert_image/1),
      "destination" => unconvert_destination(get(lead, :destination))
    }
  end

  defp unconvert_image(image) when is_map(image) do
    %{"ref" => get(image, :ref), "file" => get(image, :file), "caption" => get(image, :caption)}
  end

  defp unconvert_destination(nil), do: nil

  defp unconvert_destination(dest) when is_map(dest) do
    type = get(dest, :type)

    case type do
      "couplet" ->
        %{"type" => type, "number" => get(dest, :number), "label" => get(dest, :label)}

      "taxon" ->
        %{
          "type" => type,
          "name" => get(dest, :name),
          "context" => get(dest, :context),
          "species_id" => species_ids_to_json(get(dest, :species_ids) || [])
        }

      _ ->
        %{"type" => type}
    end
  end

  defp species_ids_to_json([single]), do: single
  defp species_ids_to_json(ids) when is_list(ids) and ids != [], do: ids
  defp species_ids_to_json(_), do: nil

  # Check if the map is already atom-keyed (runtime format)
  defp atom_keyed?(map) when map_size(map) == 0, do: true

  defp atom_keyed?(map) do
    {_key, value} = Enum.at(map, 0)
    is_map(value) and (Map.has_key?(value, :leads) or Map.has_key?(value, "leads") == false)
  end
end
