defmodule Gallformers.Guardrails.RetirementsTest do
  use ExUnit.Case, async: true

  alias Gallformers.Guardrails.Retirements

  describe "outstanding/1" do
    test "an entry whose old module and replacement both exist is outstanding" do
      entry = %{retire: Gallformers.Facts, replaced_by: Gallformers.Taxa, matter: "c800"}

      assert Retirements.outstanding([entry]) == [entry]
    end

    test "an entry whose old module is gone is done" do
      entry = %{retire: Gallformers.NoSuchModule, replaced_by: Gallformers.Taxa, matter: "c800"}

      assert Retirements.outstanding([entry]) == []
    end

    test "an entry whose replacement isn't built yet waits for it" do
      entry = %{retire: Gallformers.Facts, replaced_by: Gallformers.NotBuiltYet, matter: "c800"}

      assert Retirements.outstanding([entry]) == []
    end
  end

  test "explain/1 names each module to delete, its replacement and its matter" do
    entry = %{retire: Gallformers.Facts, replaced_by: Gallformers.Taxa, matter: "c800"}

    assert Retirements.explain([entry]) =~
             "Gallformers.Facts is replaced by Gallformers.Taxa (matter c800)"
  end

  test "the codebase has no outstanding retirements" do
    outstanding = Retirements.outstanding(Retirements.read())

    assert outstanding == [], Retirements.explain(outstanding)
  end
end
