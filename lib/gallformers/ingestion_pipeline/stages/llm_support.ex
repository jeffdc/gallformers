defmodule Gallformers.IngestionPipeline.Stages.LLMSupport do
  @moduledoc false

  alias Gallformers.IngestionPipeline.LLMClient

  @spec load_prompt!(String.t(), map()) :: String.t()
  def load_prompt!(filename, replacements \\ %{})
      when is_binary(filename) and is_map(replacements) do
    filename
    |> prompt_path()
    |> File.read!()
    |> apply_replacements(replacements)
  end

  @spec llm_client(module(), module()) :: module()
  def llm_client(config_module, default \\ LLMClient)
      when is_atom(config_module) and is_atom(default) do
    :gallformers
    |> Application.get_env(config_module, [])
    |> Keyword.get(:llm_client, default)
  end

  @spec reduce_async_result(tuple(), {:ok, list()}) ::
          {:cont, {:ok, list()}} | {:halt, {:error, term()}}
  def reduce_async_result({:ok, {:ok, item}}, {:ok, acc}), do: {:cont, {:ok, [item | acc]}}
  def reduce_async_result({:ok, {:error, reason}}, _acc), do: {:halt, {:error, reason}}

  def reduce_async_result({:exit, reason}, _acc),
    do: {:halt, {:error, normalize_async_exit(reason)}}

  defp normalize_async_exit({:timeout, _reason}), do: :timeout
  defp normalize_async_exit({:exit, {:timeout, _reason}}), do: :timeout
  defp normalize_async_exit(reason), do: reason

  @spec strip_fenced_json(String.t()) :: String.t()
  def strip_fenced_json(raw_response) when is_binary(raw_response) do
    # Handle three cases:
    # 1. Fenced with newline: ```json\n{...}\n```
    # 2. Fenced without newline: ```json{...} ``` or ```json {...} ```
    # 3. No fence: raw JSON (return as-is)
    case Regex.run(~r/```(?:json)?\s*\n?(.*?)(?:\n?```|\z)/si, raw_response,
           capture: :all_but_first
         ) do
      [json] -> String.trim(json)
      _ -> String.trim(raw_response)
    end
  end

  @doc """
  Best-effort JSON array extraction from LLM output.

  Handles: raw JSON arrays, markdown-fenced JSON, preamble text before JSON,
  and truncated JSON (returns all complete objects found).
  """
  @spec extract_json_array(String.t()) :: {:ok, list(map())} | {:error, :invalid_json}
  def extract_json_array(raw_response) when is_binary(raw_response) do
    # Strip fences first
    candidate = strip_fenced_json(raw_response)

    # If no fence, find the first '['
    candidate =
      if String.starts_with?(candidate, "[") do
        candidate
      else
        trim_to_json_start(candidate, "[")
      end

    # Try parsing as-is
    case Jason.decode(candidate) do
      {:ok, result} when is_list(result) ->
        {:ok, result}

      {:ok, result} when is_map(result) ->
        {:ok, [result]}

      {:error, _} ->
        # Truncated JSON — find the last complete object and close the array
        case find_last_complete_object(candidate) do
          nil ->
            {:error, :invalid_json}

          repaired ->
            case Jason.decode(repaired) do
              {:ok, result} when is_list(result) -> {:ok, result}
              {:ok, result} when is_map(result) -> {:ok, [result]}
              {:error, _} -> {:error, :invalid_json}
            end
        end
    end
  end

  @doc """
  Best-effort JSON object extraction from LLM output.

  Handles: raw JSON, markdown-fenced JSON, preamble text before JSON,
  and truncated JSON (returns whatever fields were complete).
  """
  @spec extract_json_object(String.t()) :: {:ok, map()} | {:error, :invalid_json}
  def extract_json_object(raw_response) when is_binary(raw_response) do
    # Strip fences first
    candidate = strip_fenced_json(raw_response)

    # If no fence, find the first '{'
    candidate =
      if String.starts_with?(candidate, "{") do
        candidate
      else
        trim_to_json_start(candidate, "{")
      end

    # Try parsing as-is
    case Jason.decode(candidate) do
      {:ok, result} when is_map(result) ->
        {:ok, result}

      {:error, _} ->
        # Truncated JSON — try progressively closing open structures
        closers = [~s'"}', ~s'"}]', ~s'"]}', ~s'"]}}', "}", " ]}"]

        Enum.reduce_while(closers, {:error, :invalid_json}, fn suffix, _acc ->
          case Jason.decode(candidate <> suffix) do
            {:ok, result} when is_map(result) -> {:halt, {:ok, result}}
            _ -> {:cont, {:error, :invalid_json}}
          end
        end)
    end
  end

  # Finds the first occurrence of a character and returns substring from there
  defp trim_to_json_start(candidate, char) do
    case :binary.match(candidate, char) do
      :nomatch -> candidate
      {pos, _len} -> String.slice(candidate, pos, String.length(candidate) - pos)
    end
  end

  # Find the last complete top-level object in a truncated JSON array.
  # Uses brace depth tracking to find where top-level objects end.
  defp find_last_complete_object(candidate) do
    chars = String.graphemes(candidate)
    do_find_last_complete_object(chars, candidate, 0, false, false, 0, -1)
  end

  defp do_find_last_complete_object([], candidate, _depth, _in_string, _escape, _index, last_obj_end),
    do: finalize_truncated_array(candidate, last_obj_end)

  defp do_find_last_complete_object([char | rest], candidate, depth, in_string, escape, index, last_obj_end) do
    cond do
      escape ->
        do_find_last_complete_object(rest, candidate, depth, in_string, false, index + 1, last_obj_end)

      char == "\\" and in_string ->
        do_find_last_complete_object(rest, candidate, depth, in_string, true, index + 1, last_obj_end)

      char == "\"" and not escape ->
        do_find_last_complete_object(rest, candidate, depth, not in_string, false, index + 1, last_obj_end)

      in_string ->
        do_find_last_complete_object(rest, candidate, depth, in_string, false, index + 1, last_obj_end)

      char == "[" or char == "{" ->
        do_find_last_complete_object(rest, candidate, depth + 1, in_string, false, index + 1, last_obj_end)

      char == "]" or char == "}" ->
        new_depth = depth - 1
        # depth == 1 means we just closed a top-level object inside the array
        new_last = if new_depth == 1 and char == "}", do: index, else: last_obj_end
        do_find_last_complete_object(rest, candidate, new_depth, in_string, false, index + 1, new_last)

      true ->
        do_find_last_complete_object(rest, candidate, depth, in_string, false, index + 1, last_obj_end)
    end
  end

  defp finalize_truncated_array(_candidate, -1), do: nil
  defp finalize_truncated_array(candidate, last_obj_end) do
    String.slice(candidate, 0, last_obj_end + 1) <> "\n]"
  end

  defp prompt_path(filename) do
    [:code.priv_dir(:gallformers), "prompts", filename]
    |> Path.join()
  end

  defp apply_replacements(prompt, replacements) do
    Enum.reduce(replacements, prompt, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", value)
    end)
  end
end
