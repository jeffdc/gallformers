defmodule Gallformers.Taxonomy.TaxonomyTest do
  use Gallformers.DataCase, async: true

  alias Gallformers.Taxonomy.Taxonomy

  describe "changeset/2" do
    test "rejects parent_id equal to id (self-reference)" do
      # Create a taxonomy struct with an existing id (simulating edit mode)
      taxonomy = %Taxonomy{id: 42, name: "Test", type: "genus", parent_id: 1}

      changeset = Taxonomy.changeset(taxonomy, %{parent_id: 42})

      assert {:parent_id, {"cannot reference itself", []}} in changeset.errors
    end

    test "allows parent_id different from id" do
      taxonomy = %Taxonomy{id: 42, name: "Test", type: "genus", parent_id: 1}

      changeset = Taxonomy.changeset(taxonomy, %{parent_id: 10})

      refute Enum.any?(changeset.errors, fn {k, {msg, _}} ->
               k == :parent_id and msg == "cannot reference itself"
             end)
    end

    test "allows parent_id on new record (id is nil)" do
      taxonomy = %Taxonomy{}

      changeset = Taxonomy.changeset(taxonomy, %{name: "Test", type: "genus", parent_id: 42})

      refute Enum.any?(changeset.errors, fn {k, {msg, _}} ->
               k == :parent_id and msg == "cannot reference itself"
             end)
    end
  end
end
