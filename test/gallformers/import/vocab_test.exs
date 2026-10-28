defmodule Gallformers.Import.VocabTest do
  @moduledoc """
  The vocabulary generator (`Gallformers.Import.Vocab`, `294c` step 3): the
  import contract's `priv/import/vocab/` files written from the database
  and code.

  The shipped files are generated from the rehearsal database, whose
  generation groups are mapped to more taxa than the test database's (only
  heterogony → Cynipini) and which holds every place. So these tests compare
  exactly what does not depend on those, and check the shape of the rest
  against the test database.

  Not async: loading the vocabularies waits on concurrent loads.
  """
  use Gallformers.DataCase, async: false

  alias Gallformers.Catalog
  alias Gallformers.Import.Vocab
  alias Gallformers.Licenses
  alias Gallformers.Places
  alias Gallformers.Taxa.Rank

  @shipped_dir Path.expand("../../../priv/import/vocab", __DIR__)
  @version "2026-01-02"

  defp shipped(file), do: @shipped_dir |> Path.join(file) |> File.read!()
  defp ordered(text), do: Jason.decode!(text, objects: :ordered_objects)

  # The generation groups' taxa depend on the database's taxa; everything
  # else in traits.json comes from the Trait vocabularies.
  defp without_group_taxa(traits) do
    update_in(traits, ["generation", "groups"], fn groups ->
      for group <- groups, do: elem(Access.pop(group, "taxa"), 1)
    end)
  end

  setup do
    # The shipped traits.json, loaded (the converted seeds hold it already).
    {:ok, _counts} = Catalog.load_vocab(test_actor())
    %{files: Vocab.render(@version)}
  end

  test "renders every file in the contract's vocab directory", %{files: files} do
    shipped = @shipped_dir |> Path.join("*.json") |> Path.wildcard() |> Enum.map(&Path.basename/1)
    assert Enum.sort(Map.keys(files)) == Enum.sort(shipped)
    assert Enum.sort(Vocab.file_names()) == Enum.sort(shipped)
  end

  describe "traits.json" do
    test "loading the shipped file and generating reproduces its Traits and mappings", %{
      files: files
    } do
      generated = ordered(files["traits.json"])
      shipped = ordered(shipped("traits.json"))

      assert without_group_taxa(generated["traits"]) == without_group_taxa(shipped["traits"])
      assert generated["mappings"] == shipped["mappings"]

      assert Enum.map(generated, &elem(&1, 0)) ==
               ["vocabulary", "vocabulary_version", "description", "traits", "mappings"]

      assert generated["description"] == shipped["description"]
      assert generated["vocabulary_version"] == @version
    end

    test "lists the Traits in the contract's order, each with its about and values", %{
      files: files
    } do
      traits = ordered(files["traits.json"])["traits"]

      assert Enum.map(traits, &elem(&1, 0)) ==
               ~w(generation detachable plant_part form shape color texture alignment walls cells season)

      for {_trait, entry} <- traits do
        assert is_binary(entry["about"]) and entry["about"] != ""
        assert [_ | _] = entry["values"]
      end

      # Values in the order they were added, which is the contract's order.
      assert Enum.map(traits["detachable"]["values"], & &1["value"]) ==
               ["integral", "detachable", "both", "unknown"]

      assert Enum.map(traits["season"]["values"], & &1["value"]) ==
               ["Spring", "Summer", "Fall", "Winter"]
    end

    test "gives each generation value its definition and other names, by group", %{files: files} do
      generation = ordered(files["traits.json"])["traits"]["generation"]
      values = Map.new(generation["values"], &{&1["value"], &1})

      assert Enum.map(generation["values"], & &1["value"]) ==
               ~w(agamic sexual spring summer autumn aecial telial fundatrix apterae exules gallicolae radicicolae)

      assert Enum.map(values["fundatrix"], &elem(&1, 0)) == ["value", "definition", "other_names"]

      assert values["fundatrix"]["definition"] ==
               "Hatches from the overwintering egg on the primary host and induces the primary gall."

      assert values["fundatrix"]["other_names"] == ["stem mother"]
      assert values["exules"]["other_names"] == ["alienicolae", "virginoparae"]
      assert values["agamic"]["other_names"] == []
      assert values["agamic"]["definition"] == nil
    end

    test "lists the generation groups in order with their values and the taxa mapped to them", %{
      files: files
    } do
      groups = ordered(files["traits.json"])["traits"]["generation"]["groups"]

      assert Enum.map(groups, fn group -> Enum.map(group, &elem(&1, 0)) end) |> Enum.uniq() ==
               [["name", "values", "taxa"]]

      shape =
        for group <- groups,
            do:
              {group["name"], group["values"], Enum.map(group["taxa"], &{&1["name"], &1["rank"]})}

      # The test database maps only heterogony (to Cynipini).
      assert shape == [
               {"heterogony", ["agamic", "sexual"], [{"Cynipini", "tribe"}]},
               {"seasonal", ["spring", "summer", "autumn"], []},
               {"rust_stages", ["aecial", "telial"], []},
               {"aphid_life_cycle", ~w(fundatrix apterae exules gallicolae radicicolae), []}
             ]
    end

    test "keeps the generation values' other names out of the term mappings", %{files: files} do
      mappings = ordered(files["traits.json"])["mappings"]
      refute Enum.any?(mappings, &(&1["trait"] == "generation"))
    end

    test "is two-space indented JSON ending in a newline", %{files: files} do
      assert files["traits.json"] =~
               ~r/\A\{\n  "vocabulary": "traits",\n  "vocabulary_version": "#{@version}",\n/

      assert files["traits.json"] =~ ~r/\n}\n\z/
    end
  end

  describe "the schemas" do
    test "the files from code and the Trait vocabularies reproduce the shipped ones exactly", %{
      files: files
    } do
      for file <-
            ~w(traits.schema.json licenses.schema.json ranks.schema.json relationships.schema.json) do
        assert files[file] == shipped(file), "#{file} differs from the shipped file"
      end
    end

    test "traits.schema.json allows every value traits.json lists, generation's from every group",
         %{files: files} do
      defs = ordered(files["traits.schema.json"])["$defs"]
      traits = ordered(files["traits.json"])["traits"]

      assert Enum.map(defs, &elem(&1, 0)) == Enum.map(traits, &elem(&1, 0))

      for {trait, entry} <- traits do
        assert defs[trait]["enum"] == Enum.map(entry["values"], & &1["value"])
      end

      assert defs["generation"]["enum"] ==
               ~w(agamic sexual spring summer autumn aecial telial fundatrix apterae exules gallicolae radicicolae)
    end

    test "ranks and licenses come from the code's lists", %{files: files} do
      assert ordered(files["ranks.schema.json"])["enum"] ==
               Enum.map(Rank.all(), &Atom.to_string/1)

      assert ordered(files["licenses.schema.json"])["enum"] == Licenses.all()
    end
  end

  describe "places" do
    test "places.json lists every place by code, with its name and type", %{files: files} do
      generated = ordered(files["places.json"])

      assert Enum.map(generated, &elem(&1, 0)) ==
               ["vocabulary", "vocabulary_version", "description", "places"]

      assert generated["vocabulary_version"] == @version
      assert generated["description"] == ordered(shipped("places.json"))["description"]

      # The test seeds' places are a few, not all production's (and RO-B is
      # a state there), so they are compared with the test database.
      expected =
        Places.list_all_places()
        |> Enum.sort_by(& &1.code)
        |> Enum.map(&[{"code", &1.code}, {"name", &1.name}, {"type", &1.type}])

      assert Enum.map(generated["places"], & &1.values) == expected
    end

    test "place-codes.schema.json allows exactly the codes places.json lists", %{files: files} do
      codes = Enum.map(ordered(files["places.json"])["places"], & &1["code"])
      assert ordered(files["place-codes.schema.json"])["enum"] == codes
    end

    test "are four-space indented JSON ending in a newline", %{files: files} do
      assert files["places.json"] =~ ~r/\A\{\n    "vocabulary": "places",\n/
      assert files["place-codes.schema.json"] =~ ~r/\A\{\n    "\$schema": /
      assert files["places.json"] =~ ~r/\n}\n\z/
      assert files["place-codes.schema.json"] =~ ~r/\n}\n\z/
    end
  end

  describe "write/2 and check/1" do
    setup do
      dir = Path.join(System.tmp_dir!(), "vocab_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf(dir) end)
      %{dir: dir}
    end

    test "writes every file, dated today unless a version is given", %{dir: dir} do
      today = Vocab.today()

      assert {:ok, %{version: ^today, written: written}} = Vocab.write(dir)
      assert written == Enum.sort(Vocab.file_names())
      assert ordered(File.read!(Path.join(dir, "places.json")))["vocabulary_version"] == today

      assert {:ok, %{version: @version}} = Vocab.write(dir, version: @version)
      assert File.read!(Path.join(dir, "traits.json")) == Vocab.render(@version)["traits.json"]
    end

    test "keeps the committed version when nothing changed", %{dir: dir} do
      {:ok, _} = Vocab.write(dir, version: @version)

      assert {:ok, %{version: @version, written: []}} = Vocab.write(dir)
    end

    test "dates the files anew when their content changed", %{dir: dir} do
      {:ok, _} = Vocab.write(dir, version: @version)
      path = Path.join(dir, "licenses.schema.json")
      File.write!(path, String.replace(File.read!(path), "CC-BY-SA", "CC-BY-XX"))

      today = Vocab.today()

      # The version changes in both files that carry it.
      assert {:ok, %{version: ^today, written: written}} = Vocab.write(dir)
      assert written == ["licenses.schema.json", "places.json", "traits.json"]
    end

    test "refuses a version that is not a date", %{dir: dir} do
      assert {:error, {:invalid_version, "next week"}} = Vocab.write(dir, version: "next week")
      refute File.exists?(dir)
    end

    test "check/1 lists the files that differ and writes nothing", %{dir: dir} do
      {:ok, _} = Vocab.write(dir, version: @version)
      assert Vocab.check(dir) == :ok

      path = Path.join(dir, "traits.json")
      stale = String.replace(File.read!(path), "The Gall's colors.", "Colours.")
      File.write!(path, stale)
      File.rm!(Path.join(dir, "ranks.schema.json"))

      assert Vocab.check(dir) == {:error, ["ranks.schema.json", "traits.json"]}
      assert File.read!(path) == stale
      refute File.exists?(Path.join(dir, "ranks.schema.json"))
    end
  end
end
