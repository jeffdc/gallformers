defmodule Gallformers.Import.GallformersFragmentTest do
  @moduledoc """
  The gall batch of Gallformers' own statements about one Gall
  (`Gallformers.Import.GallformersFragment`, `priv/import/GALLFORMERS_STATEMENTS.md`):
  the Gall named as an import names it, the taxa the statements name
  declared once each, Facts numbered in order.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Import.GallformersFragment
  alias Gallformers.Import.Validator

  defp summary(attrs \\ %{}) do
    Map.merge(
      %{
        gall_id: 42,
        name: "Andricus quercuscalifornicus (agamic)",
        generation: "agamic",
        inducers: [%{taxon_id: 1, name: "Andricus quercuscalifornicus", rank: :species}],
        hosts: [%{taxon_id: 2, name: "Quercus lobata", rank: :species}]
      },
      Map.new(attrs)
    )
  end

  defp evidence, do: [%{"statement" => %{"text" => "Seen.", "stated_on" => "2026-11-06"}}]

  defp host_fact(taxon, stance \\ "confirm") do
    %{
      "stance" => stance,
      "kind" => "relationship",
      "type" => "host_of",
      "subject" => {:taxon, taxon},
      "object" => :gall,
      "evidence" => evidence()
    }
  end

  test "the Gall by its ID and identifying taxa; each named taxon declared once, with its ID" do
    alba = %{taxon_id: 7, name: "Quercus alba", rank: :species}
    lobata = %{taxon_id: 2, name: "Quercus lobata", rank: :species}

    assert {:ok, batch} =
             GallformersFragment.gall_batch(
               summary(),
               [host_fact(alba), host_fact(lobata, "deny"), host_fact(alba)],
               taxon_ids: true
             )

    assert batch["source"] == %{"gallformers" => true}
    assert batch["mode"] == "add"
    assert batch["batch_type"] == "gall"

    assert batch["taxa"] == [
             %{
               "ref" => "t1",
               "name_as_written" => "Andricus quercuscalifornicus",
               "rank" => "species",
               "gallformers_taxon_id" => 1
             },
             %{
               "ref" => "t2",
               "name_as_written" => "Quercus alba",
               "rank" => "species",
               "gallformers_taxon_id" => 7
             },
             %{
               "ref" => "t3",
               "name_as_written" => "Quercus lobata",
               "rank" => "species",
               "gallformers_taxon_id" => 2
             }
           ]

    assert [%{"ref" => "g1", "gallformers_gall_id" => 42, "identified_by" => ident}] =
             batch["galls"]

    assert ident == %{
             "inducer" => "t1",
             "generation" => %{"value" => "agamic", "as_written" => "agamic"}
           }

    assert [
             %{"id" => "f1", "subject" => "t2", "object" => "g1", "stance" => "confirm"},
             %{"id" => "f2", "subject" => "t3", "stance" => "deny"},
             %{"id" => "f3", "subject" => "t2"}
           ] = batch["facts"]

    assert Validator.schema_errors(Map.put(batch, "batch_id", Ecto.UUID.generate())) == []
  end

  test "without taxon_ids the taxa are named only" do
    range = %{
      "stance" => "confirm",
      "kind" => "range",
      "gall" => :gall,
      "adjustment" => "exclude",
      "place" => %{"value" => "US-CA", "as_written" => "California"},
      "evidence" => evidence()
    }

    assert {:ok, batch} = GallformersFragment.gall_batch(summary(), [range])

    assert batch["taxa"] == [
             %{
               "ref" => "t1",
               "name_as_written" => "Andricus quercuscalifornicus",
               "rank" => "species"
             }
           ]

    assert [%{"id" => "f1", "gall" => "g1"}] = batch["facts"]
  end

  test "a Gall with neither Inducer nor Host is named by a Host its statements add" do
    alba = %{taxon_id: 7, name: "Quercus alba", rank: :species}
    bare = summary(inducers: [], hosts: [], generation: nil)

    assert {:ok, batch} = GallformersFragment.gall_batch(bare, [host_fact(alba)])
    assert [%{"identified_by" => %{"host" => "t1"}}] = batch["galls"]

    assert GallformersFragment.gall_batch(bare, [host_fact(alba, "deny")]) ==
             {:error, :unidentified}
  end
end
