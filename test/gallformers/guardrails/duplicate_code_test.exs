defmodule Gallformers.Guardrails.DuplicateCodeTest do
  # Runs Credo over the whole codebase once, which toggles Credo's global
  # output switch: not async.
  use ExUnit.Case, async: false

  alias Gallformers.Guardrails.DuplicateCode

  @copied """
  defmodule Copied do
    def rows(rows) do
      rows
      |> Enum.filter(&(&1.kind == :plant and &1.rank in [:species, :subspecies]))
      |> Enum.map(&%{id: "taxon:\#{&1.id}", name: &1.name, meta: Enum.join(&1.aliases, ", ")})
      |> Enum.sort_by(&{&1.meta, String.downcase(&1.name)})
      |> Enum.take(20)
    end
  end
  """

  @own """
  defmodule Own do
    def total(items), do: items |> Enum.map(& &1.count) |> Enum.sum()
  end
  """

  describe "counts/1" do
    @tag :tmp_dir
    test "a block copied between two files is a finding for that pair", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "a.ex"), @copied)
      File.write!(Path.join(dir, "b.ex"), String.replace(@copied, "Copied", "CopiedAgain"))
      File.write!(Path.join(dir, "c.ex"), @own)

      # Credo names files relative to the project root.
      pair =
        DuplicateCode.key(for f <- ["b.ex", "a.ex"], do: Path.relative_to_cwd(Path.join(dir, f)))

      assert DuplicateCode.counts(only: dir) == %{pair => 2}
    end

    @tag :tmp_dir
    test "code that isn't copied has no findings", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "a.ex"), @copied)
      File.write!(Path.join(dir, "c.ex"), @own)

      assert DuplicateCode.counts(only: dir) == %{}
    end
  end

  describe "the codebase" do
    # One test, so Credo reads the whole codebase once.
    test "matches its baseline: nothing copied beyond it, and cleanups locked in" do
      current = DuplicateCode.counts()
      baseline = DuplicateCode.read_baseline()

      worse =
        for {files, count} <- current,
            allowed = Map.get(baseline, files, 0),
            count > allowed,
            do: {files, count, allowed}

      assert worse == [], DuplicateCode.explain(worse)

      loose = for {files, count} <- baseline, Map.get(current, files, 0) < count, do: files

      assert loose == [],
             "Copied code went down in #{length(loose)} place(s). Lock it in with:\n\n" <>
               "    mix gallformers.guardrails.baseline\n"
    end
  end
end
