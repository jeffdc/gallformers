defmodule Gallformers.Import.NotePackageTest do
  @moduledoc """
  A Gall's Gallformers note as a producer package (`20e5`): the note as the
  package's document, and what identifies its Gall.

  Not async: the tests use the one Gallformers Source.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Import.NotePackage
  alias Gallformers.Import.Validator
  alias Gallformers.Sources

  setup :audit_test_metadata

  setup do
    gallformers = gallformers_source()
    legacy = source_fixture("Legacy", "1990")
    lobata = plant_fixture(name: "Quercus lobata")
    genus = taxon_fixture(name: "Notegenus", rank: :genus)
    wasp = taxon_fixture(name: "Notegenus described", parent: genus)

    described = gall_fixture(name: "Notegenus described (agamic)", generation: "agamic")
    undescribed = gall_fixture(name: "Notegenus q-lobata-bud-gall")
    silent = gall_fixture(name: "Notegenus without a note")

    for {inducer, gall} <- [{wasp, described}, {genus, undescribed}] do
      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: inducer.id, object_gall_id: gall.id},
          confirm(legacy)
        )
    end

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "host_of", subject_taxon_id: lobata.id, object_gall_id: described.id},
        confirm(legacy)
      )

    for {gall, text} <- [
          {described, "Seen in [June](https://x.org)."},
          {undescribed, "A bud gall."}
        ],
        do: {:ok, _} = Sources.store_note(test_actor(), gallformers, gall.id, text)

    %{described: described, undescribed: undescribed, silent: silent}
  end

  test "the document is the note, as one text item", ctx do
    {:ok, files} = NotePackage.files(ctx.described.id, ~D[2026-10-30])
    doc = Jason.decode!(files["document.json"])

    assert [%{"self_ref" => "#/texts/0", "text" => "Seen in [June](https://x.org)."}] =
             doc["texts"]

    assert doc["body"]["children"] == [%{"$ref" => "#/texts/0"}]
  end

  test "note.json names the Gall, what identifies it, and the date", ctx do
    {:ok, files} = NotePackage.files(ctx.described.id, ~D[2026-10-30])

    assert Jason.decode!(files["note.json"]) == %{
             "gallformers_gall_id" => ctx.described.id,
             "name" => "Notegenus described (agamic)",
             "undescribed" => false,
             "inducer" => %{"name" => "Notegenus described", "rank" => "species"},
             "generation" => "agamic",
             "hosts" => ["Quercus lobata"],
             "stated_on" => "2026-10-30"
           }
  end

  test "a Gall without a note has no package", ctx do
    assert NotePackage.files(ctx.silent.id, ~D[2026-10-30]) == {:error, :no_note}
  end

  test "the Galls with a note, described or undescribed", ctx do
    assert NotePackage.gall_ids(:undescribed) == [ctx.undescribed.id]
    assert NotePackage.gall_ids(:described) == [ctx.described.id]
    assert NotePackage.gall_ids(:all) == Enum.sort([ctx.described.id, ctx.undescribed.id])
  end

  test "a gall batch quoting the document validates", ctx do
    {:ok, files} = NotePackage.files(ctx.undescribed.id, ~D[2026-10-30])

    gall = %{
      "format" => "gallformers-import",
      "format_version" => 3,
      "vocabulary_version" => "2026-10-11",
      "batch_type" => "gall",
      "mode" => "add",
      "batch_id" => "note-test-0000",
      "produced_at" => "2026-10-30T14:00:00Z",
      "producer" => %{"name" => "notes", "version" => "0"},
      "source" => %{
        "gallformers" => true,
        "note" => %{"gallformers_gall_id" => ctx.undescribed.id, "stated_on" => "2026-10-30"},
        "document" => %{
          "file" => "document.json",
          "sha256" => Validator.sha256(files["document.json"])
        }
      },
      "taxa" => [%{"ref" => "t1", "name_as_written" => "Notegenus", "rank" => "genus"}],
      "galls" => [
        %{
          "ref" => "g1",
          "name_as_written" => "A bud gall",
          "identified_by" => %{"inducer" => "t1"}
        }
      ],
      "facts" => [
        %{
          "id" => "f1",
          "stance" => "confirm",
          "kind" => "description",
          "gall" => "g1",
          "evidence" => [%{"item" => "#/texts/0", "quote" => "A bud gall."}]
        }
      ]
    }

    package = %{"document.json" => files["document.json"], "gall.json" => Jason.encode!(gall)}
    refute Validator.errors?(Validator.validate(package))
  end
end
