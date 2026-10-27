defmodule Gallformers.CatalogMigration.NameSuffixesTest do
  @moduledoc """
  The name-suffix mapping the data migration reads gall names with
  (`9449` Task 15; `b5bd` *Name-suffix categorization*): mechanical tokens
  in parentheses, plus curated rows by gall ID.
  """
  use ExUnit.Case, async: true

  alias Gallformers.CatalogMigration.NameSuffixes

  setup_all do
    {:ok, mapping} = NameSuffixes.load()
    %{mapping: mapping}
  end

  defp write_csv!(context, body) do
    path = Path.join(System.tmp_dir!(), "name_suffixes_#{context.test |> :erlang.phash2()}.csv")
    File.write!(path, "kind,key,name,inducer,generation,needs_review,category,handling\n" <> body)
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "the shipped mapping" do
    test "holds b5bd's 47 curated gall names and 2 curated non-binomials", %{mapping: mapping} do
      assert map_size(mapping.galls) == 49
    end

    test "marks every row b5bd leaves to a curator for review", %{mapping: mapping} do
      for {_id, row} <- mapping.galls, row.handling =~ "curator checks" do
        assert row.needs_review, "#{row.name} should need review"
      end
    end
  end

  describe "parse/3, mechanical suffixes" do
    test "a cynipid generation is stripped into the generation", %{mapping: m} do
      assert NameSuffixes.parse(m, 1, "Andricus foo (agamic)") ==
               {:ok, %{base: "Andricus foo", generation: "agamic", review: nil, curated?: false}}

      assert {:ok, %{base: "Andricus foo", generation: "sexual"}} =
               NameSuffixes.parse(m, 2, "Andricus foo (sexgen)")
    end

    test "a name with no suffix is its own base", %{mapping: m} do
      assert {:ok, %{base: "Andricus foo", generation: nil, review: nil}} =
               NameSuffixes.parse(m, 1, "Andricus foo")
    end

    test "tokens match without regard to case and spacing", %{mapping: m} do
      assert {:ok, %{base: "Andricus foo", generation: "spring"}} =
               NameSuffixes.parse(m, 1, "Andricus  foo ( Spring Generation )")
    end

    test "an unknown suffix is not guessed", %{mapping: m} do
      assert NameSuffixes.parse(m, 1, "Andricus foo (pacificus)") ==
               {:error, "unknown suffix (pacificus)"}
    end

    test "two generations are an error", %{mapping: m} do
      assert {:error, "two generations" <> _} =
               NameSuffixes.parse(m, 1, "Andricus foo (agamic) (sexgen)")
    end

    test "summer and autumn broods are one summer generation", %{mapping: m} do
      for token <- ["summer and autumn generations", "summer and autumn generation"] do
        assert {:ok, %{base: "Andricus foo", generation: "summer", review: nil}} =
                 NameSuffixes.parse(m, 1, "Andricus foo (#{token})")
      end
    end

    test "a token needing review parses, with the reason", context do
      path = write_csv!(context, "token,odd,,,,true,x,ask a curator\n")
      {:ok, m} = NameSuffixes.load(path)

      assert {:ok, %{base: "Andricus foo", generation: nil, review: "ask a curator"}} =
               NameSuffixes.parse(m, 1, "Andricus foo (odd)")
    end

    test "a placeholder genus prefix is not a suffix", %{mapping: m} do
      assert {:ok, %{base: "Unknown (Cynipidae) q-alba-red-bead", generation: "agamic"}} =
               NameSuffixes.parse(m, 1, "Unknown (Cynipidae) q-alba-red-bead (agamic)")
    end
  end

  describe "parse/3, curated rows" do
    test "a curated gall takes its row's Inducer and generation", %{mapping: m} do
      assert NameSuffixes.parse(m, 2255, "Hamamelistes spinosus (on Betula)") ==
               {:ok,
                %{
                  base: "Hamamelistes spinosus",
                  generation: "exules",
                  review: nil,
                  curated?: true
                }}
    end

    test "a curated row needing review says why", context do
      path =
        write_csv!(
          context,
          "gall,7,Andricus foo (bar),Andricus foo,agamic,true,x,ask a curator\n"
        )

      {:ok, m} = NameSuffixes.load(path)

      assert {:ok, %{base: "Andricus foo", generation: "agamic", review: "ask a curator"}} =
               NameSuffixes.parse(m, 7, "Andricus foo (bar)")
    end

    test "a gall form is its species' Gall, with no review", %{mapping: m} do
      assert {:ok, %{base: "Cynips mellea", generation: "agamic", review: nil}} =
               NameSuffixes.parse(m, 3396, "Cynips mellea (rydbergiana) (agamic)")
    end

    test "a curated row names the Inducer of a name that is not a binomial", %{mapping: m} do
      assert {:ok, %{base: "Puccinia recondita", review: nil}} =
               NameSuffixes.parse(m, 6026, "Puccinia recondita species complex")

      assert {:ok, %{base: "Aceria hibisci", review: nil}} =
               NameSuffixes.parse(m, 7161, "Aceria hibisci (Nalepa, 1906)")
    end

    test "a curated row for a name the gall no longer has is stale", %{mapping: m} do
      assert {:error, "curated row is for " <> _} =
               NameSuffixes.parse(m, 2255, "Hamamelistes spinosus (on Alnus)")
    end
  end

  describe "qualifiers/3: the trailing parentheticals as name parts" do
    test "a mechanical name: its stem and generation, as written", %{mapping: m} do
      assert NameSuffixes.qualifiers(m, 1, "Andricus  foo (spring generation)") ==
               {"Andricus foo", [{:generation, "spring generation"}]}

      assert NameSuffixes.qualifiers(m, 1, "Andricus foo") == {"Andricus foo", []}
    end

    test "a placeholder prefix stays in the stem", %{mapping: m} do
      assert NameSuffixes.qualifiers(m, 1, "Unknown (Cynipidae) q-alba-red-bead (agamic)") ==
               {"Unknown (Cynipidae) q-alba-red-bead", [{:generation, "agamic"}]}
    end

    test "a parenthesis inside a word is no qualifier", %{mapping: m} do
      assert NameSuffixes.qualifiers(m, 1519, "Unknown (Cynipidae) q-alba-(deforming-pisiformis)") ==
               {"Unknown (Cynipidae) q-alba-(deforming-pisiformis)", []}
    end

    test "a gall-form row's other parentheticals are form labels", %{mapping: m} do
      assert NameSuffixes.qualifiers(m, 1076, "Neuroterus saltatorius (australis) (agamic)") ==
               {"Neuroterus saltatorius", [{:form, "australis"}, {:generation, "agamic"}]}

      assert NameSuffixes.qualifiers(m, 2886, "Asphondylia pseudorosa (leaf snap)") ==
               {"Asphondylia pseudorosa", [{:form, "leaf snap"}]}
    end

    test "a host-scoped row's (on X) is a Host qualifier", %{mapping: m} do
      assert NameSuffixes.qualifiers(
               m,
               3167,
               "Neuroterus quercicola (pacificus) (sexgen) (on Quercus douglasii)"
             ) ==
               {"Neuroterus quercicola",
                [{:form, "pacificus"}, {:generation, "sexgen"}, {:host, "Quercus douglasii"}]}
    end

    test "other parentheticals are unread", %{mapping: m} do
      assert NameSuffixes.qualifiers(m, 7161, "Aceria hibisci (Nalepa, 1906)") ==
               {"Aceria hibisci", [{:unread, "Nalepa, 1906"}]}

      assert NameSuffixes.qualifiers(m, 1340, "Neuroterus quercusbatatus (agamic) (q-bicolor)") ==
               {"Neuroterus quercusbatatus", [{:generation, "agamic"}, {:unread, "q-bicolor"}]}

      assert NameSuffixes.qualifiers(m, 1, "Andricus foo (pacificus)") ==
               {"Andricus foo", [{:unread, "pacificus"}]}
    end
  end

  describe "load/1" do
    test "rejects an unknown kind", context do
      path = write_csv!(context, "suffix,agamic,,,agamic,false,x,y\n")
      assert {:error, "row 2: " <> _} = NameSuffixes.load(path)
    end

    test "rejects a gall row without a numeric ID", context do
      path = write_csv!(context, "gall,abc,Andricus foo (x),Andricus foo,,false,x,y\n")
      assert {:error, "row 2: " <> _} = NameSuffixes.load(path)
    end
  end
end
