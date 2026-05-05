defmodule Gallformers.IngestionPipeline.Heuristics.RejoinLines do
  alias Gallformers.Utils

  @behaviour Gallformers.IngestionPipeline.Heuristics.TextHeuristic

  @impl true
  def name, do: :rejoin_lines

  @doc """
  Rejoins OCR/PDF line breaks while preserving headings and real paragraphs.
  """
  @impl true
  def apply(text) when is_binary(text) do
    text
    |> String.split(~r/\n{2,}/, trim: false)
    |> do_rejoin_lines([])
    |> Enum.reverse()
    |> Enum.join("\n\n")
  end

  defp do_rejoin_lines([], acc), do: acc

  defp do_rejoin_lines([block | rest], acc) do
    block = String.trim(block)

    cond do
      block == "" ->
        do_rejoin_lines(rest, acc)

      heading_or_special?(block) ->
        do_rejoin_lines(rest, [block | acc])

      true ->
        {parts, remaining} = collect_continuations([block], rest)

        joined =
          parts
          |> Enum.join(" ")
          |> then(&Regex.replace(~r/(?<!\n)\n(?!\n)/u, &1, " "))

        do_rejoin_lines(remaining, [joined | acc])
    end
  end

  defp heading_or_special?(line) do
    stripped = String.trim(line)

    String.starts_with?(stripped, "#") or
      (Utils.all_caps?(stripped) and String.length(stripped) < 100) or
      Regex.match?(~r/^\d+$/, stripped)
  end

  defp collect_continuations(parts, []), do: {parts, []}

  defp collect_continuations(parts, [next_block | rest]) do
    next_block = String.trim(next_block)

    cond do
      next_block == "" ->
        collect_continuations(parts, rest)

      continuation?(List.last(parts), next_block) ->
        collect_continuations(parts ++ [next_block], rest)

      true ->
        {parts, [next_block | rest]}
    end
  end

  defp continuation?(prev, current) do
    prev = String.trim_trailing(prev)
    current = String.trim_leading(current)

    if prev == "" or current == "" do
      false
    else
      prev_last = String.at(prev, -1)
      current_first = String.at(current, 0)

      prev_ends_mid = prev_last not in [".", "!", "?", ":", ";", "\""]

      current_continues =
        String.match?(current_first, ~r/^[[:lower:]]$/u) or
          current_first in [",", "(", ";", "—", "–", "-"]

      prev_ends_soft =
        prev_last in [",", ";", ":"] or
          Enum.any?(
            [" or", " and", " the", " of", " a", " an", " in", " to", " by"],
            &String.ends_with?(prev, &1)
          )

      (prev_ends_mid and current_continues) or prev_ends_soft
    end
  end
end
