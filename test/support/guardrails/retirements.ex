defmodule Gallformers.Guardrails.Retirements do
  @moduledoc """
  Replacing means deleting (matter `c800`).

  `test/support/retirements.exs` lists modules being replaced:
  `%{retire: Old, replaced_by: New, matter: "id"}`. An entry is outstanding
  while both modules exist, and its test fails until the old one is deleted.

  A task that builds a replacement adds its entry first, as its failing test,
  and deletes the old module in the same commit. Once the old module is gone,
  remove its entry.
  """

  @path "test/support/retirements.exs"

  @type entry :: %{retire: module(), replaced_by: module(), matter: String.t()}

  @doc "The entries in `test/support/retirements.exs`."
  @spec read() :: [entry()]
  def read do
    {entries, _binding} = Code.eval_file(@path)
    entries
  end

  @doc "The entries whose old module and replacement both still exist."
  @spec outstanding([entry()]) :: [entry()]
  def outstanding(entries),
    do: Enum.filter(entries, &(exists?(&1.retire) and exists?(&1.replaced_by)))

  @doc "The failure message for outstanding entries."
  @spec explain([entry()]) :: String.t()
  def explain(entries) do
    lines =
      for e <- entries,
          do:
            "  #{inspect(e.retire)} is replaced by #{inspect(e.replaced_by)} (matter #{e.matter})"

    """
    Replaced code is still here. Delete it in this change, with its tests and
    its callers moved to the replacement, then remove its entry from
    #{@path}:

    #{Enum.join(lines, "\n")}
    """
  end

  defp exists?(module), do: Code.ensure_loaded?(module)
end
