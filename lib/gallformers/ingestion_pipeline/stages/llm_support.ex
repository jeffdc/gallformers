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

  defp normalize_async_exit(:timeout), do: :timeout
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
    raw_response
    |> strip_fenced_json()
    |> trim_to_json_start("[")
    |> decode_json_array_candidate()
  end

  @doc """
  Best-effort JSON object extraction from LLM output.

  Handles: raw JSON, markdown-fenced JSON, preamble text before JSON,
  and truncated JSON (returns whatever fields were complete).
  """
  @spec extract_json_object(String.t()) :: {:ok, map()} | {:error, :invalid_json}
  def extract_json_object(raw_response) when is_binary(raw_response) do
    raw_response
    |> strip_fenced_json()
    |> trim_to_json_start("{")
    |> decode_json_object_candidate()
  end

  # Finds the first occurrence of a character and returns substring from there
  defp trim_to_json_start(candidate, char) do
    if String.starts_with?(candidate, char) do
      candidate
    else
      case :binary.match(candidate, char) do
        :nomatch -> candidate
        {pos, _len} -> String.slice(candidate, pos, String.length(candidate) - pos)
      end
    end
  end

  defp decode_json_array_candidate(candidate) do
    case decode_array_or_wrapped_object(candidate) do
      {:ok, result} -> {:ok, result}
      {:error, :invalid_json} -> decode_repaired_json_array(candidate)
    end
  end

  defp decode_array_or_wrapped_object(candidate) do
    case Jason.decode(candidate) do
      {:ok, result} when is_list(result) -> {:ok, result}
      {:ok, result} when is_map(result) -> {:ok, [result]}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp decode_repaired_json_array(candidate) do
    candidate
    |> find_last_complete_object()
    |> case do
      nil -> {:error, :invalid_json}
      repaired -> decode_array_or_wrapped_object(repaired)
    end
  end

  defp decode_json_object_candidate(candidate) do
    case Jason.decode(candidate) do
      {:ok, result} when is_map(result) ->
        {:ok, result}

      {:error, _} ->
        decode_truncated_json_object(candidate)
    end
  end

  defp decode_truncated_json_object(candidate) do
    closers = [~s'"}', ~s'"}]', ~s'"]}', ~s'"]}}', "}", " ]}"]

    Enum.reduce_while(closers, {:error, :invalid_json}, fn suffix, _acc ->
      case Jason.decode(candidate <> suffix) do
        {:ok, result} when is_map(result) -> {:halt, {:ok, result}}
        _ -> {:cont, {:error, :invalid_json}}
      end
    end)
  end

  # Find the last complete top-level object in a truncated JSON array.
  # Uses brace depth tracking to find where top-level objects end.
  defp find_last_complete_object(candidate) do
    initial_state = %{depth: 0, in_string: false, escape: false, index: 0, last_obj_end: -1}

    candidate
    |> String.graphemes()
    |> Enum.reduce(initial_state, &scan_array_char/2)
    |> Map.fetch!(:last_obj_end)
    |> finalize_truncated_array(candidate)
  end

  defp scan_array_char(_char, %{escape: true} = state),
    do: advance_scan_state(%{state | escape: false})

  defp scan_array_char("\\", %{in_string: true} = state),
    do: advance_scan_state(%{state | escape: true})

  defp scan_array_char("\"", state),
    do: advance_scan_state(%{state | in_string: not state.in_string, escape: false})

  defp scan_array_char(_char, %{in_string: true} = state), do: advance_scan_state(state)

  defp scan_array_char(char, state) when char in ["[", "{"],
    do: advance_scan_state(%{state | depth: state.depth + 1})

  defp scan_array_char("}", state) do
    new_depth = state.depth - 1

    state
    |> Map.put(:depth, new_depth)
    |> maybe_mark_last_object_end("}", new_depth)
    |> advance_scan_state()
  end

  defp scan_array_char("]", state),
    do: advance_scan_state(%{state | depth: state.depth - 1})

  defp scan_array_char(_char, state), do: advance_scan_state(state)

  defp advance_scan_state(state), do: %{state | index: state.index + 1}

  defp maybe_mark_last_object_end(state, "}", 1), do: %{state | last_obj_end: state.index}
  defp maybe_mark_last_object_end(state, _char, _depth), do: state

  defp finalize_truncated_array(-1, _candidate), do: nil

  defp finalize_truncated_array(last_obj_end, candidate) do
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
