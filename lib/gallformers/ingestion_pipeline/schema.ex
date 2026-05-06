defmodule Gallformers.IngestionPipeline.Schema do
  @moduledoc """
  Loads and validates gall records against the JSON schema.

  `priv/schemas/gall_record.json` is the canonical definition of the gall
  record contract and controlled vocabularies used for structural validation.
  """

  @schema_path "gall_record.json"

  # Prompt order is presentation-only. The contract itself comes from the schema file.
  @prompt_field_order ~w(gall_species host_species traits description location confidence)
  @prompt_trait_order ~w(shape color texture walls cells alignment plant_part form season detachable)

  @doc """
  Render a human-readable prompt description of the gall record contract.

  For the canonical machine-readable definition, see
  `priv/schemas/gall_record.json`.
  """
  @spec prompt_text() :: String.t()
  def prompt_text do
    schema = load()

    """
    ## Data Schema

    Produce one JSON object per gall-host association with these fields:

    #{schema_prompt_body(schema)}
    """
  end

  @doc """
  Validate a list of records against the schema.

  Returns `{:ok, records}` on success or `{:error, :invalid_contract, details}` on failure.
  """
  @spec validate([map()]) :: {:ok, [map()]} | {:error, :invalid_contract, [String.t()]}
  def validate(records) when is_list(records) do
    raw_schema = load()
    schema = ExJsonSchema.Schema.resolve(raw_schema)

    records
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {record, idx}, {:ok, acc} ->
      errors = schema_errors(schema, record, idx)

      if errors == [] do
        {:cont, {:ok, [record | acc]}}
      else
        {:halt, {:error, :invalid_contract, errors}}
      end
    end)
    |> case do
      {:ok, validated_records} -> {:ok, Enum.reverse(validated_records)}
      error -> error
    end
  end

  def validate(_), do: {:error, :invalid_contract, ["Expected a list of records"]}

  defp load do
    [:code.priv_dir(:gallformers), "schemas", @schema_path]
    |> Path.join()
    |> File.read!()
    |> Jason.decode!()
  end

  defp schema_prompt_body(schema) do
    schema
    |> prompt_properties()
    |> Enum.map_join("\n", &prompt_line(&1, schema))
  end

  defp prompt_properties(schema) do
    properties = Map.fetch!(schema, "properties")

    @prompt_field_order
    |> Enum.map(fn field_name -> {field_name, Map.fetch!(properties, field_name)} end)
  end

  defp prompt_line({"gall_species", property_schema}, _schema) do
    ~s(- "gall_species": object with keys #{quoted_keys(property_schema)})
  end

  defp prompt_line({"host_species", property_schema}, _schema) do
    ~s(- "host_species": object with keys #{quoted_keys(property_schema)})
  end

  defp prompt_line({"traits", property_schema}, schema) do
    trait_lines =
      property_schema
      |> Map.fetch!("properties")
      |> prompt_traits(schema)

    """
    - "traits": object with the following keys:
      #{trait_lines}
    """
    |> String.trim_trailing()
  end

  defp prompt_line({field_name, %{"description" => description}}, _schema) do
    ~s(- "#{field_name}": #{decapitalize(description)})
  end

  defp prompt_traits(trait_properties, schema) do
    @prompt_trait_order
    |> Enum.map(fn trait_name -> {trait_name, Map.fetch!(trait_properties, trait_name)} end)
    |> Enum.map_join("\n      ", &prompt_trait_line(&1, schema))
  end

  defp prompt_trait_line({trait_name, %{"$ref" => _} = trait_schema}, schema) do
    ~s|- "#{trait_name}": object with "original" (exact text from source, or null) and "suggested" (list of closest matches from: | <>
      "#{Enum.join(trait_vocab(trait_name, trait_schema, schema), ", ")}, or empty list)"
  end

  defp prompt_trait_line({trait_name, trait_schema}, schema) do
    "- \"#{trait_name}\": one of #{Enum.join(trait_vocab(trait_name, trait_schema, schema), ", ")} or null"
  end

  defp quoted_keys(property_schema) do
    property_schema
    |> Map.fetch!("properties")
    |> Map.keys()
    |> Enum.map_join(", ", &~s("#{&1}"))
  end

  defp decapitalize(<<first::utf8, rest::binary>>) do
    String.downcase(<<first::utf8>>) <> rest
  end

  defp decapitalize(""), do: ""

  defp schema_errors(schema, record, idx) do
    case ExJsonSchema.Validator.validate(schema, record) do
      :ok ->
        []

      {:error, errors} when is_list(errors) ->
        Enum.map(errors, &format_schema_error(idx, &1))
    end
  end

  defp trait_vocab(_trait_name, %{"enum" => enum}, _raw_schema) when is_list(enum) do
    Enum.reject(enum, &is_nil/1)
  end

  defp trait_vocab(trait_name, %{"$ref" => _ref}, raw_schema) do
    definition_name = "#{trait_name}_vocab"

    raw_schema
    |> get_in(["definitions", definition_name, "enum"])
    |> List.wrap()
  end

  defp format_schema_error(idx, {message, path}) do
    "Record #{idx}: #{format_schema_path(path)} #{message}"
  end

  defp format_schema_path("/"), do: "root"

  defp format_schema_path(path) do
    path
    |> String.replace("/", ".")
    |> String.trim_leading(".")
  end
end
