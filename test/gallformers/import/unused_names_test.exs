defmodule Gallformers.Import.UnusedNamesTest do
  @moduledoc """
  The missed-names check (`d213`, "Cost correction (2026-11-05)"): the
  taxon names a Source prints that Gallformers' tree holds but none of the
  package's batches declare, with where they appear. A name the batches
  declare — written in full, abbreviated, with an authority or a rank
  marker, or in the old Cynips style — is not reported; nor is a printed
  name the tree doesn't hold, nor one only in the page furniture.
  """
  use Gallformers.DataCase, async: true

  import Gallformers.TaxaFixtures

  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package
  alias Gallformers.Import.UnusedNames
  alias Gallformers.Storage.Private
  alias Gallformers.Taxa

  setup :audit_test_metadata

  setup do
    for genus <- ["Xenogallus", "Quercopsis", "Rosula"],
        do: taxon_fixture(name: genus, rank: :genus)

    undeclared = taxon_fixture(name: "Xenogallus undeclaratus")
    taxon_fixture(name: "Xenogallus declaratus")
    taxon_fixture(name: "Xenogallus lectus")
    taxon_fixture(name: "Quercopsis albida")
    rubida = taxon_fixture(name: "Quercopsis rubida")
    taxon_fixture(name: "Rosula canina")
    taxon_fixture(name: "Rosula canina var. dumalis", rank: :variety)
    # Old Cynips names: one the tree holds only as today's fused epithet,
    # one it holds as a synonym in the old form.
    vacua = taxon_fixture(name: "Xenophibolips quercusvacua")
    foliosa = taxon_fixture(name: "Xenophibolips quercusfoliosa")
    {:ok, _} = Taxa.add_synonym(test_actor(), foliosa, "Cynips quercus foliosa")

    %{undeclared: undeclared, rubida: rubida, vacua: vacua}
  end

  defp document do
    texts = [
      text(0, "Xenogallus undeclaratus and other matters", "page_header", 1),
      text(1, "1. XENOGALLUS DECLARATUS Smith, new species.", "section_header", 1),
      text(
        2,
        "Gall on Q. albida. Like the gall of Xenogallus undeclaratus Smith, but " <>
          "smaller. The Black Oak bears it, as Quercopsis albida does.",
        "text",
        1
      ),
      text(3, "Compare Q. rubida, Xenogallus lectus and Notreal speciesname.", "text", 1),
      text(4, "12 Xenogallus undeclaratus", "page_footer", 1),
      text(
        5,
        "Bred from C. q. vacua and from Cynips quercus foliosa; not Xenogallus undeclaratus.",
        "text",
        2
      ),
      text(6, "On ROSULA CANINA, var. DUMALIS L. only.", "text", 2),
      text(7, "Later called Cynips quercus vacua by Walsh.", "text", 3)
    ]

    %{
      "schema_name" => "DoclingDocument",
      "body" => %{
        "self_ref" => "#/body",
        "children" => Enum.map(texts, &%{"$ref" => &1["self_ref"]})
      },
      "texts" => texts
    }
  end

  defp text(i, text, label, page) do
    %{
      "self_ref" => "#/texts/#{i}",
      "label" => label,
      "text" => text,
      "prov" => [%{"page_no" => page}]
    }
  end

  defp taxon(ref, written, reading \\ nil) do
    %{"ref" => ref, "rank" => "species", "name_as_written" => written}
    |> then(&if(reading, do: Map.put(&1, "name_reading", reading), else: &1))
  end

  defp batches do
    taxonomy = %{
      "batch_type" => "taxonomy",
      "taxa" => [
        %{"ref" => "t1", "rank" => "genus", "name_as_written" => "Cynips"},
        taxon("t2", "Xenogallus declaratus Smith")
      ]
    }

    gall = %{
      "batch_type" => "gall",
      "taxa" => [
        %{"ref" => "t1", "rank" => "genus", "name_as_written" => "Quercopsis"},
        taxon("t2", "Q. albida"),
        taxon("t3", "C. Q. FOLIOSA"),
        taxon("t4", "Rosula canina dumalis"),
        taxon("t5", "Xenogallus leotus", "Xenogallus lectus")
      ]
    }

    [taxonomy, gall]
  end

  describe "list/2" do
    test "reports the printed names the tree holds that no batch declares, where they appear",
         %{undeclared: undeclared, rubida: rubida, vacua: vacua} do
      assert UnusedNames.list(document(), batches()) == [
               %{
                 name: "Xenogallus undeclaratus",
                 normalized: "xenogallus undeclaratus",
                 taxon_ids: [undeclared.id],
                 items: ["#/texts/2", "#/texts/5"],
                 pages: [1, 2]
               },
               %{
                 name: "Q. rubida",
                 normalized: "quercopsis rubida",
                 taxon_ids: [rubida.id],
                 items: ["#/texts/3"],
                 pages: [1]
               },
               %{
                 name: "C. q. vacua",
                 normalized: "cynips quercus vacua",
                 taxon_ids: [vacua.id],
                 items: ["#/texts/5", "#/texts/7"],
                 pages: [2, 3]
               }
             ]
    end

    test "a name a batch declares is not reported, however either writes it" do
      names = document() |> UnusedNames.list(batches()) |> Enum.map(& &1.normalized)

      for declared <- [
            # with an authority
            "xenogallus declaratus",
            # abbreviated in the batch, in full and abbreviated in the text
            "quercopsis albida",
            # Cynips style both sides ("C. Q. FOLIOSA", "Cynips quercus foliosa")
            "cynips quercus foliosa",
            # through name_reading
            "xenogallus lectus",
            # a rank marker in the text, none in the batch; nor the species
            # inside the variety's name
            "rosula canina dumalis",
            "rosula canina var. dumalis",
            "rosula canina"
          ] do
        refute declared in names
      end
    end

    test "with no batches declaring anything, every tree-held name printed is reported" do
      names = document() |> UnusedNames.list([]) |> Enum.map(& &1.normalized)

      assert "xenogallus declaratus" in names
      assert "rosula canina var. dumalis" in names
      # Without the batches' genera nothing abbreviated expands.
      refute "quercopsis rubida" in names
    end

    test "a name that ends a sentence is printed without its full stop" do
      doc = %{
        "schema_name" => "DoclingDocument",
        "body" => %{"self_ref" => "#/body", "children" => [%{"$ref" => "#/texts/0"}]},
        "texts" => [text(0, "Bred on Quercopsis albida.", "text", 1)]
      }

      assert [%{name: "Quercopsis albida"}] = UnusedNames.list(doc, [])
    end

    test "words the tree doesn't hold are not reported" do
      names = document() |> UnusedNames.list([]) |> Enum.map(& &1.normalized)

      for noise <- ["notreal speciesname", "the black", "black oak", "like the"] do
        refute noise in names
      end
    end
  end

  describe "for_package/1" do
    test "reads the package's document and its batches (a denied batch declares nothing)" do
      key = "unused-#{System.unique_integer([:positive])}"
      :ok = Private.put("import/#{key}/document.json", Jason.encode!(document()))

      package =
        Repo.insert!(%Package{key: key, s3_prefix: "import/#{key}/", submitter_name: "test"})

      [taxonomy, gall] = batches()
      insert_batch!(package, "taxonomy.json", taxonomy, :pending)
      insert_batch!(package, "gall.json", gall, :denied)

      assert {:ok, names} = UnusedNames.for_package(package)
      normalized = Enum.map(names, & &1.normalized)
      assert "xenogallus undeclaratus" in normalized
      refute "xenogallus declaratus" in normalized
      # The denied gall batch declared it.
      assert "xenogallus lectus" in normalized
    end

    test "says when the package has no document" do
      assert UnusedNames.for_package(%Package{id: -1, s3_prefix: "import/unused-none/"}) ==
               {:error, :not_found}
    end
  end

  defp insert_batch!(package, file, content, status) do
    Repo.insert!(%Batch{
      package_id: package.id,
      file: file,
      batch_type: String.to_existing_atom(content["batch_type"]),
      mode: :add,
      producer_batch_id: "#{package.key}-#{file}",
      sha256: "0",
      content: content,
      status: status,
      denied_reason: if(status == :denied, do: "test")
    })
  end
end
