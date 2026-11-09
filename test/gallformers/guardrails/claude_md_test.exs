defmodule Gallformers.Guardrails.ClaudeMdTest do
  @moduledoc """
  CLAUDE.md stays short enough to be read in full (matter `c800`): rules only,
  with status in matters and detail in the docs it links. Raising the limit
  is Jeff's call.
  """
  use ExUnit.Case, async: true

  @limit 5_000

  defp size_check(path) do
    case File.stat!(path).size do
      size when size > @limit -> {:over, size}
      _size -> :ok
    end
  end

  @tag :tmp_dir
  test "a file over the limit fails", %{tmp_dir: dir} do
    path = Path.join(dir, "CLAUDE.md")
    File.write!(path, String.duplicate("x", @limit + 1))

    assert size_check(path) == {:over, @limit + 1}
  end

  test "CLAUDE.md is within the limit" do
    assert size_check("CLAUDE.md") == :ok,
           "CLAUDE.md is over #{@limit} bytes. It holds rules only: move status to its " <>
             "matter and detail to a linked doc. Raising the limit is Jeff's call."
  end
end
